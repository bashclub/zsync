---
title: Täglicher Betrieb
audience: Admin
outline: https://docs.bashclub.org/doc/taglicher-betrieb-tSXICBsExq
outline_id: 46b28759-0518-4b4e-98ef-cf1cd1d2ddd5
---
Im Normalbetrieb ist nichts zu tun: Die Timer starten die Läufe, Checkmk meldet, wenn etwas nicht stimmt. Dieser
Artikel zeigt, wo man nachsieht.

## Was wann läuft
Alle Configs mit Auslöser, Zeitplan, Benutzer, Zustand des Timers und nächstem Lauf:
```bash
bashclub-zsync-timer list
```
Die Timer selbst:
```bash
systemctl list-timers 'bashclub-zsync@*'
```

## Was gerade läuft
```bash
bashclub-zsync busy
```
Exit-Code 0 und keine Ausgabe: nichts aktiv. Sonst nennt die Ausgabe die aktive Replikation, Wartungsaktion,
Restore-Job oder den Wechseldatenträger.

## Zustand aller Configs
So, wie Checkmk ihn sieht, mit dem Ergebnis des letzten Laufs:
```bash
bashclub-zsync -s
```
Eine Zeile je Config und je Dataset von checkzfs, vorne `OK`, `WARN` oder `CRIT`. Der Exit-Code ist der schlechteste
Zustand (0, 1, 2). `-s` schreibt dabei die Spool-Datei neu; es repliziert nichts.

## Logs
Mit Timer im Journal, je Config (Name nach `@`):
```bash
journalctl -u bashclub-zsync@pve1 --since today --no-pager
```
Mit `log_file` in der Config oder per Cron in der Datei, meist in `/var/log/bashclub-zsync/`. Die Zeilen haben eine
Stufe:
- `[INFO]`: Ablauf: welche Datasets, welche Übertragungen, welche Snapshots gelöscht
- `[WARN]`: braucht Aufmerksamkeit, die Replikation selbst ist gelungen
- `[ERROR]`: ein Dataset oder der Lauf ist gescheitert

Nur Warnungen und Fehler eines Tages:
```bash
journalctl -u 'bashclub-zsync@*' --since today --no-pager | grep -E '\[(WARN|ERROR)\]'
```
Was jede Meldung bedeutet: [Meldungen](../06-referenz/08-meldungen.md).

Ausführlicher, mit jedem Befehl: einen Lauf mit `-d` von Hand starten. Als Benutzer der Config, wenn sie ohne root läuft:
```bash
name=pve1
conf=/etc/bashclub/$name.conf
user=$(sed -n 's/^run_as=//p' "$conf" | tr -d "\"'")
if [ -n "$user" ]; then runuser -u "$user" -- bashclub-zsync -d -c "$conf"; else bashclub-zsync -d -c "$conf"; fi
```
Läuft der Timer gerade, wird der Lauf von Hand übersprungen (`Another run … is still active`).

## Einen Lauf außer der Reihe
```bash
systemctl start --no-block bashclub-zsync@pve1.service
```
Der Timer läuft danach normal weiter.

## Replikationen kurz anhalten
Für Wartung an Quelle oder Backupserver, z. B. vor einem Neustart der Quelle. Der Timer startet keine neuen Läufe,
ein laufender läuft zu Ende:
```bash
name=pve1
systemctl stop "bashclub-zsync@$name.timer"
bashclub-zsync busy --wait 3600
```
Wieder einschalten:
```bash
name=pve1
systemctl start "bashclub-zsync@$name.timer"
```
Ein Neustart des Backupservers schaltet die Timer ebenfalls wieder ein; verpasste Läufe startet er nach.

## Ergebnis für Skripte
```bash
bashclub-zsync -c /etc/bashclub/pve1.conf --result
```
`key=value`, z. B. `rc=0`, `ok_end=<Unix-Zeit>`, `decisions=0`. Alle Keys: [bashclub-zsync](../06-referenz/02-bashclub-zsync.md).
