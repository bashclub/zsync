#!/bin/bash
# ZFS-Integrationstests: echte Pools auf den Testplatten aus /etc/zsync-ci.conf, installiertes bashclub-zsync.
# Jeder Fall bekommt frische Pools zci-src/zci-dst, am Ende werden sie zerstört.
# Aufruf (als root auf der Test-VM): tests/integration/run.sh [fall ...]
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"

# Erst- und Delta-Replikation: Dateisystem mit Kind, Volume, raw-verschlüsseltes Dataset
case_replication() {
  zfs create "$ZCI_POOL_SRC/data"; zfs create "$ZCI_POOL_SRC/data/child"
  zfs create -V 64M "$ZCI_POOL_SRC/vol"
  echo "zsync-ci-passphrase" | zfs create -o encryption=on -o keyformat=passphrase "$ZCI_POOL_SRC/enc"
  zfs set bashclub:zsync=all "$ZCI_POOL_SRC/data"; zfs set bashclub:zsync=all "$ZCI_POOL_SRC/vol"
  zfs set bashclub:zsync=all "$ZCI_POOL_SRC/enc"
  for d in data data/child enc; do write "$ZCI_POOL_SRC/$d" 4; done
  for d in data data/child vol enc; do snap "$ZCI_POOL_SRC/$d" 01; done
  config replication; zsync
  equal "Erstreplikation: Exit-Code" 0 "$rc"
  for d in data data/child vol enc; do
    equal "Erstreplikation $d: gleiche guid" "$(guid "$ZCI_POOL_SRC/$d@zfs-auto-snap_daily-01")" "$(guid "$ZCI_POOL_DST/replication/$ZCI_POOL_SRC/$d@zfs-auto-snap_daily-01")"
  done
  equal "Replikat nicht eingehängt" no "$(prop "$ZCI_POOL_DST/replication/$ZCI_POOL_SRC/data" mounted)"
  equal "Replikat canmount=noauto" noauto "$(prop "$ZCI_POOL_DST/replication/$ZCI_POOL_SRC/data" canmount)"
  equal "verschlüsseltes Replikat ohne Schlüssel (raw)" unavailable "$(prop "$ZCI_POOL_DST/replication/$ZCI_POOL_SRC/enc" keystatus)"
  for d in data data/child enc; do write "$ZCI_POOL_SRC/$d" 2 more; done
  for d in data data/child vol enc; do snap "$ZCI_POOL_SRC/$d" 02; snap "$ZCI_POOL_SRC/$d" 03; done
  zsync
  equal "Delta: Exit-Code" 0 "$rc"
  for d in data data/child vol enc; do
    equal "Delta $d: Snapshots am Ziel" "zfs-auto-snap_daily-01 zfs-auto-snap_daily-02 zfs-auto-snap_daily-03" "$(snaps "$ZCI_POOL_DST/replication/$ZCI_POOL_SRC/$d")"
  done
  equal "Status: letzter Lauf erfolgreich" "rc=0" "$(grep '^rc=' "$LIB_DIR/$id.last")"
}

# Snapshot-Engine internal (remote-snapshot-manager über ssh auf localhost)
case_engine_internal() {
  zfs create "$ZCI_POOL_SRC/data"; zfs set bashclub:zsync=all "$ZCI_POOL_SRC/data"; write "$ZCI_POOL_SRC/data" 1
  config engine_internal 'zfs_auto_snapshot_keep=3
snapshot_filter=""'
  zsync
  equal "Exit-Code" 0 "$rc"
  local s; s=$(snaps "$ZCI_POOL_SRC/data")
  check "Snapshot im Schema backup-YYYY-MM-DD-HHMM auf der Quelle ($s)" grep -qE '^backup-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{4}$' <<< "$s"
  equal "Replikat hat denselben Snapshot" "$s" "$(snaps "$ZCI_POOL_DST/engine_internal/$ZCI_POOL_SRC/data")"
}

# Rotation: Löschen auf dem Ziel folgt dem ältesten Snapshot der Quelle (min_keep=1)
case_rotation() {
  zfs create "$ZCI_POOL_SRC/data"; zfs set bashclub:zsync=all "$ZCI_POOL_SRC/data"
  for n in 01 02 03; do write "$ZCI_POOL_SRC/data" 1 f$n; snap "$ZCI_POOL_SRC/data" $n; done
  config rotation; zsync
  zfs destroy "$ZCI_POOL_SRC/data@zfs-auto-snap_daily-01"; zfs destroy "$ZCI_POOL_SRC/data@zfs-auto-snap_daily-02"
  write "$ZCI_POOL_SRC/data" 1 f04; snap "$ZCI_POOL_SRC/data" 04
  zsync
  equal "Exit-Code" 0 "$rc"
  equal "Ziel wie Quelle rotiert" "zfs-auto-snap_daily-03 zfs-auto-snap_daily-04" "$(snaps "$ZCI_POOL_DST/rotation/$ZCI_POOL_SRC/data")"
}

# refquota auf der Quelle erhöht und mehr Daten als die alte refquota: Ziel wird angehoben, receive gelingt
case_refquota() {
  zfs create -o refquota=32M "$ZCI_POOL_SRC/data"; zfs set bashclub:zsync=all "$ZCI_POOL_SRC/data"
  write "$ZCI_POOL_SRC/data" 8; snap "$ZCI_POOL_SRC/data" 01
  config refquota; zsync
  equal "Erstreplikation: refquota übernommen" 32M "$(prop "$ZCI_POOL_DST/refquota/$ZCI_POOL_SRC/data" refquota)"
  zfs set refquota=256M "$ZCI_POOL_SRC/data"; write "$ZCI_POOL_SRC/data" 64 big; snap "$ZCI_POOL_SRC/data" 02
  zsync
  equal "Exit-Code" 0 "$rc"
  equal "refquota am Ziel angehoben" 256M "$(prop "$ZCI_POOL_DST/refquota/$ZCI_POOL_SRC/data" refquota)"
  check "Delta mit 64 MiB übertragen" grep -q 'zfs-auto-snap_daily-02' <<< "$(snaps "$ZCI_POOL_DST/refquota/$ZCI_POOL_SRC/data")"
}

# Rollback auf der Quelle: ohne target_rollback Zustand diverged, mit target_rollback=1 zurückrollen und anfügen
case_rollback() {
  zfs create "$ZCI_POOL_SRC/data"; zfs set bashclub:zsync=all "$ZCI_POOL_SRC/data"
  for n in 01 02 03; do write "$ZCI_POOL_SRC/data" 1 f$n; snap "$ZCI_POOL_SRC/data" $n; done
  config rollback; zsync
  zfs rollback -r "$ZCI_POOL_SRC/data@zfs-auto-snap_daily-01"; write "$ZCI_POOL_SRC/data" 1 f04; snap "$ZCI_POOL_SRC/data" 04
  zsync
  equal "ohne target_rollback: Exit-Code" 1 "$rc"
  equal "ohne target_rollback: Zustand" diverged "$(state_of "$ZCI_POOL_SRC/data")"
  echo "target_rollback=1" >> "$conf"
  zsync
  equal "mit target_rollback=1: Exit-Code" 0 "$rc"
  equal "mit target_rollback=1: zurückgerollt und angefügt" "zfs-auto-snap_daily-01 zfs-auto-snap_daily-04" "$(snaps "$ZCI_POOL_DST/rollback/$ZCI_POOL_SRC/data")"
  equal "Zustand rolled_back" rolled_back "$(state_of "$ZCI_POOL_SRC/data")"
}

# Kette gerissen: alle Snapshots des Replikats wurden auf der Quelle wegrotiert
case_broken_chain() {
  zfs create "$ZCI_POOL_SRC/data"; zfs set bashclub:zsync=all "$ZCI_POOL_SRC/data"
  write "$ZCI_POOL_SRC/data" 1; snap "$ZCI_POOL_SRC/data" 01
  config broken_chain; zsync
  snap "$ZCI_POOL_SRC/data" 02; zfs destroy "$ZCI_POOL_SRC/data@zfs-auto-snap_daily-01"
  zsync
  equal "Exit-Code" 1 "$rc"
  equal "Zustand broken" broken "$(state_of "$ZCI_POOL_SRC/data")"
  check "Ursache Rotation im Log" grep -q 'deleted by the rotation on the source' <<< "$(last_run_log)"
  check "Checkmk: CRIT" grep -q '^2 ' <<< "$(check_output)"
}

# Replikat ohne Quelle und quittiertes Replikat
case_orphans() {
  for d in keep gone kept; do zfs create "$ZCI_POOL_SRC/$d"; zfs set bashclub:zsync=all "$ZCI_POOL_SRC/$d"; snap "$ZCI_POOL_SRC/$d" 01; done
  config orphans; zsync
  zfs destroy -r "$ZCI_POOL_SRC/gone"; zfs destroy -r "$ZCI_POOL_SRC/kept"
  zfs set bashclub:zsync-orphan=keep "$ZCI_POOL_DST/orphans/$ZCI_POOL_SRC/kept"
  zsync
  equal "Exit-Code" 0 "$rc"
  equal "Zustand orphan_missing" orphan_missing "$(state_of "$ZCI_POOL_SRC/gone")"
  equal "Zustand orphan_kept" orphan_kept "$(state_of "$ZCI_POOL_SRC/kept")"
  check "Replikat bleibt erhalten" exists "$ZCI_POOL_DST/orphans/$ZCI_POOL_SRC/gone"
}

# lokaler Modus, Ziel im selben Pool: Replikate erben den Tag und werden nicht erneut repliziert
case_local_mode() {
  zfs create "$ZCI_POOL_SRC/data"; zfs set bashclub:zsync=subvols "$ZCI_POOL_SRC"
  write "$ZCI_POOL_SRC/data" 1; snap "$ZCI_POOL_SRC/data" 01
  config local_mode "source=local"
  sed -i "s#^target=.*#target=$ZCI_POOL_SRC/backup#" "$conf"
  # Debug-Modus: die Meldungen zur ssh-Cipher-Erkennung dürfen im lokalen Modus nicht erscheinen
  zsync -d; zsync -d
  equal "Exit-Code" 0 "$rc"
  equal "repliziert in denselben Pool" "zfs-auto-snap_daily-01" "$(snaps "$ZCI_POOL_SRC/backup/$ZCI_POOL_SRC/data")"
  check "Replikat nicht erneut repliziert" not exists "$ZCI_POOL_SRC/backup/$ZCI_POOL_SRC/backup"
  check "kein ssh im lokalen Modus" not grep -q 'Switching to cipher\|Using default cipher' "$log"
}

# Bandbreitenlimit mit echtem pv und Sperre: ein zweiter Lauf während des ersten wird übersprungen
case_bandwidth_lock() {
  zfs create "$ZCI_POOL_SRC/data"; zfs set bashclub:zsync=all "$ZCI_POOL_SRC/data"
  zfs set compression=off "$ZCI_POOL_SRC/data"; write "$ZCI_POOL_SRC/data" 12; snap "$ZCI_POOL_SRC/data" 01
  config bandwidth_lock "bandwidth_limit=2m"
  local start=$SECONDS
  zsync & local first=$!
  sleep 2
  local log_first=$log; log=$log.second; zsync; log=$log_first
  equal "zweiter Lauf übersprungen: Exit-Code" 1 "$rc"
  check "zweiter Lauf meldet aktiven Lauf" grep -q 'Another run with configuration' "$log.second"
  wait $first; local duration=$((SECONDS - start))
  check "12 MiB bei 2 MiB/s dauern mindestens 5 s (gemessen ${duration}s)" test $duration -ge 5
  check "Replikat vollständig" grep -q 'zfs-auto-snap_daily-01' <<< "$(snaps "$ZCI_POOL_DST/bandwidth_lock/$ZCI_POOL_SRC/data")"
}

# Checkmk-Check gegen einen echten erfolgreichen Lauf
case_checkmk() {
  zfs create "$ZCI_POOL_SRC/data"; zfs set bashclub:zsync=all "$ZCI_POOL_SRC/data"; snap "$ZCI_POOL_SRC/data" 01
  config checkmk; zsync
  local out; out=$(check_output)
  check "Service OK in der Lernphase ($out)" grep -qE '^0 "zsync checkmk" .*learning 0/5' <<< "$out"
  check "Statusdatei des Laufs entfernt" test ! -e "$RUN_DIR/$id.state"
}

all_cases=(replication engine_internal rotation refquota rollback broken_chain orphans local_mode bandwidth_lock checkmk)
cases=("${@:-${all_cases[@]}}")
safety
rm -rf /var/log/zsync-ci
echo "bashclub-zsync $(dpkg-query -W -f='${Version}' bashclub-zsync 2>/dev/null), $(zfs version | head -1)"
for c in "${cases[@]}"; do
  echo "### $c"
  case_failed=0
  reset_pools
  "case_$c"
  if [ $case_failed -ne 0 ]; then
    failed_cases+=("$c")
    echo "  Log: /var/log/zsync-ci/$c.log"
  fi
done
cleanup_pools
echo "### Ergebnis: $(( ${#cases[@]} - ${#failed_cases[@]} ))/${#cases[@]} Fälle bestanden${failed_cases:+, fehlgeschlagen: ${failed_cases[*]}}"
[ ${#failed_cases[@]} -eq 0 ]
