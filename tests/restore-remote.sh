#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Testet bashclub-zsync-restore-remote (command= des Restore-Benutzers auf dem Backupserver) ohne ssh und ohne ZFS:
# ein zfs-Stub gibt seine Argumente aus. Lesende Befehle unter --root müssen genau diese Argumente ausführen, alles
# andere (außerhalb von --root, schreibend, Shell) wird mit 126 abgewiesen.
# Aufruf: tests/restore-remote.sh (ohne root)
here=$(cd "$(dirname "$0")" && pwd)
wrapper=$here/../bashclub-zsync-restore/usr/bin/bashclub-zsync-restore-remote
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
printf '#!/bin/bash\necho "zfs $*"\n' > "$w/zfs"
printf '#!/bin/bash\n' > "$w/logger"
chmod +x "$w"/*
export PATH=$w:$PATH
passed=0; total=0
root=tank/backup/pve1

run() { SSH_ORIGINAL_COMMAND=$1 "$wrapper" --root "$root" 2>&1; }
# allow <befehl> [<erwartete ausgabe>, sonst der Befehl selbst]
allow() {
  local out expected=${2-$1}; ((total++))
  out=$(run "$1"); local rc=$?
  if [ $rc -eq 0 ] && [[ $out == "$expected" ]]; then ((passed++)); echo "ok   $1"
  else echo "FAIL $1"; echo "     erwartet: $expected"; echo "     erhalten ($rc): $out"; fi
}
deny() {
  local out; ((total++))
  out=$(run "$1"); local rc=$?
  if [ $rc -eq 126 ] && [[ $out == "bashclub-zsync-restore-remote: command not allowed: $1" ]]; then ((passed++)); echo "ok   abgewiesen: $1"
  else echo "FAIL nicht abgewiesen: $1"; echo "     erhalten ($rc): $out"; fi
}

# feste Befehle
allow 'exit' ''
allow 'root' "$root"

# lesen unter --root
allow "zfs list -H -o name,type,guid -t filesystem,volume -r $root"
allow "zfs list -Hp -o name,guid,createtxg -s createtxg -t snapshot $root/rpool/data/vm-100-disk-0"
allow "zfs list -H -o name -d 1 $root/rpool"
allow "zfs get -H -o name,property,value -s local all $root/rpool/data"
allow "zfs get -Hp -o value -t snapshot guid $root/rpool/data@daily-2026-10-18-0000"
allow "zfs list -H $root"
allow "zfs send -w -n -v -P $root/rpool/data@daily-1"
allow "zfs send -w -v -P $root/rpool/data@daily-1"
allow "zfs send -L -e -c -p $root/rpool/data@daily-1"
allow "zfs send -w -v -P -I $root/rpool/data@daily-1 $root/rpool/data@daily-5"
allow "zfs send -w -i $root/rpool/data#bm $root/rpool/data@daily-5"
allow "zfs send -v -P -t 1-e3f8a2b1c-c8-789c636064000310a500c4ec50360710e72765a5269740"
allow "zfs hold zsync-restore-20261018-1530-ab12 $root/rpool/data@daily-1 $root/rpool/data@daily-2"
allow "zfs release zsync-restore-20261018-1530-ab12 $root/rpool/data@daily-1"

# außerhalb von --root
deny 'zfs list -H -o name'
deny 'zfs list -H -o name -r tank/backup'
deny 'zfs list -H -o name -r tank/backup/pve10'
deny 'zfs list -H -o name rpool/data'
deny "zfs list -H -o name $root/../pve2"
deny "zfs list -H -o name $root//x"
deny 'zfs get -H -o value guid tank/backup/pve2/rpool/data'
deny "zfs get -H -o value guid $root/x tank/other"
deny 'zfs send -w tank/backup/pve2/rpool/data@daily-1'
deny "zfs send -w -I tank/backup/pve2/x@a $root/x@b"
deny "zfs hold zsync-restore-x tank/backup/pve2/x@a"

# schreibend oder unbekannt
deny "zfs destroy $root/rpool/data@daily-1"
deny "zfs destroy -r $root"
deny "zfs rename $root/rpool/data $root/rpool/x"
deny "zfs receive $root/rpool/data"
deny "zfs recv -F $root/rpool/data"
deny "zfs set mountpoint=/ $root/rpool/data"
deny "zfs inherit mountpoint $root/rpool/data"
deny "zfs rollback $root/rpool/data@daily-1"
deny "zfs snapshot $root/rpool/data@x"
deny "zfs clone $root/rpool/data@x $root/rpool/y"
deny "zfs allow $root"
deny "zfs send -R $root/rpool/data@daily-1"
deny "zfs send -w $root/rpool/data"
deny "zfs send -w $root/rpool/data@a $root/rpool/data@b"
deny "zfs hold keep $root/rpool/data@daily-1"
deny "zfs release zsync_backup $root/rpool/data@daily-1"
deny "zfs list -H -o name -r $root; id"
deny "zfs list -H -o name -r $root && id"
deny "zfs list -H -o name -r \$(id)"
deny "zfs list -H -o name -r $root | sh"
deny "zfs get -H -o value guid $root > /tmp/x"
deny "zfs list -H -o name -r $root"$'\n'"id"
deny 'id'
deny 'sh -c id'
deny 'cat /etc/shadow'
deny 'zfs'

# Option im authorized_keys fehlt oder ist ungültig
((total++)); out=$(SSH_ORIGINAL_COMMAND=root "$wrapper" 2>&1); rc=$?
if [ $rc -eq 126 ]; then ((passed++)); echo "ok   ohne --root abgewiesen"; else echo "FAIL ohne --root: $rc $out"; fi
((total++)); out=$(SSH_ORIGINAL_COMMAND=root "$wrapper" --root 'tank/$(id)' 2>&1); rc=$?
if [ $rc -eq 126 ]; then ((passed++)); echo "ok   ungültiges --root abgewiesen"; else echo "FAIL ungültiges --root: $rc $out"; fi

echo "$passed/$total bestanden"
[ $passed -eq $total ]
