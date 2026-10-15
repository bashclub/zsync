# source_bookmark=1
DEBUG=1; CHECKZFS=0
CONF='target=backup/zsync
source=root@src
sshport=22
tag=bashclub:zsync
snapshot_filter="daily"
min_keep=1
zfs_auto_snapshot_keep=0
zfs_auto_snapshot_label=backup
zfs_auto_snapshot_engine=internal
source_bookmark=1
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
declare -A SNAPS_source=([pool/x]=$'pool/x@zfs-auto-snap_daily-04 104\npool/x@zfs-auto-snap_daily-05 105')
declare -A SNAPS_target=([backup/zsync/pool/x]=$'backup/zsync/pool/x@zfs-auto-snap_daily-02 102\nbackup/zsync/pool/x@zfs-auto-snap_daily-03 103')
# Bookmark-Name enthält den Hostnamen des Backupservers
declare -A BOOKMARKS_source=([pool/x]="pool/x#zsync_$(hostname -s)_backup_zsync 103")
