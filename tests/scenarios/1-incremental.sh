# SPDX-License-Identifier: GPL-3.0-or-later
# Delta, Löschen alter Snapshots, Erstreplikation eines Kindes, Volume mit fehlschlagendem receive,
# subvols/received/none, interne Snapshot-Engine, checkzfs lokal, Debug
DEBUG=1; CHECKZFS=1
CONF='target=backup/zsync
source=root@src
sshport=22
tag=bashclub:zsync
snapshot_filter="hourly|daily|weekly|monthly"
min_keep=3
zfs_auto_snapshot_keep=3
zfs_auto_snapshot_label=backup
zfs_auto_snapshot_engine=internal
checkzfs_disabled=0
checkzfs_local=0
checkzfs_prefix=zsync
checkzfs_max_age=1500,6000
checkzfs_max_snapshot_count=150,165
checkzfs_spool=0
checkzfs_spool_maxage=87000'
TAGS=$'pool/data\tall\tlocal\npool/data/sub\tall\tinherited from pool/data\npool/vm\tsubvols\tlocal\npool/vm/disk1\tsubvols\tinherited from pool/vm\npool/skip\tnone\tlocal\npool/recv\tall\treceived'
declare -A TYPES=([pool/vm/disk1]=volume)
DATASETS_source="pool pool/data pool/data/sub pool/vm pool/vm/disk1 pool/skip pool/recv"
DATASETS_target="backup backup/zsync backup/zsync/pool backup/zsync/pool/data backup/zsync/pool/vm backup/zsync/pool/vm/disk1"
declare -A SNAPS_source=(
  [pool/data]=$'pool/data@zfs-auto-snap_daily-01 101\npool/data@zfs-auto-snap_daily-02 102\npool/data@zfs-auto-snap_hourly-01 103\npool/data@zfs-auto-snap_daily-03 104\npool/data@zfs-auto-snap_hourly-02 105\npool/data@manual 106'
  [pool/data/sub]=$'pool/data/sub@zfs-auto-snap_daily-01 201\npool/data/sub@zfs-auto-snap_daily-02 202'
  [pool/vm/disk1]=$'pool/vm/disk1@zfs-auto-snap_daily-01 301\npool/vm/disk1@zfs-auto-snap_daily-02 302\npool/vm/disk1@zfs-auto-snap_daily-03 303'
)
declare -A SNAPS_target=(
  [backup/zsync/pool/data]=$'backup/zsync/pool/data@zfs-auto-snap_daily-a 90\nbackup/zsync/pool/data@zfs-auto-snap_daily-b 91\nbackup/zsync/pool/data@zfs-auto-snap_daily-c 92\nbackup/zsync/pool/data@zfs-auto-snap_daily-d 93\nbackup/zsync/pool/data@zfs-auto-snap_daily-01 101\nbackup/zsync/pool/data@zfs-auto-snap_daily-02 102\nbackup/zsync/pool/data@zfs-auto-snap_daily-03 104'
  [backup/zsync/pool/vm/disk1]=$'backup/zsync/pool/vm/disk1@zfs-auto-snap_daily-01 301'
)
RECV_FAIL=backup/zsync/pool/vm/disk1
