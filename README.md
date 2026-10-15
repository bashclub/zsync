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
- `bashclub-zsync` lists such snapshots as `[WARN]` (source and target) and reports an `[ERROR]` if the oldest source snapshot of an interval is missing on the target.

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
`bashclub-zsync` records a state per dataset in `/var/lib/bashclub-zsync/<config>.datasets` and logs a copyable fix:
- **no common snapshot with the source**: either the rotation on the source has deleted all snapshots of the replica (the replication was stopped longer than the snapshots are kept), or the dataset was created again on the source. Only a full replication helps; rename the replica to keep it, the next run replicates again: `zfs rename <replica> <replica>.broken-<date>`
- **chain at risk**: the replication of a dataset failed and its base is the oldest snapshot of its interval on the source; with the next rotation there is no common snapshot anymore
- **replica only on the target**: the dataset was deleted or renamed on the source, or it is no longer selected (`bashclub:zsync`). It is not replicated anymore and never deleted automatically. To keep it as archive without warning: `zfs set bashclub:zsync-orphan=keep <replica>`. One target per source: datasets of another configuration in the same target would count as replicas without source.

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

Following features are on the wishlist:
- Removable device support (Autostart on connect, remove when finished)
- E-Mail notifications
- Internal verification logic for checkzfs replacement
- Parallel replication (multi-threaded, per dataset)
- Resume replication after failure caused by changes on source


# Author

### Thorsten Spille
[<img src="https://storage.ko-fi.com/cdn/brandasset/kofi_s_tag_dark.png" rel="Support me on Ko-Fi">](https://ko-fi.com/thorakel)
