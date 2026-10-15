# ein anderer Lauf mit derselben Config ist aktiv: dieser Lauf wird ohne jeden Aufruf übersprungen
DEBUG=0; CHECKZFS=1
CONF='target=backup/zsync
source=root@src
sshport=22
tag=bashclub:zsync
snapshot_filter="daily"
min_keep=3
zfs_auto_snapshot_keep=0
zfs_auto_snapshot_label=backup
zfs_auto_snapshot_engine=internal
checkzfs_disabled=0
checkzfs_local=0
checkzfs_prefix=zsync
checkzfs_max_age=1500,6000
checkzfs_max_snapshot_count=150,165
checkzfs_spool=0
checkzfs_spool_maxage=87000'
TAGS=$'pool/x\tall\tlocal'
declare -A TYPES=()
DATASETS_source="pool pool/x"
DATASETS_target="backup backup/zsync backup/zsync/pool backup/zsync/pool/x"
declare -A SNAPS_source=([pool/x]=$'pool/x@zfs-auto-snap_daily-01 601')
declare -A SNAPS_target=([backup/zsync/pool/x]=$'backup/zsync/pool/x@zfs-auto-snap_daily-01 601')

# Sperre wie das Skript bilden und halten, die Datei enthält die pid des aktiven Laufs
before_run() {
  local lockdir=/run/lock; [ -d $lockdir ] || lockdir=/tmp
  lockfile=$lockdir/bashclub-zsync$(readlink -m "$1/zsync.conf" | tr '/' '_').lock
  exec {lockfd}> "$lockfile"; flock -n $lockfd; echo 4242 > "$lockfile"
}
after_run() { exec {lockfd}>&-; rm -f "$lockfile"; }
