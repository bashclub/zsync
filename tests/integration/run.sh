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
  equal "Status: letzter Lauf erfolgreich" "rc=0" "$(grep '^rc=' "$(status_path last)")"
  # Originalwerte der Quelle am Replikat (für einen Restore)
  equal "Originalwert: mountpoint geerbt" "inherited:/zci/src/data" "$(prop "$ZCI_POOL_DST/replication/$ZCI_POOL_SRC/data" bashclub:zsync-source.mountpoint)"
  equal "Originalwert: Tag lokal" "local:all" "$(prop "$ZCI_POOL_DST/replication/$ZCI_POOL_SRC/data" bashclub:zsync-source.bashclub:zsync)"
  equal "Originalwert: auto-snapshot geerbt" "inherited:false" "$(prop "$ZCI_POOL_DST/replication/$ZCI_POOL_SRC/data" bashclub:zsync-source.com.sun:auto-snapshot)"
  equal "Originalwert am Volume: refquota" "-:-" "$(prop "$ZCI_POOL_DST/replication/$ZCI_POOL_SRC/vol" bashclub:zsync-source.refquota)"
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
  zfs create -o canmount=noauto -o mountpoint=none -o com.sun:auto-snapshot=false "$ZCI_POOL_DST/unprivileged"
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
  # abgelehnt werden nur die Properties zum Einhängen (nicht delegiert), ihre Werte stehen am Replikat
  equal "nur Properties zum Einhängen abgelehnt" "" "$(grep 'permission denied' "$log" | grep -vE 'cannot receive (mountpoint|canmount|setuid|exec|devices) property')"
  check "Jobbenutzer kann mountpoint nicht setzen" not su $user -c "zfs set mountpoint=/tmp/zci-x $ZCI_POOL_DST/unprivileged/$ZCI_POOL_SRC/subvol-100-disk-0"
  equal "Replikat ohne mountpoint" none "$(prop "$ZCI_POOL_DST/unprivileged/$ZCI_POOL_SRC/subvol-100-disk-0" mountpoint)"
  equal "Originalwert gesichert: mountpoint" "inherited:/zci/src/subvol-100-disk-0" "$(prop "$ZCI_POOL_DST/unprivileged/$ZCI_POOL_SRC/subvol-100-disk-0" bashclub:zsync-source.mountpoint)"
  equal "nicht eingehängt" no "$(prop "$ZCI_POOL_DST/unprivileged/$ZCI_POOL_SRC/subvol-100-disk-0" mounted)"
  equal "keine Holds übrig" "" "$(zfs list -H -o name -t snapshot -r "$ZCI_POOL_SRC" | xargs zfs holds -H | grep zsync_)"
  check "Bookmarks angelegt" test "$(zfs list -H -o name -t bookmark -r "$ZCI_POOL_SRC" | wc -l)" -ge 3
  equal "Status für das Monitoring geschrieben" "rc=0" "$(grep '^rc=' "$(status_path last)")"
  check "keine Warnung zu Rechten im Log" not grep -q 'not writable\|cannot be used' "$log"
  check "Status im eigenen Ordner des Benutzers" test -f "$LIB_DIR/$user/$id.last"
  check "Checkmk: Service aus dem Ordner des Benutzers" grep -q '"zsync unprivileged"' <<< "$("$CHECK")"
  # Sperre auf der Config: auch über Benutzer hinweg läuft nur ein Lauf
  su $user -c "flock $conf sleep 8" & sleep 1
  zsync; local lock_rc=$rc; wait
  equal "Lauf von root, während $user die Config sperrt: übersprungen" 1 "$lock_rc"
  check "Meldung: anderer Lauf aktiv" grep -q "Another run with configuration $conf is still active" <(last_run_log)
}

# systemd-Timer (#12): echter Timer und Dienst, Checkmk liest das Intervall aus dem Timer, Migration von Cronjobs
# (die Test-Cronjobs liegen in einem eigenen Verzeichnis, der cron der VM führt sie nicht aus)
case_timer() {
  local name=zci-timer tconf=/etc/bashclub/zci-timer.conf lconf=/etc/bashclub/zci-legacy.conf crondir=/tmp/zci-cron unit=bashclub-zsync@zci-timer.timer
  zfs create "$ZCI_POOL_SRC/data"; zfs set bashclub:zsync=all "$ZCI_POOL_SRC/data"; snap "$ZCI_POOL_SRC/data" 01
  config timer; cp "$conf" "$tconf"; cp "$conf" "$lconf"; conf=$tconf; id=$(tr '/' '_' <<< "$conf")
  # Bestand: Configs ohne trigger bekommen keinen Timer, auch nicht durch daemon-reload oder sync
  systemctl daemon-reload
  check "ohne trigger: kein Timer nach daemon-reload" not systemctl is-active --quiet bashclub-zsync@zci-legacy.timer
  check "ohne trigger: sync startet nichts" grep -q "no configuration with trigger=systemd" <<< "$(bashclub-zsync-timer sync)"
  check "ohne trigger: kein Timer nach sync" not systemctl is-active --quiet $unit
  # enable schreibt die Config, der Generator erzeugt den Timer
  check "Timer einschalten" bashclub-zsync-timer enable $name "0 3 * * *"
  check "Config: trigger=systemd" grep -qx 'trigger=systemd' "$tconf"
  check "Config: schedule im Cron-Format" grep -qx "schedule='0 3 \* \* \*'" "$tconf"
  equal "Timer vom Generator" enabled-runtime "$(systemctl is-enabled $unit)"
  check "Timer aktiv" systemctl is-active --quiet $unit
  check "Zeitplan umgerechnet" grep -q 'OnCalendar=\*-\*-\* 03:00:00' <<< "$(systemctl show -p TimersCalendar --value $unit)"
  local since; since=$(date '+%Y-%m-%d %H:%M:%S')
  systemctl start bashclub-zsync@$name.service
  equal "Dienst erfolgreich" success "$(systemctl show -p Result --value bashclub-zsync@$name.service)"
  equal "repliziert" "zfs-auto-snap_daily-01" "$(snaps "$ZCI_POOL_DST/timer/$ZCI_POOL_SRC/data")"
  check "Log im Journal" grep -q 'Reading configuration /etc/bashclub/zci-timer.conf' <<< "$(journalctl -u bashclub-zsync@$name.service --since "$since" --no-pager)"
  check "Checkmk: Intervall aus dem Timer" grep -q "from bashclub-zsync@$name.timer" <<< "$(check_output)"
  # Zeitplan und Benutzer in der Config ändern, sync übernimmt sie
  sed -i 's/^schedule=.*/schedule="*\/30 * * * *"/' "$tconf"; echo "run_as=nobody" >> "$tconf"
  check "Probelauf sync" grep -q "plan  update $unit" <<< "$(bashclub-zsync-timer sync --dry-run)"
  check "sync nach Änderung" bashclub-zsync-timer sync
  check "neuer Zeitplan" grep -q 'OnCalendar=\*-\*-\* \*:00/30:00' <<< "$(systemctl show -p TimersCalendar --value $unit)"
  equal "Benutzer aus run_as" nobody "$(systemctl show -p User --value bashclub-zsync@$name.service)"
  sed -i '/^run_as=/d' "$tconf"
  sed -i 's/^schedule=.*/schedule="@reboot"/' "$tconf"
  check "ungültiger Zeitplan: sync meldet Fehler" grep -q "error $name: schedule '@reboot'" <<< "$(bashclub-zsync-timer sync --dry-run)"
  sed -i 's/^schedule=.*/schedule="0 3 * * *"/' "$tconf"
  # ungültige Eingaben werden abgewiesen, die Config bleibt unverändert
  local before_conf; before_conf=$(md5sum < "$tconf")
  check "enable: ungültiger Benutzer abgewiesen" not bashclub-zsync-timer enable $name --user 'nobody;id'
  check "enable: Logdatei mit Leerzeichen abgewiesen" not bashclub-zsync-timer enable $name --log '/var/log/a b.log'
  check "enable: Logdatei mit % abgewiesen" not bashclub-zsync-timer enable $name --log '/var/log/%n.log'
  equal "Config nach abgewiesenen Eingaben unverändert" "$before_conf" "$(md5sum < "$tconf")"
  # Wechseldatenträger: list erkennt die Verwendung durch zsync-autorun
  ln -sfn "$lconf" /etc/default/zsync-autorun@zci-usb
  check "list: Hinweis auf autorun" grep -q "zci-legacy is used by zsync-autorun@zci-usb: set trigger=autorun" <<< "$(bashclub-zsync-timer list)"
  rm -f /etc/default/zsync-autorun@zci-usb
  # disable: trigger=cron, Timer gestoppt
  check "Timer ausschalten" bashclub-zsync-timer disable $name
  check "Config: trigger=cron" grep -qx 'trigger=cron' "$tconf"
  check "Timer gestoppt" not systemctl is-active --quiet $unit
  # Migration: Cronjob mit Benutzer und Logdatei plus cron.daily-Skript derselben Config
  rm -rf "$crondir"; mkdir -p $crondir/cron.d $crondir/cron.daily
  echo "*/15 6-22 * * 1-5 root /usr/bin/bashclub-zsync -c $tconf >> /var/log/bashclub-zsync/zci-timer.log 2>&1" > $crondir/cron.d/zsync
  printf '#!/bin/sh\n/usr/bin/bashclub-zsync -c %s > /dev/null\n' "$tconf" > $crondir/cron.daily/zsync
  local before; before=$(cat $crondir/cron.d/zsync $crondir/cron.daily/zsync "$tconf" | md5sum)
  local plan; plan=$(ZSYNC_CRON_DIRS="$crondir/cron.d $crondir/cron.daily" bashclub-zsync-timer migrate --dry-run)
  check "Probelauf: Cron-Zeitplan übernommen" grep -qF 'schedule="*/15 6-22 * * 1-5"' <<< "$plan"
  check "Probelauf: cron.daily mit Debian-Zeit" grep -qF 'schedule="25 6 * * *"' <<< "$plan"
  equal "Probelauf ändert nichts" "$before" "$(cat $crondir/cron.d/zsync $crondir/cron.daily/zsync "$tconf" | md5sum)"
  # Cronjob einer anderen Config bleibt, wenn nur diese übernommen wird
  echo "0 2 * * * root /usr/bin/bashclub-zsync -c $lconf" > $crondir/cron.d/legacy
  ZSYNC_CRON_DIRS="$crondir/cron.d $crondir/cron.daily" bashclub-zsync-timer migrate $name > /dev/null
  check "migrate <name>: andere Config unverändert" grep -q '^0 2 \* \* \* root' $crondir/cron.d/legacy
  check "migrate <name>: andere Config ohne trigger" not grep -q '^trigger=' "$lconf"
  check "Cron-Zeile auskommentiert" grep -q '^# bashclub-zsync-timer: migrated' $crondir/cron.d/zsync
  check "cron.daily-Zeile auskommentiert" grep -q '^# bashclub-zsync-timer: migrated' $crondir/cron.daily/zsync
  check "Config: beide Zeitpläne" grep -qE "^schedule='(\*/15 6-22 \* \* 1-5;25 6 \* \* \*|25 6 \* \* \*;\*/15 6-22 \* \* 1-5)'$" "$tconf"
  check "Config: Logdatei" grep -qx 'log_file=/var/log/bashclub-zsync/zci-timer.log' "$tconf"
  equal "beide Zeitpläne im Timer" 2 "$(systemctl show -p TimersCalendar --value $unit | grep -o OnCalendar= | wc -l)"
  systemctl start bashclub-zsync@$name.service
  check "Ausgabe in der übernommenen Logdatei" grep -q 'Reading configuration' /var/log/bashclub-zsync/zci-timer.log
  check "erneute Migration findet nichts mehr" grep -q 'no cron jobs' <<< "$(ZSYNC_CRON_DIRS="$crondir/cron.d $crondir/cron.daily" bashclub-zsync-timer migrate --dry-run $name)"
  # aufräumen: ohne Config verschwindet der Timer mit sync
  rm -f "$tconf" "$lconf"
  bashclub-zsync-timer sync > /dev/null
  check "Timer ohne Config gestoppt" not systemctl is-active --quiet $unit
  systemctl stop bashclub-zsync@$name.service 2> /dev/null; rm -f "$tconf" /var/lib/systemd/timers/stamp-bashclub-zsync@$name.timer
  rm -rf "$crondir" /var/log/bashclub-zsync/zci-timer.log
}

# Snapshots verschiedener Labels in derselben Sekunde (#30): Erstreplikation beginnt beim ältesten,
# das Löschen folgt dem ältesten Snapshot der Quelle
case_same_second() {
  zfs create "$ZCI_POOL_SRC/data"; zfs set bashclub:zsync=all "$ZCI_POOL_SRC/data"; write "$ZCI_POOL_SRC/data" 1
  if ! snaps_same_second "$ZCI_POOL_SRC/data" daily-01 weekly-01; then
    skip "zwei Snapshots in derselben Sekunde unter Last nicht herstellbar"; return
  fi
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
# Benutzer auf der Quelle mit command=bashclub-zsync-remote (restrict): Replikation mit allen Funktionen,
# eine Shell wird abgewiesen
case_restricted() {
  local user=zsync-ci-r home=/var/lib/zsync-ci-r
  id $user > /dev/null 2>&1 || useradd --system --create-home --home-dir $home --shell /bin/bash $user
  usermod -aG bashclub-zsync $user
  if [ ! -f $home/.ssh/id_ed25519 ]; then
    su - $user -c 'install -d -m 700 ~/.ssh && ssh-keygen -q -t ed25519 -N "" -f ~/.ssh/id_ed25519'
  fi
  echo "restrict,from=\"127.0.0.1,::1\",command=\"/usr/bin/bashclub-zsync-remote\" $(cat $home/.ssh/id_ed25519.pub)" > $home/.ssh/authorized_keys
  chown $user: $home/.ssh/authorized_keys; chmod 600 $home/.ssh/authorized_keys
  su - $user -c 'ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new localhost exit'
  # Spool auf der Quelle (checkzfs_spool=1) für die Gruppe beschreibbar
  install -d -m 3775 -g bashclub-zsync /var/lib/check_mk_agent/spool
  zfs create "$ZCI_POOL_SRC/data"; zfs create -V 64M "$ZCI_POOL_SRC/vol"
  zfs set bashclub:zsync=all "$ZCI_POOL_SRC/data"; zfs set bashclub:zsync=all "$ZCI_POOL_SRC/vol"
  write "$ZCI_POOL_SRC/data" 2
  zfs allow -u $user send,snapshot,destroy,mount,hold,release,bookmark "$ZCI_POOL_SRC"
  zfs create -o canmount=noauto -o mountpoint=none -o com.sun:auto-snapshot=false "$ZCI_POOL_DST/restricted"
  zfs allow -u $user "create,receive,mount,destroy,rollback,hold,release,userprop,$ZCI_RECV_PROPS" "$ZCI_POOL_DST/restricted"
  config restricted "source=$user@localhost
snapshot_filter=\"\"
zfs_auto_snapshot_keep=3
source_hold=1
source_bookmark=1
transfer_resume=1
checkzfs_disabled=0
checkzfs_spool=1"
  local out
  out=$(su - $user -c 'ssh -o BatchMode=yes localhost id' 2>&1); rc=$?
  equal "Shell abgewiesen: Exit-Code" 126 "$rc"
  check "Shell abgewiesen: Meldung" grep -q "command not allowed: id" <<< "$out"
  for n in 1 2; do
    echo "===== $(date +%T) als $user (command=)" >> "$log"
    su - $user -c "bashclub-zsync -c $conf" >> "$log" 2>&1; rc=$?
    equal "Lauf $n: Exit-Code" 0 "$rc"
    [ $n -eq 1 ] && sleep 61   # eigener Snapshot-Name pro Minute (remote-snapshot-manager)
  done
  check "nichts abgewiesen" not grep -q "command not allowed" "$log"
  for d in data vol; do
    equal "$d: zwei Snapshots repliziert" 2 "$(zfs list -H -o name -t snapshot "$ZCI_POOL_DST/restricted/$ZCI_POOL_SRC/$d" | wc -l)"
  done
  equal "Bookmarks angelegt" 2 "$(zfs list -H -o name -t bookmark -r "$ZCI_POOL_SRC" | grep -c zsync_)"
  equal "keine Holds übrig" "" "$(zfs list -H -o name -t snapshot -r "$ZCI_POOL_SRC" | xargs zfs holds -H | grep zsync_)"
  check "checkzfs-Ausgabe im Spool der Quelle" grep -q "<<<local>>>" /var/lib/check_mk_agent/spool/87000_zsync
  rm -f /var/lib/check_mk_agent/spool/87000_zsync
}
# Quellpaket: Verwaltungsbenutzer zsync legt per sudo den Benutzer eines Replikationsjobs an, der nur die
# getaggten Datasets lesen darf und nur per command= von seiner Adresse aus erreichbar ist
case_job_user() {
  local backup=zsync-ci-j home=/var/lib/zsync-ci-j job=bashclub-zsync-job-user out
  id $backup > /dev/null 2>&1 || useradd --system --create-home --home-dir $home --shell /bin/bash $backup
  usermod -aG bashclub-zsync $backup
  [ -f $home/.ssh/id_ed25519 ] || su - $backup -c 'install -d -m 700 ~/.ssh && ssh-keygen -q -t ed25519 -N "" -f ~/.ssh/id_ed25519'
  zfs create "$ZCI_POOL_SRC/data"; zfs create "$ZCI_POOL_SRC/other"
  zfs set bashclub:zsync=all "$ZCI_POOL_SRC/data"
  write "$ZCI_POOL_SRC/data" 1; snap "$ZCI_POOL_SRC/other" 01
  check "Verwaltungsbenutzer zsync vom Paket" id zsync
  check "zsync: sudo nur für $job" not su - zsync -c "sudo -n id"
  check "Job anlegen als zsync" su - zsync -c "sudo -n /usr/sbin/$job add cij 127.0.0.1,::1 $(cat $home/.ssh/id_ed25519.pub)"
  check "Rechte als zsync" su - zsync -c "sudo -n /usr/sbin/$job allow cij bashclub:zsync"
  check "kein RSA-Schlüssel" not $job add cij2 127.0.0.1 "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ== x"
  check "kein ungültiger Jobname" not $job add ../x 127.0.0.1 "$(cat $home/.ssh/id_ed25519.pub)"
  check "kein fremder Benutzer" not $job add ci-j 127.0.0.1 "$(cat $home/.ssh/id_ed25519.pub)"
  equal "Schlüssel mit restrict, from und command" 'restrict,from="127.0.0.1,::1",command="/usr/bin/bashclub-zsync-remote" ssh-ed25519' \
    "$(cut -d' ' -f1-2 /var/lib/bashclub-zsync-source/cij/.ssh/authorized_keys)"
  out=$($job list)
  check "list: Adresse und Dataset ($out)" grep -qE "^zsync-cij	from 127.0.0.1,::1	$ZCI_POOL_SRC/data	all snapshots$" <<< "$out"
  zfs create -o canmount=noauto -o mountpoint=none -o com.sun:auto-snapshot=false "$ZCI_POOL_DST/job_user"
  zfs allow -u $backup "create,receive,mount,destroy,rollback,hold,release,userprop,$ZCI_RECV_PROPS" "$ZCI_POOL_DST/job_user"
  config job_user "source=zsync-cij@localhost
snapshot_filter=\"\"
zfs_auto_snapshot_keep=3
source_hold=1
source_bookmark=1"
  su - $backup -c 'ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new zsync-cij@localhost exit'
  echo "===== $(date +%T) als $backup" >> "$log"
  su - $backup -c "bashclub-zsync -c $conf" >> "$log" 2>&1; rc=$?
  equal "Replikation über den Jobbenutzer: Exit-Code" 0 "$rc"
  equal "Snapshot repliziert" 1 "$(zfs list -H -o name -t snapshot "$ZCI_POOL_DST/job_user/$ZCI_POOL_SRC/data" 2>/dev/null | wc -l)"
  check "nicht getaggtes Dataset nicht lesbar" not su - $backup -c "ssh -o BatchMode=yes zsync-cij@localhost zfs send -w $ZCI_POOL_SRC/other@zfs-auto-snap_daily-01 > /dev/null"
  check "keine Shell" not su - $backup -c "ssh -o BatchMode=yes zsync-cij@localhost id"
  check "Job entfernen" $job remove cij
  check "Benutzer entfernt" not id zsync-cij
  check "Rechte entfernt" not grep -q zsync-cij <<< "$(zfs allow "$ZCI_POOL_SRC/data")"
}
# geführtes Setup: Jobbenutzer auf beiden Seiten, Config, Timer, erster Lauf; Einrichtung der Quelle als root und
# als Verwaltungsbenutzer zsync, dazu --root im lokalen Modus
case_setup() {
  local name=zci-setup conf_s=/etc/bashclub/zci-setup.conf host; host=$(hostname -s)
  local sjob; sjob=$(echo "$host-zci-setup" | tr 'A-Z_.' 'a-z--' | cut -c1-26)
  zfs create "$ZCI_POOL_SRC/data"; zfs create "$ZCI_POOL_SRC/other"; write "$ZCI_POOL_SRC/data" 1
  check "Setup als root" bashclub-zsync-setup -y -s localhost -t "$ZCI_POOL_DST/setup" --schedule "0 4 * * *" --keep 3 \
    --login root --tag-datasets "$ZCI_POOL_SRC/data" $name
  conf=$conf_s; id=$(tr '/' '_' <<< "$conf"); log=/var/log/zsync-ci/setup.log
  check "Config: trigger=systemd" grep -qx 'trigger=systemd' "$conf"
  check "Config: Jobbenutzer als run_as" grep -qx 'run_as=zsync-zci-setup' "$conf"
  check "Config: Quelle mit Jobbenutzer" grep -qx "source=zsync-$sjob@localhost" "$conf"
  check "Config: neue Defaults (strict)" grep -qx 'zfs_auto_snapshot_label_match=strict' "$conf"
  equal "Tag gesetzt" all "$(prop "$ZCI_POOL_SRC/data" bashclub:zsync)"
  check "Jobbenutzer auf der Quelle mit command=" grep -q 'command="/usr/bin/bashclub-zsync-remote[ "]' "/var/lib/bashclub-zsync-source/$sjob/.ssh/authorized_keys"
  check "Rechte nur auf dem Ziel" grep -q "user zsync-zci-setup " <<< "$(zfs allow "$ZCI_POOL_DST/setup")"
  check "Timer aktiv" systemctl is-active --quiet bashclub-zsync@$name.timer
  systemctl start bashclub-zsync@$name.service
  equal "erster Lauf erfolgreich" success "$(systemctl show -p Result --value bashclub-zsync@$name.service)"
  equal "Lauf als Jobbenutzer" zsync-zci-setup "$(systemctl show -p User --value bashclub-zsync@$name.service)"
  equal "Setup: Ziel ohne mountpoint" none "$(prop "$ZCI_POOL_DST/setup" mountpoint)"
  check "Setup: Jobbenutzer ohne Recht auf mountpoint" not grep -qE "(^|,)mountpoint(,|$)" <<< "$(zfs allow "$ZCI_POOL_DST/setup" | awk '/user zsync-zci-setup/ { print $3 }')"
  equal "ein Snapshot repliziert" 1 "$(zfs list -H -o name -t snapshot "$ZCI_POOL_DST/setup/$ZCI_POOL_SRC/data" 2>/dev/null | wc -l)"
  check "nicht getaggtes Dataset nicht repliziert" not exists "$ZCI_POOL_DST/setup/$ZCI_POOL_SRC/other"
  # Schlüssel nur für die Snapshots, den Hold-Tag und das Bookmark dieses Jobs
  check "command= mit Label und Job-Tag" grep -qF -- "--label zsync-$host --job-tag zsync_${host}_$(tr / _ <<< "$ZCI_POOL_DST/setup")" "/var/lib/bashclub-zsync-source/$sjob/.ssh/authorized_keys"
  zfs snapshot "$ZCI_POOL_SRC/data@zfs-auto-snap_daily-2026-01-01-0000"; zfs snapshot "$ZCI_POOL_SRC/data@zsync-$host-2000-01-01-0000"
  local ssh_job="ssh -o BatchMode=yes zsync-$sjob@localhost"
  check "fremder Snapshot nicht löschbar" not su - zsync-zci-setup -c "$ssh_job zfs destroy $ZCI_POOL_SRC/data@zfs-auto-snap_daily-2026-01-01-0000"
  check "fremder Snapshot noch da" exists "$ZCI_POOL_SRC/data@zfs-auto-snap_daily-2026-01-01-0000"
  check "eigener Snapshot löschbar" su - zsync-zci-setup -c "$ssh_job zfs destroy $ZCI_POOL_SRC/data@zsync-$host-2000-01-01-0000"
  check "fremder Hold-Tag abgewiesen" not su - zsync-zci-setup -c "$ssh_job zfs release other-tag $ZCI_POOL_SRC/data@zfs-auto-snap_daily-2026-01-01-0000"
  check "Bookmark des Jobs angelegt" grep -q "#zsync_${host}_" <<< "$(zfs list -H -o name -t bookmark -r "$ZCI_POOL_SRC")"
  check "vorhandene Config wird nicht überschrieben" not bashclub-zsync-setup -y -s localhost $name
  zfs create -o mountpoint=/zci/mounted "$ZCI_POOL_DST/mounted"
  check "Ziel mit mountpoint für Jobbenutzer abgewiesen" not bashclub-zsync-setup -y -s localhost -t "$ZCI_POOL_DST/mounted" --login root zci-setup6
  check "abgewiesen, bevor etwas angelegt wird" not test -e /etc/bashclub/zci-setup6.conf
  # Verwaltungsbenutzer zsync: Schlüssel von root eintragen, Einrichtung ohne root auf der Quelle
  local rootkey; rootkey=$(cat /root/.ssh/id_ed25519.pub)
  install -d -m 700 -o zsync -g zsync /var/lib/zsync/.ssh
  echo "from=\"127.0.0.1,::1\" $rootkey" > /var/lib/zsync/.ssh/authorized_keys; chown zsync: /var/lib/zsync/.ssh/authorized_keys
  check "Setup als Verwaltungsbenutzer" bashclub-zsync-setup -y -s localhost -t "$ZCI_POOL_DST/setup2" --login zsync zci-setup2
  check "Jobbenutzer über zsync angelegt" id "zsync-$(echo "$host-zci-setup2" | tr 'A-Z_.' 'a-z--' | cut -c1-26)"
  check "--tag-datasets nur als root" not bashclub-zsync-setup -y -s localhost -t "$ZCI_POOL_DST/setup3" --login zsync --tag-datasets "$ZCI_POOL_SRC/other" zci-setup3
  check "--tag-datasets abgewiesen, bevor etwas angelegt wird" not test -e /etc/bashclub/zci-setup3.conf
  # ungültige Eingaben: abgewiesen, bevor etwas angelegt wird
  local opt value
  while IFS=$'\t' read -r opt value; do
    check "ungültig abgewiesen: $opt $value" not bashclub-zsync-setup -y -s localhost --login root -t "$ZCI_POOL_DST/bad" "$opt" "$value" zci-bad
  done << 'EOT'
-s	pve1;id
-p	70000
-t	zci-dst/a$(id)
--tag	nocolon
--label	a b
--tag-datasets	zci-src/x;id
EOT
  check "nach ungültigen Eingaben keine Config" not test -e /etc/bashclub/zci-bad.conf
  check "nach ungültigen Eingaben kein Ziel" not exists "$ZCI_POOL_DST/bad"
  # Fragen: Antworten aus der Eingabe, Abbruch bei der Bestätigung ändert nichts
  local out; out=$(printf 'localhost\n2222\n\n\n0 5 * * *\n7\n\nn\n' | bashclub-zsync-setup zci-setup5 2>&1)
  check "Fragen: Antworten übernommen" grep -q "source         localhost (port 2222)" <<< "$out"
  check "Fragen: Zeitplan übernommen" grep -q "schedule       0 5 \* \* \*, snapshots zsync-$host (keep 7)" <<< "$out"
  check "Fragen: Abbruch ändert nichts" not test -e /etc/bashclub/zci-setup5.conf
  # --root im lokalen Modus: keine Jobbenutzer
  out=$(bashclub-zsync-setup -y -s local -t "$ZCI_POOL_DST/setup4" zci-setup4 2>&1); rc=$?
  equal "Setup lokal als root" 0 "$rc" || echo "$out" | tail -5 | sed 's/^/       /'
  check "lokal: source=local, run_as leer" grep -qx 'source=local' /etc/bashclub/zci-setup4.conf
  # aufräumen
  rm -f /var/lib/zsync/.ssh/authorized_keys
  remove_timer_configs /etc/bashclub/zci-setup*.conf
  for n in zci-setup zci-setup2 zci-setup3; do
    bashclub-zsync-job-user remove "$(echo "$host-$n" | tr 'A-Z_.' 'a-z--' | cut -c1-26)" > /dev/null 2>&1
    id "zsync-$n" > /dev/null 2>&1 && { pkill -u "zsync-$n"; sleep 1; userdel -r "zsync-$n"; }
  done
}
# Wechseldatenträger: Zielplatte vorbereiten (Auswahl, LUKS, Pool, udev-Regel, Config-Link), Anschließen mit
# zsync-autorun wie der Dienst (mail und udisksctl als Stubs: die Platte der VM wird nicht abgeschaltet)
case_disk() {
  local label=zci-usb uconf=/etc/bashclub/zci-usb.conf stub=/tmp/zci-stub rule=/etc/udev/rules.d/90-zsync-autorun-zci-usb.rules
  local key=/etc/bashclub/zci-usb.key real serial out part
  zpool destroy "$ZCI_POOL_DST"
  real=$(readlink -f "$ZCI_DISK_DST"); serial=$(lsblk -dno SERIAL "$real" | tr -d ' ')
  zfs create "$ZCI_POOL_SRC/data"; zfs set bashclub:zsync=all "$ZCI_POOL_SRC/data"; snap "$ZCI_POOL_SRC/data" 01
  # Config wie im README: Setup für einen Wechseldatenträger (kein Timer, Jobbenutzer auf der Quelle mit dem Schlüssel von root)
  check "Setup --autorun" bashclub-zsync-setup -y --autorun -s localhost --login root -t $label/backup $label
  check "Setup: trigger=autorun" grep -qx 'trigger=autorun' "$uconf"
  check "Setup: kein Timer" not systemctl is-active --quiet bashclub-zsync@$label.timer
  set_conf "$uconf" checkzfs_disabled 1
  out=$(bashclub-zsync-disk list)
  check "list: freie Platte" grep -q "^$ZCI_DISK_DST " <<< "$out"
  check "list: Platte im Pool fehlt" not grep -q "^$ZCI_DISK_SRC " <<< "$out"
  check "Platte im Pool abgewiesen" not bashclub-zsync-disk create "$ZCI_DISK_SRC" zci-x --yes --serial x
  check "falsche Seriennummer abgewiesen" not bashclub-zsync-disk create "$ZCI_DISK_DST" $label --yes --serial falsch
  check "falsche Bestätigung abgewiesen" not bashclub-zsync-disk create "$ZCI_DISK_DST" $label <<< "falsch"
  check "Abbruch ändert nichts" not test -e $rule
  check "Ziel der Config muss im Pool liegen" not bashclub-zsync-disk create "$ZCI_DISK_DST" zci-other --config zci-usb --yes --serial "$serial"
  # Passphrase (z. B. YubiKey) ohne Terminal aus der Eingabe
  check "Platte mit LUKS und Passphrase anlegen" bashclub-zsync-disk create "$ZCI_DISK_DST" $label --luks --passphrase --config zci-usb --yes --serial "$serial" <<< "zsync-ci-pass"
  part=$(lsblk -lnpo NAME,TYPE "$real" | awk '$2 == "part" { print $1; exit }')
  equal "LUKS2 mit Label" "crypto_LUKS $label" "$(blkid -s TYPE -o value "$part") $(blkid -s LABEL -o value "$part")"
  equal "Schlüsseldatei nur für root" 600 "$(stat -c %a $key)"
  check "Passphrase öffnet LUKS" cryptsetup open --test-passphrase "$part" <<< "zsync-ci-pass"
  check "udev-Regel mit UUID der Partition" grep -qF "ENV{ID_FS_UUID}==\"$(blkid -s UUID -o value "$part")\", ENV{SYSTEMD_WANTS}+=\"zsync-autorun@$label.service\"" $rule
  equal "Config verlinkt" "$uconf" "$(readlink /etc/default/zsync-autorun@$label)"
  check "Config: trigger=autorun" grep -qx 'trigger=autorun' "$uconf"
  check "Pool exportiert" not zpool list $label
  check "LUKS geschlossen" not test -e /dev/mapper/$label
  # Anschließen: zsync-autorun wie zsync-autorun@zci-usb.service
  rm -rf "$stub"; mkdir -p "$stub"
  printf '#!/bin/sh\necho "udisksctl $*" >> %s/calls\n' "$stub" > "$stub/udisksctl"
  printf '#!/bin/sh\necho "mail $*" >> %s/calls\ncat > /dev/null\n' "$stub" > "$stub/mail"
  chmod +x "$stub/udisksctl" "$stub/mail"
  echo "===== $(date +%T) zsync-autorun" >> /var/log/zsync-ci/disk.log
  PATH=$stub:$PATH zsync-autorun /etc/default/zsync-autorun@$label >> /var/log/zsync-ci/disk.log 2>&1; rc=$?
  equal "zsync-autorun: Exit-Code" 0 "$rc"
  check "Mail: Replikation erfolgreich" grep -q "^mail -s zsync-autorun - Replication succeeded for $label" "$stub/calls"
  check "Abschalten der ganzen Platte (nicht der Partition)" grep -qx "udisksctl power-off --block-device $real" "$stub/calls"
  check "Pool nach dem Lauf exportiert" not zpool list $label
  check "LUKS nach dem Lauf geschlossen" not test -e /dev/mapper/$label
  cryptsetup open --key-file $key "$part" $label && zpool import $label
  check "auf die Platte repliziert" test "$(zfs list -H -o name -t snapshot "$label/backup/$ZCI_POOL_SRC/data" 2>/dev/null | wc -l)" -ge 1
  zpool export $label; cryptsetup close $label
  # ohne LUKS: Regel mit der UUID des Pools
  rm -f $rule /etc/default/zsync-autorun@$label; udevadm control --reload
  check "Platte ohne LUKS anlegen" bashclub-zsync-disk create "$ZCI_DISK_DST" $label --yes --serial "$serial"
  part=$(lsblk -lnpo NAME,TYPE "$real" | awk '$2 == "part" { print $1; exit }')
  equal "Pool direkt auf der Partition" zfs_member "$(blkid -s TYPE -o value "$part")"
  check "udev-Regel mit UUID des Pools" grep -qF "ENV{ID_FS_UUID}==\"$(blkid -s UUID -o value "$part")\"" $rule
  # aufräumen: Regel zuerst, damit beim Löschen nichts startet
  rm -f $rule /etc/default/zsync-autorun@$label "$uconf" $key; udevadm control --reload
  bashclub-zsync-job-user remove "$(echo "$(hostname -s)-$label" | tr 'A-Z_.' 'a-z--' | cut -c1-26)" > /dev/null
  rm -rf "$stub"
  wipefs -qa "$part" "$real"
}
# fehlt der älteste Quell-Snapshot am Ziel, ist nur die Rotation blockiert: Warnung, Exit 0, Status cleanup_blocked
case_cleanup_blocked() {
  zfs create "$ZCI_POOL_SRC/data"; zfs set bashclub:zsync=all "$ZCI_POOL_SRC/data"
  for n in 01 02 03; do write "$ZCI_POOL_SRC/data" 1 f$n; snap "$ZCI_POOL_SRC/data" $n; done
  config cleanup_blocked; zsync
  zfs destroy "$ZCI_POOL_DST/cleanup_blocked/$ZCI_POOL_SRC/data@zfs-auto-snap_daily-01"
  snap "$ZCI_POOL_SRC/data" 04
  zsync
  equal "Exit-Code trotz blockierter Rotation" 0 "$rc"
  equal "Delta repliziert" "zfs-auto-snap_daily-02 zfs-auto-snap_daily-03 zfs-auto-snap_daily-04" "$(snaps "$ZCI_POOL_DST/cleanup_blocked/$ZCI_POOL_SRC/data")"
  check "Warnung im Log" grep -q "\[WARN\] $ZCI_POOL_SRC/data - the oldest source snapshot of interval daily" <(last_run_log)
  equal "Status des Datasets" cleanup_blocked "$(state_of "$ZCI_POOL_SRC/data")"
  check "Checkmk: WARN" grep -qE '^1 "zsync cleanup_blocked" .*rotation on the target blocked' <<< "$(check_output)"
}
# Quelle nicht erreichbar: sofort Exit 1, Fehler im Log und im Status, keine Replikation
case_source_unreachable() {
  zfs create "$ZCI_POOL_SRC/data"; zfs set bashclub:zsync=all "$ZCI_POOL_SRC/data"; snap "$ZCI_POOL_SRC/data" 01
  config source_unreachable; sed -i 's/^sshport=22$/sshport=1/' "$conf"
  zsync
  equal "Exit-Code" 1 "$rc"
  check "Fehler im Log" grep -q "\[ERROR\] source root@localhost (port 1) is not reachable" <(last_run_log)
  check "nichts repliziert" not exists "$ZCI_POOL_DST/source_unreachable/$ZCI_POOL_SRC/data"
  equal "Status: Lauf fehlgeschlagen" "rc=1" "$(grep '^rc=' "$(status_path last)")"
}
# Rechte der Ordner: Logs nur root (logrotate), Status-Ordner mit Sticky-Bit, je Benutzer ein eigener Ordner
case_permissions() {
  equal "Log-Ordner root:root 755" "root root 755" "$(stat -c '%U %G %a' /var/log/bashclub-zsync)"
  check "logrotate rotiert die Logs" not grep -q "insecure permissions" <<< "$(logrotate -d /etc/logrotate.d/bashclub-zsync 2>&1)"
  equal "Status-Ordner mit Sticky-Bit" "root bashclub-zsync 1775" "$(stat -c '%U %G %a' /var/lib/bashclub-zsync)"
  equal "Laufzeit-Ordner mit Sticky-Bit" "root bashclub-zsync 1775" "$(stat -c '%U %G %a' /run/bashclub-zsync)"
  equal "Ordner von root" "root root 755" "$(stat -c '%U %G %a' /var/lib/bashclub-zsync/root)"
  zfs create "$ZCI_POOL_SRC/data"; zfs set bashclub:zsync=all "$ZCI_POOL_SRC/data"; snap "$ZCI_POOL_SRC/data" 01
  config permissions; zsync
  equal "Lauf als root: Exit-Code" 0 "$rc"
  check "Status von root in seinem Ordner" test -f "/var/lib/bashclub-zsync/root/$id.last"
  check "keine Status-Datei im Basisordner" test -z "$(find /var/lib/bashclub-zsync /run/bashclub-zsync -maxdepth 1 -type f)"
}
case_checkmk() {
  zfs create "$ZCI_POOL_SRC/data"; zfs set bashclub:zsync=all "$ZCI_POOL_SRC/data"; snap "$ZCI_POOL_SRC/data" 01
  config checkmk; zsync
  local out; out=$(check_output)
  check "Service OK in der Lernphase ($out)" grep -qE '^0 "zsync checkmk" .*learning 0/5' <<< "$out"
  check "Statusdatei des Laufs entfernt" test -z "$(status_path state)"
}

all_cases=(replication engine_internal rotation refquota rollback broken_chain orphans local_mode bandwidth_lock bookmark hold deleted_during resume unprivileged timer same_second restricted job_user setup disk cleanup_blocked source_unreachable permissions checkmk)
cases=("${@:-${all_cases[@]}}")
safety
# ein Lauf zur Zeit (CI und remote.sh teilen sich Platten und Pools): ein zweiter wartet
exec 9> /run/lock/zsync-ci.lock
flock 9 || { echo "Sperre /run/lock/zsync-ci.lock nicht erhalten"; exit 2; }
rm -rf /var/log/zsync-ci
echo "bashclub-zsync $(dpkg-query -W -f='${Version}' bashclub-zsync 2>/dev/null), $(zfs version | head -1)"
skipped_cases=()
for c in "${cases[@]}"; do
  echo "### $c"
  case_failed=0; case_skipped=0
  reset_pools
  "case_$c"
  if [ $case_skipped -ne 0 ] && [ $case_failed -eq 0 ]; then skipped_cases+=("$c"); fi
  if [ $case_failed -ne 0 ]; then
    failed_cases+=("$c")
    echo "  Log: /var/log/zsync-ci/$c.log"
  fi
done
cleanup_pools
echo "### Ergebnis: $(( ${#cases[@]} - ${#failed_cases[@]} - ${#skipped_cases[@]} ))/${#cases[@]} Fälle bestanden${skipped_cases:+, übersprungen: ${skipped_cases[*]}}${failed_cases:+, fehlgeschlagen: ${failed_cases[*]}}"
[ ${#failed_cases[@]} -eq 0 ]
