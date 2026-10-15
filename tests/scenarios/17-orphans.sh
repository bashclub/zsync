# Datasets nur auf dem Ziel: Quelle fehlt (gone), Quelle nicht mehr ausgewählt (untagged), quittiert (kept);
# die Zwischenebene backup/zsync/pool hat keine Snapshots und ist kein Replikat
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
TAGS=$'pool/a\tall\tlocal\npool/untagged\tnone\tlocal'
declare -A TYPES=()
DATASETS_source="pool pool/a pool/untagged"
DATASETS_target="backup backup/zsync backup/zsync/pool backup/zsync/pool/a backup/zsync/pool/gone backup/zsync/pool/untagged backup/zsync/pool/kept"
declare -A ORPHAN_KEEP=([backup/zsync/pool/kept]=keep)
declare -A SNAPS_source=([pool/a]=$'pool/a@zfs-auto-snap_daily-01 1\npool/a@zfs-auto-snap_daily-02 2' [pool/untagged]=$'pool/untagged@zfs-auto-snap_daily-01 11')
declare -A SNAPS_target=([backup/zsync/pool/a]=$'backup/zsync/pool/a@zfs-auto-snap_daily-01 1'
  [backup/zsync/pool/gone]=$'backup/zsync/pool/gone@zfs-auto-snap_daily-01 21'
  [backup/zsync/pool/untagged]=$'backup/zsync/pool/untagged@zfs-auto-snap_daily-01 11'
  [backup/zsync/pool/kept]=$'backup/zsync/pool/kept@zfs-auto-snap_daily-01 31')
