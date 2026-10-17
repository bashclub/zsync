# Hilfsfunktionen für die ZFS-Integrationstests (wird von run.sh eingebunden)

# Testumgebung: Platten und Poolnamen aus /etc/zsync-ci.conf (nur diese werden angefasst)
ZCI_CONF=${ZCI_CONF:-/etc/zsync-ci.conf}
CONF_DIR=/etc/zsync-ci
LIB_DIR=/var/lib/bashclub-zsync
RUN_DIR=/run/bashclub-zsync
CHECK=/usr/share/bashclub-zsync/checkmk/bashclub_zsync

# Properties, die zfs send -p mitbringen kann, ohne sharenfs/sharesmb und ohne die zum Einhängen (mountpoint, canmount,
# setuid, exec, devices): Rechte für den Betrieb ohne root, wie im README
ZCI_RECV_PROPS=aclinherit,aclmode,acltype,atime,checksum,compression,context,copies,dedup,defcontext,dnodesize,filesystem_limit,fscontext,logbias,nbmand,overlay,primarycache,quota,readonly,recordsize,redundant_metadata,refquota,refreservation,relatime,reservation,rootcontext,secondarycache,snapdev,snapdir,snapshot_limit,special_small_blocks,sync,volmode,volsize,vscan,xattr

failed_cases=()
case_failed=0

fail() { echo "  FAIL $*"; case_failed=1; }
ok() { echo "  ok   $*"; }
# check <beschreibung> <befehl...>, verneint: check <beschreibung> not <befehl...>
check() { local desc=$1; shift; if "$@"; then ok "$desc"; else fail "$desc"; fi; }
# Vorbedingung eines Falls nicht herstellbar: übersprungen (weder bestanden noch fehlgeschlagen)
skip() { echo "  skip $*"; case_skipped=1; }
not() { ! "$@"; }
# equal <beschreibung> <erwartet> <ist>
equal() { if [[ $2 == "$3" ]]; then ok "$1"; else fail "$1: erwartet '$2', ist '$3'"; return 1; fi; }

# Sicherheitsprüfung: Pools mit Präfix zci-, Platten per by-id und nicht in fremden Pools
safety() {
  [[ -r $ZCI_CONF ]] || { echo "$ZCI_CONF fehlt"; exit 2; }
  . "$ZCI_CONF"
  [[ $ZCI_POOL_SRC == zci-* && $ZCI_POOL_DST == zci-* ]] || { echo "Poolnamen müssen mit zci- beginnen"; exit 2; }
  local disk dev
  for disk in "$ZCI_DISK_SRC" "$ZCI_DISK_DST"; do
    [[ $disk == /dev/disk/by-id/* && -b $disk ]] || { echo "Platte $disk fehlt oder nicht per by-id"; exit 2; }
    dev=$(readlink -f "$disk")
    if zpool status -P 2>/dev/null | awk -v d="$dev" '/^ *pool:/ { p = $2 } index($0, d) && p !~ /^zci-/ { found = 1 } END { exit !found }'; then
      echo "Platte $disk gehört zu einem fremden Pool"; exit 2
    fi
  done
}

# frische Pools für jeden Fall: Quelle mit Mountpoint (Daten schreiben), Ziel ohne
reset_pools() {
  local p
  for p in $(zpool list -H -o name 2>/dev/null | grep '^zci-'); do zpool destroy -f "$p"; done
  zpool create -f -o ashift=12 -O compression=lz4 -O com.sun:auto-snapshot=false \
    -O mountpoint=/zci/src "$ZCI_POOL_SRC" "$ZCI_DISK_SRC"
  zpool create -f -o ashift=12 -O compression=lz4 -O com.sun:auto-snapshot=false \
    -O mountpoint=none "$ZCI_POOL_DST" "$ZCI_DISK_DST"
  rm -rf "$CONF_DIR" "$LIB_DIR"/*/_etc_zsync-ci_* "$RUN_DIR"/*/_etc_zsync-ci_*
  mkdir -p "$CONF_DIR" /var/log/zsync-ci
}

cleanup_pools() {
  local p
  for p in $(zpool list -H -o name 2>/dev/null | grep '^zci-'); do zpool destroy -f "$p"; done
  rm -rf /zci
}

# Config des Falls: config <name> [zusätzliche Zeilen]; setzt $conf, $id, $log
config() {
  conf=$CONF_DIR/$1.conf
  id=$(tr '/' '_' <<< "$conf")
  log=/var/log/zsync-ci/$1.log
  cat > "$conf" << EOF
target=$ZCI_POOL_DST/$1
source=root@localhost
sshport=22
tag=bashclub:zsync
snapshot_filter="daily"
min_keep=1
zfs_auto_snapshot_keep=0
zfs_auto_snapshot_label=backup
zfs_auto_snapshot_engine=internal
zfs_auto_snapshot_label_match=strict
checkzfs_disabled=1
${2:-}
EOF
}

# zsync-Lauf, Ausgabe an das Log des Falls angehängt; setzt $rc
zsync() {
  echo "===== $(date +%T) bashclub-zsync -c $conf $*" >> "$log"
  bashclub-zsync -c "$conf" "$@" >> "$log" 2>&1
  rc=$?
  return $rc
}
# Setting in einer Config ersetzen oder anhängen: set_conf <datei> <name> <wert>
set_conf() { grep -q "^$2=" "$1" && sed -i "s|^$2=.*|$2=$3|" "$1" || echo "$2=$3" >> "$1"; }
# Timer von Test-Configs sicher entfernen: erst abschalten und laufende Dienste stoppen, dann die Configs löschen
# (ein Lauf ohne Config legt sonst das Template wieder an), Zeitstempel weg (Persistent=true startet sonst sofort)
remove_timer_configs() {
  local c n
  for c in "$@"; do [[ -f $c ]] && set_conf "$c" trigger cron; done
  bashclub-zsync-timer sync > /dev/null
  for c in "$@"; do
    n=$(basename "$c" .conf)
    systemctl stop "bashclub-zsync@$n.timer" "bashclub-zsync@$n.service" 2> /dev/null
    rm -f "$c" "/var/lib/systemd/timers/stamp-bashclub-zsync@$n.timer"
  done
  bashclub-zsync-timer sync > /dev/null
}
last_run_log() { awk '/^===== /{ buf = "" } { buf = buf $0 "\n" } END { printf "%s", buf }' "$log"; }

# Daten und Snapshots auf der Quelle
write() { dd if=/dev/urandom of="$(zfs get -H -o value mountpoint "$1")/${3:-file}" bs=1M count=${2:-1} status=none conv=fsync; }
# eigene Sekunde je Snapshot (realistische Zeiten); Snapshots in derselben Sekunde prüft case_same_second
snap() { sleep 1.05; zfs snapshot "$1@zfs-auto-snap_daily-$2"; }
# Snapshots mit verschiedenen Namen in derselben Sekunde: zu Beginn einer neuen Sekunde ohne Pause anlegen.
# ZFS legt Snapshots eines Datasets nie in derselben Transaktion an (zfs program: EAGAIN), es braucht also zwei
# Transaktionen in einer Sekunde; unter Last gelingt das nicht immer -> erneut versuchen, sonst Rückgabe 1
snaps_same_second() {
  local ds=$1 n try; shift
  for try in $(seq 1 10); do
    sleep "$(printf '0.%03d' $((1000 - 10#$(date +%3N))))"
    for n in "$@"; do zfs snapshot "$ds@zfs-auto-snap_$n"; done
    [ "$(zfs list -Hp -o creation -t snapshot "$ds" | sort -u | wc -l)" -eq 1 ] && return 0
    for n in "$@"; do zfs destroy "$ds@zfs-auto-snap_$n"; done
  done
  return 1
}
seconds_of() { zfs list -Hp -o creation -t snapshot "$1" | sort -u | wc -l; }
# Snapshot-Namen (ohne Dataset) älteste zuerst
snaps() { zfs list -H -o name -t snapshot -s creation "$1" 2>/dev/null | sed 's/.*@//' | paste -sd' '; }
guid() { zfs get -H -o value guid "$1" 2>/dev/null; }
exists() { zfs list "$1" > /dev/null 2>&1; }
prop() { zfs get -H -o value "$2" "$1" 2>/dev/null; }
# Status-Dateien des Falls (Ordner des Benutzers, der lief): status_path <endung>
status_path() { ls "$LIB_DIR"/*/"$id.$1" "$RUN_DIR"/*/"$id.$1" 2>/dev/null | head -1; }
state_of() { awk -F'\t' -v d="$1" '$1 == d { print $2 }' "$(status_path datasets)" 2>/dev/null; }
check_output() { "$CHECK" | grep "\"zsync $(basename "$conf" .conf)\""; }
