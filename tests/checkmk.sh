#!/bin/bash
# Tests für den Checkmk-Check bashclub_zsync: Status-Dateien und ein nachgebautes /proc, feste Uhrzeit.
# Aufruf: tests/checkmk.sh [check]   (ohne root, ohne ZFS)
here=$(cd "$(dirname "$0")" && pwd)
check=$(readlink -f "${1:-$here/../bashclub-zsync/usr/share/bashclub-zsync/checkmk/bashclub_zsync}")
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
export ZSYNC_RUN_DIR=$w/run ZSYNC_LIB_DIR=$w/lib ZSYNC_PROC=$w/proc ZSYNC_CHECK_CONF=$w/none
T=1760000000; id=_etc_bashclub_pve1.conf; conf=$w/etc/pve1.conf
failed=0; count=0

reset() {
  rm -rf "$w"/{run,lib,proc,etc}; mkdir -p "$w"/{run,lib,proc,etc}
  printf 'target=backup/pve1\nsource=root@pve1\n%s\n' "${1:-}" > "$conf"
  # Config-Pfad in den Status-Dateien zeigt auf die Test-Config
}
# history <abstand> <anzahl>: Startzeiten im festen Abstand, letzte bei T - abstand
history() { for ((i = $2; i >= 1; i--)); do echo $((T - i * $1)); done > "$w/lib/$id.history"; }
# last <rc> <ende> [ok_ende] [dauer]
last() {
  local ok_end=${3-$2}
  printf 'config=%s\nstart=%s\nend=%s\nduration=%s\nrc=%s\ndatasets=3\ndatasets_failed=%s\nok_start=%s\nok_end=%s\nok_duration=%s\n' \
    "$conf" $(($2 - ${4:-60})) $2 ${4:-60} $1 $(( $1 ? 1 : 0 )) "${ok_end:+$((ok_end - ${4:-60}))}" "$ok_end" ${4:-60} > "$w/lib/$id.last"
}
# proc <pid> <ppid> <zustand> <start> <cmdline> [rchar] [wchan]
proc() {
  mkdir -p "$w/proc/$1"
  echo "$1 (${5%% *}) $3 $2 $(printf '0 %.0s' {1..17})$4 0 0" > "$w/proc/$1/stat"
  printf '%s\0' $5 > "$w/proc/$1/cmdline"
  echo "rchar: ${6:-0}" > "$w/proc/$1/io"
  echo "${7:-0}" > "$w/proc/$1/wchan"
}
# state <phase> <phase_since> [dataset] [pid] [pid_start] [run_start]
state() {
  printf 'config=%s\npid=%s\npid_start=%s\nrun_start=%s\nphase=%s\ndataset=%s\nphase_since=%s\n' \
    "$conf" ${4:-100} ${5:-555} ${6:-$((T - 600))} $1 "${3:-}" $2 > "$w/run/$id.state"
}
run() { ZSYNC_NOW=${2:-$T} bash "$check"; }
# expect <beschreibung> <zustand> <text-regex> [zeitpunkt]
expect() {
  local out; out=$(run "" "${4:-$T}"); ((count++))
  if [[ $out =~ ^$2\ \"zsync\ pve1\"\ .*$3 ]]; then echo "ok   $1"
  else echo "FAIL $1"; echo "     erwartet: $2 ... $3"; echo "     erhalten: $out"; ((failed++)); fi
}
expect_none() { local out; out=$(run); ((count++)); if [[ -z $out ]]; then echo "ok   $1"; else echo "FAIL $1: $out"; ((failed++)); fi; }

reset; expect_none "keine Status-Dateien: kein Service"

reset; last 0 $((T - 60)); expect "erster Lauf, noch kein Intervall: OK in der Lernphase" 0 "learning 0/5"
reset; last 1 $((T - 60)) ""; expect "erster Lauf fehlgeschlagen: WARN" 1 "failed \(exit code 1, 1 of 3 datasets failed\)"
reset; last 1 $((T - 60)) ""; history 3600 1; expect "noch nie erfolgreich: Hinweis" 1 "no successful run yet"

# stündlich, Lernphase: 2 Abstände, letzter Erfolg vor 10 h -> nur WARN
reset; last 0 $((T - 36000)); history 3600 3; expect "Lernphase überfällig: höchstens WARN" 1 "learning 2/5, preliminary interval 1h 0m"
# stündlich, scharf
reset; last 0 $((T - 1800)); history 3600 6; expect "scharf, im Intervall: OK" 0 "interval 1h 0m from 5 runs"
reset; last 0 $((T - 5000)); history 3600 6; expect "scharf, ein Lauf verpasst: WARN" 1 "last successful run 1h 23m ago"
reset; last 0 $((T - 12000)); history 3600 6; expect "scharf, drei Intervalle: CRIT" 2 "last successful run 3h 20m ago"
# 5 Minuten: mindestens 5 min Puffer
reset; last 0 $((T - 500)); history 300 6; expect "5-Minuten-Intervall, 8 min: OK (Puffer 5 min)" 0 "interval 5m"
reset; last 0 $((T - 700)); history 300 6; expect "5-Minuten-Intervall, 11 min: WARN" 1 "interval 5m"
# Median ignoriert einzelne Handläufe
reset; last 0 $((T - 1800)); for s in 0 3600 3700 7200 10800 14400 18000; do echo $((T - 20000 + s)); done > "$w/lib/$id.history"
expect "Handlauf verfälscht das Intervall nicht" 0 "interval 1h 0m from 6 runs"
# Override in der Config
reset 'monitor_max_age=2h'; last 0 $((T - 8000)); history 3600 6; expect "monitor_max_age=2h überschritten: WARN" 1 "monitor_max_age=2h"
reset 'monitor_max_age=0'; last 0 $((T - 999999)); history 3600 6; expect "monitor_max_age=0: keine Altersprüfung" 0 "age check disabled"

# aktiver Lauf
reset; last 0 $((T - 3600)); history 3600 6; proc 100 1 S 555 "bash /usr/bin/bashclub-zsync -c pve1.conf"
state replicate $((T - 60)) rpool/data; expect "Lauf aktiv, Phase kurz: OK" 0 "running for 10m, phase replicate rpool/data since 1m"
state delete $((T - 1200)) rpool/data; expect "Phase ohne Transfer 20 min: WARN" 1 "phase delete takes 20m"
state list $((T - 4000)) rpool/data; expect "Phase ohne Transfer > 1 h: CRIT" 2 "phase list takes 1h 6m"
# Transfer mit und ohne Fortschritt (Zustand des Checks bleibt zwischen den Aufrufen erhalten)
state send $((T - 60)) rpool/data; proc 101 100 S 556 "ssh root@pve1 zfs send -w -i a b"; proc 102 100 S 557 "zfs receive -F backup/pve1/rpool/data" 1000
expect "Transfer, erster Check: OK" 0 "phase send rpool/data"
proc 102 100 S 557 "zfs receive -F backup/pve1/rpool/data" 5000; expect "Transfer mit Fortschritt nach 11 min: OK" 0 "phase send" $((T + 660))
expect "Transfer ohne Fortschritt seit 11 min: WARN" 1 "no transfer progress for 11m" $((T + 1320))
expect "Transfer ohne Fortschritt seit 31 min: CRIT" 2 "no transfer progress for 31m" $((T + 2520))
proc 102 100 S 557 "zfs receive -F backup/pve1/rpool/data" 9000; expect "Transfer läuft wieder: OK (langer Lauf verschiebt die Altersprüfung)" 0 "phase send" $((T + 2580))
# Prozess im Zustand D
proc 102 100 D 557 "zfs receive -F backup/pve1/rpool/data" 9000 txg_wait_synced
expect "D-Zustand gerade erst: OK" 0 "phase send" $((T + 2640))
expect "D-Zustand 6 min: WARN mit wchan" 1 "zfs receive -F backup/pve1/rpool/data\) blocked for 6m in txg_wait_synced" $((T + 3000))
expect "D-Zustand 16 min: CRIT" 2 "blocked for 16m" $((T + 3600))
# übersprungene Läufe
reset; last 0 $((T - 3600)); history 3600 6; proc 100 1 S 555 "bash bashclub-zsync"; state replicate $((T - 60)) rpool/data
printf '%s\n' $((T - 9000)) $((T - 500)) $((T - 300)) > "$w/lib/$id.skipped"; expect "2 übersprungene Läufe: Hinweis" 0 "2 runs skipped"
printf '%s\n' $((T - 9000)) $((T - 550)) $((T - 500)) $((T - 300)) > "$w/lib/$id.skipped"; expect "3 übersprungene Läufe in diesem Lauf: WARN" 1 "3 runs skipped"
# abgebrochener Lauf
reset; last 0 $((T - 3600)); history 3600 6; state send $((T - 300)) rpool/data; expect "Prozess weg: WARN abgebrochen" 1 "aborted in phase send \(rpool/data\)"
proc 100 1 S 999 "bash other"; expect "pid wiederverwendet: WARN abgebrochen" 1 "aborted in phase send"
# Config gelöscht
reset; last 0 $((T - 60)); rm "$conf"; expect_none "Config gelöscht: kein Service"
# Zustand pro Dataset (.datasets: Dataset, Zustand, seit, Detail)
ds() { printf '%s\t%s\t%s\t%s\n' "$@" >> "$w/lib/$id.datasets"; }
reset; last 0 $((T - 1800)); history 3600 6; ds pool/ok ok $((T - 99)) ""
expect "alle Datasets ok: OK" 0 "last successful run 30m ago"
ds pool/rot broken $((T - 172800)) "all snapshots of the replica were deleted by the rotation on the source"
expect "Kette gerissen: CRIT mit Ursache" 2 "full replication needed for 1 datasets: pool/rot \(all snapshots of the replica were deleted by the rotation on the source, since 2d 0h\)"
reset; last 1 $((T - 1800)) $((T - 5400)); history 3600 6; ds pool/e empty $((T - 600)) "no snapshot on backup/pve1/pool/e"
expect "Ziel ohne Snapshots: CRIT" 2 "full replication needed for 1 datasets: pool/e"
reset; last 1 $((T - 1800)) $((T - 1800)); history 3600 6; ds pool/r at_risk $((T - 600)) "base zfs-auto-snap_daily-01 is the oldest snapshot of interval daily on the source"
expect "Kette in Gefahr: WARN" 1 "chain at risk, the next rotation on the source breaks it: pool/r \(base zfs-auto-snap_daily-01"
reset; last 1 $((T - 1800)) $((T - 1800)); history 3600 6; ds pool/d diverged $((T - 600)) "newest common snapshot daily-01"
expect "auseinandergelaufen: WARN" 1 "newest target snapshot missing on the source: pool/d"
reset; last 0 $((T - 1800)); history 3600 6; ds pool/gone orphan_missing $((T - 3600)) "does not exist on the source"
expect "verwaist seit 1 h (Karenzzeit): OK mit Hinweis" 0 "1 new datasets only on the target"
reset; last 0 $((T - 1800)); history 3600 6; ds pool/gone orphan_missing $((T - 90000)) "does not exist on the source"
ds pool/untagged orphan_unselected $((T - 90000)) "is not selected for replication anymore (bashclub:zsync)"
expect "verwaist seit 25 h: WARN" 1 "2 datasets only on the target: pool/gone \(does not exist on the source, since 1d 1h\), pool/untagged \(is not selected for replication anymore, since 1d 1h\)"
reset; last 0 $((T - 1800)); history 3600 6; ds pool/kept orphan_kept $((T - 900000)) "does not exist on the source"; ds pool/m no_snapshots $T ""
expect "quittiert und ohne Snapshots: OK mit Hinweis" 0 "1 kept replicas without source, 1 datasets without matching snapshots"
reset; last 0 $((T - 1800)); history 3600 6; ds pool/x rolled_back $T "rolled back to daily-02, 2 snapshots destroyed"
expect "Rollback im letzten Lauf: OK mit Hinweis" 0 "rolled back by the last run: pool/x \(rolled back to daily-02, 2 snapshots destroyed\)"
reset; last 0 $((T - 1800)); history 3600 6; for x in a b c d e; do ds pool/$x broken $T "x"; done
expect "lange Liste wird gekürzt" 2 "full replication needed for 5 datasets: pool/a \(x, since 0s\), pool/b \(x, since 0s\), pool/c \(x, since 0s\) \(\+2 more\)"

# systemd-Timer der Config: Intervall aus letztem und nächstem Start, keine Lernphase
cat > "$w/systemctl" << 'EOS'
#!/bin/bash
case $1 in
  is-active) [[ $ZTEST_TIMER == on ]] ;;
  show)
    case "$*" in
      *"-p LastTriggerUSec "*) if [ "$ZTEST_TIMER_LAST" -gt 0 ]; then date -d "@$ZTEST_TIMER_LAST" '+%a %Y-%m-%d %H:%M:%S %Z'; else echo; fi ;;
      *"-p NextElapseUSecRealtime "*) date -d "@$ZTEST_TIMER_NEXT" '+%a %Y-%m-%d %H:%M:%S %Z' ;;
    esac ;;
esac
EOS
chmod +x "$w/systemctl"
export ZSYNC_SYSTEMCTL=$w/systemctl ZSYNC_CONF_DIR=$w/etc ZTEST_TIMER=on ZTEST_TIMER_LAST=$((T - 1800)) ZTEST_TIMER_NEXT=$((T + 1800))
reset; last 0 $((T - 1800)); history 3600 1
expect "Timer aktiv: Intervall aus dem Timer, keine Lernphase" 0 "interval 1h 0m from bashclub-zsync@pve1.timer"
reset; last 0 $((T - 12000)); history 3600 1
expect "Timer aktiv: drei Intervalle ohne Erfolg -> CRIT ohne Lernphase" 2 "from bashclub-zsync@pve1.timer"
ZTEST_TIMER_LAST=0; reset; last 0 $((T - 600)); history 3600 1
expect "Timer noch nie ausgelöst: letzter Erfolg als letzter Start" 0 "from bashclub-zsync@pve1.timer"
ZTEST_TIMER_LAST=$((T - 1800))
ZTEST_TIMER=off; reset; last 0 $((T - 1800)); history 3600 1
expect "Timer aus: Lernphase wie bisher" 0 "learning 0/5"
unset ZSYNC_SYSTEMCTL ZSYNC_CONF_DIR

# Metriken
reset; last 0 $((T - 1800)) $((T - 1800)) 120; history 3600 6
out=$(run); ((count++)); if [[ $out == **"last_success_age=1800;4440;10920|last_duration=120|datasets_failed=0 "* ]]; then echo "ok   Metriken"; else echo "FAIL Metriken: $out"; ((failed++)); fi

echo "$((count - failed))/$count bestanden"
[ $failed -eq 0 ]
