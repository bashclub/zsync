#!/bin/bash
# Führt bashclub-zsync mit Stubs statt zfs/ssh in allen Szenarien aus.
# Ergebnis je Szenario in <ausgabe>: .calls (alle Aufrufe), .log (Ausgabe), .conf, .spool
# Aufruf: tests/run.sh <skript> <ausgabe>   (als root, z. B. im Container)
set -u
here=$(cd "$(dirname "$0")" && pwd)
script=$(readlink -f "$1"); out=$2
mkdir -p "$out"
for sc in "$here"/scenarios/*.sh; do
  n=$(basename "$sc" .sh); w=$(mktemp -d /tmp/zsync-test.XXXX)
  cp "$script" "$w/bashclub-zsync"
  cp "$here"/stubs/{zfs,ssh,scp,remote-snapshot-manager,zfs-auto-snapshot} "$w/"
  DEBUG=0; CHECKZFS=1; CONF=; source "$sc"
  [[ $CHECKZFS == 1 ]] && cp "$here/stubs/checkzfs" "$w/"
  [[ -n $CONF ]] && printf '%s\n' "$CONF" > "$w/zsync.conf"
  rm -rf /var/lib/check_mk_agent/spool /tmp/*_zsync
  : > "$out/$n.calls"
  args=(-c "$w/zsync.conf"); [[ $DEBUG == 1 ]] && args=(-d "${args[@]}")
  ZTEST_LOG="$out/$n.calls" ZTEST_SCENARIO="$sc" bash "$w/bashclub-zsync" "${args[@]}" > "$out/$n.log" 2>&1
  echo "exit=$?" >> "$out/$n.calls"
  sed -i -E "s#^[A-Z][a-z]{2} [ 0-9][0-9] [0-9:]{8} ##; s#$w#<dir>#g" "$out/$n.log" "$out/$n.calls"
  cp "$w/zsync.conf" "$out/$n.conf" 2>/dev/null
  cat /var/lib/check_mk_agent/spool/* > "$out/$n.spool" 2>/dev/null
  rm -rf "$w"
done
