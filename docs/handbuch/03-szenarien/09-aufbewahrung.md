---
title: Aufbewahrungsstufen
audience: Admin
outline:
---
Wie weit ein Backup zurückreicht, hängt davon ab, welche Snapshots es auf der Quelle gibt und wie viele davon der
Backupserver behält. Die Regeln dazu: [Snapshots und Aufbewahrung](../01-konzept/05-snapshots-und-aufbewahrung.md).

## Stufen auf der Quelle: zfs-auto-snapshot
Für Stufen (stündlich, täglich, wöchentlich, monatlich) braucht die Quelle ein Werkzeug, das solche Snapshots anlegt,
meist `zfs-auto-snapshot`. Bei Proxmox ist es nicht vorinstalliert:
```bash
apt install -y zfs-auto-snapshot
```
Es legt per Cron für alle Datasets ohne `com.sun:auto-snapshot=false` Snapshots an und behält auf der Quelle:

| Label | Abstand | behält |
|---|---|---|
| `frequent` | 15 Minuten | 4 |
| `hourly` | stündlich | 24 |
| `daily` | täglich | 31 |
| `weekly` | wöchentlich | 8 |
| `monthly` | monatlich | 12 |

## Snapshots von zsync
Dazu legt zsync vor jeder Übertragung einen eigenen Snapshot an (Label `zsync-<backupserver>`, auf der Quelle behält
es `--keep`, Vorschlag 14). Er sorgt dafür, dass jedes Backup den Stand des Laufs hat, nicht nur den des letzten
stündlichen Snapshots.

:::warning
Ohne `zfs-auto-snapshot` auf der Quelle gibt es nur die Snapshots von zsync. Mit den Vorschlägen des Setups behält der
Backupserver davon 14; bei Läufen alle 15 Minuten reicht das Backup dann nur 3,5 Stunden zurück. Entweder
`zfs-auto-snapshot` auf der Quelle installieren oder die Zahl für das Label von zsync erhöhen.
:::

## Stufen auf dem Backupserver
`snapshot_filter` bestimmt je Label, wie viele Snapshots der Backupserver behält (ab 2.0 mit Zahl, unabhängig von der
Quelle). Der Vorschlag des Setups:
```
snapshot_filter="hourly=24|daily=30|weekly=8|monthly=12|zsync-backup1=14"
```
Das ergibt auf dem Backupserver: 14 Stände der letzten Läufe, die letzten 24 Stunden stündlich, einen Monat täglich,
zwei Monate wöchentlich, ein Jahr monatlich. Der Backupserver kann mehr behalten als die Quelle, z. B.
`daily=90|monthly=36`; er bekommt aber nur Snapshots, die es auf der Quelle gab, als zsync lief.

`frequent` steht nicht im Vorschlag: Die Snapshots alle 15 Minuten leben auf der Quelle nur eine Stunde; die Snapshots
von zsync decken dasselbe ab.

## Platz
Ein Snapshot belegt den Platz der Blöcke, die sich seit ihm geändert haben. Wie viel die Snapshots eines Replikats
belegen:
```bash
conf=/etc/bashclub/pve1.conf
( . "$conf"; zfs list -r -o name,used,usedbysnapshots,refer "$target" )
```
`usedbysnapshots` wächst mit der Zahl der Snapshots und mit der Änderungsrate der Daten. Ein Datenbankserver mit vielen
Schreibvorgängen braucht für 30 Tage deutlich mehr als ein Fileserver.

## Monitoring anpassen
checkzfs warnt ab 150 Snapshots je Dataset (`checkzfs_max_snapshot_count=150,165`). Die Summe der Zahlen in
`snapshot_filter` muss darunter liegen, sonst warnt Checkmk dauerhaft. Bei längerer Aufbewahrung den Wert anpassen,
z. B. für `hourly=24|daily=90|weekly=16|monthly=36|zsync-backup1=14` (180 Snapshots):
```bash
conf=/etc/bashclub/pve1.conf
sed -i 's/^checkzfs_max_snapshot_count=.*/checkzfs_max_snapshot_count=200,220/' "$conf"
```
`checkzfs_max_age` (Minuten, Vorschlag `1500,6000`) passt für tägliche oder häufigere Snapshots.
