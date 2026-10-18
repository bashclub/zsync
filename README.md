# zsync

> Development takes place at https://code.bashclub.org/bashclub/zsync

ZFS replication script by Thorsten Spille <thorsten@spille-edv.de>
- replicates ZFS filesystems/volumes with user parameter bashclub:zsync (or custom name) configured
- creates optional snapshot before replication (via zfs-auto-snapshot or included remote-snapshot-manager)
- parameter setting uses zfs hierarchy on source
- mirrored replication with existing snapshots (filtered by snapshot_filter)
- pull replication only
- auto creates full path on target pool, enforce com.sun:auto-snapshot=false, inherits mountpoint and sets canmount=noauto
- raw replication
- tested on Proxmox VE 9.x, usable on Debian, Ubuntu and TrueNAS SCALE
- ssh cipher auto selection

## Installation
Supported platforms:

| Platform | Installation |
|---|---|
| Proxmox VE 8 / 9, Proxmox Backup Server | apt package |
| Debian 12 (`bookworm`) / 13 (`trixie`) | apt package |
| Ubuntu 24.04 (`noble`) / 26.04 (`resolute`) | apt package |
| TrueNAS SCALE | manual installation on a dataset |

`bashclub-zsync` is only installed on the replication target (pull replication). The source hosts only need ZFS and SSH access.

### Proxmox VE / Debian / Ubuntu (apt)

#### 1. Enable required components
`zfsutils-linux` and `zfs-auto-snapshot` are in the Debian `contrib` component (Ubuntu: `main` and `universe`).
Proxmox VE and Ubuntu have them enabled by default, so you can skip this step there.

Debian 13 (deb822 format, `/etc/apt/sources.list.d/debian.sources`):
~~~
sed -i '/^Components:/{/contrib/!s/$/ contrib/}' /etc/apt/sources.list.d/debian.sources
~~~

Debian 12 (one-line format, `/etc/apt/sources.list`):
~~~
sed -i -E '/^deb .*debian\.org/{/ contrib( |$)/!s/$/ contrib/}' /etc/apt/sources.list
~~~

`bashclub-checkzfs` (monitoring, see [checkzfs](https://code.bashclub.org/bashclub/checkzfs)) comes from the bashclub repository itself.

#### 2. Add the bashclub repository and install
The release codename (`bookworm`, `trixie`, `noble` or `resolute`) is read from `/etc/os-release`, so the commands can be copied as they are.

Debian 13 / Proxmox VE 9 / Ubuntu 24.04 and 26.04 (deb822 format):
~~~
wget -O- https://apt.bashclub.org/gpg/bashclub.pub | gpg --dearmor > /usr/share/keyrings/bashclub-archive-keyring.gpg
cat > /etc/apt/sources.list.d/bashclub.sources << EOF
Types: deb
URIs: https://apt.bashclub.org/release
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: main
Signed-By: /usr/share/keyrings/bashclub-archive-keyring.gpg
EOF
apt update
apt install bashclub-zsync
~~~

Debian 12 / Proxmox VE 8:
~~~
wget -O- https://apt.bashclub.org/gpg/bashclub.pub | gpg --dearmor > /usr/share/keyrings/bashclub-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/bashclub-archive-keyring.gpg] https://apt.bashclub.org/release $(. /etc/os-release && echo "$VERSION_CODENAME") main" > /etc/apt/sources.list.d/bashclub.list
apt update
apt install bashclub-zsync
~~~

`cryptsetup` and a `mail` command (`bsd-mailx`) are installed as recommended packages. They are only needed for `zsync-autorun` (removable disks with LUKS, mail notification).

Packages up to 1.0.19 created `/etc/bashclub` with the owner of their build user (uid 995). An update to 2.0 corrects it; on an installation that stays on 1.0.x, make the folder of the configurations writable only for root:
~~~
chown root:root /etc/bashclub; chmod go-w /etc/bashclub
~~~

### TrueNAS SCALE
TrueNAS does not allow installing packages and the system files are replaced on every update. The scripts are therefore installed into `scripts/bashclub-zsync` on your data pool. The first data pool is detected automatically; to use another one, set it first, e.g. `pool=tank`.
~~~
pool=${pool:-$(zpool list -H -o name | grep -vx boot-pool | head -n1)}
dir=$(zfs get -H -o value mountpoint "$pool")/scripts/bashclub-zsync
mkdir -p "$dir" && cd "$dir"
curl -fsSL -o bashclub-zsync https://code.bashclub.org/bashclub/zsync/raw/branch/main/bashclub-zsync/usr/bin/bashclub-zsync
curl -fsSL -o remote-snapshot-manager https://code.bashclub.org/bashclub/zsync/raw/branch/main/bashclub-zsync/usr/bin/remote-snapshot-manager
# optional: checkzfs for monitoring
curl -fsSL -o checkzfs https://code.bashclub.org/bashclub/checkzfs/raw/branch/main/bashclub-checkzfs/usr/bin/checkzfs
chmod +x bashclub-zsync remote-snapshot-manager checkzfs

# creates zsync.conf on first run, adjust it afterwards
./bashclub-zsync -c "$dir/zsync.conf"

# prints the command for the cron job
echo "$dir/bashclub-zsync -c $dir/zsync.conf >> $dir/bashclub-zsync.log 2>&1"
~~~
`bashclub-zsync` finds `remote-snapshot-manager` and `checkzfs` in its own directory. Create the cron job in the web UI under *System → Advanced Settings → Cron Jobs* with the command printed by the last line.
The log is not covered by logrotate there, so `bashclub-zsync` rotates it itself at 10 MiB and keeps 4 compressed old logs (`bashclub-zsync.log.1.gz` … `.4.gz`).

`zfs-auto-snapshot` is not available on TrueNAS, keep `zfs_auto_snapshot_engine="internal"`.

### Manual installation (other distributions)
~~~
wget -q --no-cache -O /usr/local/bin/bashclub-zsync https://code.bashclub.org/bashclub/zsync/raw/branch/main/bashclub-zsync/usr/bin/bashclub-zsync
wget -q --no-cache -O /usr/local/bin/remote-snapshot-manager https://code.bashclub.org/bashclub/zsync/raw/branch/main/bashclub-zsync/usr/bin/remote-snapshot-manager
chmod +x /usr/local/bin/bashclub-zsync /usr/local/bin/remote-snapshot-manager

# optional: download checkzfs for monitoring (requires python3)
wget -q --no-cache -O /usr/local/bin/checkzfs https://code.bashclub.org/bashclub/checkzfs/raw/branch/main/bashclub-checkzfs/usr/bin/checkzfs
chmod +x /usr/local/bin/checkzfs
checkzfs --help
~~~

## Documentation
[DOCUMENTATION_DE.md](DOCUMENTATION_DE.md)


## Guided setup
`bashclub-zsync-setup` sets up a new replication on the backup server (as root) and asks for each setting, the default in brackets:
- configuration `/etc/bashclub/<name>.conf` with the defaults of new configurations and a systemd timer (`trigger=systemd`, schedule in cron format)
- user `zsync-<name>` on the backup server (`run_as`) with its own ssh-ed25519 key, ZFS permissions only on its target
- user `zsync-<backup host>-<name>` on the source (package `bashclub-zsync-source`): its key only works from the address of the backup server and only for the commands of bashclub-zsync, it may only read the datasets with the tag (see [Users per replication job on the source](#users-per-replication-job-on-the-source))

The source is set up over ssh, as its management user `zsync` (no root access needed: the key of root of the backup server in `/var/lib/zsync/.ssh/authorized_keys` on the source) or as root (installs `bashclub-zsync-source` if missing). Set up the configuration `/etc/bashclub/zsync.conf`, the questions start with the source:
~~~
bashclub-zsync-setup zsync
~~~
For automation every question has an option, `--yes` takes the defaults for the rest, e.g. (source, datasets and name are examples) `bashclub-zsync-setup --yes --source pve1 --login root --tag-datasets "rpool/data" --run pve1`. All options: `bashclub-zsync-setup --help`. `--source local` replicates pools of the backup server, `--root` sets up a replication as root without job users (as before 2.0). An existing configuration is never overwritten.

## Configuration
After first execution bashclub-zsync will create `/etc/bashclub/zsync.conf` if no configuration parameter is given and file not exists.
The installation package provides `/etc/bashclub/zsync.conf.example` with the default values.

~~~
# replication target path on local machine 
target=pool/dataset

# ssh address of remote machine, "local" = datasets of this machine without ssh (pool to pool)
source=user@host

# ssh port of remote machine
sshport=22

# zfs user parameter to identify filesystems/volumes to replicate
tag=bashclub:zsync

# pipe separated list of the snapshot labels to replicate, each with the number of its snapshots to keep on the
# backup server: daily=30 keeps the 30 newest daily snapshots here, whatever the source deletes;
# daily or daily=source follows the source (deletes what the source deleted, at least min_keep remain)
snapshot_filter="hourly|daily|weekly|monthly"

# deprecated (will be removed in a later version): minimum number of snapshots per label that stay on the backup
# server for labels with "source"; use a number in snapshot_filter instead
min_keep=3

# number of zfs snapshots to keep on source (0 or 1 = snapshot function disabled)
zfs_auto_snapshot_keep=0

# make snapshot via zfs-auto-snapshot before replication
zfs_auto_snapshot_label="backup"

# select snapshot engine: "zas" (zfs-auto-snapshot on the source) or "internal" (remote-snapshot-manager)
# new configurations use "internal"; existing configurations without this setting keep using "zas"
zfs_auto_snapshot_engine="internal"

# snapshots of the label: "strict" = only the name scheme of the snapshot engine
# (internal: <label>-YYYY-MM-DD-HHMM, zas: zfs-auto-snap_<label>-YYYY-MM-DD-HHMM), "legacy" = any name containing the label
# new configurations use "strict"; existing configurations without this setting keep using "legacy"
zfs_auto_snapshot_label_match="strict"

# maximum age of the last successful run for the checkmk check bashclub_zsync, e.g. 26h, 90m or seconds
# empty = derived from the start times of the previous runs, 0 = no age check (e.g. removable disks)
monitor_max_age=""

# bandwidth limit of the transfer in bytes per second with suffix k, m, g (1024 based), e.g. 10m = 10 MiB/s
# (about 84 Mbit/s); applied on this host with pv (package pv), empty = no limit
bandwidth_limit=""

# keep a bookmark of the newest replicated snapshot on the source (one per backup host and target): if the rotation
# on the source deletes this snapshot before the next replication, the replication continues from the bookmark
# 1 = on, 0 = off; existing configurations without this setting keep 0, new configurations get 1
source_bookmark=1

# hold the snapshots of a dataset on the source (zfs hold) while it is replicated, so the rotation or an admin cannot
# delete the base or a snapshot that is still to be sent; released at the end of the dataset or of the run
# 1 = on, 0 = off; existing configurations without this setting keep 0, new configurations get 1
source_hold=1

# resumable transfers (zfs receive -s): a transfer interrupted by a network or power failure continues where it
# stopped in the next run instead of starting again; 1 = on, 0 = off
# existing configurations without this setting keep 0, new configurations get 1
transfer_resume=1

# disable checkzfs with value > 0
checkzfs_disabled=0

# set checkzfs parameter "--prefix", also the name of the spool file <checkzfs_spool_maxage>_<prefix> and of the
# service "<prefix> <config>" of the runs; several backup servers writing into the spool of one source need different ones
checkzfs_prefix=zsync

# set checkzfs maximum age of last snapshot in minutes (comma separated => warn,crit)
checkzfs_max_age=1500,6000

# set checkzfs maximum count of snapshots per dataset (comma separated => warn,crit)
checkzfs_max_snapshot_count=150,165

# set where to move the checkzfs output (0 = local machine, 1 = source machine)
checkzfs_spool=0

# set maxmimum age of checkzfs data in seconds (hourly = 3900, daily = 87000)
checkzfs_spool_maxage=87000
~~~

### Snapshot label and snapshot engine
- A label must not contain the label of another configuration on the same source (e.g. `zsync` and `zsync-miyagi`): in `legacy` mode each configuration would treat the snapshots of the other one as its own.
- With `zfs_auto_snapshot_label_match="strict"` only snapshots in the name scheme of the configured engine belong to the label. Snapshots of the label in another scheme, e.g. `zfs-auto-snap_<label>-…` left over after switching from `zas` to `internal`, are neither replicated nor used to decide which target snapshots are deleted. In `legacy` mode such a snapshot can be the oldest snapshot of the label on the source; if it does not exist on the target, no snapshots of the label are deleted on the target anymore.
- `bashclub-zsync` lists such snapshots as `[WARN]` (source and target) and warns if the oldest source snapshot of an interval is missing on the target (state `cleanup_blocked` in the monitoring).
- The engine `zas` runs `zfs-auto-snapshot` on the source; the packages only recommend it (`bashclub-zsync` needs it on the backup server only for `source=local`). If it is missing on the source, `bashclub-zsync` warns that no snapshots are created.

To switch an existing configuration from `zas` to `internal`, set both values and remove the remaining `zfs-auto-snapshot` snapshots of the label on the source. The commands read source, port and label from the configuration; the first one only shows what would be deleted:
~~~
conf=/etc/bashclub/zsync.conf
( . "$conf"; ssh -p "$sshport" "$source" "zfs list -H -t snapshot -o name | grep '@zfs-auto-snap_${zfs_auto_snapshot_label}-' | xargs -r -n1 zfs destroy -nv" )
~~~
If the list is correct, delete them:
~~~
conf=/etc/bashclub/zsync.conf
( . "$conf"; ssh -p "$sshport" "$source" "zfs list -H -t snapshot -o name | grep '@zfs-auto-snap_${zfs_auto_snapshot_label}-' | xargs -r -n1 zfs destroy -v" )
~~~

### Local replication (pool to pool)
To replicate datasets of the same host, e.g. from `rpool` to a backup pool, set `source=local`: the commands run on this host without ssh (no ssh login to localhost needed), `remote-snapshot-manager` and checkzfs work locally. Datasets in the target are never selected, also if the target is in the same pool and inherits `bashclub:zsync`. `source=root@localhost` still works as before.

### Bookmarks on the source
If the replication stops longer than the source keeps its snapshots, the rotation deletes the snapshot the replica ends with, and only a full replication would help. With `source_bookmark=1` (default for new configurations) `bashclub-zsync` keeps a ZFS bookmark of the newest replicated snapshot on the source, e.g. `rpool/data#zsync_backup1_backup_pve1` (backup host and target in the name, so several backup servers do not interfere). A bookmark takes no space and holds no data, the rotation can still delete the snapshot. The next run then continues from the bookmark (also raw encrypted). A rollback on the source destroys newer bookmarks (`zfs rollback -r`), so a replica is never appended to a different history; see [Rollback on the source](#rollback-on-the-source) for this case. Bookmarks of datasets that are no longer replicated stay on the source (`zfs list -t bookmark`).

### Holds on the source
ZFS itself only protects the snapshot that is being sent. With `source_hold=1` (default for new configurations) `bashclub-zsync` puts a hold (`zfs hold`, tag per backup host and target like the bookmark) on the base and on all snapshots that are still to be sent, before the transfer of a dataset starts, and releases them when the dataset is done or the run ends. During that time the rotation (`zfs-auto-snapshot`, `remote-snapshot-manager`) or an admin cannot delete them (`dataset is busy`), they are deleted with the next rotation. A hold left over by a killed run is released by the next run of the same configuration; to release it manually:
~~~
zfs holds -r <pool> | grep zsync_
zfs release <tag> <snapshot>
~~~

### Resuming interrupted transfers
With `transfer_resume=1` (default for new configurations) the replica is received with `zfs receive -s`. If a transfer is interrupted (network, reboot, killed run), ZFS keeps the received part and the next run continues it (`zfs send -t <token>`) instead of sending the whole delta or the initial replication again, also raw encrypted. If the snapshot was deleted on the source in the meantime, or `transfer_resume=0`, the partial state is discarded (`zfs receive -A`) with a warning, otherwise it would block every further receive into the replica.

### Bandwidth limit
`bandwidth_limit` limits the transfer to the given bytes per second, e.g. `bandwidth_limit=10m` (10 MiB/s, about 84 Mbit/s) for an offsite backup over a shared line. The limit is applied on the backup server with `pv` between `zfs send` and `zfs receive`; install it with `apt install pv`. Without `pv` the transfer runs without limit and the log shows a warning.

### Rollback on the source
If the newest snapshots of a replica do not exist on the source anymore (rolled back or deleted on the source), `bashclub-zsync` continues on a new chain and keeps the old one. Nothing on the target is deleted, so a rollback or a deletion on the source (also by an attacker) can never destroy backups:
- the newest common snapshot is cloned and promoted, the replica continues from it in the same run, without a full replication (also raw encrypted and without root)
- the old chain with all its snapshots stays as `<replica>.zsync-branch-<date>` (property `bashclub:zsync-branch`), child datasets stay below the new chain
- the Checkmk check warns until the admin decides with `bashclub-zsync-maintenance`: keep the old chain (archive) or delete it
- while the old chain exists, the rotation keeps the common snapshot it starts from

Without root the user needs the permissions `clone`, `promote` and `rename` on its target (see [Running without root](#running-without-root)); without them the dataset is reported as before (newest common snapshot in the log and the Checkmk check) until it is fixed.

### refquota
The `refquota` of a filesystem is replicated with the initial replication only. If it is raised on the source later, the target keeps the old value and the replication fails with "quota exceeded" as soon as the data exceeds it. Before each incremental replication `bashclub-zsync` therefore raises the `refquota` on the target to the value of the source, or removes it if the source has none. It never lowers it, and `quota` is not changed.

### Monitoring with Checkmk
`bashclub-zsync` writes the state of each configuration as Checkmk service `<checkzfs_prefix> <config>` (with the default prefix `zsync <config>`). It goes into the spool of the Checkmk agent, in the same file as the checkzfs output: `/var/lib/check_mk_agent/spool/<checkzfs_spool_maxage>_<checkzfs_prefix>`, the name checkzfs used before 2.0. The number in the name is the maximum age the agent accepts for the file.
- **Where:** on the backup server, or with `checkzfs_spool=1` on the source.
- **Several backup servers on one source** need different `checkzfs_prefix` values, as for checkzfs before; otherwise they overwrite each other's file. The same applies to several configurations with the same prefix on one backup server.

It writes it at the end of each run (also after an error), every 5 minutes during a run (on the source only when the state changes), and on request. With the spool on the source the services stay visible while the backup server is switched off between the runs (e.g. a backup server that only starts for the replication); if no run comes anymore, the spool file becomes older than its maxage and Checkmk reports the services as missing. To disable it: `touch /etc/bashclub/zsync-checkmk.disabled`.

Show the state and refresh the spool at once (checkzfs and the services of `bashclub-zsync`, without snapshots, replication or deletion; exit code 0 OK, 1 WARN, 2 CRIT), for `/etc/bashclub/zsync.conf`, for all configurations, or in the raw Checkmk format:
~~~
bashclub-zsync -c /etc/bashclub/zsync.conf -s
bashclub-zsync -s
bashclub-zsync -c /etc/bashclub/zsync.conf -s checkmk
~~~
The evaluation reads only status files of `bashclub-zsync` and `/proc`, it never calls `zfs` itself (the check `/usr/share/bashclub-zsync/checkmk/bashclub_zsync`):

| State | Detection |
|---|---|
| last successful run too old | WARN after interval + max(20 %, 5 min) + duration of the last successful run, CRIT after 3 intervals |
| last run failed | WARN |
| phase without transfer too long (listing, snapshots, deletion, checkzfs) | WARN 15 min, CRIT 1 h |
| transfer without progress (bytes read by `zfs receive`) | WARN 10 min, CRIT 30 min |
| process of the run blocked in state D, e.g. waiting for ZFS (with kernel function) | WARN 5 min, CRIT 15 min |
| run aborted (killed, crashed, power loss) | WARN until the next run |
| 3 or more runs skipped during one active run | WARN |
| dataset without common snapshot with the source, or replica without snapshots (full replication needed) | CRIT, with cause |
| replication of a dataset failed and its base is the oldest snapshot of its interval on the source (chain at risk) | WARN |
| old chain after a rollback on the source (see [Rollback on the source](#rollback-on-the-source)) | WARN until kept or deleted |
| replica without source dataset, or source no longer selected (after 1 day) | WARN |

The interval is the median of the start intervals of the last 10 runs, so it needs no configuration and manual runs do not change it. Until 5 intervals are known (learning phase) the age check is at most WARN. `monitor_max_age` in the configuration sets the maximum age instead (WARN, CRIT at 3 times the value), `monitor_max_age=0` disables the age check, e.g. for removable disks. All other checks are active from the first run. The thresholds can be changed in `/etc/bashclub/zsync-checkmk.conf`, e.g. `stall_crit=3600` (variables at the top of the check).

The age of the replicated snapshots per dataset is still checked by checkzfs.

### State of the datasets
`bashclub-zsync` records a state per dataset in `/var/lib/bashclub-zsync/<user>/<config>.datasets` and logs a copyable fix:
- **no common snapshot with the source**: either the rotation on the source has deleted all snapshots of the replica (the replication was stopped longer than the snapshots are kept), or the dataset was created again on the source. Only a full replication helps; rename the replica to keep it, the next run replicates again: `zfs rename <replica> <replica>.broken-<date>`
- **chain at risk**: the replication of a dataset failed and its base is the oldest snapshot of its interval on the source; with the next rotation there is no common snapshot anymore
- **rotation on the target blocked**: the oldest source snapshot of an interval is missing on the target (e.g. a leftover snapshot of another engine with the same label, see [Snapshot label](#snapshot-label-and-snapshot-engine)), so zsync deletes no snapshots of this interval on the target. The replication itself succeeded, the run is not failed; the monitoring warns until the snapshot is gone.
- **replica only on the target**: the dataset was deleted or renamed on the source, or it is no longer selected (`bashclub:zsync`). It is not replicated anymore and never deleted automatically. To keep it as archive without warning: `zfs set bashclub:zsync-orphan=keep <replica>`. One target per source: datasets of another configuration in the same target would count as replicas without source.

### Decisions: bashclub-zsync-maintenance
`bashclub-zsync` detects and reports, the admin decides on the backup server, `bashclub-zsync-maintenance` runs the action. It collects the open cases of all configurations, shows context, options and the exact commands (for a deletion also what ZFS would delete), asks for confirmation, runs the action under the lock of the configuration (never during a run) and logs every decision with time and user to `/var/log/bashclub-zsync/maintenance.log` and syslog.

| case | options |
|---|---|
| replica only on the target (orphan) | `keep` (`bashclub:zsync-orphan=keep`), `delete`, `later` |
| no common snapshot with the source, or replica without snapshots | `rename` (the old replica stays, the next run replicates again), `delete` (the next run replicates again), `later` |
| snapshots of the label in another name scheme on the target | `delete`, `later` |
| old chain after a rollback on the source (`<replica>.zsync-branch-<date>`) | `keep` (archive, no warning anymore), `delete` (the replication already continues on the new chain), `later` |

All open cases one after the other:
~~~
bashclub-zsync-maintenance
~~~
Without questions, e.g. for scripts: `bashclub-zsync-maintenance --list [--tsv]` and `bashclub-zsync-maintenance --decide <case> <option> [--dry-run]`.

### Snapshots to keep on the backup server
Each label in `snapshot_filter` can have the number of its snapshots that stay on the backup server: `snapshot_filter="hourly=24|daily=30|weekly=8|monthly=12"`. These snapshots are kept whatever happens on the source, so deleting snapshots on the source (also by an attacker) cannot shrink the backup. A label alone or `label=source` keeps the previous behavior: the backup server deletes what the source deleted, at least `min_keep` remain (deprecated, it will be removed in a later version). Existing configurations keep working unchanged; `bashclub-zsync-setup` writes numbers for new ones.

Limit: who controls the source can still create many new snapshots of a label, so they push the older ones out of the number kept on the backup server.

### Original properties of the source
The replication changes or leaves out some properties: `mountpoint` (not received), `canmount` (`noauto`), `com.sun:auto-snapshot` and the tag (not received), `refquota` (raised on the target, see [refquota](#refquota)); without root also the properties a job user may not set. After each dataset `bashclub-zsync` saves their values on the source and where they come from on the replica, as user properties `bashclub:zsync-source.<property>=<local|inherited|default|received>:<value>`. Show them for the replicas of `/etc/bashclub/zsync.conf`:
~~~
( . /etc/bashclub/zsync.conf; zfs get -H -o name,property,value -s local -r all "$target" | grep 'bashclub:zsync-source\.' )
~~~
After a restore, the values that were set locally on the source are set again on the restored dataset; inherited and default values come back by themselves. The commands for all restored datasets below `rpool/data` (the restored dataset of a replica `<target>/rpool/data`), shown first and run after checking them:
~~~
restored=rpool/data
zfs get -H -o name,property,value -s local -r all "$restored" | awk -F'\t' '$2 ~ /^bashclub:zsync-source\./ && $3 ~ /^local:/ { sub(/^bashclub:zsync-source\./, "", $2); sub(/^local:/, "", $3); printf "zfs set \"%s=%s\" %s\n", $2, $3, $1 }'
~~~

### Exit code
A failing dataset never stops the run: all other datasets are replicated, the errors are collected and returned at the end.
- `0`: all datasets replicated. Warnings (e.g. a blocked rotation on the target) do not change the exit code, the monitoring reports them.
- `1`: at least one dataset was not replicated, or the run stopped at once because nothing can be replicated: wrong configuration (empty `source`), the source is not reachable, or the same configuration is already running (the run is skipped).

### Running without root
`bashclub-zsync` can run as an unprivileged user on the backup server and log in to the source as an unprivileged user. Both only get the ZFS permissions they need (`zfs allow`), there is no root login on the source anymore. On Linux only root may mount, so the replicas are received without mounting (`zfs receive -u`); the users of the group `bashclub-zsync` write the run status into their own folder (`/var/lib/bashclub-zsync/<user>`), logs go to the journal or to the log file systemd opens for them.

Run the following blocks as root on the backup server, once per configuration. They read target, source and port from the configuration and set up the source over the existing root access.

1. User `zsync` on the backup server, member of the group `bashclub-zsync`, with its own ssh key:
~~~
conf=/etc/bashclub/zsync.conf
id zsync > /dev/null 2>&1 || useradd --system --create-home --home-dir /var/lib/zsync --shell /bin/bash --groups bashclub-zsync zsync
test -f /var/lib/zsync/.ssh/id_ed25519 || su - zsync -c 'install -d -m 700 ~/.ssh && ssh-keygen -q -t ed25519 -N "" -f ~/.ssh/id_ed25519'
~~~
2. Target with the permissions to receive. `zsync` gets the properties `zfs send -p` can bring along, except `sharenfs`/`sharesmb` and those that decide whether and how root mounts a replica (`mountpoint`, `canmount`, `setuid`, `exec`, `devices`). The target gets `mountpoint=none`, which `zsync` cannot change, so no replica is ever mounted by root with content an unprivileged user received. `zfs receive` skips these properties with "permission denied"; their values of the source are saved on the replica (see [Original properties of the source](#original-properties-of-the-source)):
~~~
( . "$conf"
  zfs list "$target" > /dev/null 2>&1 || zfs create -p -o canmount=noauto -o com.sun:auto-snapshot=false "$target"
  zfs set mountpoint=none "$target"
  zfs allow -u zsync create,receive,mount,destroy,rollback,clone,promote,rename,hold,release,userprop,aclinherit,aclmode,acltype,atime,checksum,compression,context,copies,dedup,defcontext,dnodesize,filesystem_limit,fscontext,logbias,nbmand,overlay,primarycache,quota,readonly,recordsize,redundant_metadata,refquota,refreservation,relatime,reservation,rootcontext,secondarycache,snapdev,snapdir,snapshot_limit,special_small_blocks,sync,volmode,volsize,vscan,xattr "$target" )
~~~
3. User `zsync` on the source with the key of the backup server and the permissions to send, snapshot, hold and bookmark on all pools:
~~~
( . "$conf"; key=$(cat /var/lib/zsync/.ssh/id_ed25519.pub)
  ssh -p "$sshport" "$source" "id zsync > /dev/null 2>&1 || useradd --system --create-home --home-dir /var/lib/zsync --shell /bin/bash zsync
    install -d -m 700 -o zsync -g zsync /var/lib/zsync/.ssh
    grep -qxF '$key' /var/lib/zsync/.ssh/authorized_keys 2> /dev/null || echo '$key' >> /var/lib/zsync/.ssh/authorized_keys
    chown zsync: /var/lib/zsync/.ssh/authorized_keys; chmod 600 /var/lib/zsync/.ssh/authorized_keys
    for p in \$(zpool list -H -o name); do zfs allow -u zsync send,snapshot,destroy,mount,hold,release,bookmark \$p; done" )
~~~
4. Restrict the key to the commands of bashclub-zsync (`command=`), to the snapshots, hold tag and bookmark of this configuration (`--label`, `--job-tag`) and to the address of this backup server (`from=`, as the source sees it). Installs the package `bashclub-zsync-source` on the source, which needs the bashclub package source there as for `bashclub-zsync`:
~~~
( . "$conf"; key=$(cat /var/lib/zsync/.ssh/id_ed25519.pub)
  limits="--label $zfs_auto_snapshot_label --job-tag zsync_$(hostname -s)_${target//\//_}"
  ssh -p "$sshport" "$source" "apt-get install -y bashclub-zsync-source > /dev/null || exit 1
    keys=/var/lib/zsync/.ssh/authorized_keys
    grep -vF '${key#* }' \$keys > \$keys.new
    echo \"restrict,from=\\\"\${SSH_CLIENT%% *}\\\",command=\\\"/usr/bin/bashclub-zsync-remote $limits\\\" $key\" >> \$keys.new
    chown zsync: \$keys.new; chmod 600 \$keys.new; mv \$keys.new \$keys; grep -F '${key#* }' \$keys" )
~~~
5. Switch the configuration to the user and test the connection:
~~~
( . "$conf"; sed -i "s|^source=.*|source=zsync@${source#*@}|" "$conf"
  su - zsync -c "ssh -p $sshport -o StrictHostKeyChecking=accept-new zsync@${source#*@} zfs list -H -o name" | head -n 3 )
~~~
6. Run as `zsync` with a systemd timer: cron jobs of this configuration are taken over (schedule and log file), then the timer runs as `zsync`. systemd opens the log file as root, the log folder stays writable only for root:
~~~
bashclub-zsync-timer migrate "$(basename "$conf" .conf)"
bashclub-zsync-timer enable "$(basename "$conf" .conf)" --user zsync
~~~
The checkzfs output goes to the checkmk spool `/var/lib/check_mk_agent/spool` (with `checkzfs_spool=1` on the source). It belongs to root; `bashclub-zsync` logs a warning and skips it until the group may write there:
~~~
install -d -m 3775 -g bashclub-zsync /var/lib/check_mk_agent/spool
~~~
The snapshot engine `zas` (zfs-auto-snapshot on the source) also works as user `zsync` with these permissions.

With `command=` the user `zsync` on the source cannot open a shell: `bashclub-zsync-remote` runs only the commands bashclub-zsync, remote-snapshot-manager and checkzfs send (zfs list/get/send, the checkzfs spool), without a shell. With `--label` and `--job-tag` it creates and destroys only the snapshots of this label (`<label>-YYYY-MM-DD-HHMM`, with zas `zfs-auto-snap_<label>-...`) and uses only this hold tag and bookmark: a backup server that is taken over cannot destroy the other snapshots of the source (zfs-auto-snapshot, other backup servers, manual ones). After changing `zfs_auto_snapshot_label` or `target` run the block again. Denied commands end with exit code 126 and are logged to syslog: `journalctl -t bashclub-zsync-remote`.

### Users per replication job on the source
With the package `bashclub-zsync-source` on the source each replication job gets its own user `zsync-<job>`: its key only works from the address of its backup server, only runs the commands of bashclub-zsync (`command=`, see above) and it may only read the datasets selected by the tag of its configuration. Another backup server or configuration cannot use it. The package also creates the management user `zsync`, which may only run `bashclub-zsync-job-user` with sudo (no password, login only with a key), so a setup tool needs no root access to the source.

Run as root on the backup server, once per configuration, after the blocks 1 and 2 of [Running without root](#running-without-root). The job name is derived from host and configuration, the block sets up the source over the existing root access and switches the configuration to the job user:
~~~
conf=/etc/bashclub/zsync.conf
( . "$conf"; job=$(echo "$(hostname -s)-$(basename "$conf" .conf)" | tr 'A-Z_.' 'a-z--' | cut -c1-26)
  key=$(cat /var/lib/zsync/.ssh/id_ed25519.pub)
  ssh -p "$sshport" "$source" "apt-get install -y bashclub-zsync-source > /dev/null || exit 1
    bashclub-zsync-job-user add --label $zfs_auto_snapshot_label --job-tag zsync_$(hostname -s)_${target//\//_} $job \${SSH_CLIENT%% *} $key \
      && bashclub-zsync-job-user allow $job $tag" || exit 1
  sed -i "s|^source=.*|source=zsync-$job@${source#*@}|" "$conf"
  su - zsync -c "ssh -p $sshport -o StrictHostKeyChecking=accept-new zsync-$job@${source#*@} zfs get -H -o name,value $tag" | head -n 3 )
~~~
Then continue with block 6 of [Running without root](#running-without-root). On the source:
- `bashclub-zsync-job-user list` shows the job users with address and datasets
- `bashclub-zsync-job-user allow <job> <tag>` again after tagging more datasets (permissions follow the tag)
- `bashclub-zsync-job-user remove <job>` removes user and permissions
- for the checkzfs spool on the source (`checkzfs_spool=1`) the job users are in the group `bashclub-zsync`: `install -d -m 3775 -g bashclub-zsync /var/lib/check_mk_agent/spool`

Only `ssh-ed25519` keys are accepted.

### Run with systemd timers
The configuration decides who starts its runs (`trigger`):
- `cron` – also without the setting: the configuration runs as before from cron (or by hand), nothing is changed by an update
- `systemd` – a timer `bashclub-zsync@<name>.timer` for `/etc/bashclub/<name>.conf`, created from the settings `schedule` (cron format, several separated by `;`), `run_as` (user, empty = root) and `log_file` (empty = journal)
- `autorun` – removable disk (`zsync-autorun@`, udev): no timer, no age check in the Checkmk check (unless `monitor_max_age` is set)

A run missed while the host was off is started after the next boot, a timer never starts a second run while the previous one is still active, and the Checkmk check takes the interval for the age check from the timer.

Switch `/etc/bashclub/zsync.conf` to a timer at 23:00 (writes `trigger=systemd` and `schedule` into the configuration and activates it), show all configurations, and read the log:
~~~
bashclub-zsync-timer enable zsync "0 23 * * *"
bashclub-zsync-timer list
journalctl -u bashclub-zsync@zsync
~~~
After editing `trigger`, `schedule`, `run_as` or `log_file` in a configuration, activate the changes for all configurations; the dry run only shows what would be started, updated or stopped:
~~~
bashclub-zsync-timer sync --dry-run
bashclub-zsync-timer sync
~~~
Take over existing cron jobs that run `bashclub-zsync -c /etc/bashclub/<name>.conf`, also scripts in `/etc/cron.{hourly,daily,weekly,monthly}`: schedule, user and log file go into the configuration, the cron lines are commented out and the timers activated. Schedules that systemd cannot run exactly (e.g. `@reboot`) are listed and left as they are:
~~~
bashclub-zsync-timer migrate --dry-run
bashclub-zsync-timer migrate
~~~
`bashclub-zsync-timer enable <name> --user <user> --log <file>` sets `run_as` and `log_file`, `bashclub-zsync-timer disable <name>` writes `trigger=cron` and stops the timer. The timers are generated at boot and with `systemctl daemon-reload` (generator `bashclub-zsync-generator`), so a configuration with `trigger=systemd` also gets its timer after a reboot without `sync`. The package does not change any configuration by itself, it only shows a hint if cron jobs exist. TrueNAS SCALE keeps using cron.

### Removable disks
`bashclub-zsync-disk` prepares a removable disk, connecting it later starts `zsync-autorun@<label>`: it imports the pool (and opens LUKS with the key file), replicates with the configuration of the disk, exports the pool, powers off the disk and mails the result to root. The disk must not be mounted or used (pool, LVM, RAID, LUKS) and its serial number has to be typed to confirm.

Show the disks that can be used:
~~~
bashclub-zsync-disk list
~~~
Create the configuration of the disk first, its target has to be in the pool of the disk: `bashclub-zsync-setup --autorun --target usb-backup1/pve1 usb-backup1` (no timer, `zsync-autorun` runs it as root, the job user on the source gets the key of root). Then prepare the disk with LUKS2 (key file `/etc/bashclub/<label>.key`, keep a copy outside of the host), optionally a passphrase as second key (e.g. a YubiKey with a static password: `ykman otp static --generate 2`) and the configuration of the disk (linked as `/etc/default/zsync-autorun@<label>`, `trigger=autorun`):
~~~
bashclub-zsync-disk create /dev/disk/by-id/usb-... usb-backup1 --luks --passphrase --config usb-backup1
~~~
The udev rule `/etc/udev/rules.d/90-zsync-autorun-<label>.rules` matches the UUID of this disk only. A configuration with `trigger=autorun` gets no timer and no age check in the monitoring. The manual steps are in [notizen-luks](notizen-luks).

### Define a cronjob
#### cron.d example
File: /etc/cron.d/bashclub-zsync
~~~
00 23 * * * root /usr/bin/bashclub-zsync -c /etc/bashclub/zsync.conf >> /var/log/bashclub-zsync/zsync.log
~~~

#### cron.{hourly|daily|weekly|monthly}
File: /etc/cron.hourly/bashclub-zsync
~~~
/usr/bin/bashclub-zsync -c /etc/bashclub/zsync.conf >> /var/log/bashclub-zsync/zsync.log
~~~

Only one run per configuration is active at a time, a second run is skipped with an error message.
Append to the log (`>>`): `>` would empty the log of a run that is still active, even if the new run is skipped.
Logs in `/var/log/bashclub-zsync/` are rotated weekly by logrotate. A log file in a directory that no logrotate config mentions is rotated by `bashclub-zsync` itself at 10 MiB (4 compressed old logs are kept).

## Restore
The package `bashclub-zsync-restore` restores replicas in both directions, whichever the network allows:
- **pull**: the system to restore reads from the backup server. It logs in as a restore user who can only read the replicas of one configuration. The backup server needs no access to the system, and the system cannot change or delete any backup.
- **push**: the backup server writes to the system to restore, typically a fresh Proxmox or a rescue system with sshd and zfs. It uses a one-time key that expires and only works from the backup server.

It is recommended by `bashclub-zsync`, so it is installed on the backup server with it. For pull, install it on the system to restore as well (repository as in [Installation](#installation)): `apt install bashclub-zsync-restore`.

### Access for a restore
**Pull.** 1. On the system to restore, create its key and print the command for the backup server:
~~~
bashclub-zsync-restore access key
~~~
2. On the backup server as root, run the printed command and choose the configuration. It creates the user `zsync-restore-<configuration>`:
   - Its key works only from the address of the system and only runs `bashclub-zsync-restore-remote`: `zfs list`, `get` and `send` and holds with a restore tag, all below the target of the configuration.
   - ZFS allows it only `send,hold,release` on this target (`zfs allow`), no `destroy`, `rename` or `receive`.
   - Denied commands end with exit code 126 and are logged to syslog: `journalctl -t bashclub-zsync-restore-remote`.

3. On the system to restore, run the printed connection test.

With NAT in between, the backup server sees another address than the system: replace the address in the printed command by the one the backup server sees. `bashclub-zsync-restore access key <backup server>` prints the address of the system towards the backup server instead of all its addresses.

**Push.** On the backup server as root, set the address of the system to restore in the first line:
~~~
host=192.0.2.10
bashclub-zsync-restore access push "$host"
~~~
It prints three commands:
- the line for `/root/.ssh/authorized_keys` on the system, with `restrict`, `from=<address of the backup server>` and `expiry-time` (valid for 3 days, `--days <n>`; needs OpenSSH 8.2 or newer);
- the connection test on the backup server;
- the command that removes the line again after the restore.

Each push gets its own key, never the key of a replication job.

On the backup server:
- `bashclub-zsync-restore access list` shows the restore users and push keys
- `bashclub-zsync-restore access remove <user|push key>` removes a restore user with its permissions, or a push key; for a push key it prints the command for the system

### Restoring datasets
All commands work in three ways:

| option | way |
|---|---|
| `--from zsync-restore-<configuration>@<backup server>` | pull: run on the system to restore |
| `--to <system>` | push: run on the backup server, with the push key |
| neither | both on the backup server, e.g. into another pool (`--config <configuration>` for names below its target) |

A replica is named by its full name on the backup server, or with pull and `--config` by its name on the source.

Show the replicas and their state on the system, then one chain:
~~~
bashclub-zsync-restore list --from zsync-restore-pve1@192.0.2.20
bashclub-zsync-restore show --from zsync-restore-pve1@192.0.2.20 rpool/data/vm-100-disk-0
~~~
`show` compares the snapshots by GUID: `=` exists on both sides, `+` is missing on the system, `!` exists only on the system after the common snapshot. At the end it prints the matching restore command.

**dataset** restores a dataset with its complete snapshot chain:
- `--recursive` includes its children; `--snapshot <name>` restores up to this snapshot instead of the newest; `--as <dataset>` restores under another name.
- Encrypted datasets are sent raw (the key never leaves the source). Load the key afterwards; the report prints the command.
- The original properties (see [Original properties of the source](#original-properties-of-the-source)) are set again. Mountpoint and tag are only set at the original place, so a copy under another name is not mounted over the original and not backed up twice.
- An existing dataset is never overwritten. `--force` renames it to `<dataset>.before-restore-<time>` first.

**reattach** sends only the snapshots that are missing on the system after the common one, e.g. after a rollback or a lost snapshot there. The GUIDs stay the same, so the replication continues without a full replication. Snapshots or changes on the system after the common snapshot block it; `--rollback` destroys them (the plan lists them first).

Each command shows the plan first (datasets, snapshots, size, action); `--dry-run` also shows the commands and changes nothing. Then it writes a restore job and asks whether to start it (`--start`: without asking).

### Restore jobs
A job runs in the background (systemd unit `bashclub-zsync-restore@<job>`, without systemd with `setsid`), so it survives the end of the ssh session:
- `bashclub-zsync-restore status <job> --follow` shows the progress (bytes, rate, time left); Ctrl-C ends only the display.
- `bashclub-zsync-restore jobs` lists all jobs.
- `bashclub-zsync-restore stop <job>` stops a job, `bashclub-zsync-restore resume <job>` continues it.

Every start plans again from what is on the system:
- an interrupted transfer continues from its resume token;
- finished datasets are skipped;
- a failed transfer is retried 3 times, after 30, 60 and 120 seconds.

While a job runs, the snapshots it sends are held (`zfs hold`), so the rotation of bashclub-zsync cannot delete them. A `reattach` on the backup server also waits for a running replication of the configuration. With push, the state is also copied to `/run/bashclub-zsync-restore.state` on the system, so it can be read there without this package.

At the end the job checks each dataset against the plan and writes a report: OK, WARN or ERROR per dataset (`status <job>`). The check covers:
- the same snapshots by GUID;
- the requested snapshot is the newest;
- no partial receive is left;
- the same `logicalreferenced`;
- the restored properties;
- the key status of encrypted datasets.

`--scrub` adds a scrub of the restored pools, the only check that reads all data. The job ends with exit code 0 only if everything is OK.

Jobs, logs and reports are in `/var/lib/bashclub-zsync-restore/jobs`. The log is also in the journal: `journalctl -u bashclub-zsync-restore@<job>`.

### Full restore of a server
`server` restores all replicas of a configuration in one job: parents first, with the original properties, raw for encrypted datasets.
- `--pool <pool>` restores only these pools.
- `--exclude <dataset>` leaves out a dataset and its children (names on the source).
- `--map <from>=<to>` restores under other names; the longest `<from>` wins (e.g. `--map rpool=tank --map rpool/data=fast/vm`).
- `--snapshot <name>` gives one point in time: each dataset takes this snapshot, or its newest one that is not newer.
- Pool roots are never replaced, only their children are restored. A pool missing on the system stops the plan.
- Existing datasets need `--force` (they are renamed, as with `dataset`).

Restore the data pools onto a fresh Proxmox with the root file system of the new installation, pulled from the backup server (the restore user of the configuration `pve1`):
~~~
bashclub-zsync-restore server --from zsync-restore-pve1@192.0.2.20 --exclude rpool/ROOT
~~~
If `rpool/data` itself was replicated (tag `all` instead of `subvols`), the plan stops at the `rpool/data` of the fresh installation. Then add `--force`, which renames it to `rpool/data.before-restore-<time>`.

The plan ends with what to check afterwards. It is not changed automatically:
- `/etc/pve/storage.cfg` if pool names change;
- the VM and CT configurations: they name storages, so with the same storage names they work unchanged;
- `proxmox-boot-tool refresh` if a root file system was restored;
- network, host name and keys.

A root pool (`rpool/ROOT`) is restored from a rescue system with sshd and zfs, by push from the backup server:
1. create the pool there;
2. `bashclub-zsync-restore access push <system>`, and add the printed line there;
3. `bashclub-zsync-restore server --to <system> --config pve1 --pool rpool`;
4. on the system: `proxmox-boot-tool` and the boot loader.

### Guided restore
Without parameters, `bashclub-zsync-restore` asks for each step:
- the way: push, this host or pull;
- the configuration;
- what to restore: dataset, reattach, server or files;
- the dataset and the snapshot (the newest 15);
- children and name.

At the end it prints the complete command, to copy and document, and runs it after a confirmation. The command then shows the plan and asks again before it starts.

### Single files: read-only clones on the backup server
~~~
bashclub-zsync-restore mount <replica>@<snapshot>
~~~
`mount` makes a read-only clone of the snapshot in `<pool>/zsync-restore-clones` (outside of the targets) and mounts it below `/run/bashclub-zsync-restore/mnt/<clone>`.
- **Volumes:** its partitions are mounted read-only. The journal is not replayed: `noload` for ext3/4, `norecovery` for xfs. LVM, LUKS or an unknown file system shows the device instead.
- **Encrypted replicas:** only with their key loaded on the backup server, otherwise it prints the `zfs load-key` command.
- **Rotation:** while the clone exists, the rotation of bashclub-zsync keeps its snapshot and logs that a clone depends on it.

`bashclub-zsync-restore mounts` lists the clones. `bashclub-zsync-restore cleanup <clone>` (or `--all`) unmounts and destroys them; it only touches clones made by `mount`.

## Releases
Packages are built by Forgejo CI on https://code.bashclub.org/bashclub/zsync:
- pull request: build and test only
- merge to `main`: publish to the **testing** repository
- tag `vX.Y.Z` (e.g. via "New release" in Forgejo): build, test and publish version `X.Y.Z` to the **release** repository

The version shown by `bashclub-zsync -h` is read from the installed package, so there is nothing to bump in the code. Please add the changes to `CHANGELOG.md` before tagging.

# Roadmap

The roadmap and the open tickets are in the issue tracker: https://code.bashclub.org/bashclub/zsync/issues/16
Ideas for later include parallel replication per dataset, an own snapshot check instead of checkzfs and e-mail
notifications.


# License

Since version 2.0.0 bashclub-zsync is licensed under the GNU General Public License, version 3 or later
([LICENSE](LICENSE), `SPDX-License-Identifier: GPL-3.0-or-later`). Versions up to 1.0.19 were published under the
MIT license; their notice is kept in the copyright file of the packages (`/usr/share/doc/bashclub-zsync/copyright`).
Contributions: see [CONTRIBUTING.md](CONTRIBUTING.md).


# Author

### Thorsten Spille
[<img src="https://storage.ko-fi.com/cdn/brandasset/kofi_s_tag_dark.png" rel="Support me on Ko-Fi">](https://ko-fi.com/thorakel)
