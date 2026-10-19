#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
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
  # min_keep stoppt das Löschen: die ältesten gehen zuerst, die neuesten bleiben (GitHub-PR #3)
  set_conf "$conf" min_keep 3
  for n in 05 06 07; do write "$ZCI_POOL_SRC/data" 1 f$n; snap "$ZCI_POOL_SRC/data" $n; done
  zsync
  for n in 03 04 05 06; do zfs destroy "$ZCI_POOL_SRC/data@zfs-auto-snap_daily-$n"; done
  write "$ZCI_POOL_SRC/data" 1 f08; snap "$ZCI_POOL_SRC/data" 08
  zsync
  equal "min_keep: Exit-Code" 0 "$rc"
  equal "min_keep: die neuesten bleiben" "zfs-auto-snap_daily-06 zfs-auto-snap_daily-07 zfs-auto-snap_daily-08" "$(snaps "$ZCI_POOL_DST/rotation/$ZCI_POOL_SRC/data")"
}

# nichts auf der Quelle ausgewählt: Warnung im Log, kein Bash-Fehler, Exit 0, Monitoring WARN
case_nothing_selected() {
  zfs create "$ZCI_POOL_SRC/data"
  config nothing_selected; zsync
  equal "Exit-Code" 0 "$rc"
  check "Warnung im Log" grep -q '\[WARN\] no dataset on root@localhost is selected for the replication' <(last_run_log)
  check "kein Bash-Fehler" not grep -q 'substring expression' <(last_run_log)
  equal "Status: 0 Datasets" "datasets=0" "$(grep '^datasets=' "$(status_path last)")"
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

# Rollback auf der Quelle: neue Kette per Klon, die alte bleibt als Zweig, nichts wird gelöscht; Kind-Datasets bleiben
# an der neuen Kette, auch raw verschlüsselt; Entscheidung über den Zweig im Wartungswerkzeug
case_rollback() {
  local d="$ZCI_POOL_DST/rollback/$ZCI_POOL_SRC" branch list
  zfs create "$ZCI_POOL_SRC/data"; zfs create "$ZCI_POOL_SRC/data/child"
  echo "zsync-ci-passphrase" | zfs create -o encryption=on -o keyformat=passphrase "$ZCI_POOL_SRC/enc"
  for c in data enc; do zfs set bashclub:zsync=all "$ZCI_POOL_SRC/$c"; done
  for n in 01 02 03; do for c in data data/child enc; do write "$ZCI_POOL_SRC/$c" 1 f$n; snap "$ZCI_POOL_SRC/$c" $n; done; done
  config rollback "source_bookmark=1"; zsync
  zfs set compression=zstd "$d/data"
  for c in data enc; do zfs rollback -r "$ZCI_POOL_SRC/$c@zfs-auto-snap_daily-01"; write "$ZCI_POOL_SRC/$c" 1 f04; snap "$ZCI_POOL_SRC/$c" 04; done
  snap "$ZCI_POOL_SRC/data/child" 04
  zsync
  equal "Exit-Code" 0 "$rc"
  equal "neue Kette ab dem gemeinsamen Snapshot" "zfs-auto-snap_daily-01 zfs-auto-snap_daily-04" "$(snaps "$d/data")"
  equal "verschlüsselt: neue Kette" "zfs-auto-snap_daily-01 zfs-auto-snap_daily-04" "$(snaps "$d/enc")"
  branch=$(zfs list -H -o name -d 1 "$d" | grep '/data\.zsync-branch-')
  check "alter Zweig vorhanden ($branch)" test -n "$branch"
  equal "alter Zweig mit allen Snapshots" "zfs-auto-snap_daily-02 zfs-auto-snap_daily-03" "$(snaps "$branch")"
  check "Zweig markiert" grep -q "newest common snapshot zfs-auto-snap_daily-01" <<< "$(prop "$branch" bashclub:zsync-branch)"
  check "verschlüsselt: alter Zweig vorhanden" test -n "$(zfs list -H -o name -d 1 "$d" | grep '/enc\.zsync-branch-')"
  equal "Kind unter der neuen Kette weiterrepliziert" "zfs-auto-snap_daily-01 zfs-auto-snap_daily-02 zfs-auto-snap_daily-03 zfs-auto-snap_daily-04" "$(snaps "$d/data/child")"
  equal "Eigenschaften übernommen" zstd "$(prop "$d/data" compression)"
  equal "Zustand der neuen Kette" branched "$(state_of "$ZCI_POOL_SRC/data")"
  equal "Zustand des alten Zweigs" branch "$(state_of "${branch#$ZCI_POOL_DST/rollback/}")"
  check "kein Anfügen aus einem Bookmark nach Rollback" not grep -q 'continuing from the bookmark' "$log"
  check "Checkmk: WARN zum alten Zweig" grep -qE '^1 "zsync rollback" .*old chain after a rollback on the source' <<< "$(check_output)"
  # Entscheidung: alten Zweig löschen
  list=$(ZSYNC_CONF_DIR=$CONF_DIR bashclub-zsync-maintenance --list --tsv)
  local case_id; case_id=$(awk -F'\t' -v r="$branch" '$3 == "branch" && $4 == r { print $1 }' <<< "$list")
  check "Fall alter Zweig im Wartungswerkzeug" test -n "$case_id"
  check "alten Zweig löschen" env ZSYNC_CONF_DIR=$CONF_DIR bashclub-zsync-maintenance --decide "$case_id" delete
  check "alter Zweig gelöscht" not exists "$branch"
  zsync
  equal "nächster Lauf: Exit-Code" 0 "$rc"
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
  check "Rechte auf dem Ziel" zfs allow -u $user "create,receive,mount,destroy,rollback,clone,promote,rename,hold,release,userprop,$ZCI_RECV_PROPS" "$ZCI_POOL_DST/unprivileged"
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
  # Rollback auf der Quelle ohne root: neue Kette per Klon mit den Rechten clone, promote, rename
  zfs rollback -r "$ZCI_POOL_SRC/subvol-100-disk-0@$(snaps "$ZCI_POOL_SRC/subvol-100-disk-0" | cut -d' ' -f1)"
  sleep 61   # der Lauf legt einen neuen Snapshot mit eigenem Namen pro Minute an (remote-snapshot-manager)
  su - $user -c "bashclub-zsync -c $conf" >> "$log" 2>&1; rc=$?
  equal "ohne root nach Rollback: Exit-Code" 0 "$rc"
  check "ohne root: alter Zweig angelegt" test -n "$(zfs list -H -o name -d 1 "$ZCI_POOL_DST/unprivileged/$ZCI_POOL_SRC" | grep 'subvol-100-disk-0\.zsync-branch-')"
  equal "ohne root: neue Kette weiterrepliziert" "$(snaps "$ZCI_POOL_SRC/subvol-100-disk-0" | awk '{ print $NF }')" "$(snaps "$ZCI_POOL_DST/unprivileged/$ZCI_POOL_SRC/subvol-100-disk-0" | awk '{ print $NF }')"
  check "Status im eigenen Ordner des Benutzers" test -f "$LIB_DIR/$user/$id.last"
  check "Checkmk: Service aus dem Ordner des Benutzers" grep -q '"zsync unprivileged"' <<< "$("$CHECK")"
  # -s als root für eine Config mit run_as: läuft als dieser Benutzer (sein Schlüssel für checkzfs auf der Quelle),
  # die Spool-Datei gehört ihm, sein nächster Lauf kann sie ersetzen
  local spool=/var/lib/check_mk_agent/spool/87000_zsync out
  set_conf "$conf" run_as $user; set_conf "$conf" checkzfs_disabled 0
  rm -f "$spool"
  out=$(bashclub-zsync -c "$conf" -s 2>&1); echo "$out" >> "$log"
  check "-s als root: keine Anmeldung als root an der Quelle" not grep -qi 'permission denied' <<< "$out"
  check "-s als root: checkzfs-Service in der Ausgabe" grep -q "$ZCI_POOL_SRC/subvol-100-disk-0" <<< "$out"
  equal "-s als root: Spool-Datei gehört $user" "$user" "$(stat -c %U "$spool" 2>/dev/null)"
  echo "===== $(date +%T) als $user nach -s von root" >> "$log"
  su - $user -c "bashclub-zsync -c $conf" >> "$log" 2>&1; rc=$?
  equal "Lauf als $user nach -s von root: Exit-Code" 0 "$rc"
  check "Lauf als $user ersetzt die Spool-Datei" not grep -q 'Operation not permitted' <(last_run_log)
  set_conf "$conf" checkzfs_disabled 1; sed -i '/^run_as=/d' "$conf"
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
  zfs allow -u $user "create,receive,mount,destroy,rollback,clone,promote,rename,hold,release,userprop,$ZCI_RECV_PROPS" "$ZCI_POOL_DST/restricted"
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
  zfs allow -u $backup "create,receive,mount,destroy,rollback,clone,promote,rename,hold,release,userprop,$ZCI_RECV_PROPS" "$ZCI_POOL_DST/job_user"
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
  local out; out=$(printf 'localhost\n2222\n\n\n0 5 * * *\n7\n\n\nn\n' | bashclub-zsync-setup zci-setup5 2>&1)
  check "Fragen: Antworten übernommen" grep -q "source         localhost (port 2222)" <<< "$out"
  check "Fragen: Zeitplan übernommen" grep -q "schedule       0 5 \* \* \*, snapshots zsync-$host (keep 7)" <<< "$out"
  check "Fragen: Abbruch ändert nichts" not test -e /etc/bashclub/zci-setup5.conf
  # --root im lokalen Modus: keine Jobbenutzer
  out=$(bashclub-zsync-setup -y -s local -t "$ZCI_POOL_DST/setup4" zci-setup4 2>&1); rc=$?
  equal "Setup lokal als root" 0 "$rc" || echo "$out" | tail -5 | sed 's/^/       /'
  check "lokal: source=local, run_as leer" grep -qx 'source=local' /etc/bashclub/zci-setup4.conf
  # von einem anderen Werkzeug gestartet (Miyagi): trigger=external, kein Timer, ausgegebener Befehl läuft als Jobbenutzer
  out=$(bashclub-zsync-setup -y -s localhost -t "$ZCI_POOL_DST/setup7" --login root --external zci-setup7 2>&1); rc=$?
  equal "Setup --external" 0 "$rc" || echo "$out" | tail -5 | sed 's/^/       /'
  check "external: trigger=external" grep -qx 'trigger=external' /etc/bashclub/zci-setup7.conf
  check "external: Jobbenutzer als run_as" grep -qx 'run_as=zsync-zci-setup7' /etc/bashclub/zci-setup7.conf
  check "external: kein Timer" not systemctl is-active --quiet bashclub-zsync@zci-setup7.timer
  check "external: Timer-Liste zeigt external" grep -qE '^zci-setup7 +external ' <<< "$(bashclub-zsync-timer list)"
  local ext_cmd; ext_cmd=$(grep '^    runuser -u zsync-zci-setup7 -- bashclub-zsync -c /etc/bashclub/zci-setup7.conf$' <<< "$out" | sed 's/^ *//')
  check "external: Befehl für das Werkzeug ausgegeben ($out)" test -n "$ext_cmd"
  bash -c "$ext_cmd" >> "$log" 2>&1; rc=$?
  equal "external: Lauf mit dem ausgegebenen Befehl" 0 "$rc"
  check "external: repliziert" test "$(zfs list -H -o name -t snapshot "$ZCI_POOL_DST/setup7/$ZCI_POOL_SRC/data" 2>/dev/null | wc -l)" -ge 1
  check "--autorun und --external zusammen abgewiesen" not bashclub-zsync-setup -y -s localhost --login root --autorun --external zci-setup8
  # aufräumen
  rm -f /var/lib/zsync/.ssh/authorized_keys
  remove_timer_configs /etc/bashclub/zci-setup*.conf
  for n in zci-setup zci-setup2 zci-setup3 zci-setup7; do
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
# Engine zas ohne zfs-auto-snapshot auf der Quelle: Warnung, Exit-Code wie bisher
case_zas_missing() {
  local zas; zas=$(command -v zfs-auto-snapshot)
  zfs create "$ZCI_POOL_SRC/data"; zfs set bashclub:zsync=all "$ZCI_POOL_SRC/data"; snap "$ZCI_POOL_SRC/data" 01
  config zas_missing "zfs_auto_snapshot_engine=zas
zfs_auto_snapshot_keep=3"
  zsync
  check "mit zfs-auto-snapshot: keine Warnung" not grep -q "zfs-auto-snapshot is not installed" <(last_run_log)
  mv "$zas" "$zas.zci-hidden"
  zsync; local zrc=$rc
  mv "$zas.zci-hidden" "$zas"
  equal "ohne zfs-auto-snapshot: Exit-Code wie bisher" 0 "$zrc"
  check "ohne zfs-auto-snapshot: Warnung mit Hinweis" grep -q "zfs-auto-snapshot is not installed on the source" <(last_run_log)
}
# Entscheidungen: verwaistes Replikat, gerissene Kette, Snapshot-Altlast; Aktionen mit Vorschau, Sperre und Protokoll
case_maintenance() {
  local m=bashclub-zsync-maintenance mlog=/var/log/bashclub-zsync/maintenance.log list c T=$ZCI_POOL_DST/maintenance/$ZCI_POOL_SRC
  for c in data gone gone/sub broken other; do zfs create "$ZCI_POOL_SRC/$c"; snap "$ZCI_POOL_SRC/$c" 01; done
  for c in data gone broken other; do zfs set bashclub:zsync=all "$ZCI_POOL_SRC/$c"; done
  # legacy: ein Snapshot des Labels im Schema von zas wird mitrepliziert und ist am Ziel eine Altlast (wie bei einem
  # Wechsel der Engine)
  config maintenance "zfs_auto_snapshot_keep=3
zfs_auto_snapshot_label_match=legacy"
  zsync
  equal "Erstreplikation" 0 "$rc"
  zfs destroy -r "$ZCI_POOL_SRC/gone"; zfs destroy -r "$ZCI_POOL_SRC/other"
  zfs list -H -o name -t snapshot "$ZCI_POOL_SRC/broken" | xargs -n1 zfs destroy
  snap "$ZCI_POOL_SRC/broken" 02
  zfs snapshot "$ZCI_POOL_SRC/data@zfs-auto-snap_backup-2026-01-01-0000"
  zsync
  # zsync markiert die Fälle am Replikat
  check "Markierung orphan" grep -q "^orphan;[0-9]*;$conf;" <<< "$(prop "$T/gone" bashclub:zsync-case)"
  check "Markierung am Kind (eigener Fall)" grep -q "^orphan;" <<< "$(zfs get -H -o value -s local bashclub:zsync-case "$T/gone/sub")"
  check "Markierung broken" grep -q "^broken;" <<< "$(prop "$T/broken" bashclub:zsync-case)"
  check "Markierung leftovers mit Anzahl" grep -q "^leftovers;.*;1 snapshots of the label" <<< "$(prop "$T/data" bashclub:zsync-case)"
  local before; before=$(zfs get -H -p -o value written "$T/gone")
  list=$(ZSYNC_CONF_DIR=$CONF_DIR $m --list --tsv)
  equal "fünf Fälle (tsv: auch das Kind)" 5 "$(grep -c . <<< "$list")"
  local orphan broken left
  orphan=$(awk -F'\t' -v d="$T/gone" '$3 == "orphan" && $4 == d { print $1 }' <<< "$list")
  broken=$(awk -F'\t' '$3 == "broken" { print $1 }' <<< "$list")
  left=$(awk -F'\t' '$3 == "leftovers" { print $1 }' <<< "$list")
  check "Fall verwaistes Replikat" test -n "$orphan"
  check "Fall gerissene Kette" test -n "$broken"
  check "Fall Snapshot-Altlast" test -n "$left"
  check "Übersicht: Kind unter dem Elternteil" grep -qE "$T/gone \+1 " <<< "$(ZSYNC_CONF_DIR=$CONF_DIR $m --list)"
  # Übersicht, dann „alle später“ (Standard): nichts ändert sich
  local out; out=$(printf '\n' | ZSYNC_CONF_DIR=$CONF_DIR $m 2>&1)
  check "Übersicht vor der Frage ($out)" grep -q "^case 4: " <<< "$out"
  check "Übersicht: Anzahl je Typ" grep -q "2 x orphan" <<< "$out"
  equal "alle später ändert nichts" 5 "$(ZSYNC_CONF_DIR=$CONF_DIR $m --list --tsv | grep -c .)"
  # einzeln: bisheriger Ablauf, leere Antworten = später
  out=$(printf '3\n\n\n\n\n' | ZSYNC_CONF_DIR=$CONF_DIR $m 2>&1)
  check "einzeln: vier Fälle nacheinander" grep -q '^\[4/4\]' <<< "$out"
  check "Probelauf zeigt den Befehl" grep -q "zfs rename $T/broken" <<< "$(ZSYNC_CONF_DIR=$CONF_DIR $m --decide "$broken" rename --dry-run)"
  check "Probelauf ändert nichts" exists "$T/broken"
  check "unbekannte Option abgewiesen" not env ZSYNC_CONF_DIR=$CONF_DIR $m --decide "$orphan" rename
  # je Typ ohne Fragen: Vorschau der ganzen Gruppe
  out=$(ZSYNC_CONF_DIR=$CONF_DIR $m --decide-type orphan delete --dry-run 2>&1)
  check "je Typ: Vorschau der Gruppe ($out)" grep -q "delete for all 2 cases of type orphan" <<< "$out"
  check "je Typ: Platz zusammen" grep -q "together .* used" <<< "$out"
  check "je Typ: Probelauf ändert nichts" exists "$T/other"
  # während eines Laufs (Sperre der Config) wird nichts ausgeführt
  flock "$conf" sleep 5 & sleep 1
  check "während eines Laufs abgewiesen" not env ZSYNC_CONF_DIR=$CONF_DIR $m --decide "$orphan" keep
  wait
  # je Typ im geführten Modus: orphan behalten (beide), broken umbenennen, Altlast löschen
  out=$(printf '2\n1\ny\n1\ny\n1\ny\n' | ZSYNC_CONF_DIR=$CONF_DIR $m 2>&1); echo "$out" >> "$log"
  equal "orphan behalten: Markierung" keep "$(prop "$T/gone" bashclub:zsync-orphan)"
  equal "orphan behalten: auch das zweite" keep "$(prop "$T/other" bashclub:zsync-orphan)"
  check "gerissene Kette umbenannt" exists "$T/broken.broken-$(date +%Y-%m-%d)"
  equal "umbenannte Kette ohne Markierung" "" "$(zfs get -H -o value -s local bashclub:zsync-case "$T/broken.broken-$(date +%Y-%m-%d)")"
  check "Altlast weg" not exists "$T/data@zfs-auto-snap_backup-2026-01-01-0000"
  equal "Altlast: Markierung entfernt" "" "$(zfs get -H -o value -s local bashclub:zsync-case "$T/data")"
  equal "keine offenen Fälle mehr" "no open cases" "$(ZSYNC_CONF_DIR=$CONF_DIR $m --list)"
  check "Entscheidungen einzeln protokolliert" test "$(grep -c "case \($orphan\|$broken\|$left\)" "$mlog")" -ge 3
  # die Quelle löscht die Altlast auch (sonst käme sie mit dem nächsten Delta wieder)
  zfs destroy "$ZCI_POOL_SRC/data@zfs-auto-snap_backup-2026-01-01-0000"
  zsync
  check "nächster Lauf repliziert die umbenannte Kette neu" exists "$T/broken@zfs-auto-snap_daily-02"
  equal "behaltenes Replikat: Markierung vom Lauf entfernt" "" "$(zfs get -H -o value -s local bashclub:zsync-case "$T/gone")"
  equal "Altlast: nach dem Lauf ohne Markierung" "" "$(zfs get -H -o value -s local bashclub:zsync-case "$T/data")"
}
# Anzahl am Backupserver je Label (snapshot_filter="daily=3"): unabhängig davon, was die Quelle löscht; daily ohne Zahl
# folgt der Quelle wie bisher
case_keep_count() {
  local d="$ZCI_POOL_DST/keep_count/$ZCI_POOL_SRC"
  zfs create "$ZCI_POOL_SRC/data"; zfs set bashclub:zsync=all "$ZCI_POOL_SRC/data"
  zfs create "$ZCI_POOL_SRC/legacy"; zfs set bashclub:zsync=all "$ZCI_POOL_SRC/legacy"
  for n in 01 02 03 04 05; do snap "$ZCI_POOL_SRC/data" $n; done
  config keep_count 'snapshot_filter="daily=3"'
  zsync
  equal "Exit-Code" 0 "$rc"
  equal "die 3 neuesten bleiben" "zfs-auto-snap_daily-03 zfs-auto-snap_daily-04 zfs-auto-snap_daily-05" "$(snaps "$d/data")"
  # Angreifer löscht auf der Quelle alles bis auf den neuesten Snapshot
  for n in 01 02 03 04; do zfs destroy "$ZCI_POOL_SRC/data@zfs-auto-snap_daily-$n"; done
  snap "$ZCI_POOL_SRC/data" 06
  zsync
  equal "Löschen auf der Quelle verkleinert das Backup nicht" "zfs-auto-snap_daily-04 zfs-auto-snap_daily-05 zfs-auto-snap_daily-06" "$(snaps "$d/data")"
  check "kein Fehler zur Rotation" not grep -q "no snapshots of this interval are deleted" <(last_run_log)
  # daily=source: wie bisher folgt das Ziel der Quelle (min_keep=1 aus der Config des Tests)
  for n in 01 02 03; do snap "$ZCI_POOL_SRC/legacy" $n; done
  sed -i 's/^snapshot_filter=.*/snapshot_filter="daily=source"/' "$conf"
  zsync
  zfs destroy "$ZCI_POOL_SRC/legacy@zfs-auto-snap_daily-01"; snap "$ZCI_POOL_SRC/legacy" 04
  zsync
  equal "daily=source folgt der Quelle" "zfs-auto-snap_daily-02 zfs-auto-snap_daily-03 zfs-auto-snap_daily-04" "$(snaps "$d/legacy")"
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
  equal "Config-Ordner nur für root" "root root 755" "$(stat -c '%U %G %a' /etc/bashclub)"
  equal "doc-Ordner gehört root" "root root" "$(stat -c '%U %G' /usr/share/doc/bashclub-zsync)"
  zfs create "$ZCI_POOL_SRC/data"; zfs set bashclub:zsync=all "$ZCI_POOL_SRC/data"; snap "$ZCI_POOL_SRC/data" 01
  config permissions; zsync
  equal "Lauf als root: Exit-Code" 0 "$rc"
  check "Status von root in seinem Ordner" test -f "/var/lib/bashclub-zsync/root/$id.last"
  check "keine Status-Datei im Basisordner" test -z "$(find /var/lib/bashclub-zsync /run/bashclub-zsync -maxdepth 1 -type f)"
}
case_checkmk() {
  # eine Spool-Datei je Lauf unter dem Namen von checkzfs: <maxage>_<checkzfs_prefix>
  local spool=/var/lib/check_mk_agent/spool/87000_zsync out before mid host
  local old1=/var/lib/check_mk_agent/spool/87000_bashclub-zsync-checkmk old2
  host=$(hostname -s); old2=/var/lib/check_mk_agent/spool/87000_bashclub-zsync-$host-checkmk
  zfs create "$ZCI_POOL_SRC/data"; zfs set bashclub:zsync=all "$ZCI_POOL_SRC/data"; snap "$ZCI_POOL_SRC/data" 01
  # Dateien der testing-Versionen mit eigenem Namen für den Status
  echo '0 "zsync checkmk" - alt' > $old1; echo '0 "zsync x checkmk" - alt' > $old2
  config checkmk; rm -f $spool; zsync
  check "alte Status-Dateien der testing-Versionen entfernt" not test -e $old1 -o -e $old2
  out=$(check_output)
  check "Service OK in der Lernphase ($out)" grep -qE '^0 "zsync checkmk" .*learning 0/5' <<< "$out"
  check "Statusdatei des Laufs entfernt" test -z "$(status_path state)"
  # Ergebnis des Laufs als Spool-Datei, kein local check mehr
  check "Spool-Datei nach dem Lauf" grep -qE '^0 "zsync checkmk"' $spool
  check "Spool-Datei mit Abschnitt local" grep -qx '<<<local>>>' $spool
  check "kein Link als local check" not test -L /usr/lib/check_mk_agent/local/bashclub_zsync
  # -s: Spool und Anzeige, ohne Lauf (Status-Dateien unverändert)
  before=$(cat "$(status_path last)" "$(status_path history)" | md5sum)
  rm -f $spool
  out=$(bashclub-zsync -c "$conf" -s 2>&1); rc=$?
  equal "-s: Exit-Code" 0 "$rc"
  check "-s: lesbare Ausgabe ($out)" grep -qE '^OK +zsync checkmk +last successful run' <<< "$out"
  check "-s: Spool neu geschrieben" grep -qE '^0 "zsync checkmk"' $spool
  equal "-s: Laufstatus unverändert" "$before" "$(cat "$(status_path last)" "$(status_path history)" | md5sum)"
  check "-s checkmk: Rohformat" grep -qE '^0 "zsync checkmk" ' <<< "$(bashclub-zsync -c "$conf" -s checkmk 2>/dev/null)"
  check "-s ohne -c: alle Configs (hier keine unter /etc/bashclub)" bashclub-zsync -s
  # Watchdog: während eines langsamen Laufs wird der Spool laufend geschrieben
  write "$ZCI_POOL_SRC/data" 6 big; snap "$ZCI_POOL_SRC/data" 02
  echo "bandwidth_limit=1m" >> "$conf"; rm -f $spool
  ZSYNC_WATCHDOG_INTERVAL=1 bashclub-zsync -c "$conf" >> "$log" 2>&1 &
  sleep 4; mid=$(cat $spool 2>/dev/null); wait
  check "Watchdog: Spool während des Laufs ($mid)" grep -q 'running for' <<< "$mid"
  check "nach dem Lauf: endgültiger Stand" not grep -q 'running for' $spool
  sed -i '/^bandwidth_limit=/d' "$conf"
  # mit checkzfs: checkzfs-Services und Laufstatus in derselben Datei; -s führt checkzfs aus (#106)
  set_conf "$conf" checkzfs_disabled 0
  rm -f $spool; zsync
  check "eine Datei: checkzfs-Service" grep -q "$ZCI_POOL_SRC/data" $spool
  check "eine Datei: Laufstatus" grep -qE '^0 "zsync checkmk"' $spool
  equal "eine Datei: ein Abschnitt" 1 "$(grep -c '^<<<local>>>' $spool)"
  rm -f $spool
  out=$(bashclub-zsync -c "$conf" -s 2>&1); rc=$?
  echo "$out" >> "$log"
  check "-s mit checkzfs: keine Meldung command not found ($out)" not grep -q "command not found" <<< "$out"
  check "-s mit checkzfs: checkzfs-Service in der Datei" grep -q "$ZCI_POOL_SRC/data" $spool
  check "-s mit checkzfs: Laufstatus in der Datei" grep -qE '^0 "zsync checkmk"' $spool
  check "-s mit checkzfs: checkzfs-Services in der Ausgabe" grep -q "$ZCI_POOL_SRC/data" <<< "$out"
  # Watchdog: schreibt die checkzfs-Services des letzten Laufs mit, sie verschwinden während eines Laufs nicht
  write "$ZCI_POOL_SRC/data" 6 big2; snap "$ZCI_POOL_SRC/data" 03
  echo "bandwidth_limit=1m" >> "$conf"
  ZSYNC_WATCHDOG_INTERVAL=1 bashclub-zsync -c "$conf" >> "$log" 2>&1 &
  sleep 4; mid=$(cat $spool 2>/dev/null); wait
  check "Watchdog: Laufstatus während des Laufs ($mid)" grep -q 'running for' <<< "$mid"
  check "Watchdog: checkzfs-Services bleiben" grep -q "$ZCI_POOL_SRC/data" <<< "$mid"
  sed -i '/^bandwidth_limit=/d' "$conf"
  # Spool auf der Quelle (hier derselbe Host), anderer Prefix: Datei und Service mit dem Prefix
  local onsource=/var/lib/check_mk_agent/spool/87000_backup1
  set_conf "$conf" checkzfs_spool 1; set_conf "$conf" checkzfs_prefix backup1
  rm -f $onsource $spool; zsync
  check "Prefix: Laufstatus als <prefix> <config>" grep -qE '^0 "backup1 checkmk"' $onsource
  check "Prefix: checkzfs-Service in derselben Datei" grep -q "$ZCI_POOL_SRC/data" $onsource
  check "Prefix: keine Datei unter dem Standard-Prefix" not test -e $spool
  out=$(bashclub-zsync -c "$conf" -s 2>&1)
  check "-s: Service mit Prefix ($out)" grep -qE "^OK +backup1 checkmk " <<< "$out"
  rm -f $onsource $spool
}

# Restore-Zugang: Pull-Benutzer liest nur die Replikate seiner Config, Push-Key mit Ablaufdatum; die ausgegebenen
# Befehle werden so ausgeführt, wie sie ausgegeben werden (kopierbar)
case_restore_access() {
  local r=bashclub-zsync-restore key=/root/zci-restore-pull-key out cmd user=zsync-restore-restore-access ak=/root/.ssh/authorized_keys
  zfs create "$ZCI_POOL_SRC/data"; zfs set bashclub:zsync=all "$ZCI_POOL_SRC/data"
  write "$ZCI_POOL_SRC/data" 1; snap "$ZCI_POOL_SRC/data" 01
  zfs create "$ZCI_POOL_DST/other"; zfs snapshot "$ZCI_POOL_DST/other@x"
  config restore_access; zsync
  local replica=$ZCI_POOL_DST/restore_access/$ZCI_POOL_SRC/data
  check "Replikat vorhanden" exists "$replica@zfs-auto-snap_daily-01"
  # Pull: Schlüssel des wiederherzustellenden Systems, Befehl für den Backupserver, Config per Auswahl
  rm -f $key $key.pub
  out=$(ZSYNC_RESTORE_PULL_KEY=$key $r access key 127.0.0.1)
  check "access key: Schlüssel angelegt" test -f $key
  cmd=$(grep "access pull" <<< "$out" | sed 's/^ *//')
  equal "access key: Befehl für den Backupserver" "bashclub-zsync-restore access pull 127.0.0.1 '$(cut -d' ' -f1-3 $key.pub)'" "$cmd"
  local n; n=$(ls "$CONF_DIR"/*.conf | xargs -n1 basename | sed 's/\.conf$//' | grep -nx restore_access | cut -d: -f1)
  out=$(echo "$n" | ZSYNC_CONF_DIR=$CONF_DIR bash -c "$cmd" 2>&1)
  check "access pull: Benutzer angelegt ($out)" user_exists $user
  check "access pull: zfs allow send,hold,release" grep -qE "user $user hold,release,send" <<< "$(zfs allow "$ZCI_POOL_DST/restore_access")"
  equal "access pull: Schlüssel mit restrict, from und command" "restrict,from=\"127.0.0.1\",command=\"/usr/bin/bashclub-zsync-restore-remote --root $ZCI_POOL_DST/restore_access\" ssh-ed25519" \
    "$(cut -d' ' -f1-4 /var/lib/bashclub-zsync-restore-users/restore-access/.ssh/authorized_keys)"
  cmd=$(grep "access test" <<< "$out" | sed 's/^ *//')
  out=$(ZSYNC_RESTORE_PULL_KEY=$key bash -c "$cmd" 2>&1)
  equal "access test (pull)" "$user@127.0.0.1: connected, may read $ZCI_POOL_DST/restore_access" "$out"
  local s="ssh -o BatchMode=yes -o IdentitiesOnly=yes -i $key $user@127.0.0.1"
  check "Pull: Replikat lesbar" test "$($s zfs list -H -o name -t snapshot $replica)" == "$replica@zfs-auto-snap_daily-01"
  check "Pull: send unter der Config" bash -c "$s zfs send -w $replica@zfs-auto-snap_daily-01 > /dev/null"
  check "Pull: hold und release mit Restore-Tag" $s zfs hold zsync-restore-ci $replica@zfs-auto-snap_daily-01
  check "Pull: release" $s zfs release zsync-restore-ci $replica@zfs-auto-snap_daily-01
  check "Pull: fremdes Dataset nicht lesbar" not $s zfs list -H "$ZCI_POOL_DST/other" 2>/dev/null
  check "Pull: fremdes Dataset nicht sendbar" not bash -c "$s zfs send -w $ZCI_POOL_DST/other@x > /dev/null 2>&1"
  check "Pull: kein destroy" not $s zfs destroy "$replica@zfs-auto-snap_daily-01" 2>/dev/null
  check "Pull: keine Shell" not $s id 2>/dev/null
  # ZFS selbst erlaubt dem Benutzer außerhalb nichts (auch ohne Wrapper)
  check "ZFS: send außerhalb verweigert" not su -s /bin/bash $user -c "zfs send -w $ZCI_POOL_DST/other@x > /dev/null" 2>/dev/null
  check "ZFS: destroy am Replikat verweigert" not su -s /bin/bash $user -c "zfs destroy $replica@zfs-auto-snap_daily-01" 2>/dev/null
  check "Snapshot unverändert" exists "$replica@zfs-auto-snap_daily-01"
  # Push: Einmal-Key, Zeile für authorized_keys mit Ablaufdatum, Test, Entfernen
  cp -a $ak $ak.zci 2>/dev/null || touch $ak.zci
  out=$($r access push --days 2 127.0.0.1)
  local id; id=$(sed -n 's/^push key \(push-[^ ]*\) .*/\1/p' <<< "$out")
  check "access push: Zeile mit restrict, from und expiry-time" grep -qE "restrict,from=\"127.0.0.1\",expiry-time=\"$(date -d '+2 days' +%Y%m%d)[0-9]{4}\" ssh-ed25519 " <<< "$out"
  cmd=$(grep "authorized_keys$" <<< "$out" | grep "^    install" | sed 's/^ *//')
  bash -c "$cmd"
  check "Push: Zeile in authorized_keys" grep -q " bashclub-zsync-restore-$id$" $ak
  cmd=$(grep "access test root@" <<< "$out" | sed 's/^ *//')
  out2=$(bash -c "$cmd" 2>&1)
  equal "access test (push)" "root@127.0.0.1: connected, zfs available" "$out2"
  out2=$($r access list)
  check "access list: Pull-Benutzer" grep -qE "^pull	$user	from 127.0.0.1	reads $ZCI_POOL_DST/restore_access$" <<< "$out2"
  check "access list: Push-Key gültig" grep -qE "^push	$id	root@127.0.0.1	valid until " <<< "$out2"
  cmd=$(grep "^    sed" <<< "$out" | sed 's/^ *//')
  bash -c "$cmd"
  check "Push: Zeile entfernt (ausgegebener Befehl)" not grep -q "bashclub-zsync-restore" $ak
  check "Push: übrige Schlüssel unverändert" cmp -s $ak $ak.zci
  cat $ak.zci > $ak; rm -f $ak.zci
  check "access remove: Push-Key" $r access remove "$id" > /dev/null
  check "Push-Key entfernt" not test -f "/var/lib/bashclub-zsync-restore/keys/$id"
  check "access remove: Pull-Benutzer" $r access remove $user > /dev/null
  check "Benutzer entfernt" not user_exists $user
  check "Rechte entfernt" not grep -q $user <<< "$(zfs allow "$ZCI_POOL_DST/restore_access")"
  rm -f $key $key.pub
}

# Restore eines Datasets mit kompletter Kette: unter neuem Namen (ohne Tag und Mountpoint), an der alten Stelle
# (mit den Originalwerten, die Replikation läuft danach inkrementell weiter), vorhandenes Ziel nur mit --force
case_restore_dataset() {
  local R=$ZCI_POOL_DST/restore/$ZCI_POOL_SRC
  zfs create -o atime=off "$ZCI_POOL_SRC/data"; zfs create -o mountpoint=/zci/child-mp "$ZCI_POOL_SRC/data/child"
  zfs set bashclub:zsync=all "$ZCI_POOL_SRC/data"
  write "$ZCI_POOL_SRC/data" 2; write "$ZCI_POOL_SRC/data/child" 1
  for n in 01 02 03; do snap "$ZCI_POOL_SRC/data" $n; snap "$ZCI_POOL_SRC/data/child" $n; write "$ZCI_POOL_SRC/data" 1 f$n; done
  config restore; zsync
  equal "Replikation: Exit-Code" 0 "$rc"
  # Planung ohne Ausführung
  local out; out=$(ZSYNC_CONF_DIR=$CONF_DIR bashclub-zsync-restore dataset "$R/data" --recursive --as "$ZCI_POOL_SRC/copy" --dry-run 2>&1)
  echo "$out" >> "$log"
  check "dry-run: Befehle für das Kind" grep -q "zfs send -L -e -c -p -I $R/data/child@zfs-auto-snap_daily-01 $R/data/child@zfs-auto-snap_daily-03" <<< "$out"
  check "dry-run: kein Job" not grep -q "written" <<< "$out"
  # unter neuem Namen
  restore dataset "$R/data" --recursive --as "$ZCI_POOL_SRC/copy"
  equal "neuer Name: Job fertig" done "$phase"
  for d in data data/child; do
    equal "neuer Name $d: gleiche Kette (GUID)" "$(zfs list -H -o guid -s createtxg -t snapshot -d 1 "$R/$d" | paste -sd' ')" \
      "$(zfs list -H -o guid -s createtxg -t snapshot -d 1 "$ZCI_POOL_SRC/copy${d#data}" | paste -sd' ')"
  done
  equal "neuer Name: Property der Quelle (atime)" off "$(prop "$ZCI_POOL_SRC/copy" atime)"
  equal "neuer Name: kein Tag (keine zweite Sicherung)" "-" "$(prop "$ZCI_POOL_SRC/copy" bashclub:zsync)"
  equal "neuer Name: Mountpoint unter dem neuen Namen" "/zci/src/copy/child" "$(prop "$ZCI_POOL_SRC/copy/child" mountpoint)"
  equal "neuer Name: eingehängt" yes "$(prop "$ZCI_POOL_SRC/copy/child" mounted)"
  check "neuer Name: Datei da" test -f /zci/src/copy/f02
  check "Bericht OK" grep -q "^OK	$ZCI_POOL_SRC/copy/child	" "/var/lib/bashclub-zsync-restore/jobs/$job.report"
  check "keine Holds mehr am Replikat" test -z "$(zfs holds -H "$R/data@zfs-auto-snap_daily-01")"
  # vorhandenes Ziel: ohne --force abgewiesen, mit --force zur Seite gelegt
  restore dataset "$R/data" --as "$ZCI_POOL_SRC/copy"
  check "vorhanden ohne --force: abgewiesen" test -z "$job"
  check "vorhanden ohne --force: Meldung" grep -q "exists (--force renames it" <<< "$(last_restore_output)"
  restore dataset "$R/data" --as "$ZCI_POOL_SRC/copy" --force
  equal "--force: Job fertig" done "$phase"
  check "--force: altes Dataset zur Seite gelegt" test -n "$(zfs list -H -o name | grep "^$ZCI_POOL_SRC/copy.before-restore-")"
  # Verlust auf der Quelle, Restore an der alten Stelle
  zfs destroy -r "$ZCI_POOL_SRC/data"
  restore dataset "$R/data" --recursive
  equal "alte Stelle: Job fertig" done "$phase"
  equal "alte Stelle: Tag wieder lokal" "all	local" "$(zfs get -H -o value,source bashclub:zsync "$ZCI_POOL_SRC/data")"
  equal "alte Stelle: Mountpoint des Kindes wieder lokal" "/zci/child-mp	local" "$(zfs get -H -o value,source mountpoint "$ZCI_POOL_SRC/data/child")"
  equal "alte Stelle: atime" off "$(prop "$ZCI_POOL_SRC/data" atime)"
  check "alte Stelle: Datei des Kindes" test -f /zci/child-mp/file
  snap "$ZCI_POOL_SRC/data" 04; snap "$ZCI_POOL_SRC/data/child" 04
  zsync
  equal "Replikation danach: Exit-Code" 0 "$rc"
  equal "Replikation danach: inkrementell weiter" "zfs-auto-snap_daily-01 zfs-auto-snap_daily-02 zfs-auto-snap_daily-03 zfs-auto-snap_daily-04" "$(snaps "$R/data")"
  check "Replikation danach: kein Zweig" not grep -q zsync-branch <<< "$(zfs list -H -o name -r "$ZCI_POOL_DST")"
}

# Nach einem Rollback auf der Quelle nur die fehlenden Snapshots zurück; Snapshots nach dem gemeinsamen nur mit
# --rollback; die Replikation läuft danach ohne Zweig weiter
case_restore_reattach() {
  local R=$ZCI_POOL_DST/restore/$ZCI_POOL_SRC
  zfs create "$ZCI_POOL_SRC/data"; zfs set bashclub:zsync=all "$ZCI_POOL_SRC/data"
  for n in 01 02 03; do write "$ZCI_POOL_SRC/data" 1 f$n; snap "$ZCI_POOL_SRC/data" $n; done
  config restore; zsync
  zfs rollback -r "$ZCI_POOL_SRC/data@zfs-auto-snap_daily-01"
  zfs snapshot "$ZCI_POOL_SRC/data@manual"
  restore reattach "$ZCI_POOL_SRC/data" --config restore
  check "Snapshot nur auf der Quelle: ohne --rollback abgewiesen" test -z "$job"
  check "Meldung nennt --rollback" grep -q "rollback destroys them" <<< "$(last_restore_output)"
  restore reattach "$ZCI_POOL_SRC/data" --config restore --rollback
  equal "reattach --rollback: Job fertig" done "$phase"
  equal "Kette wieder vollständig (GUID)" "$(zfs list -H -o guid -s createtxg -t snapshot "$R/data" | paste -sd' ')" \
    "$(zfs list -H -o guid -s createtxg -t snapshot "$ZCI_POOL_SRC/data" | paste -sd' ')"
  check "Datei des fehlenden Snapshots zurück" test -f /zci/src/data/f03
  equal "Properties der Quelle unverändert (Tag)" "all	local" "$(zfs get -H -o value,source bashclub:zsync "$ZCI_POOL_SRC/data")"
  # nur ein Snapshot fehlt, keine Änderung: ohne --rollback
  zfs rollback -r "$ZCI_POOL_SRC/data@zfs-auto-snap_daily-02"
  restore reattach "$ZCI_POOL_SRC/data" --config restore
  equal "reattach: Job fertig" done "$phase"
  equal "reattach: Snapshots" "zfs-auto-snap_daily-01 zfs-auto-snap_daily-02 zfs-auto-snap_daily-03" "$(snaps "$ZCI_POOL_SRC/data")"
  write "$ZCI_POOL_SRC/data" 1 f04; snap "$ZCI_POOL_SRC/data" 04
  zsync
  equal "Replikation danach: Exit-Code" 0 "$rc"
  check "Replikation danach: kein Zweig" not grep -q zsync-branch <<< "$(zfs list -H -o name -r "$ZCI_POOL_DST")"
  equal "Replikation danach: Snapshots" "zfs-auto-snap_daily-01 zfs-auto-snap_daily-02 zfs-auto-snap_daily-03 zfs-auto-snap_daily-04" "$(snaps "$R/data")"
}

# Pull über den Restore-Benutzer (lesend) und Push mit dem Einmal-Key, jeweils über ssh auf localhost;
# Volume und raw verschlüsseltes Dataset (ohne Schlüssel übertragen, danach mit Passphrase einhängbar)
case_restore_pull_push() {
  local R=$ZCI_POOL_DST/restore/$ZCI_POOL_SRC key=/root/zci-restore-pull-key ak=/root/.ssh/authorized_keys out
  zfs create -V 32M "$ZCI_POOL_SRC/vol"
  echo "zsync-ci-passphrase" | zfs create -o encryption=on -o keyformat=passphrase "$ZCI_POOL_SRC/enc"
  zfs set bashclub:zsync=all "$ZCI_POOL_SRC/vol"; zfs set bashclub:zsync=all "$ZCI_POOL_SRC/enc"
  dd if=/dev/urandom of=/dev/zvol/$ZCI_POOL_SRC/vol bs=1M count=8 status=none conv=fsync; write "$ZCI_POOL_SRC/enc" 2
  for n in 01 02; do snap "$ZCI_POOL_SRC/vol" $n; snap "$ZCI_POOL_SRC/enc" $n; done
  config restore; zsync
  # Pull
  rm -f $key $key.pub
  ZSYNC_RESTORE_PULL_KEY=$key bashclub-zsync-restore access key > /dev/null
  ZSYNC_CONF_DIR=$CONF_DIR bashclub-zsync-restore access pull --config restore 127.0.0.1 "$(cut -d' ' -f1-3 $key.pub)" >> "$log"
  out=$(ZSYNC_RESTORE_PULL_KEY=$key bashclub-zsync-restore list --from zsync-restore-restore@127.0.0.1 2>&1)
  echo "$out" >> "$log"
  check "Pull list: Volume, Zustand auf dem System ($out)" grep -qE "^  $ZCI_POOL_SRC/vol +volume +2 +zfs-auto-snap_daily-02 +- +up to date" <<< "$out"
  check "Pull list: raw verschlüsselt" grep -qE "^  $ZCI_POOL_SRC/enc +filesystem +2 .* raw " <<< "$out"
  ZSYNC_RESTORE_PULL_KEY=$key restore dataset "$ZCI_POOL_SRC/vol" --from zsync-restore-restore@127.0.0.1 --as "$ZCI_POOL_SRC/vol-pulled"
  equal "Pull Volume: Job fertig" done "$phase"
  equal "Pull Volume: gleiche Kette" "$(zfs list -H -o guid -s createtxg -t snapshot "$R/vol" | paste -sd' ')" "$(zfs list -H -o guid -s createtxg -t snapshot "$ZCI_POOL_SRC/vol-pulled" | paste -sd' ')"
  check "Pull Volume: Daten gleich" cmp -s /dev/zvol/$ZCI_POOL_SRC/vol /dev/zvol/$ZCI_POOL_SRC/vol-pulled
  ZSYNC_RESTORE_PULL_KEY=$key restore dataset "$ZCI_POOL_SRC/enc" --from zsync-restore-restore@127.0.0.1 --as "$ZCI_POOL_SRC/enc-pulled"
  equal "Pull raw: Job fertig" done "$phase"
  equal "Pull raw: ohne Schlüssel angekommen" unavailable "$(prop "$ZCI_POOL_SRC/enc-pulled" keystatus)"
  check "Pull raw: Bericht nennt load-key" grep -q "zfs load-key $ZCI_POOL_SRC/enc-pulled" "/var/lib/bashclub-zsync-restore/jobs/$job.report"
  echo "zsync-ci-passphrase" | zfs load-key "$ZCI_POOL_SRC/enc-pulled" && zfs mount "$ZCI_POOL_SRC/enc-pulled"
  check "Pull raw: mit Passphrase lesbar" cmp -s /zci/src/enc/file /zci/src/enc-pulled/file
  bashclub-zsync-restore access remove zsync-restore-restore > /dev/null; rm -f $key $key.pub
  # Push
  cp -a $ak $ak.zci 2>/dev/null || touch $ak.zci
  out=$(bashclub-zsync-restore access push 127.0.0.1)
  bash -c "$(grep "^    install" <<< "$out" | sed 's/^ *//')"
  restore dataset "$R/vol" --to 127.0.0.1 --as "$ZCI_POOL_SRC/vol-pushed"
  equal "Push Volume: Job fertig" done "$phase"
  check "Push Volume: Daten gleich" cmp -s /dev/zvol/$ZCI_POOL_SRC/vol /dev/zvol/$ZCI_POOL_SRC/vol-pushed
  check "Push: Statuskopie auf dem System" grep -q "^phase=done" /run/bashclub-zsync-restore.state
  bash -c "$(grep "^    sed" <<< "$out" | sed 's/^ *//')"
  cat $ak.zci > $ak; rm -f $ak.zci /run/bashclub-zsync-restore.state
  check "Push-Key nach dem Restore entfernt" bashclub-zsync-restore access remove "$(sed -n 's/^push key \(push-[^ ]*\) .*/\1/p' <<< "$out")"
}

# Abbruch mitten im Transfer (stop), Holds während des Restores, Fortsetzen ab Abbruchstelle (Resume-Token)
case_restore_resume() {
  local R=$ZCI_POOL_DST/restore/$ZCI_POOL_SRC
  if ! command -v pv > /dev/null; then skip "pv fehlt"; return; fi
  zfs create "$ZCI_POOL_SRC/data"; zfs set bashclub:zsync=all "$ZCI_POOL_SRC/data"
  write "$ZCI_POOL_SRC/data" 24; snap "$ZCI_POOL_SRC/data" 01
  config restore; zsync
  local out; out=$(ZSYNC_CONF_DIR=$CONF_DIR bashclub-zsync-restore dataset "$R/data" --as "$ZCI_POOL_SRC/slow" --bwlimit 2m --start < /dev/null 2>&1)
  echo "$out" >> "$log"
  job=$(sed -n 's/^job \([0-9a-f-]*\) written.*/\1/p' <<< "$out")
  sleep 5
  check "während des Restores: Hold am Replikat" grep -q "zsync-restore-$job" <<< "$(zfs holds -H "$R/data@zfs-auto-snap_daily-01")"
  out=$(ZSYNC_CONF_DIR=$CONF_DIR bashclub-zsync-restore dataset "$R/data" --as "$ZCI_POOL_SRC/slow" --force --dry-run 2>&1)
  check "während des Restores: kein zweiter Job auf dasselbe Ziel" grep -q "ERROR: job $job is restoring $ZCI_POOL_SRC/slow" <<< "$out"
  out=$(bashclub-zsync-restore status "$job")
  echo "$out" >> "$log"
  check "status: Fortschritt ($out)" grep -qE '\] +[0-9]+%.*of' <<< "$out"
  bashclub-zsync-restore stop "$job" >> "$log" 2>&1
  sleep 2
  equal "nach stop: Phase" stopped "$(bashclub-zsync-restore status "$job" | sed -n '1s/^job [^:]*: //p')"
  check "nach stop: Resume-Token" test "$(prop "$ZCI_POOL_SRC/slow" receive_resume_token)" != "-"
  check "nach stop: Hold freigegeben" test -z "$(zfs holds -H "$R/data@zfs-auto-snap_daily-01")"
  sed -i '/^bwlimit=/d' "/var/lib/bashclub-zsync-restore/jobs/$job.job"
  bashclub-zsync-restore resume "$job" < /dev/null >> "$log" 2>&1
  wait_job "$job"
  equal "resume: Job fertig" done "$phase"
  check "resume: ab Abbruchstelle fortgesetzt" grep -q "resume: $ZCI_POOL_SRC/slow" "/var/lib/bashclub-zsync-restore/jobs/$job.log"
  equal "resume: gleiche Kette" "$(guid "$R/data@zfs-auto-snap_daily-01")" "$(guid "$ZCI_POOL_SRC/slow@zfs-auto-snap_daily-01")"
  check "resume: Daten gleich" cmp -s /zci/src/data/file /zci/src/slow/file
}

# Einzelne Dateien: Snapshot als lesender Clone am Backupserver (Dateisystem, Volume mit Partition), die Rotation
# behält den Snapshot solange, cleanup entfernt nur die Clones; verschlüsselt ohne Schlüssel nur Hinweis
case_restore_mount() {
  local R=$ZCI_POOL_DST/restore/$ZCI_POOL_SRC r=bashclub-zsync-restore out id dir
  zfs create "$ZCI_POOL_SRC/data"; zfs set bashclub:zsync=all "$ZCI_POOL_SRC/data"
  echo "version 1" > /zci/src/data/doc.txt; snap "$ZCI_POOL_SRC/data" 01
  echo "version 2" > /zci/src/data/doc.txt; snap "$ZCI_POOL_SRC/data" 02
  zfs create -V 64M "$ZCI_POOL_SRC/vol"; zfs set bashclub:zsync=all "$ZCI_POOL_SRC/vol"
  udevadm settle
  echo 'type=83' | sfdisk -q /dev/zvol/$ZCI_POOL_SRC/vol; udevadm settle
  for i in $(seq 1 20); do [[ -e /dev/zvol/$ZCI_POOL_SRC/vol-part1 ]] && break; sleep 0.5; done
  mkfs.ext4 -q /dev/zvol/$ZCI_POOL_SRC/vol-part1
  mkdir -p /zci/volmnt && mount /dev/zvol/$ZCI_POOL_SRC/vol-part1 /zci/volmnt && echo "in the vm" > /zci/volmnt/vm.txt && umount /zci/volmnt
  snap "$ZCI_POOL_SRC/vol" 01
  echo "zsync-ci-passphrase" | zfs create -o encryption=on -o keyformat=passphrase "$ZCI_POOL_SRC/enc"
  zfs set bashclub:zsync=all "$ZCI_POOL_SRC/enc"; snap "$ZCI_POOL_SRC/enc" 01
  config restore; zsync
  # Dateisystem
  out=$($r mount "$R/data@zfs-auto-snap_daily-01" 2>&1); echo "$out" >> "$log"
  dir=$(sed -n 's/^.*(read only): //p' <<< "$out"); id=$(sed -n 's/^remove it: .* cleanup //p' <<< "$out")
  equal "mount: alter Stand lesbar ($out)" "version 1" "$(cat "$dir/doc.txt" 2>&1)"
  check "mount: nur lesend" not touch "$dir/new" 2>/dev/null
  check "mounts: Clone gelistet" grep -q "$R/data@zfs-auto-snap_daily-01" <<< "$($r mounts)"
  # Rotation (daily=1) würde 01 löschen: der Clone hält ihn
  set_conf "$conf" snapshot_filter '"daily=1"'
  snap "$ZCI_POOL_SRC/data" 03; zsync
  check "Rotation: Snapshot des Clones bleibt" exists "$R/data@zfs-auto-snap_daily-01"
  check "Rotation: anderer alter Snapshot gelöscht" not exists "$R/data@zfs-auto-snap_daily-02"
  # Volume mit Partition
  out=$($r mount "$R/vol@zfs-auto-snap_daily-01" 2>&1); echo "$out" >> "$log"
  local vid; vid=$(sed -n 's/^remove it: .* cleanup //p' <<< "$out")
  equal "Volume: Datei der Partition lesbar ($out)" "in the vm" "$(cat "/run/bashclub-zsync-restore/mnt/$vid/part1/vm.txt" 2>&1)"
  # verschlüsselt ohne Schlüssel
  out=$($r mount "$R/enc@zfs-auto-snap_daily-01" 2>&1)
  check "verschlüsselt: Hinweis auf load-key ($out)" grep -q "zfs load-key $R/enc" <<< "$out"
  check "verschlüsselt: kein Clone" not grep -q "$R/enc" <<< "$($r mounts)"
  # aufräumen
  check "cleanup Dateisystem" $r cleanup "$id"
  check "cleanup: Clone weg" not exists "$ZCI_POOL_DST/zsync-restore-clones/$id"
  check "cleanup --all" $r cleanup --all
  check "cleanup: Partition ausgehängt" not grep -q "/run/bashclub-zsync-restore/mnt/$vid" /proc/mounts
  equal "keine Clones mehr" "" "$($r mounts)"
  check "Replikate unverändert" exists "$R/vol@zfs-auto-snap_daily-01"
  zsync
  check "Rotation nach cleanup: alter Snapshot gelöscht" not exists "$R/data@zfs-auto-snap_daily-01"
}

# Full Restore eines Servers: alle Replikate der Config mit Umbenennung, Ausschluss und einem Zeitpunkt; fehlender
# Pool im Plan abgewiesen; geführter Ablauf (Wizard) gibt den passenden Befehl aus
case_restore_server() {
  local R=$ZCI_POOL_DST/restore/$ZCI_POOL_SRC out n
  zfs create "$ZCI_POOL_SRC/data"; zfs create "$ZCI_POOL_SRC/data/child"; zfs create "$ZCI_POOL_SRC/other"
  zfs create -V 32M "$ZCI_POOL_SRC/vol"
  for d in data other vol; do zfs set bashclub:zsync=all "$ZCI_POOL_SRC/$d"; done
  write "$ZCI_POOL_SRC/data" 1; write "$ZCI_POOL_SRC/data/child" 1
  snap "$ZCI_POOL_SRC/vol" 01
  for n in 01 02 03; do snap "$ZCI_POOL_SRC/data" $n; snap "$ZCI_POOL_SRC/data/child" $n; snap "$ZCI_POOL_SRC/other" $n; done
  config restore; zsync
  out=$(ZSYNC_CONF_DIR=$CONF_DIR bashclub-zsync-restore server --config restore --map "$ZCI_POOL_SRC/data=nopool/data" --dry-run 2>&1)
  echo "$out" >> "$log"
  check "fehlender Pool: im Plan abgewiesen" grep -q "ERROR: pool nopool does not exist" <<< "$out"
  restore server --config restore --map "$ZCI_POOL_SRC=$ZCI_POOL_SRC/srv" --exclude "$ZCI_POOL_SRC/other" --snapshot zfs-auto-snap_daily-02
  equal "server: Job fertig" done "$phase"
  check "server: Hinweise nach dem Restore" grep -q "after the restore, check on" <<< "$(last_restore_output)"
  equal "server: Kette bis zum Zeitpunkt" "zfs-auto-snap_daily-01 zfs-auto-snap_daily-02" "$(snaps "$ZCI_POOL_SRC/srv/data")"
  equal "server: Kind" "zfs-auto-snap_daily-01 zfs-auto-snap_daily-02" "$(snaps "$ZCI_POOL_SRC/srv/data/child")"
  equal "server: Volume ohne den Snapshot nimmt den älteren" "zfs-auto-snap_daily-01" "$(snaps "$ZCI_POOL_SRC/srv/vol")"
  check "server: ausgeschlossen" not exists "$ZCI_POOL_SRC/srv/other"
  check "server: Bericht ohne Fehler" not grep -q "^ERROR" "/var/lib/bashclub-zsync-restore/jobs/$job.report"
  # Wizard: auf diesem Host, Config, ein Dataset, neuester Snapshot, ohne Kinder, anderer Name, nicht ausführen
  n=$(ZSYNC_CONF_DIR=$CONF_DIR bashclub-zsync-restore list --config restore | awk '$1 ~ /^zci/ { print $1 }' | grep -nx "$ZCI_POOL_SRC/data" | cut -d: -f1)
  local jobs_before; jobs_before=$(ls /var/lib/bashclub-zsync-restore/jobs/*.job | wc -l)
  out=$(printf '2\n1\n1\n%s\n1\ny\n%s\nn\n' "$n" "$ZCI_POOL_SRC/wiz" | ZSYNC_CONF_DIR=$CONF_DIR script -qec bashclub-zsync-restore /dev/null 2>&1 | tr -d '\r')
  echo "$out" >> "$log"
  check "Wizard: fertiger Befehl ($out)" grep -qx "    bashclub-zsync-restore dataset --config restore $ZCI_POOL_SRC/data --snapshot zfs-auto-snap_daily-03 --recursive --as $ZCI_POOL_SRC/wiz" <<< "$out"
  equal "Wizard: mit n kein Job angelegt" "$jobs_before" "$(ls /var/lib/bashclub-zsync-restore/jobs/*.job | wc -l)"
  check "Wizard: nichts ausgeführt" not exists "$ZCI_POOL_SRC/wiz"
}

# Hooks vor und nach einem Lauf: global und je Config, Umgebung, Ausgabe im Log; pre-run mit Fehler überspringt den Lauf,
# post-run mit Fehler nur Warnung; nur Dateien von root, die nur root schreiben darf; Zeitlimit
case_hooks() {
  local hd=$CONF_DIR/hooks.d mark=/tmp/zci-hooks R
  zfs create "$ZCI_POOL_SRC/data"; zfs set bashclub:zsync=all "$ZCI_POOL_SRC/data"; write "$ZCI_POOL_SRC/data" 1; snap "$ZCI_POOL_SRC/data" 01
  config hooks; R=$ZCI_POOL_DST/hooks/$ZCI_POOL_SRC/data
  rm -rf "$hd" $mark.*; install -d -m 755 "$hd" "$hd/pre-run" "$hd/hooks" "$hd/hooks/post-run"
  printf '#!/bin/bash\necho "$ZSYNC_NAME $ZSYNC_TARGET $ZSYNC_PHASE $ZSYNC_CONFIG" > %s.pre\necho "hello from pre"\n' $mark > "$hd/pre-run/10-pre"
  printf '#!/bin/bash\necho "$ZSYNC_RC" > %s.post\n' $mark > "$hd/hooks/post-run/10-post"
  chmod 755 "$hd/pre-run/10-pre" "$hd/hooks/post-run/10-post"
  ZSYNC_HOOKS_DIR=$hd zsync
  equal "Hooks: Exit-Code" 0 "$rc"
  equal "pre-run: Umgebung" "hooks $ZCI_POOL_DST/hooks pre-run $conf" "$(cat $mark.pre 2>/dev/null)"
  check "pre-run: Ausgabe im Log" grep -q "10-pre: hello from pre" <<< "$(last_run_log)"
  equal "post-run je Config: Exit-Code des Laufs" 0 "$(cat $mark.post 2>/dev/null)"
  check "repliziert" exists "$R@zfs-auto-snap_daily-01"
  # pre-run mit Fehler: Lauf übersprungen, post-run läuft mit dem Exit-Code
  printf '#!/bin/bash\nexit 3\n' > "$hd/pre-run/20-fail"; chmod 755 "$hd/pre-run/20-fail"
  snap "$ZCI_POOL_SRC/data" 02
  ZSYNC_HOOKS_DIR=$hd zsync
  equal "pre-run Fehler: Exit-Code" 1 "$rc"
  check "pre-run Fehler: Meldung" grep -q "a pre-run hook failed, the run is skipped" <<< "$(last_run_log)"
  check "pre-run Fehler: nichts repliziert" not exists "$R@zfs-auto-snap_daily-02"
  equal "pre-run Fehler: post-run mit Exit-Code 1" 1 "$(cat $mark.post 2>/dev/null)"
  rm -f "$hd/pre-run/20-fail"
  # post-run mit Fehler: nur Warnung
  printf '#!/bin/bash\nexit 5\n' > "$hd/hooks/post-run/20-fail"; chmod 755 "$hd/hooks/post-run/20-fail"
  ZSYNC_HOOKS_DIR=$hd zsync
  equal "post-run Fehler: Exit-Code unverändert" 0 "$rc"
  check "post-run Fehler: Warnung" grep -q "a post-run hook failed, the exit code of the run stays 0" <<< "$(last_run_log)"
  check "post-run Fehler: repliziert" exists "$R@zfs-auto-snap_daily-02"
  rm -f "$hd/hooks/post-run/20-fail"
  # nicht vertrauenswürdig: für andere schreibbar
  chmod 757 "$hd/pre-run/10-pre"
  ZSYNC_HOOKS_DIR=$hd zsync
  equal "für andere schreibbarer Hook: Lauf übersprungen" 1 "$rc"
  check "für andere schreibbarer Hook: Meldung" grep -q "is not an executable file of root that only root may write" <<< "$(last_run_log)"
  chmod 755 "$hd/pre-run/10-pre"
  # Zeitlimit
  printf '#!/bin/bash\nsleep 30\n' > "$hd/pre-run/30-slow"; chmod 755 "$hd/pre-run/30-slow"
  echo "hook_timeout=2" >> "$conf"
  ZSYNC_HOOKS_DIR=$hd zsync
  equal "Zeitlimit: Lauf übersprungen" 1 "$rc"
  check "Zeitlimit: Meldung" grep -q "stopped after 2s" <<< "$(last_run_log)"
  rm -rf "$hd" $mark.*
  # ohne Hook-Ordner wie bisher
  zsync
  equal "ohne Hooks: Exit-Code" 0 "$rc"
}

# Schnittstelle für übergeordnete Abläufe: --result (key=value), busy (auch --wait), Inhibitor während eines Laufs,
# unterbrochener Transfer im Ergebnis
case_result_busy() {
  local out R
  if ! command -v pv > /dev/null; then skip "pv fehlt"; return; fi
  zfs create "$ZCI_POOL_SRC/data"; zfs set bashclub:zsync=all "$ZCI_POOL_SRC/data"; write "$ZCI_POOL_SRC/data" 1; snap "$ZCI_POOL_SRC/data" 01
  config result "transfer_resume=1"; R=$ZCI_POOL_DST/result/$ZCI_POOL_SRC/data
  zsync
  out=$(bashclub-zsync -c "$conf" --result); echo "$out" >> "$log"
  equal "--result: erste Zeile" "format=1" "$(head -1 <<< "$out")"
  check "--result: rc=0 ($out)" grep -qx 'rc=0' <<< "$out"
  check "--result: läuft nicht" grep -qx 'running=0' <<< "$out"
  check "--result: Zustand ok" grep -qx 'state.ok=1' <<< "$out"
  check "--result: keine offenen Entscheidungen" grep -qx 'decisions=0' <<< "$out"
  check "--result: kein unterbrochener Transfer" grep -qx 'resume_datasets=0' <<< "$out"
  check "busy: nichts aktiv" bashclub-zsync busy
  # langsamer Lauf: busy meldet ihn, Inhibitor gesetzt, Ergebnis zeigt running=1
  write "$ZCI_POOL_SRC/data" 8 big; snap "$ZCI_POOL_SRC/data" 02
  echo "bandwidth_limit=1m" >> "$conf"
  bashclub-zsync -c "$conf" >> "$log" 2>&1 &
  local runpid=$!
  sleep 3
  out=$(bashclub-zsync busy); local brc=$?
  equal "busy während des Laufs: Exit-Code" 1 "$brc"
  check "busy: nennt die Config ($out)" grep -q "replication: $conf" <<< "$out"
  check "Inhibitor während des Laufs" grep -q "bashclub-zsync" <<< "$(systemd-inhibit --list --no-pager 2>/dev/null)"
  check "--result während des Laufs: running=1" grep -qx 'running=1' <<< "$(bashclub-zsync -c "$conf" --result)"
  # Transfer unterbrechen: receive abbrechen, der Lauf endet mit Fehler, der Teilstand bleibt für den nächsten Lauf
  pkill -f "zfs receive -s" ; wait $runpid
  out=$(bashclub-zsync -c "$conf" --result); echo "$out" >> "$log"
  check "--result nach Abbruch: rc=1 ($out)" grep -qx 'rc=1' <<< "$out"
  check "--result: unterbrochener Transfer" grep -qx 'resume_datasets=1' <<< "$out"
  check "--result: Dataset mit Teilstand" grep -qx "resume.$ZCI_POOL_SRC/data=1" <<< "$out"
  check "kein Inhibitor nach dem Lauf" not grep -q "bashclub-zsync" <<< "$(systemd-inhibit --list --no-pager 2>/dev/null)"
  check "busy nach dem Lauf: nichts aktiv" bashclub-zsync busy
  # busy --wait wartet auf das Ende des Laufs
  sed -i '/^bandwidth_limit=/d' "$conf"; echo "bandwidth_limit=4m" >> "$conf"
  bashclub-zsync -c "$conf" >> "$log" 2>&1 &
  sleep 2
  check "busy --wait: wartet bis zum Ende" bashclub-zsync busy --wait 120
  check "busy --wait: Lauf beendet" not kill -0 $! 2>/dev/null
  wait
  out=$(bashclub-zsync -c "$conf" --result)
  check "--result danach: rc=0 und fortgesetzt ($out)" grep -qx 'rc=0' <<< "$out"
  check "--result danach: kein Teilstand" grep -qx 'resume_datasets=0' <<< "$out"
  # gehaltene Sperre einer Config in /etc/bashclub (z. B. Wartungsaktion): aktiv, --wait endet nach dem Zeitlimit
  local lockconf=/etc/bashclub/zci-busy.conf; cp "$conf" $lockconf
  check "busy --wait mit Zeitlimit: Exit 1 solange gesperrt" bash -c "exec 9< $lockconf; flock 9; ! bashclub-zsync busy --wait 6 > /dev/null"
  out=$(bash -c "exec 9< $lockconf; flock 9; bashclub-zsync busy")
  check "busy: gesperrte Config ($out)" grep -q "replication or maintenance: $lockconf" <<< "$out"
  rm -f $lockconf
}

all_cases=(replication engine_internal rotation nothing_selected refquota rollback broken_chain orphans local_mode bandwidth_lock bookmark hold deleted_during resume unprivileged timer same_second restricted job_user setup disk cleanup_blocked source_unreachable zas_missing maintenance keep_count permissions checkmk restore_access restore_dataset restore_reattach restore_pull_push restore_resume restore_mount restore_server hooks result_busy)
cases=("${@:-${all_cases[@]}}")
safety
# ein Lauf zur Zeit (CI und remote.sh teilen sich Platten, Pools und die installierten Pakete): ein zweiter wartet;
# ci.sh und remote.sh halten die Sperre schon vor dem Installieren der Pakete (ZCI_LOCK_HELD=1)
if [[ $ZCI_LOCK_HELD != 1 ]]; then
  exec 9> /run/lock/zsync-ci.lock
  flock 9 || { echo "Sperre /run/lock/zsync-ci.lock nicht erhalten"; exit 2; }
fi
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
