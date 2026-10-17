#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Tests der Bibliothek schedule.sh (Cron-Umrechnung, Settings schreiben und lesen, Prüfungen von Eingaben).
# Aufruf: tests/schedule.sh (ohne root)
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../bashclub-zsync/usr/lib/bashclub-zsync/schedule.sh"
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
passed=0; total=0

# equal <beschreibung> <erwartet> <ist>
equal() { ((total++)); if [[ $2 == "$3" ]]; then ((passed++)); echo "ok   $1"; else echo "FAIL $1: erwartet '$2', ist '$3'"; fi; }
yes() { ((total++)); if "${@:2}"; then ((passed++)); echo "ok   $1"; else echo "FAIL $1"; fi; }
no() { ((total++)); if "${@:2}"; then echo "FAIL $1"; else ((passed++)); echo "ok   $1"; fi; }

# Cron -> OnCalendar
equal "*/15 werktags" "Mon..Fri *-*-* 6..22:0/15:00" "$(cron_to_calendar '*/15 6-22 * * 1-5')"
equal "@daily" "daily" "$(cron_to_calendar '@daily')"
equal "mehrere Zeitpläne" $'*-*-* 23:00:00\n*-*-* 6:25:00' "$(schedule_calendars '0 23 * * *;25 6 * * *')"
no "@reboot nicht umrechenbar" schedule_calendars '@reboot'
no "Befehl im Zeitplan" schedule_calendars '0 3 * * * $(id)'

# Settings schreiben: beim Ausführen der Config wird nichts ersetzt, gelesen wird derselbe Wert
conf=$w/test.conf; printf 'target=pool/x\nschedule="0 1 * * *"\n' > "$conf"
set_conf_value "$conf" schedule '*/15 * * * *'
set_conf_value "$conf" label 'a $(touch '"$w"'/EXECUTED) `id` b'
set_conf_value "$conf" run_as zsync-pve1
equal "Zeitplan in einfachen Anführungszeichen" "schedule='*/15 * * * *'" "$(grep '^schedule=' "$conf")"
equal "einfacher Wert ohne Anführungszeichen" "run_as=zsync-pve1" "$(grep '^run_as=' "$conf")"
equal "ersetzt statt angehängt" 1 "$(grep -c '^schedule=' "$conf")"
equal "Config ausführen: Wert unverändert" 'a $(touch '"$w"'/EXECUTED) `id` b' "$(bash -c ". '$conf'; echo \"\$label\"")"
no "Config ausführen: nichts ausgeführt" test -e "$w/EXECUTED"
equal "conf_value liest denselben Wert" '*/15 * * * *' "$(conf_value "$conf" schedule)"
equal "conf_value liest alte doppelte Anführungszeichen" '0 1 * * *' "$(printf 'schedule="0 1 * * *"\n' > "$w/old.conf"; conf_value "$w/old.conf" schedule)"
no "Wert mit ' abgewiesen" set_conf_value "$conf" label "a'b"
no "Wert mit \\ abgewiesen" set_conf_value "$conf" label 'a\b'
no "Wert mit Zeilenumbruch abgewiesen" set_conf_value "$conf" label $'a\nb'
no "ungültiger Name abgewiesen" set_conf_value "$conf" 'x;y' 1

# Prüfungen von Eingaben
yes "Dataset" valid_dataset rpool/data/subvol-100-disk-0
no "Dataset mit Befehl" valid_dataset 'rpool/$(id)'
no "Dataset mit Leerzeichen" valid_dataset 'rpool/a b'
no "Dataset mit //" valid_dataset 'rpool//a'
yes "Host-Name" valid_host pve1.example.org
yes "IPv4" valid_host 192.168.1.10
yes "IPv6" valid_host fd00::10
no "Host mit ;" valid_host 'pve1;id'
yes "Port" valid_port 22
no "Port 70000" valid_port 70000
no "Port 0" valid_port 0
yes "Tag" valid_tag bashclub:zsync
no "Tag ohne Doppelpunkt" valid_tag zsync
yes "Label" valid_label zsync-pve1
no "Label mit Leerzeichen" valid_label 'zsync pve1'
yes "Benutzer" valid_user zsync-pve1
no "Benutzer mit ;" valid_user 'zsync;id'
yes "Pfad" valid_path /var/log/bashclub-zsync/pve1.log
no "Pfad mit .." valid_path /var/log/../etc/passwd
no "Pfad mit %" valid_path /var/log/%n.log
no "Pfad relativ" valid_path log/pve1.log

echo "$passed/$total bestanden"
[ $passed -eq $total ]
