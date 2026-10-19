---
title: Monitoring-Konzept
audience: Admin
outline: https://docs.bashclub.org/doc/monitoring-konzept-kKCu5unJeG
outline_id: ed075723-b975-4619-910a-fb3ae90cdad9
---
Ein Backup, dessen Ausfall niemand bemerkt, ist keins. zsync meldet deshalb an Checkmk, ob die Replikation läuft und
ob die Backups aktuell sind.

## Zwei Arten von Services
**checkzfs** (Paket `bashclub-checkzfs`) vergleicht nach jedem Lauf je Dataset die Snapshots der Quelle mit denen des
Replikats und meldet einen Service je Dataset: Alter des neuesten Snapshots (`checkzfs_max_age`) und Anzahl der
Snapshots (`checkzfs_max_snapshot_count`).

**Der Service der Config** (ab 2.0), z. B. `zsync-pve1 pve1` für `/etc/bashclub/pve1.conf` mit
`checkzfs_prefix=zsync-pve1`, meldet den Zustand der
Replikation selbst:
- ob der letzte Lauf erfolgreich war und wie lange er her ist
- ob ein laufender Lauf hängt (keine Übertragung, Prozess blockiert) oder abgebrochen ist
- ob Läufe übersprungen werden, weil der vorige noch läuft
- den Zustand jedes Datasets: Kette gerissen oder in Gefahr, Replikat ohne Quelle, alte Kette nach einem Rollback,
  blockierte Rotation
- ob überhaupt Datasets ausgewählt sind

Zu jedem Zustand nennt der Service die Ursache und, wo nötig, die Entscheidung in `bashclub-zsync-maintenance`.

:::warning
**checkzfs und Bookmarks:** checkzfs (bis Version 4.14) bricht ab, sobald auf der Quelle oder dem Backupserver ein
Bookmark existiert (`'NoneType' object has no attribute 'add_snapshot'`). Dann fehlen alle checkzfs-Services; der
Service der Config meldet weiter. Solange checkzfs das Monitoring macht, `source_bookmark=0` setzen. Neue Configs aus
dem Setup haben `source_bookmark=1`. Eine eigene Prüfung in zsync, die checkzfs ersetzt, ist geplant.
:::

## Der Spool: Meldung zum Ende des Laufs
zsync schreibt beides in eine Datei im Spool des Checkmk-Agenten: `/var/lib/check_mk_agent/spool/87000_zsync` (aus
`checkzfs_spool_maxage` und `checkzfs_prefix`). Der Agent liefert sie bei jeder Abfrage mit aus, solange sie jünger
ist als die Zahl im Namen (in Sekunden). Ist sie älter, meldet Checkmk die Services als fehlend.

zsync schreibt die Datei:
- am Ende jedes Laufs, auch nach einem Fehler
- ab 2.0 alle 5 Minuten während eines Laufs, damit ein Hänger auffällt
- ab 2.0 auf Anfrage: `bashclub-zsync -s`

Die Prüfung geschieht nicht im Takt des Agenten. Sie braucht keine Verbindung zur Quelle und liest nur, was der Lauf
hinterlassen hat.

### Spool auf dem Backupserver oder auf der Quelle
`checkzfs_spool` bestimmt, wohin die Datei geht:
- `0`: auf den Backupserver. Die Services hängen am Backupserver in Checkmk.
- `1`: auf die Quelle. Die Services hängen an der Quelle, also an dem Host, dessen Daten gesichert werden.

Der Spool auf der Quelle passt für einen Backupserver, der nur zur Replikation eingeschaltet wird: Die Services
bleiben sichtbar, während er aus ist. Kommt kein Lauf mehr, wird die Datei älter als ihre Zahl im Namen, und Checkmk
meldet das.

**Jede Replikation braucht ein eigenes `checkzfs_prefix`.** Das Präfix bestimmt den Namen der Spool-Datei und der
Services. Zwei Configs mit demselben Präfix, die in denselben Spool schreiben (mehrere Configs auf einem Backupserver,
oder mehrere Backupserver mit Spool auf derselben Quelle), überschreiben sich gegenseitig die Datei, und ihre Services
kollidieren in Checkmk. Das Setup setzt das Präfix nicht; der Admin wählt es, z. B. `zsync-<config>`.

## Wie alt darf der letzte Lauf sein
Ab 2.0 lernt der Service der Config das Intervall selbst: Er nimmt den Median der Abstände der letzten 10 Starts. Bis
5 Abstände bekannt sind (Lernphase), meldet er höchstens WARN. Läuft die Config per systemd-Timer, nimmt er das
Intervall aus dem Timer, ohne Lernphase.
- WARN, wenn der letzte erfolgreiche Lauf länger her ist als ein Intervall plus Zuschlag
- CRIT nach drei Intervallen
- `monitor_max_age` in der Config setzt die Grenze fest, `monitor_max_age=0` schaltet die Prüfung ab, etwa für
  Wechseldatenträger

:::info
**Geändert in 2.0:** Bis 1.0.19 enthielt die Spool-Datei nur die Services von checkzfs. Ab 2.0 enthält dieselbe Datei
mit demselben Namen zusätzlich den Service der Config. Nach dem Update erscheint er bei der nächsten Service-Erkennung
in Checkmk; an den bestehenden Services ändert sich nichts.
:::

Abschalten lässt sich der Service der Config auf dem Backupserver mit
`touch /etc/bashclub/zsync-checkmk.disabled`; checkzfs bleibt davon unberührt (`checkzfs_disabled`).
