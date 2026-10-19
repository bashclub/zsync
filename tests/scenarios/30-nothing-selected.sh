# SPDX-License-Identifier: GPL-3.0-or-later
# kein Dataset auf der Quelle ausgewählt: Warnung im Log statt Bash-Fehler, Lauf endet ohne Fehler
DEBUG=0; CHECKZFS=1
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
TAGS=$'pool\t-\tdefault\npool/data\t-\tdefault'
DATASETS_source="pool pool/data"
DATASETS_target="backup backup/zsync"
