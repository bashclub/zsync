#!/bin/bash
# Vergleicht zwei Ergebnisse von run.sh: zuerst nur die verändernden Aufrufe (send, receive, destroy,
# create, set, unmount, Snapshots, checkzfs, scp, Exit-Code), dann alle Aufrufe und die Logs.
# Aufruf: tests/compare.sh <alt> <neu>
old=$1 new=$2
changing='^(source|target): zfs (send|receive|destroy|create|set|unmount|rollback|snapshot)|^(remote-snapshot-manager|zfs-auto-snapshot|checkzfs|scp) |^exit='
for f in "$old"/*.calls; do
  n=$(basename "$f" .calls)
  echo "===== $n"
  if diff <(grep -E "$changing" "$f") <(grep -E "$changing" "$new/$n.calls") > /tmp/compare.$$; then
    echo "verändernde Aufrufe: identisch"
  else
    echo "verändernde Aufrufe: UNTERSCHIED"; cat /tmp/compare.$$
  fi
  echo "Abfragen: $(grep -vcE "$changing" "$f") -> $(grep -vcE "$changing" "$new/$n.calls")"
  for x in conf spool; do cmp -s "$old/$n.$x" "$new/$n.$x" || echo ".$x: UNTERSCHIED"; done
  diff -U0 "$old/$n.log" "$new/$n.log" | grep -v '^@@\|^---\|^+++' | sed 's/^/log /'
done
rm -f /tmp/compare.$$
