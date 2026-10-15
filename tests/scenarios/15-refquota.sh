# refquota der Quelle: auf dem Ziel nur erhöhen (a) oder aufheben (b), nie verkleinern (c), ein Ziel ohne refquota
# bleibt so (d), Volumes haben keine (vol)
DEBUG=0; CHECKZFS=0
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
TAGS=$'pool\tsubvols\tlocal\npool/a\tsubvols\tinherited from pool\npool/b\tsubvols\tinherited from pool\npool/c\tsubvols\tinherited from pool\npool/d\tsubvols\tinherited from pool\npool/vol\tsubvols\tinherited from pool'
declare -A TYPES=([pool/vol]=volume)
DATASETS_source="pool pool/a pool/b pool/c pool/d pool/vol"
DATASETS_target="backup backup/zsync backup/zsync/pool backup/zsync/pool/a backup/zsync/pool/b backup/zsync/pool/c backup/zsync/pool/d backup/zsync/pool/vol"
declare -A REFQUOTA_source=([pool/a]=21474836480 [pool/b]=0 [pool/c]=5368709120 [pool/d]=10737418240)
declare -A REFQUOTA_target=([backup/zsync/pool/a]=10737418240 [backup/zsync/pool/b]=5368709120 [backup/zsync/pool/c]=10737418240 [backup/zsync/pool/d]=0)
declare -A SNAPS_source SNAPS_target
for d in a b c d vol; do
  SNAPS_source[pool/$d]="pool/$d@zfs-auto-snap_daily-01 ${d}1"$'\n'"pool/$d@zfs-auto-snap_daily-02 ${d}2"
  SNAPS_target[backup/zsync/pool/$d]="backup/zsync/pool/$d@zfs-auto-snap_daily-01 ${d}1"
done
