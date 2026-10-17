# SPDX-License-Identifier: GPL-3.0-or-later
# Retention auf der Quelle löscht während der Replikation den ältesten daily-Snapshot:
# das Löschen auf dem Ziel muss sich nach dem Stand nach der Replikation richten
DEBUG=1; CHECKZFS=0
CONF='target=backup/zsync
source=root@src
sshport=22
tag=bashclub:zsync
snapshot_filter="daily"
min_keep=3
zfs_auto_snapshot_keep=0
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
declare -A SNAPS_source=([pool/x]=$'pool/x@daily-01 701\npool/x@daily-02 702\npool/x@daily-03 703\npool/x@daily-04 704')
declare -A SNAPS_source_post=([pool/x]=$'pool/x@daily-02 702\npool/x@daily-03 703\npool/x@daily-04 704')
declare -A SNAPS_target=([backup/zsync/pool/x]=$'backup/zsync/pool/x@daily-c 690\nbackup/zsync/pool/x@daily-b 691\nbackup/zsync/pool/x@daily-a 692\nbackup/zsync/pool/x@daily-01 701\nbackup/zsync/pool/x@daily-02 702')
