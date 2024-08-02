# Repository moved

This repository has benn moved to https://gitlab.bashclub.org/bashclub/zsync/

## Quick Installation

#### Install via Repository (Debian / Ubuntu / Proxmox)
~~~
echo "deb [signed-by=/usr/share/keyrings/bashclub-archive-keyring.gpg] https://apt.bashclub.org/release bookworm main" > /etc/apt/sources.list.d/bashclub.list
wget -O- https://apt.bashclub.org/gpg/bashclub.pub | gpg --dearmor > /usr/share/keyrings/bashclub-archive-keyring.gpg
apt update
apt install bashclub-zsync
~~~

#### Download and make executable (Other Linux and TrueNAS)
~~~
wget -q --no-cache -O /usr/bin/bashclub-zsync https://gitlab.bashclub.org/bashclub/zsync/-/raw/main/bashclub-zsync/usr/bin/bashclub-zsync
chmod +x /usr/bin/bashclub-zsync
bashclub-zsync
~~~
