# SPDX-License-Identifier: GPL-3.0-or-later
# Quelle nicht erreichbar (ssh Exit 255): sofort Fehler und Exit 1, keine Replikation, Status für das Monitoring
DEBUG=0; CHECKZFS=0; SSH_FAIL=1
CONF='target=backup/zsync
source=root@src
sshport=22
tag=bashclub:zsync
snapshot_filter=""
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
declare -A SNAPS_source=([pool/x]=$'pool/x@zfs-auto-snap_backup-2026-07-20-1051 800\npool/x@backup-2026-10-01-1804 801\npool/x@backup-2026-10-02-1804 802\npool/x@backup-old-2026-10-02-1900 806\npool/x@backup-2026-10-03-1804 803')
declare -A SNAPS_target=([backup/zsync/pool/x]=$'backup/zsync/pool/x@zfs-auto-snap_backup-2026-08-01-0000 780\nbackup/zsync/pool/x@backup-2026-08-28-1805 790\nbackup/zsync/pool/x@backup-2026-08-29-1805 791\nbackup/zsync/pool/x@backup-2026-10-01-1804 801\nbackup/zsync/pool/x@backup-2026-10-02-1804 802')
