#!/bin/bash
# Führt bashclub-zsync mit Stubs statt zfs/ssh in allen Szenarien aus.
# Ergebnis je Szenario in <ausgabe>: .calls (alle Aufrufe), .log (Ausgabe), .conf, .spool,
# .files (Dateien im Spool und Spool-Reste in /tmp), .status (Status-Dateien für das Monitoring, ohne Zeiten)
# Ein Szenario kann before_run/after_run definieren (Argument: Arbeitsverzeichnis), z. B. um die Sperre zu halten.
# Aufruf: tests/run.sh <skript> <ausgabe>   (als root, z. B. im Container)
set -u
here=$(cd "$(dirname "$0")" && pwd)
script=$(readlink -f "$1"); out=$2
mkdir -p "$out"
for sc in "$here"/scenarios/*.sh; do
  n=$(basename "$sc" .sh); w=$(mktemp -d /tmp/zsync-test.XXXX)
  cp "$script" "$w/bashclub-zsync"
  cp "$here"/stubs/{zfs,ssh,scp,remote-snapshot-manager,zfs-auto-snapshot} "$w/"
  DEBUG=0; CHECKZFS=1; CONF=; unset SNAPS_source_post; declare -A SNAPS_source_post=(); unset -f before_run after_run
  source "$sc"
  [[ $CHECKZFS == 1 ]] && cp "$here/stubs/checkzfs" "$w/"
  [[ -n $CONF ]] && printf '%s\n' "$CONF" > "$w/zsync.conf"
  rm -rf /var/lib/check_mk_agent/spool /tmp/*_zsync /tmp/.*_zsync.* /run/bashclub-zsync /var/lib/bashclub-zsync
  : > "$out/$n.calls"
  args=(-c "$w/zsync.conf"); [[ $DEBUG == 1 ]] && args=(-d "${args[@]}")
  mkdir -p "$w/state"
  declare -F before_run > /dev/null && before_run "$w"
  ZTEST_STATE="$w/state" ZTEST_LOG="$out/$n.calls" ZTEST_SCENARIO="$sc" bash "$w/bashclub-zsync" "${args[@]}" > "$out/$n.log" 2>&1
  echo "exit=$?" >> "$out/$n.calls"
  declare -F after_run > /dev/null && after_run "$w"
  # Zeitstempel, Arbeitsverzeichnis (auch im Namen der Sperrdatei) und Zufallsteil der temporären Spooldatei
  sed -i -E "s#^[A-Z][a-z]{2} [ 0-9][0-9] [0-9:]{8} ##; s#$w#<dir>#g; s#${w//\//_}#<dir>#g; s#(/\.[0-9]+_[^ /]+)\.[A-Za-z0-9]{6}([^A-Za-z0-9]|\$)#\1.XXXXXX\2#g" "$out/$n.log" "$out/$n.calls"
  cp "$w/zsync.conf" "$out/$n.conf" 2>/dev/null
  { for f in /run/bashclub-zsync/* /var/lib/bashclub-zsync/*; do
      [ -e "$f" ] || continue
      echo "== ${f##*.} ($(grep -c . "$f") Zeilen)"
      grep -E '^(config|rc|datasets|datasets_failed|phase|ok_end)=' "$f" | sed -E 's/^(ok_end=)[0-9]+$/\1<zeit>/'
    done; } 2>/dev/null | sed "s#$w#<dir>#g" > "$out/$n.status"
  cat /var/lib/check_mk_agent/spool/* > "$out/$n.spool" 2>/dev/null
  { ls -A /var/lib/check_mk_agent/spool; ls -A /tmp | grep -E '_zsync'; } 2>/dev/null \
    | sed -E 's#\.[A-Za-z0-9]{6}$#.XXXXXX#' > "$out/$n.files"
  rm -rf "$w"
done
