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
| Ubuntu 24.04 (`noble`) | apt package |
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
Replace `<codename>` with your release codename (`bookworm`, `trixie` or `noble`).

Debian 13 / Proxmox VE 9 / Ubuntu 24.04 (deb822 format):
~~~
wget -O- https://apt.bashclub.org/gpg/bashclub.pub | gpg --dearmor > /usr/share/keyrings/bashclub-archive-keyring.gpg
cat > /etc/apt/sources.list.d/bashclub.sources << EOF
Types: deb
URIs: https://apt.bashclub.org/release
Suites: <codename>
Components: main
Signed-By: /usr/share/keyrings/bashclub-archive-keyring.gpg
EOF
apt update
apt install bashclub-zsync
~~~

Debian 12 / Proxmox VE 8:
~~~
wget -O- https://apt.bashclub.org/gpg/bashclub.pub | gpg --dearmor > /usr/share/keyrings/bashclub-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/bashclub-archive-keyring.gpg] https://apt.bashclub.org/release <codename> main" > /etc/apt/sources.list.d/bashclub.list
apt update
apt install bashclub-zsync
~~~

`cryptsetup` and a `mail` command (`bsd-mailx`) are installed as recommended packages. They are only needed for `zsync-autorun` (removable disks with LUKS, mail notification).

### TrueNAS SCALE
TrueNAS does not allow installing packages and the system files are replaced on every update. Install the scripts into a dataset on your pool instead, e.g. `tank/scripts` (replace `tank` with your pool name):
~~~
mkdir -p /mnt/tank/scripts/zsync && cd /mnt/tank/scripts/zsync
curl -fsSL -o bashclub-zsync https://code.bashclub.org/bashclub/zsync/raw/branch/main/bashclub-zsync/usr/bin/bashclub-zsync
curl -fsSL -o remote-snapshot-manager https://code.bashclub.org/bashclub/zsync/raw/branch/main/bashclub-zsync/usr/bin/remote-snapshot-manager
# optional: checkzfs for monitoring
curl -fsSL -o checkzfs https://code.bashclub.org/bashclub/checkzfs/raw/branch/main/bashclub-checkzfs/usr/bin/checkzfs
chmod +x bashclub-zsync remote-snapshot-manager checkzfs

# creates zsync.conf on first run, adjust it afterwards
./bashclub-zsync -c /mnt/tank/scripts/zsync/zsync.conf
~~~
`bashclub-zsync` finds `remote-snapshot-manager` and `checkzfs` in its own directory. Keep the configuration on the dataset as well and create the cronjob in the web UI under *System → Advanced Settings → Cron Jobs*, e.g.:
~~~
/mnt/tank/scripts/zsync/bashclub-zsync -c /mnt/tank/scripts/zsync/zsync.conf > /mnt/tank/scripts/zsync/zsync.log 2>&1
~~~
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

# ssh address of remote machine
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

### Define a cronjob
#### cron.d example
File: /etc/cron.d/bashclub-zsync
~~~
00 23 * * * root /usr/bin/bashclub-zsync -c /etc/bashclub/zsync.conf > /var/log/bashclub-zsync/zsync.log
~~~

#### cron.{hourly|daily|weekly|monthly}
File: /etc/cron.hourly/bashclub-zsync
~~~
/usr/bin/bashclub-zsync -c /etc/bashclub/zsync.conf > /var/log/bashclub-zsync/zsync.log
~~~

## Releases
Packages are built by Forgejo CI on https://code.bashclub.org/bashclub/zsync:
- pull request: build and test only
- merge to `main`: publish to the **testing** repository
- tag `vX.Y.Z` (e.g. via "New release" in Forgejo): build, test and publish version `X.Y.Z` to the **release** repository

The version shown by `bashclub-zsync -h` is read from the installed package, so there is nothing to bump in the code. Please add the changes to `CHANGELOG.md` before tagging.

# Roadmap

Following features are on the wishlist:
- Local replication without SSH connections
- Removable device support (Autostart on connect, remove when finished)
- E-Mail notifications
- Internal verification logic for checkzfs replacement
- Parallel replication (multi-threaded, per dataset)
- Resume replication after failure caused by changes on source


# Author

### Thorsten Spille
[<img src="https://storage.ko-fi.com/cdn/brandasset/kofi_s_tag_dark.png" rel="Support me on Ko-Fi">](https://ko-fi.com/thorakel)
