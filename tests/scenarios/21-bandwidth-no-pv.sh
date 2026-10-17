# SPDX-License-Identifier: GPL-3.0-or-later
# bandwidth_limit=10m ohne pv: Warnung, Übertragung ohne Limit wie bisher
DEBUG=0; CHECKZFS=0; PV=0
CONF='target=backup/zsync
source=root@src
sshport=22
tag=bashclub:zsync
snapshot_filter="daily"
min_keep=3
zfs_auto_snapshot_keep=0
zfs_auto_snapshot_label=backup
zfs_auto_snapshot_engine=internal
bandwidth_limit=10m
checkzfs_disabled=1
checkzfs_local=0
checkzfs_prefix=zsync
checkzfs_max_age=1500,6000
checkzfs_max_snapshot_count=150,165
checkzfs_spool=0
checkzfs_spool_maxage=87000'
TAGS=$'pool/x\tall\tlocal\npool/new\tall\tlocal'
declare -A TYPES=()
DATASETS_source="pool pool/x pool/new"
DATASETS_target="backup backup/zsync backup/zsync/pool backup/zsync/pool/x"
declare -A SNAPS_source=([pool/x]=$'pool/x@zfs-auto-snap_daily-01 1\npool/x@zfs-auto-snap_daily-02 2' [pool/new]=$'pool/new@zfs-auto-snap_daily-01 11')
declare -A SNAPS_target=([backup/zsync/pool/x]=$'backup/zsync/pool/x@zfs-auto-snap_daily-01 1')
