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
  config rollback "source_bookmark=1"; zsync
  zfs rollback -r "$ZCI_POOL_SRC/data@zfs-auto-snap_daily-01"; write "$ZCI_POOL_SRC/data" 1 f04; snap "$ZCI_POOL_SRC/data" 04
  zsync
  equal "ohne target_rollback: Exit-Code" 1 "$rc"
  equal "ohne target_rollback: Zustand" diverged "$(state_of "$ZCI_POOL_SRC/data")"
  check "kein Anfügen aus einem Bookmark nach Rollback" not grep -q 'continuing from the bookmark' "$log"
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

# Bookmark (#22): die Rotation löscht auf der Quelle alle Snapshots des Replikats, zsync fügt aus dem Bookmark an
# (unverschlüsselt und raw-verschlüsselt)
case_bookmark() {
  zfs create "$ZCI_POOL_SRC/plain"
  echo "zsync-ci-passphrase" | zfs create -o encryption=on -o keyformat=passphrase "$ZCI_POOL_SRC/enc"
  local d bm=zsync_$(hostname -s)_${ZCI_POOL_DST}_bookmark
  for d in plain enc; do
    zfs set bashclub:zsync=all "$ZCI_POOL_SRC/$d"; write "$ZCI_POOL_SRC/$d" 1; snap "$ZCI_POOL_SRC/$d" 01; snap "$ZCI_POOL_SRC/$d" 02
  done
  config bookmark "source_bookmark=1"; zsync
  equal "Exit-Code" 0 "$rc"
  for d in plain enc; do
    equal "$d: Bookmark zeigt auf den neuesten replizierten Snapshot" "$(guid "$ZCI_POOL_SRC/$d@zfs-auto-snap_daily-02")" "$(guid "$ZCI_POOL_SRC/$d#$bm")"
    write "$ZCI_POOL_SRC/$d" 1 more; snap "$ZCI_POOL_SRC/$d" 03
    zfs destroy "$ZCI_POOL_SRC/$d@zfs-auto-snap_daily-01"; zfs destroy "$ZCI_POOL_SRC/$d@zfs-auto-snap_daily-02"
  done
  zsync
  equal "nach Rotation: Exit-Code" 0 "$rc"
  check "aus dem Bookmark angefügt" grep -q 'continuing from the bookmark' <<< "$(last_run_log)"
  for d in plain enc; do
    equal "$d: Ziel rotiert wie die Quelle" "zfs-auto-snap_daily-03" "$(snaps "$ZCI_POOL_DST/bookmark/$ZCI_POOL_SRC/$d")"
    equal "$d: Bookmark weitergesetzt" "$(guid "$ZCI_POOL_SRC/$d@zfs-auto-snap_daily-03")" "$(guid "$ZCI_POOL_SRC/$d#$bm")"
    equal "$d: Zustand ok" ok "$(state_of "$ZCI_POOL_SRC/$d")"
  done
}

# Holds (#6): Basis und noch zu sendende Snapshots sind während der Replikation geschützt, danach freigegeben;
# ein Hold aus einem abgebrochenen Lauf wird beim nächsten Lauf mit freigegeben
case_hold() {
  zfs create -o compression=off "$ZCI_POOL_SRC/data"; zfs set bashclub:zsync=all "$ZCI_POOL_SRC/data"
  write "$ZCI_POOL_SRC/data" 1; snap "$ZCI_POOL_SRC/data" 01
  config hold "source_hold=1
bandwidth_limit=1m"
  zsync
  local tag=zsync_$(hostname -s)_${ZCI_POOL_DST}_hold s
  write "$ZCI_POOL_SRC/data" 6 big; snap "$ZCI_POOL_SRC/data" 02; write "$ZCI_POOL_SRC/data" 1 more; snap "$ZCI_POOL_SRC/data" 03
  zsync & local run=$!
  sleep 3
  check "während des Deltas: Basis daily-01 nicht löschbar" not zfs destroy "$ZCI_POOL_SRC/data@zfs-auto-snap_daily-01"
  check "während des Deltas: daily-03 (noch zu senden) nicht löschbar" not zfs destroy "$ZCI_POOL_SRC/data@zfs-auto-snap_daily-03"
  wait $run; rc=$?
  equal "Exit-Code" 0 "$rc"
  equal "alle Snapshots repliziert" "zfs-auto-snap_daily-01 zfs-auto-snap_daily-02 zfs-auto-snap_daily-03" "$(snaps "$ZCI_POOL_DST/hold/$ZCI_POOL_SRC/data")"
  equal "danach keine Holds mehr" "" "$(zfs list -H -o name -t snapshot "$ZCI_POOL_SRC/data" | xargs zfs holds -H | grep -F "$tag")"
  # Hold aus einem abgebrochenen Lauf
  zfs hold "$tag" "$ZCI_POOL_SRC/data@zfs-auto-snap_daily-03"
  zsync
  equal "Hold eines abgebrochenen Laufs freigegeben" "" "$(zfs holds -H "$ZCI_POOL_SRC/data@zfs-auto-snap_daily-03" | grep -F "$tag")"
}

# Snapshot während der Replikation gelöscht (#7, ohne Holds): er wird übersprungen, die übrigen werden übertragen
case_deleted_during() {
  zfs create -o compression=off "$ZCI_POOL_SRC/data"; zfs set bashclub:zsync=all "$ZCI_POOL_SRC/data"
  write "$ZCI_POOL_SRC/data" 1; snap "$ZCI_POOL_SRC/data" 01
  config deleted_during "bandwidth_limit=1m"
  zsync
  write "$ZCI_POOL_SRC/data" 6 big; snap "$ZCI_POOL_SRC/data" 02
  write "$ZCI_POOL_SRC/data" 1 c; snap "$ZCI_POOL_SRC/data" 03
  write "$ZCI_POOL_SRC/data" 1 d; snap "$ZCI_POOL_SRC/data" 04
  zsync & local run=$!
  sleep 3
  check "während des Deltas 01 -> 02: daily-03 gelöscht (keine Holds)" zfs destroy "$ZCI_POOL_SRC/data@zfs-auto-snap_daily-03"
  wait $run; rc=$?
  equal "Exit-Code" 0 "$rc"
  equal "daily-03 übersprungen, daily-04 übertragen" "zfs-auto-snap_daily-01 zfs-auto-snap_daily-02 zfs-auto-snap_daily-04" "$(snaps "$ZCI_POOL_DST/deleted_during/$ZCI_POOL_SRC/data")"
  check "Hinweis im Log" grep -q 'was deleted on the source during the replication' <<< "$(last_run_log)"
}

# Resume (#8): abgebrochene Erstreplikation und abgebrochenes Delta werden im nächsten Lauf fortgesetzt statt neu
# übertragen; ein Teilstand, dessen Snapshot auf der Quelle gelöscht wurde, wird verworfen
interrupt_send() { sleep "$1"; pkill -f '^zfs send'; }
case_resume() {
  zfs create -o compression=off "$ZCI_POOL_SRC/data"; zfs set bashclub:zsync=all "$ZCI_POOL_SRC/data"
  write "$ZCI_POOL_SRC/data" 12; snap "$ZCI_POOL_SRC/data" 01
  config resume "transfer_resume=1
bandwidth_limit=2m"
  local start
  # Erstreplikation nach 3 s abbrechen (12 MiB bei 2 MiB/s dauern 6 s)
  zsync & local run=$!; interrupt_send 3; wait $run
  check "abgebrochene Erstreplikation hinterlässt Token" test "$(prop "$ZCI_POOL_DST/resume/$ZCI_POOL_SRC/data" receive_resume_token)" != "-"
  start=$SECONDS; zsync
  equal "Erstreplikation fortgesetzt: Exit-Code" 0 "$rc"
  check "Erstreplikation fortgesetzt" grep -q 'resuming the interrupted transfer' <<< "$(last_run_log)"
  check "nur der Rest übertragen ($((SECONDS - start)) s statt 6 s)" test $((SECONDS - start)) -lt 6
  equal "Replikat vollständig" "zfs-auto-snap_daily-01" "$(snaps "$ZCI_POOL_DST/resume/$ZCI_POOL_SRC/data")"
  equal "Replikat nicht eingehängt" no "$(prop "$ZCI_POOL_DST/resume/$ZCI_POOL_SRC/data" mounted)"
  # Delta abbrechen und fortsetzen
  write "$ZCI_POOL_SRC/data" 12 more; snap "$ZCI_POOL_SRC/data" 02
  zsync & run=$!; interrupt_send 3; wait $run
  start=$SECONDS; zsync
  equal "Delta fortgesetzt: Exit-Code" 0 "$rc"
  check "nur der Rest des Deltas übertragen ($((SECONDS - start)) s statt 6 s)" test $((SECONDS - start)) -lt 6
  equal "Delta vollständig" "zfs-auto-snap_daily-01 zfs-auto-snap_daily-02" "$(snaps "$ZCI_POOL_DST/resume/$ZCI_POOL_SRC/data")"
  # Delta abbrechen, Snapshot auf der Quelle löschen: Teilstand verwerfen, mit dem nächsten Snapshot weiter
  write "$ZCI_POOL_SRC/data" 12 third; snap "$ZCI_POOL_SRC/data" 03
  zsync & run=$!; interrupt_send 3; wait $run
  write "$ZCI_POOL_SRC/data" 1 fourth; snap "$ZCI_POOL_SRC/data" 04; zfs destroy "$ZCI_POOL_SRC/data@zfs-auto-snap_daily-03"
  zsync
  equal "Teilstand verworfen: Exit-Code" 0 "$rc"
  check "Hinweis zum verworfenen Teilstand" grep -q 'discarding the partial state' <<< "$(last_run_log)"
  equal "weiter mit daily-04" "zfs-auto-snap_daily-01 zfs-auto-snap_daily-02 zfs-auto-snap_daily-04" "$(snaps "$ZCI_POOL_DST/resume/$ZCI_POOL_SRC/data")"
}

# Betrieb ohne root (#11): Benutzer mit zfs allow auf Quelle und Ziel repliziert über ssh (zsync-ci@localhost),
# mit Snapshot-Engine internal, Holds, Bookmarks und Resume; Proxmox-typische Datasets
case_unprivileged() {
  local user=zsync-ci home=/var/lib/zsync-ci-user
  id $user > /dev/null 2>&1 || useradd --system --create-home --home-dir $home --shell /bin/bash $user
  usermod -aG bashclub-zsync $user
  if [ ! -f $home/.ssh/id_ed25519 ]; then
    su - $user -c 'ssh-keygen -q -t ed25519 -N "" -f ~/.ssh/id_ed25519'
    echo "from=\"127.0.0.1,::1\" $(cat $home/.ssh/id_ed25519.pub)" > $home/.ssh/authorized_keys
    chown $user: $home/.ssh/authorized_keys; chmod 600 $home/.ssh/authorized_keys
    su - $user -c 'ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new localhost true'
  fi
  zfs create -o acltype=posixacl -o xattr=sa -o refquota=1G "$ZCI_POOL_SRC/subvol-100-disk-0"
  zfs create -V 64M "$ZCI_POOL_SRC/vm-101-disk-0"
  echo "zsync-ci-passphrase" | zfs create -o encryption=on -o keyformat=passphrase "$ZCI_POOL_SRC/enc"
  zfs set bashclub:zsync=subvols "$ZCI_POOL_SRC"
  write "$ZCI_POOL_SRC/subvol-100-disk-0" 2; write "$ZCI_POOL_SRC/enc" 2
  # Rechte wie im README
  check "Rechte auf der Quelle" zfs allow -u $user send,snapshot,destroy,mount,hold,release,bookmark "$ZCI_POOL_SRC"
  zfs create -o canmount=noauto -o com.sun:auto-snapshot=false "$ZCI_POOL_DST/unprivileged"
  check "Rechte auf dem Ziel" zfs allow -u $user "create,receive,mount,destroy,rollback,hold,release,userprop,$ZCI_RECV_PROPS" "$ZCI_POOL_DST/unprivileged"
  config unprivileged "source=$user@localhost
snapshot_filter=\"\"
zfs_auto_snapshot_keep=3
source_hold=1
source_bookmark=1
transfer_resume=1"
  local d run_as="su - $user -c"
  for n in 1 2; do
    echo "===== $(date +%T) als $user" >> "$log"
    $run_as "bashclub-zsync -c $conf" >> "$log" 2>&1; rc=$?
    equal "Lauf $n als $user: Exit-Code" 0 "$rc"
    [ $n -eq 1 ] && sleep 61   # eigener Snapshot-Name pro Minute (remote-snapshot-manager)
  done
  for d in subvol-100-disk-0 vm-101-disk-0 enc; do
    equal "$d: zwei Snapshots repliziert" 2 "$(zfs list -H -o name -t snapshot "$ZCI_POOL_DST/unprivileged/$ZCI_POOL_SRC/$d" | wc -l)"
  done
  equal "Subvol: refquota übernommen" 1G "$(prop "$ZCI_POOL_DST/unprivileged/$ZCI_POOL_SRC/subvol-100-disk-0" refquota)"
  equal "Subvol: acltype wie auf der Quelle" "$(prop "$ZCI_POOL_SRC/subvol-100-disk-0" acltype)" "$(prop "$ZCI_POOL_DST/unprivileged/$ZCI_POOL_SRC/subvol-100-disk-0" acltype)"
  equal "Subvol: xattr wie auf der Quelle" "$(prop "$ZCI_POOL_SRC/subvol-100-disk-0" xattr)" "$(prop "$ZCI_POOL_DST/unprivileged/$ZCI_POOL_SRC/subvol-100-disk-0" xattr)"
  check "keine abgelehnten Properties" not grep -q 'permission denied' "$log"
  equal "nicht eingehängt" no "$(prop "$ZCI_POOL_DST/unprivileged/$ZCI_POOL_SRC/subvol-100-disk-0" mounted)"
  equal "keine Holds übrig" "" "$(zfs list -H -o name -t snapshot -r "$ZCI_POOL_SRC" | xargs zfs holds -H | grep zsync_)"
  check "Bookmarks angelegt" test "$(zfs list -H -o name -t bookmark -r "$ZCI_POOL_SRC" | wc -l)" -ge 3
  equal "Status für das Monitoring geschrieben" "rc=0" "$(grep '^rc=' "$LIB_DIR/$id.last")"
  check "keine Warnung zu Rechten im Log" not grep -q 'not writable' "$log"
}

# Snapshots verschiedener Labels in derselben Sekunde (#30): Erstreplikation beginnt beim ältesten,
# das Löschen folgt dem ältesten Snapshot der Quelle
case_same_second() {
  zfs create "$ZCI_POOL_SRC/data"; zfs set bashclub:zsync=all "$ZCI_POOL_SRC/data"; write "$ZCI_POOL_SRC/data" 1
  snaps_same_second "$ZCI_POOL_SRC/data" daily-01 weekly-01
  equal "zwei Labels in derselben Sekunde" 1 "$(seconds_of "$ZCI_POOL_SRC/data")"
  config same_second 'snapshot_filter="daily|weekly"'
  zsync
  equal "Exit-Code" 0 "$rc"
  equal "Erstreplikation beginnt beim ältesten" "zfs-auto-snap_daily-01 zfs-auto-snap_weekly-01" "$(snaps "$ZCI_POOL_DST/same_second/$ZCI_POOL_SRC/data")"
  snap "$ZCI_POOL_SRC/data" 02; zfs destroy "$ZCI_POOL_SRC/data@zfs-auto-snap_daily-01"
  zsync
  equal "Exit-Code nach Rotation" 0 "$rc"
  equal "Ziel rotiert wie die Quelle" "zfs-auto-snap_weekly-01 zfs-auto-snap_daily-02" "$(snaps "$ZCI_POOL_DST/same_second/$ZCI_POOL_SRC/data")"
}

# Checkmk-Check gegen einen echten erfolgreichen Lauf
case_checkmk() {
  zfs create "$ZCI_POOL_SRC/data"; zfs set bashclub:zsync=all "$ZCI_POOL_SRC/data"; snap "$ZCI_POOL_SRC/data" 01
  config checkmk; zsync
  local out; out=$(check_output)
  check "Service OK in der Lernphase ($out)" grep -qE '^0 "zsync checkmk" .*learning 0/5' <<< "$out"
  check "Statusdatei des Laufs entfernt" test ! -e "$RUN_DIR/$id.state"
}

all_cases=(replication engine_internal rotation refquota rollback broken_chain orphans local_mode bandwidth_lock bookmark hold deleted_during resume unprivileged same_second checkmk)
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
