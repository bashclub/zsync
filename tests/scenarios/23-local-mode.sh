# source=local: alles auf einem Host ohne ssh, Ziel im selben Pool (pool/backup) – die Replikate erben den Tag
# und dürfen nicht selbst repliziert werden; remote-snapshot-manager ohne -h, checkzfs lokal (Spool lokal statt scp)
DEBUG=0; CHECKZFS=1
CONF='target=pool/backup
source=local
sshport=22
tag=bashclub:zsync
snapshot_filter="daily"
min_keep=3
zfs_auto_snapshot_keep=3
zfs_auto_snapshot_label=backup
zfs_auto_snapshot_engine=internal
checkzfs_disabled=0
checkzfs_local=0
checkzfs_prefix=zsync
checkzfs_max_age=1500,6000
checkzfs_max_snapshot_count=150,165
checkzfs_spool=1
checkzfs_spool_maxage=87000'
TAGS=$'pool\tsubvols\tlocal'
for d in pool/x pool/new pool/backup pool/backup/pool pool/backup/pool/x; do TAGS+=$'\n'"$d"$'\tsubvols\tinherited from pool'; done
declare -A TYPES=()
# ein Host: alle Datasets und Snapshots auf der Seite "target" des Stubs (ohne ssh kein ZSIDE=source)
DATASETS_target="pool pool/x pool/new pool/backup pool/backup/pool pool/backup/pool/x"
declare -A SNAPS_source=()
declare -A SNAPS_target=([pool/x]=$'pool/x@zfs-auto-snap_daily-01 1\npool/x@zfs-auto-snap_daily-02 2'
  [pool/new]=$'pool/new@zfs-auto-snap_daily-01 11'
  [pool/backup/pool/x]=$'pool/backup/pool/x@zfs-auto-snap_daily-01 1')
