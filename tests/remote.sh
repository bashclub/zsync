#!/bin/bash
# Testet bashclub-zsync-remote (command= auf der Quelle) ohne ssh und ohne ZFS: ein zfs-Stub gibt seine
# Argumente aus. Erlaubte Befehle müssen genau diese Argumente ausführen, alles andere wird mit 126 abgewiesen.
# Dass alle Befehle von bashclub-zsync durchgehen, prüft run.sh mit ZTEST_WRAPPER (siehe README).
# Aufruf: tests/remote.sh (ohne root)
here=$(cd "$(dirname "$0")" && pwd)
wrapper=$here/../bashclub-zsync-source/usr/bin/bashclub-zsync-remote
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
printf '#!/bin/bash\necho "zfs $*"\n' > "$w/zfs"
printf '#!/bin/bash\necho "zas $*"\n' > "$w/zfs-auto-snapshot"
printf '#!/bin/bash\n' > "$w/logger"
chmod +x "$w"/*
export PATH=$w:$PATH
passed=0; total=0

# Optionen des Wrappers (wie in authorized_keys): leer oder per job=(--label ... --job-tag ...)
job=()
run() { SSH_ORIGINAL_COMMAND=$1 "$wrapper" "${job[@]}" 2>&1; }
# allow <befehl> <erwartete ausgabe>
allow() {
  local out; ((total++))
  out=$(run "$1"); local rc=$?
  if [ $rc -eq 0 ] && [[ $out == "$2" ]]; then ((passed++)); echo "ok   $1"
  else echo "FAIL $1"; echo "     erwartet: $2"; echo "     erhalten ($rc): $out"; fi
}
deny() {
  local out; ((total++))
  out=$(run "$1"); local rc=$?
  if [ $rc -eq 126 ] && [[ $out == "bashclub-zsync-remote: command not allowed: $1" ]]; then ((passed++)); echo "ok   abgewiesen: $1"
  else echo "FAIL nicht abgewiesen: $1"; echo "     erhalten ($rc): $out"; fi
}

# Befehle von bashclub-zsync, remote-snapshot-manager und checkzfs
allow 'zfs get -H -o name,value,source -t filesystem,volume bashclub:zsync' 'zfs get -H -o name,value,source -t filesystem,volume bashclub:zsync'
allow 'zfs list -Hp -o name,type,refquota -t filesystem,volume' 'zfs list -Hp -o name,type,refquota -t filesystem,volume'
allow 'zfs list -H -o name,guid -s createtxg -t snapshot rpool/data/subvol-100-disk-0 2>/dev/null' 'zfs list -H -o name,guid -s createtxg -t snapshot rpool/data/subvol-100-disk-0'
allow 'zfs send -w -p -v rpool/x@zfs-auto-snap_daily-2026-10-16-0625' 'zfs send -w -p -v rpool/x@zfs-auto-snap_daily-2026-10-16-0625'
allow 'zfs send -w  -i rpool/x#zsync_backup_backup_pve1 rpool/x@daily-02' 'zfs send -w -i rpool/x#zsync_backup_backup_pve1 rpool/x@daily-02'
allow 'zfs send  -t 1-e3f8a2b1c-c8-789c636064000310a500c4ec50360710e72765a5269740' 'zfs send -t 1-e3f8a2b1c-c8-789c636064000310a500c4ec50360710e72765a5269740'
allow 'zfs list -t all -Hp -o name,type,creation,guid,used,available,written,origin,com.sun:auto-snapshot,tv.sysops:checkzfs' 'zfs list -t all -Hp -o name,type,creation,guid,used,available,written,origin,com.sun:auto-snapshot,tv.sysops:checkzfs'
allow 'zfs snapshot rpool/x@backup-2026-10-16-1804' 'zfs snapshot rpool/x@backup-2026-10-16-1804'
allow 'zfs destroy rpool/x@backup-2026-10-01-1804' 'zfs destroy rpool/x@backup-2026-10-01-1804'
allow 'exit' ''
allow 'which zfs-auto-snapshot' "$w/zfs-auto-snapshot"
allow 'for s in rpool/x@a rpool/x@b ; do zfs hold zsync_backup_backup_pve1 $s 2>/dev/null; done; true' $'zfs hold zsync_backup_backup_pve1 rpool/x@a\nzfs hold zsync_backup_backup_pve1 rpool/x@b'
allow 'for s in rpool/x@a ; do zfs release zsync_backup_backup_pve1 $s 2>/dev/null; done; true' 'zfs release zsync_backup_backup_pve1 rpool/x@a'
allow 'zfs list -H -t snapshot -o name -S createtxg rpool/x | grep -E "(@backup-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{4}([[:space:]]|$)|@.*daily)" | tail -1' ''
allow 'zfs get -Hp -o value creation rpool/x; zfs list -Hp -o creation -s createtxg -t snapshot rpool/x | head -1' $'zfs get -Hp -o value creation rpool/x\nzfs list -Hp -o creation -s createtxg -t snapshot rpool/x'
allow 'if [ "$(zfs get -H -o value guid rpool/x#zsync_b 2>/dev/null)" != "$(zfs get -H -o value guid rpool/x@daily-02)" ]; then zfs destroy rpool/x#zsync_b 2>/dev/null; zfs bookmark rpool/x@daily-02 rpool/x#zsync_b; fi' $'zfs destroy rpool/x#zsync_b\nzfs bookmark rpool/x@daily-02 rpool/x#zsync_b'
allow 'which zfs-auto-snapshot > /dev/null || exit 0 ; zfs-auto-snapshot --quiet --syslog --label=backup --keep=3 //' 'zas --quiet --syslog --label=backup --keep=3 //'
allow 'grep -m1 -o aes /proc/cpuinfo | uniq' "$(grep -m1 -o aes /proc/cpuinfo | uniq)"

# Shell, andere Programme, Datasets löschen, Optionen und Namen außerhalb der Formen
deny ''
deny 'bash'
deny 'sh -c id'
deny 'id'
deny 'zfs destroy rpool/x'
deny 'zfs destroy -r rpool/x@a'
deny 'zfs destroy rpool/x@a%b'
deny 'zfs destroy rpool/x@a,b'
deny 'zfs rollback -r rpool/x@a'
deny 'zfs set mountpoint=/tmp rpool/x'
deny 'zfs create rpool/evil'
deny 'zfs receive rpool/x'
deny 'zfs allow -u zsync create rpool'
deny 'zfs list; id'
deny 'zfs list && id'
deny 'zfs list | sh'
deny 'zfs list $(id)'
deny 'zfs list `id`'
deny 'zfs list > /etc/passwd'
deny 'zfs list -H -o name rpool/x
id'
deny 'zfs send -R rpool/x@a'
deny 'zfs send -w rpool/x'
deny 'zfs send -i rpool/x@a'
deny 'zfs list -o name -s "$(id)"'
deny 'zfs get -H -o value guid -rpool/x'
deny 'zfs list -H -t snapshot -o name -S createtxg rpool/x | grep -E "$(id)" | tail -1'
deny 'zfs list -H -t snapshot -o name -S createtxg rpool/x | grep -E "a`id`" | tail -1'
deny 'zfs list -H -t snapshot -o name -S createtxg rpool/x | grep -E "a" | sh'
deny 'for s in rpool/x@a; id ; do zfs hold t $s 2>/dev/null; done; true'
deny 'for s in rpool/x@a /etc ; do zfs hold t $s 2>/dev/null; done; true'
deny 'for s in rpool/x@a ; do zfs destroy t $s 2>/dev/null; done; true'
deny 'zfs get -Hp -o value creation rpool/x; zfs list -Hp -o creation -s createtxg -t snapshot rpool/y | head -1'
deny 'if [ "$(zfs get -H -o value guid rpool/x#a 2>/dev/null)" != "$(zfs get -H -o value guid rpool/x@b)" ]; then zfs destroy rpool/y#a 2>/dev/null; zfs bookmark rpool/x@b rpool/x#a; fi'
deny 'which zfs-auto-snapshot > /dev/null || exit 0 ; zfs-auto-snapshot --quiet --syslog --label=x;id --keep=3 //'
deny 'cat > /etc/cron.d/evil'
deny 'cat > /var/lib/check_mk_agent/spool/../../../../etc/cron.d/evil'
deny 'mv /var/lib/check_mk_agent/spool/a /etc/passwd'
deny 'mkdir -p /etc/evil'
deny 'scp -t /tmp'
deny 'grep -E "^ID=" /etc/shadow'

# mit --label und --job-tag: nur Snapshots, Holds und Bookmarks dieses Jobs
job=(--label zsync-backup1 --job-tag zsync_backup1_backup_pve1)
allow 'zfs snapshot rpool/x@zsync-backup1-2026-10-17-1200' 'zfs snapshot rpool/x@zsync-backup1-2026-10-17-1200'
allow 'zfs destroy rpool/x@zsync-backup1-2026-10-01-1200' 'zfs destroy rpool/x@zsync-backup1-2026-10-01-1200'
allow 'zfs destroy rpool/x@zfs-auto-snap_zsync-backup1-2026-10-01-1200' 'zfs destroy rpool/x@zfs-auto-snap_zsync-backup1-2026-10-01-1200'
allow 'zfs destroy rpool/x#zsync_backup1_backup_pve1' 'zfs destroy rpool/x#zsync_backup1_backup_pve1'
allow 'for s in rpool/x@a ; do zfs hold zsync_backup1_backup_pve1 $s 2>/dev/null; done; true' 'zfs hold zsync_backup1_backup_pve1 rpool/x@a'
allow 'if [ "$(zfs get -H -o value guid rpool/x#zsync_backup1_backup_pve1 2>/dev/null)" != "$(zfs get -H -o value guid rpool/x@b)" ]; then zfs destroy rpool/x#zsync_backup1_backup_pve1 2>/dev/null; zfs bookmark rpool/x@b rpool/x#zsync_backup1_backup_pve1; fi' $'zfs destroy rpool/x#zsync_backup1_backup_pve1\nzfs bookmark rpool/x@b rpool/x#zsync_backup1_backup_pve1'
allow 'which zfs-auto-snapshot > /dev/null || exit 0 ; zfs-auto-snapshot --quiet --syslog --label=zsync-backup1 --keep=3 //' 'zas --quiet --syslog --label=zsync-backup1 --keep=3 //'
allow 'zfs send -w -i rpool/x@zfs-auto-snap_daily-01 rpool/x@zfs-auto-snap_daily-02' 'zfs send -w -i rpool/x@zfs-auto-snap_daily-01 rpool/x@zfs-auto-snap_daily-02'
deny 'zfs destroy rpool/x@zfs-auto-snap_daily-2026-10-01-0625'
deny 'zfs destroy rpool/x@zsync-backup2-2026-10-01-1200'
deny 'zfs destroy rpool/x@zsync-backup1-old-2026-10-01-1200'
deny 'zfs destroy rpool/x@zsync-backup1-manual'
deny 'zfs destroy rpool/x#zsync_backup2_backup_pve1'
deny 'zfs snapshot rpool/x@daily-2026-10-17-1200'
deny 'zfs release admin-hold rpool/x@a'
deny 'zfs hold zsync_backup2_backup_pve1 rpool/x@a'
deny 'for s in rpool/x@a ; do zfs release zsync_backup2_backup_pve1 $s 2>/dev/null; done; true'
deny 'zfs bookmark rpool/x@b rpool/x#zsync_backup2_backup_pve1'
deny 'if [ "$(zfs get -H -o value guid rpool/x#other 2>/dev/null)" != "$(zfs get -H -o value guid rpool/x@b)" ]; then zfs destroy rpool/x#other 2>/dev/null; zfs bookmark rpool/x@b rpool/x#other; fi'
deny 'which zfs-auto-snapshot > /dev/null || exit 0 ; zfs-auto-snapshot --quiet --syslog --label=daily --keep=1 //'
# ungültige Optionen in authorized_keys: alles abgewiesen
job=(--label 'a;b'); ((total++)); out=$(run 'zfs list'); if [[ $? -eq 126 && $out == *"invalid --label"* ]]; then ((passed++)); echo "ok   ungültiges --label"; else echo "FAIL ungültiges --label: $out"; fi
job=(--unknown x); ((total++)); out=$(run 'zfs list'); if [[ $? -eq 126 && $out == *"unknown option"* ]]; then ((passed++)); echo "ok   unbekannte Option"; else echo "FAIL unbekannte Option: $out"; fi

echo "$passed/$total bestanden"
[ $passed -eq $total ]
