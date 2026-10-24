---
title: Cron auf systemd-Timer
audience: Admin
outline: https://docs.bashclub.org/doc/cron-auf-systemd-timer-eyigqq2J2E
outline_id: 990fdecc-a219-48cb-b7f0-0cf9432a1b0f
---
Ab 2.0 kann systemd die Läufe einer Config starten statt Cron. Das ist freiwillig; Cron-Jobs laufen nach dem Update
unverändert weiter.

## Was der Timer besser kann
- Ein Lauf, der verpasst wurde, weil der Host aus war, startet nach dem nächsten Boot.
- Der Timer startet nie einen zweiten Lauf, solange der vorige noch läuft.
- Der Checkmk-Service der Config nimmt das Intervall aus dem Timer und braucht keine Lernphase.
- Die Ausgabe landet im Journal (`journalctl -u bashclub-zsync@<name>`) oder in einer Logdatei.
- Ab 2.0 kann der Lauf als eigener Benutzer laufen (`run_as`, siehe [Betrieb ohne root](05-betrieb-ohne-root.md)).

Auf TrueNAS SCALE bleibt es bei Cron.

## Vorher
Die Config `/etc/bashclub/zsync.conf` läuft per Cron, z. B. aus `/etc/cron.d/bashclub-zsync`:
```
00 23 * * * root /usr/bin/bashclub-zsync -c /etc/bashclub/zsync.conf >> /var/log/bashclub-zsync/zsync.log
```

## Umstellen
`bashclub-zsync-timer migrate` übernimmt Cron-Jobs, die `bashclub-zsync -c /etc/bashclub/<name>.conf` aufrufen, auch
Skripte in `/etc/cron.{hourly,daily,weekly,monthly}`. Ein Cron-Job ohne `-c` läuft mit `/etc/bashclub/zsync.conf` und
wird ab 2.0 ebenfalls übernommen (Timer `bashclub-zsync@zsync.timer`). Zeitplan, Benutzer und Logdatei gehen in die Config, die
Cron-Zeile wird auskommentiert und der Timer gestartet.

Erst ansehen, was passieren würde:
```bash
bashclub-zsync-timer migrate --dry-run
```
Dann umstellen:
```bash
bashclub-zsync-timer migrate
```
Zeitpläne, die systemd nicht genau so ausführen kann (z. B. `@reboot`), listet das Werkzeug auf und lässt sie, wie
sie sind. Nur eine Config umstellen: `bashclub-zsync-timer migrate zsync`.

## Nachher
In der Config stehen jetzt z. B.:
```
trigger=systemd
schedule='00 23 * * *'
log_file=/var/log/bashclub-zsync/zsync.log
```
Die Cron-Zeile beginnt mit `# bashclub-zsync-timer: migrated to bashclub-zsync@zsync.timer:`.

## Prüfen
Alle Configs mit Auslöser, Zeitplan, Benutzer und nächstem Lauf:
```bash
bashclub-zsync-timer list
```
Den nächsten Start des Timers und das Journal eines Laufs:
```bash
name=zsync
systemctl list-timers "bashclub-zsync@$name.timer"
journalctl -u "bashclub-zsync@$name" -n 50
```

## Ändern
Zeitplan, Benutzer und Logdatei stehen in der Config (`schedule`, `run_as`, `log_file`). Nach einer Änderung von Hand
die Timer aller Configs anpassen; der Probelauf zeigt, was gestartet, geändert oder gestoppt würde:
```bash
bashclub-zsync-timer sync --dry-run
bashclub-zsync-timer sync
```
Oder direkt mit dem Werkzeug, z. B. täglich um 23 Uhr:
```bash
bashclub-zsync-timer enable zsync "0 23 * * *"
```
Mehrere Zeitpläne trennt `;`, z. B. `"*/15 6-22 * * 1-5;0 23 * * *"`.

## Rückweg
Den Timer stoppen (schreibt `trigger=cron` in die Config) und die auskommentierten Cron-Zeilen dieser Config wieder
einschalten. Der Name der Config steht in der ersten Zeile:
```bash
name=zsync
bashclub-zsync-timer disable "$name"
marker="# bashclub-zsync-timer: migrated to bashclub-zsync@$name.timer: "
grep -rlsF "$marker" /etc/crontab /etc/cron.d /etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly /var/spool/cron/crontabs | while read -r f; do sed -i "s|^$marker||" "$f"; done
```
