# strict mit Engine zas: nur zfs-auto-snap_<label>-<Datum> zählt, ein Snapshot im Schema von internal ist ein Rest
DEBUG=1; CHECKZFS=0
CONF='target=backup/zsync
source=root@src
sshport=22
tag=bashclub:zsync
snapshot_filter=""
min_keep=1
zfs_auto_snapshot_keep=3
zfs_auto_snapshot_label=backup
zfs_auto_snapshot_engine=zas
zfs_auto_snapshot_label_match=strict
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
declare -A SNAPS_source=([pool/x]=$'pool/x@zfs-auto-snap_backup-2026-10-01-1804 901\npool/x@zfs-auto-snap_backup-2026-10-02-1804 902\npool/x@backup-2026-10-02-2000 905\npool/x@zfs-auto-snap_backup-2026-10-03-1804 903')
declare -A SNAPS_target=([backup/zsync/pool/x]=$'backup/zsync/pool/x@zfs-auto-snap_backup-2026-09-30-1804 900\nbackup/zsync/pool/x@zfs-auto-snap_backup-2026-10-01-1804 901\nbackup/zsync/pool/x@zfs-auto-snap_backup-2026-10-02-1804 902')
