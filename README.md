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

# pipe separated list of snapshot name filters
snapshot_filter="hourly|daily|weekly|monthly"

# minimum count of snapshots per filter to keep
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

# newest target snapshot does not exist on the source anymore (rollback or deleted on the source):
# 1 = roll the target back to the newest common snapshot and continue from there,
# 0 = no replication of this dataset until it is fixed manually (previous behavior)
target_rollback=0

# maximum number of target snapshots a rollback may destroy, otherwise only an error is logged
target_rollback_max=24

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

# set checkzfs parameter "--prefix"
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
If the replication stops longer than the source keeps its snapshots, the rotation deletes the snapshot the replica ends with, and only a full replication would help. With `source_bookmark=1` (default for new configurations) `bashclub-zsync` keeps a ZFS bookmark of the newest replicated snapshot on the source, e.g. `rpool/data#zsync_backup1_backup_pve1` (backup host and target in the name, so several backup servers do not interfere). A bookmark takes no space and holds no data, the rotation can still delete the snapshot. The next run then continues from the bookmark (also raw encrypted). A rollback on the source destroys newer bookmarks (`zfs rollback -r`), so a replica is never appended to a different history; see `target_rollback` for this case. Bookmarks of datasets that are no longer replicated stay on the source (`zfs list -t bookmark`).

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
If the newest snapshot of a replica does not exist on the source anymore (rolled back or deleted on the source), the dataset cannot be appended. By default it is not replicated anymore until it is fixed manually; the log and the Checkmk check name the newest common snapshot. With `target_rollback=1` `bashclub-zsync` rolls the replica back to the newest common snapshot (`zfs rollback -r`, the newer snapshots of the replica are destroyed) and continues from there, if it destroys at most `target_rollback_max` snapshots (default 24). Otherwise it logs the command to roll back manually. Rollbacks are listed in the log and as a hint in the Checkmk check.

### refquota
The `refquota` of a filesystem is replicated with the initial replication only. If it is raised on the source later, the target keeps the old value and the replication fails with "quota exceeded" as soon as the data exceeds it. Before each incremental replication `bashclub-zsync` therefore raises the `refquota` on the target to the value of the source, or removes it if the source has none. It never lowers it, and `quota` is not changed.

### Monitoring with Checkmk
The package contains the local check `bashclub_zsync`. If the Checkmk agent is installed (`/usr/lib/check_mk_agent` exists, also when the agent is installed later), it is linked to `/usr/lib/check_mk_agent/local/bashclub_zsync`. To disable it:
~~~
touch /etc/bashclub/zsync-checkmk.disabled
dpkg-reconfigure bashclub-zsync
~~~
It shows one service `zsync <config>` per configuration and reads only status files of `bashclub-zsync` and `/proc`, it never calls `zfs` itself:

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
| newest snapshot of the replica missing on the source (rollback or deleted on the source) | WARN |
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

All open cases one after the other:
~~~
bashclub-zsync-maintenance
~~~
Without questions, e.g. for scripts: `bashclub-zsync-maintenance --list [--tsv]` and `bashclub-zsync-maintenance --decide <case> <option> [--dry-run]`.

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
  zfs allow -u zsync create,receive,mount,destroy,rollback,hold,release,userprop,aclinherit,aclmode,acltype,atime,checksum,compression,context,copies,dedup,defcontext,dnodesize,filesystem_limit,fscontext,logbias,nbmand,overlay,primarycache,quota,readonly,recordsize,redundant_metadata,refquota,refreservation,relatime,reservation,rootcontext,secondarycache,snapdev,snapdir,snapshot_limit,special_small_blocks,sync,volmode,volsize,vscan,xattr "$target" )
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
