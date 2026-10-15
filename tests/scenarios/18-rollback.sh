# target_rollback=1: neuester Ziel-Snapshot fehlt auf der Quelle -> Rollback auf den neuesten gemeinsamen Snapshot
# (2 Snapshots verworfen), danach Anfügen ab dort
DEBUG=0; CHECKZFS=0
CONF='target=backup/zsync
source=root@src
sshport=22
tag=bashclub:zsync
snapshot_filter="daily"
min_keep=1
zfs_auto_snapshot_keep=0
zfs_auto_snapshot_label=backup
zfs_auto_snapshot_engine=internal
target_rollback=1
target_rollback_max=24
checkzfs_disabled=1
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
# Quelle nach Rollback auf daily-02: daily-03/04 fehlen, daily-05 ist neu
declare -A SNAPS_source=([pool/x]=$'pool/x@zfs-auto-snap_daily-01 101\npool/x@zfs-auto-snap_daily-02 102\npool/x@zfs-auto-snap_daily-05 105')
declare -A SNAPS_target=([backup/zsync/pool/x]=$'backup/zsync/pool/x@zfs-auto-snap_daily-01 101\nbackup/zsync/pool/x@zfs-auto-snap_daily-02 102\nbackup/zsync/pool/x@zfs-auto-snap_daily-03 103\nbackup/zsync/pool/x@zfs-auto-snap_daily-04 104')
