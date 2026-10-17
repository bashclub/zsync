# SPDX-License-Identifier: GPL-3.0-or-later
# Zustand pro Dataset beim Anfügen (guid = Zeitpunkt): normal (ok), neuester Ziel-Snapshot fehlt auf der Quelle (div),
# Rotation durchgelaufen (rot), Dataset auf der Quelle neu angelegt (new), Ziel ohne Snapshots (empty),
# Replikation fehlgeschlagen und Basis ist der älteste Snapshot der Quelle (risk), keine passenden Snapshots (nosnap)
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
TAGS=$'pool\tsubvols\tlocal'
for d in ok div rot new empty risk nosnap; do TAGS+=$'\n'"pool/$d"$'\tsubvols\tinherited from pool'; done
declare -A TYPES=()
DATASETS_source="pool pool/ok pool/div pool/rot pool/new pool/empty pool/risk pool/nosnap"
DATASETS_target="backup backup/zsync backup/zsync/pool backup/zsync/pool/ok backup/zsync/pool/div backup/zsync/pool/rot backup/zsync/pool/new backup/zsync/pool/empty backup/zsync/pool/risk backup/zsync/pool/nosnap"
declare -A CREATION_source=([pool/rot]=50 [pool/new]=700)
s() { local d=$1; shift; local out= g; for g in "$@"; do out+="${out:+$'\n'}$d@zfs-auto-snap_daily-$g $g"; done; printf '%s' "$out"; }
declare -A SNAPS_source=(
  [pool/ok]=$(s pool/ok 100 200) [pool/div]=$(s pool/div 100 300) [pool/rot]=$(s pool/rot 500 600)
  [pool/new]=$(s pool/new 800) [pool/empty]=$(s pool/empty 100) [pool/risk]=$(s pool/risk 100 200)
  [pool/nosnap]=$'pool/nosnap@manual 100')
declare -A SNAPS_target=(
  [backup/zsync/pool/ok]=$(s backup/zsync/pool/ok 100) [backup/zsync/pool/div]=$(s backup/zsync/pool/div 100 250)
  [backup/zsync/pool/rot]=$(s backup/zsync/pool/rot 100 200) [backup/zsync/pool/new]=$(s backup/zsync/pool/new 100 200)
  [backup/zsync/pool/risk]=$(s backup/zsync/pool/risk 100))
RECV_FAIL=backup/zsync/pool/risk
