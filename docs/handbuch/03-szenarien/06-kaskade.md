---
title: "Kaskade: Backupserver → Offsite-Backupserver"
audience: Admin
outline: https://docs.bashclub.org/doc/kaskade-backupserver-offsite-backupserver-5gc87kTv6L
outline_id: ff21009d-49b3-4161-8228-f988826a580e
---
## Ausgangslage
`backup1` sichert `pve1` im LAN wie im [Standardfall](01-standardfall.md). Eine weitere Kopie soll von `backup1` kommen,
ohne die Quelle ein zweites Mal zu belasten:
- **zweiter Backupserver** `backup2` an einem anderen Standort, oder
- **Wechseldatenträger** am `backup1` selbst, wie im Szenario [Wechseldatenträger](03-wechseldatentraeger.md), nur mit
  den Replikaten von `backup1` als Quelle.

```
pve1  <── SSH ──  backup1  <── SSH ──  backup2 (offsite)
                     └──── lokal ────  USB-Platte am backup1
```

Die zweite Stufe holt die Replikate von `backup1`; für sie ist `backup1` die Quelle. `backup1` erreicht `backup2` nie:
Wer `backup1` übernimmt, kann die Kopie auf `backup2` nicht löschen.

**Kaskade oder parallel?** Die zweite Stufe kann auf den Replikaten von `backup1` keine eigenen Snapshots anlegen (siehe
unten); sie hängt an dem, was `backup1` hat, und ein Bookmark hält ihre Kette. Soll das zweite Ziel eigene Snapshots
auf `pve1` haben, z. B. ein Offsite-Server, der nur einmal pro Woche läuft, holt es parallel direkt von `pve1`, wie in
[Offsite](04-offsite.md); das Setup gibt jedem Backupserver sein eigenes Label. Die Kaskade passt, wenn `pve1` nur
einmal belastet werden soll oder nur `backup1` die Quelle erreicht.

## 1. Auf backup1: Replikate für die zweite Stufe auswählen
Ein eigenes Tag, damit `backup1` selbst nichts davon repliziert. Das Target der Config `pve1` steht in der ersten Zeile:
```bash
conf=/etc/bashclub/pve1.conf
( . "$conf"; zfs set bashclub:zsync-offsite=subvols "$target" )
```
`subvols` wählt alle Replikate unter dem Target aus, nicht das Target selbst; `all` geht ebenso. Für einen zweiten
Backupserver dazu `bashclub-zsync-source` auf `backup1` installieren:
```bash
apt install -y bashclub-zsync-source
```

## 2a. Zweiter Backupserver: Replikation auf backup2
Zugang für das Setup wie im Standardfall, Schritt 2, mit `backup1` als Quelle. Dann auf `backup2`:
```bash
source=backup1
bashclub-zsync-setup --source "$source" --tag bashclub:zsync-offsite --keep 0 --filter "hourly=24|daily=60|weekly=16|monthly=24|zsync-backup1=14" "$source"
```
- `--tag bashclub:zsync-offsite`: das Tag aus Schritt 1
- `--keep 0`: die zweite Stufe legt keine eigenen Snapshots an (siehe unten)
- `--filter`: alle Labels, die auf `backup1` ankommen, auch das Label der Snapshots von zsync auf `pve1`
  (`zsync-backup1`, wenn es auf `backup1` eingerichtet wurde). Die Zahlen bestimmen, wie lange `backup2` sie behält,
  hier länger als `backup1`. Ohne Zahlen behält `backup2` nur, was `backup1` noch hat.

Danach wie im [Standardfall](01-standardfall.md), Schritt 5 und 6: Monitoring vorbereiten (eigenes
`checkzfs_prefix`), dann den ersten Lauf starten.

Die Replikate auf `backup2` heißen `<target>/<target von backup1>/rpool/data/…`, z. B.
`backup/zsync/backup1/backup/zsync/pve1/rpool/data/vm-100-disk-0`.

## 2b. Wechseldatenträger am backup1
Die Platte wie im Szenario [Wechseldatenträger](03-wechseldatentraeger.md), Schritt 2, vorbereiten. Die Config der
Platte statt Schritt 1 dort mit `--source local`, dem Tag aus Schritt 1 und ohne eigene Snapshots; die Platte steht in
der ersten Zeile:
```bash
label=usb-backup1
bashclub-zsync-setup --source local --autorun --tag bashclub:zsync-offsite --keep 0 --filter "hourly=24|daily=60|weekly=16|monthly=24|zsync-backup1=14" --target "$label/$(hostname -s)" "$label"
```
Die Replikate der Platte liegen unter `<label>/<backup1>/<target von backup1>/…`.

## Was zu beachten ist
Getestet in den Integrationsfällen `cascade`, `cascade_local` und `cascade_upgrade`.

- **Keine eigenen Snapshots auf der zweiten Stufe.** Snapshots, die die zweite Stufe auf den Replikaten von `backup1`
  anlegt, sieht `backup1` beim nächsten Lauf als Rollback auf seinem Ziel: 2.0 legt dann jedes Mal eine neue Kette an,
  1.0 bricht ab. Ab 2.0 schützt sich die zweite Stufe selbst: Die Engine `internal` legt auf Replikaten von
  bashclub-zsync keine Snapshots an und warnt, `zas` übergeht sie wegen `com.sun:auto-snapshot=false`. Trotzdem
  `--keep 0` setzen; Replikate, die nur von 1.0 geschrieben wurden, erkennt die zweite Stufe nicht.
- **Bookmark statt eigener Snapshots.** Die zweite Stufe bekommt nur Snapshots, die es auf `backup1` gibt, solange es
  sie gibt. Läuft sie seltener, als `backup1` die Snapshots behält, setzt sie mit `source_bookmark=1` (Default neuer
  Configs) vom Bookmark auf `backup1` fort. Ohne Bookmark reißt ihre Kette, sobald `backup1` ihren letzten Snapshot
  löscht; sie meldet dann einen Fehler und löscht nichts.
- **Holds:** Während die zweite Stufe überträgt, hält sie die Snapshots auf `backup1`. Will die Rotation auf `backup1`
  einen davon löschen, scheitert das mit `dataset is busy` und gelingt im nächsten Lauf.
- **Rollback auf pve1:** `backup1` legt eine neue Kette an und behält die alte als `…zsync-branch-…`. Für die zweite
  Stufe sieht das wie ein Rollback auf ihrer Quelle aus; mit 2.0 legt sie ebenfalls eine neue Kette an und behält ihre
  alte. Die alte Kette von `backup1` holt sie ab 2.0 nicht (im Log unter „Excluded datasets“), sie hat dieselben
  Snapshots schon in ihrer eigenen.
- **Update von 1.0:** erst die zweite Stufe, dann `backup1`, oder beide zusammen. Eine zweite Stufe mit 1.0 bricht nach
  einem Rollback auf `pve1` für dieses Dataset ab, wenn `backup1` schon 2.0 hat (siehe
  [Upgrade auf 2.0](../02-installation/03-upgrade-auf-2-0.md)).
- **Zeitplan:** die zweite Stufe am besten zeitversetzt nach `backup1`, z. B. nachts.

## Monitoring
Beide Stufen melden ihren eigenen Service, mit eigenem Präfix: `zsync-pve1 pve1` auf `backup1`,
`zsync-backup1 backup1` auf `backup2` bzw. `zsync-usb-backup1 usb-backup1` für die Platte. Am einfachsten bleibt der
Spool je auf dem eigenen Host.
