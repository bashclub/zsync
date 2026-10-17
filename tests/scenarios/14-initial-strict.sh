# SPDX-License-Identifier: GPL-3.0-or-later
# Erstreplikation mit strict: das Muster läuft per ssh durch die Shell der Quelle; der älteste passende
# Snapshot ist backup-2026-10-01-1804, nicht der ältere zas-Rest
DEBUG=1; CHECKZFS=0
CONF='target=backup/zsync
source=root@src
sshport=22
tag=bashclub:zsync
snapshot_filter=""
min_keep=1
zfs_auto_snapshot_keep=3
zfs_auto_snapshot_label=backup
zfs_auto_snapshot_engine=internal
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
DATASETS_target="backup backup/zsync"
declare -A SNAPS_source=([pool/x]=$'pool/x@zfs-auto-snap_backup-2026-07-20-1051 800\npool/x@backup-2026-10-01-1804 801\npool/x@backup-2026-10-02-1804 802')
declare -A SNAPS_target=()
