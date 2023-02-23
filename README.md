# zsync

ZFS replication script by Thorsten Spille <thorsten@spille-edv.de>
- replicates ZFS filesystems/volumes with user parameter bashclub:zsync configured
- mirrored replication with existing snapshots
- pull replication only
- creates full path on target pool

## Installation

#### Download and make executable
~~~
wget -q --no-cache -O /usr/bin/bashclub-zsync https://git.bashclub.org/bashclub/zsync/raw/branch/main/bashclub-zsync/usr/bin/bashclub-zsync
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

# if set to bashclub:zsync=subvol, use inherited only or inherited and received
subvol_source="inherited|received"

# snapshot name filter
snapshot_filter="hourly|daily|weekly|monthly"
~~~

### Define a cronjob
#### cron.d example
File: /etc/cron.d/bashclub-zsync
~~~
00 23 * * * root /usr/bin/bashclub-zsync -c /etc/bashclub/zsync.conf > /var/log/bashclub-zsync.log
~~~

#### cron.{hourly|daily|weekly|monthly}
File: /etc/cron.hourly/bashclub-zsync
~~~
/usr/bin/bashclub-zsync -c /etc/bashclub/zsync.conf > /var/log/bashclub-zsync.log
~~~

