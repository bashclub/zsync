# SPDX-License-Identifier: GPL-3.0-or-later
# Dataset-Namen, die "local" bzw. "received" enthalten: maßgeblich ist die Quelle der Eigenschaft, nicht der Name
DEBUG=1; CHECKZFS=1
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
TAGS=$'pool/received-data\tall\tlocal\npool/vms\tsubvols\tlocal\npool/vms/localdisk\tsubvols\tinherited from pool/vms\npool/backup\tall\treceived\npool/local\tall\tinherited from pool/received-data'
declare -A TYPES=([pool/vms/localdisk]=volume)
DATASETS_source="pool pool/received-data pool/vms pool/vms/localdisk pool/backup pool/local"
DATASETS_target="backup backup/zsync backup/zsync/pool"
declare -A SNAPS_source=(); declare -A SNAPS_target=()
