# Ziel fehlt ganz (Erstreplikation mit Anlegen des Pfads), keine gemeinsame GUID,
# zfs-auto-snapshot als Engine, checkzfs nicht installiert, ohne Debug
DEBUG=0; CHECKZFS=0
CONF='target=backup/zsync
source=root@src
sshport=2222
tag=bashclub:zsync
snapshot_filter="daily|weekly"
min_keep=2
zfs_auto_snapshot_keep=5
zfs_auto_snapshot_label=backup
zfs_auto_snapshot_engine=zas
checkzfs_disabled=0
checkzfs_local=0
checkzfs_prefix=zsync
checkzfs_max_age=1500,6000
checkzfs_max_snapshot_count=150,165
checkzfs_spool=0
checkzfs_spool_maxage=87000'
TAGS=$'tank/a\tall\tlocal\ntank/b\tall\tlocal'
declare -A TYPES=()
DATASETS_source="tank tank/a tank/b"
DATASETS_target="backup backup/tank backup/tank/b"
declare -A SNAPS_source=(
  [tank/a]=$'tank/a@zfs-auto-snap_backup-01 401\ntank/a@zfs-auto-snap_daily-01 402'
  [tank/b]=$'tank/b@zfs-auto-snap_daily-05 505\ntank/b@zfs-auto-snap_daily-06 506'
)
declare -A SNAPS_target=(
  [backup/tank/b]=$'backup/tank/b@zfs-auto-snap_daily-01 501'
)
