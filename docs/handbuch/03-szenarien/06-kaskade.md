---
title: "Kaskade: Backupserver → Offsite-Backupserver"
audience: Admin
outline:
---
## Ausgangslage
`backup1` sichert `pve1` im LAN wie im [Standardfall](01-standardfall.md). Ein zweiter Backupserver `backup2` an einem
anderen Standort soll eine weitere Kopie haben, ohne die Quelle zu belasten und ohne dass `backup1` einen Zugang zu
`backup2` hat.

```
pve1  <── SSH ──  backup1  <── SSH ──  backup2 (offsite)
```

`backup2` holt die Replikate von `backup1` ab; für `backup2` ist `backup1` die Quelle. `backup1` erreicht `backup2`
nie: Wer `backup1` übernimmt, kann die Kopie auf `backup2` nicht löschen.

## 1. Auf backup1: Replikate für backup2 auswählen
Ein eigenes Tag, damit `backup1` selbst nichts davon repliziert. Das Target der Config `pve1` steht in der ersten Zeile:
```bash
conf=/etc/bashclub/pve1.conf
( . "$conf"; zfs set bashclub:zsync-offsite=subvols "$target" )
```
`subvols` wählt alle Replikate unter dem Target aus, nicht das Target selbst. Dazu `bashclub-zsync-source` auf
`backup1` installieren:
```bash
apt install -y bashclub-zsync-source
```

## 2. Auf backup2: Replikation einrichten
Zugang für das Setup wie im Standardfall, Schritt 2, mit `backup1` als Quelle. Dann:
```bash
source=backup1
bashclub-zsync-setup --source "$source" --tag bashclub:zsync-offsite --keep 0 --filter "hourly=24|daily=60|weekly=16|monthly=24|zsync-backup1=14" "$source"
```
- `--tag bashclub:zsync-offsite`: das Tag aus Schritt 1
- `--keep 0`: `backup2` legt keine eigenen Snapshots an. Snapshots, die `backup2` auf den Replikaten von `backup1`
  anlegte, würde der nächste Empfang auf `backup1` wieder verwerfen.
- `--filter`: alle Labels, die auf `backup1` ankommen, auch das Label der Snapshots von zsync auf `pve1`
  (`zsync-backup1`, wenn es auf `backup1` eingerichtet wurde). Die Zahlen bestimmen, wie lange `backup2` sie behält,
  hier länger als `backup1`.

Danach wie im [Standardfall](01-standardfall.md), Schritt 5 und 6: Monitoring vorbereiten (eigenes `checkzfs_prefix`,
`source_bookmark=0`), dann den ersten Lauf starten.

Die Replikate auf `backup2` heißen `<target>/<target von backup1>/rpool/data/…`, z. B.
`backup/zsync/backup1/backup/zsync/pve1/rpool/data/vm-100-disk-0`.

## Was zu beachten ist
- **Rotation:** `backup2` bekommt nur Snapshots, die es auf `backup1` gibt, solange es sie gibt. Läuft `backup2` seltener,
  als `backup1` die Snapshots behält, reißt die Kette. Bookmarks würden helfen, bleiben aber aus, solange checkzfs das
  Monitoring macht.
- **Holds:** Während `backup2` überträgt, hält es die Snapshots auf `backup1`. Will die Rotation auf `backup1` einen davon
  löschen, scheitert das mit `dataset is busy` und gelingt im nächsten Lauf.
- **Zeitplan:** `backup2` am besten zeitversetzt nach `backup1`, z. B. nachts.
- **Rollback auf pve1:** `backup1` legt eine neue Kette an und behält die alte als `…zsync-branch-…`. Für `backup2` sieht
  das wie ein Rollback auf seiner Quelle aus; es verfährt genauso.

## Monitoring
Beide Backupserver melden ihren eigenen Service, mit eigenem Präfix: `zsync-pve1 pve1` auf `backup1`,
`zsync-backup1 backup1` auf `backup2`. Am einfachsten bleibt der Spool je auf dem eigenen Backupserver.
