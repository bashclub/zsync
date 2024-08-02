**https://gitlab.bashclub.org/bashclub/zsync/
**
---- THIS IS A CLONE OF THE ORIGINAL REPOSITORY ON git.bashclub.org ----

# zsync

ZFS replication script by Thorsten Spille <thorsten@spille-edv.de>
- replicates ZFS filesystems/volumes with user parameter bashclub:zsync (or custom name) configured
- creates optional snapshot before replication (required zfs-auto-znapshot)
- parameter setting uses zfs hierarchy on source
- mirrored replication with existing snapshots (filtered by snapshot_filter)
- pull/local replication only
- auto creates full path on target pool, enforce com.sun:auto-snapshot=false, inherits mountpoint and sets canmount=noauto
- raw replication
- tested on Proxmox VE 7.x/8.x
- ssh cipher auto selection

## Installation

#### Download and make executable
~~~
wget -q --no-cache -O /usr/bin/bashclub-zsync https://git.bashclub.org/bashclub/zsync/raw/branch/dev/bashclub-zsync/usr/bin/bashclub-zsync
chmod +x /usr/bin/bashclub-zsync
bashclub-zsync
~~~

## Configuration
After first execution adjust the default config file `/etc/bashclub/zsync.conf`:

~~~
# target path on local machine
target=backup/px1

# source host
source=user@host

# source host ssh port
sshport=22

# tag to mark source filesystem
tag=bashclub:zsync

# snapshot name filter
snapshot_filter="hourly|daily|weekly|monthly"

# number of minimum snapshots to keep (per snapshot filter)
min_keep=3

# number of zfs snapshots to keep on source (0 = snapshot function disabled)
zfs_auto_snapshot_keep=0

# make snapshot via zfs-auto-snapshot before replication
zfs_auto_snapshot_label="backup"

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

# Author

### Thorsten Spille
[<img src="https://storage.ko-fi.com/cdn/brandasset/kofi_s_tag_dark.png" rel="Support me on Ko-Fi">](https://ko-fi.com/thorakel)
