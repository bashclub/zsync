# SPDX-License-Identifier: GPL-3.0-or-later
# Label steht schon in snapshot_filter: jedes Intervall wird nur einmal geprüft
DEBUG=1; CHECKZFS=0
CONF='target=backup/zsync
source=root@src
sshport=22
tag=bashclub:zsync
snapshot_filter="daily|backup"
min_keep=1
zfs_auto_snapshot_keep=3
zfs_auto_snapshot_label=backup
zfs_auto_snapshot_engine=internal
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
declare -A SNAPS_source=([pool/x]=$'pool/x@backup-2026-10-02-1800 702\npool/x@zfs-auto-snap_daily-02 703\npool/x@backup-2026-10-03-1800 704')
declare -A SNAPS_target=([backup/zsync/pool/x]=$'backup/zsync/pool/x@backup-2026-10-01-1800 701\nbackup/zsync/pool/x@backup-2026-10-02-1800 702\nbackup/zsync/pool/x@zfs-auto-snap_daily-02 703')
