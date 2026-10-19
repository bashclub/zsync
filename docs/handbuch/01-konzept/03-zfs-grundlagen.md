---
title: ZFS-Grundlagen für zsync
audience: Admin
outline:
---
Dieser Artikel erklärt die ZFS-Begriffe, auf denen zsync aufbaut. Wer sie kennt, versteht die Meldungen im Log und im
Monitoring.

## Snapshot
Ein Snapshot ist ein schreibgeschützter Stand eines Datasets zu einem Zeitpunkt, z. B.
`rpool/data/vm-100-disk-0@zfs-auto-snap_daily-2026-10-19-0000`. Er belegt nur den Platz der Blöcke, die sich seitdem
geändert haben. zsync überträgt Snapshots, nie den laufenden Stand eines Datasets.

## GUID
Jeder Snapshot hat eine eindeutige Nummer, die GUID. Ein übertragener Snapshot hat auf dem Backupserver dieselbe GUID
wie auf der Quelle. zsync vergleicht Snapshots deshalb über die GUID, nicht über den Namen. Ein Snapshot, der auf der
Quelle gelöscht und unter demselben Namen neu angelegt wurde, ist für zsync ein anderer.
```bash
zfs list -t snapshot -o name,guid rpool/data
```

## Kette und gemeinsamer Snapshot
Die Snapshots eines Datasets bilden eine Kette. Eine inkrementelle Übertragung schickt nur die Änderungen zwischen zwei
Snapshots. Dafür muss der ältere davon auf beiden Seiten existieren: der **gemeinsame Snapshot**.

- **Erstreplikation:** Gibt es das Replikat noch nicht, überträgt zsync den ältesten passenden Snapshot vollständig und
  danach alle neueren inkrementell, einen nach dem anderen.
- **Inkrementell:** Danach überträgt jeder Lauf nur die Snapshots, die seit dem neuesten gemeinsamen dazugekommen sind.
- **Kette gerissen:** Hat die Quelle alle Snapshots gelöscht, die das Replikat auch hat, gibt es keinen gemeinsamen
  Snapshot mehr. Dann hilft nur eine neue Erstreplikation.

### Warum zsync bei gerissener Kette nicht selbst neu überträgt
Eine neue Erstreplikation in dasselbe Replikat müsste das alte Replikat mit allen Snapshots ersetzen. Das wären
genau die Backups, die man nach einem Angriff braucht. Wer die Quelle übernimmt, könnte so durch Löschen der Snapshots
auf der Quelle auch die Backups löschen lassen. zsync meldet den Fall deshalb nur (Checkmk: CRIT). Ab 2.0 entscheidet
der Admin mit `bashclub-zsync-maintenance`: das alte Replikat umbenennen und behalten, oder löschen. Danach überträgt der
nächste Lauf neu.

## Warum der Backupserver Löschungen der Quelle nicht einfach übernimmt
`zfs receive -F` setzt das Replikat vor dem Empfang auf seinen neuesten Snapshot zurück. Es löscht aber keine
Snapshots, die es auf der Quelle nicht mehr gibt, weil zsync jeden Schritt einzeln überträgt (`zfs send -i`) und
keinen Replikationsstrom der ganzen Quelle (`zfs send -R`). Welche Snapshots auf dem Backupserver gelöscht werden,
entscheidet zsync selbst nach `snapshot_filter` (siehe [Snapshots und Aufbewahrung](05-snapshots-und-aufbewahrung.md)).

## Raw-Übertragung und Verschlüsselung
zsync überträgt raw (`zfs send -w`). Verschlüsselte Datasets bleiben auf dem Backupserver verschlüsselt, der Schlüssel
verlässt die Quelle nie. Der Backupserver kann die Daten ohne den Schlüssel nicht lesen, aber vollständig sichern und
zurückspielen. Unverschlüsselte Datasets gehen mit ihren komprimierten Blöcken über die Leitung, ohne sie zu entpacken.

## Bookmark
Ab 2.0, Parameter `source_bookmark`.

Ein Bookmark merkt sich, wo ein Snapshot in der Kette stand, ohne Daten festzuhalten. Er belegt keinen Platz. Von
einem Bookmark aus kann ZFS inkrementell senden, auch wenn der Snapshot selbst schon gelöscht ist.

zsync legt auf der Quelle einen Bookmark auf den neuesten übertragenen Snapshot, z. B.
`rpool/data#zsync_backup1_backup_pve1` (Backupserver und Target im Namen, damit sich mehrere Backupserver nicht
stören). War der Backupserver länger aus als die Quelle ihre Snapshots behält, geht es vom Bookmark aus weiter, statt
dass die Kette reißt.

## Hold
Ab 2.0, Parameter `source_hold`.

Ein Hold sperrt einen Snapshot gegen Löschen (`dataset is busy`). zsync setzt vor dem Transfer eines Datasets einen
Hold auf die Basis und auf alle Snapshots, die noch übertragen werden, und löst ihn danach. So kann die Rotation auf
der Quelle oder ein Admin sie während der Übertragung nicht löschen. Sie werden mit der nächsten Rotation gelöscht.

## Resume
Ab 2.0, Parameter `transfer_resume`.

Bricht eine Übertragung ab (Netz, Neustart, abgebrochener Lauf), behält ZFS den empfangenen Teil (`zfs receive -s`).
Der nächste Lauf setzt dort fort, statt neu zu beginnen. Das zählt vor allem bei der Erstreplikation großer Datasets
über eine langsame Leitung.

:::info
**Geändert in 2.0:** Bookmark, Hold und Resume gibt es ab 2.0. Bestehende Configs ohne diese Parameter laufen nach
dem Update wie bisher (`0` = aus). Neue Configs aus `bashclub-zsync-setup` schalten alle drei ein (`1`).
:::
