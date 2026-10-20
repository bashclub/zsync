---
title: Dataset oder VM-Disk wiederherstellen
audience: Admin
outline: https://docs.bashclub.org/doc/dataset-oder-vm-disk-wiederherstellen-cqoK34N2uG
outline_id: 952f50da-0977-4006-9e53-dbd21755f708
---
Ab 2.0. Stellt ein Dataset oder die Disk einer VM mit ihrer ganzen Snapshot-Kette wieder her: auf der Quelle, auf einem
neuen Server oder auf dem Backupserver in einen anderen Pool. Die Kette bleibt dieselbe; danach kann die Replikation
ohne Erstreplikation weiterlaufen.

Die Beispiele verwenden Pull: Befehle auf dem System, das wiederhergestellt wird, mit dem Restore-Benutzer der Config
`pve1` (siehe [Zugang](02-zugang.md)). Für Push dieselben Befehle auf dem Backupserver mit `--to <system>` statt
`--from`, ohne beides auf dem Backupserver selbst.

## 1. Ansehen
Alle Replikate der Config und ihr Zustand auf dem System:
```bash
from=zsync-restore-pve1@backup1
bashclub-zsync-restore list --from "$from"
```
Die Kette einer Disk im Vergleich mit dem System, mit dem passenden Befehl am Ende:
```bash
from=zsync-restore-pve1@backup1
bashclub-zsync-restore show --from "$from" rpool/data/vm-100-disk-0
```
`=` gibt es auf beiden Seiten, `+` fehlt auf dem System, `!` gibt es nur auf dem System.

## 2. Wiederherstellen
Eine gelöschte Disk an ihrem alten Platz, mit dem neuesten Snapshot:
```bash
from=zsync-restore-pve1@backup1
bashclub-zsync-restore dataset --from "$from" rpool/data/vm-100-disk-0
```
Das Werkzeug zeigt den Plan (Datasets, Snapshots, Größe), schreibt ihn als Job und fragt, ob es ihn starten soll. Nach
`y` zeigt es den Fortschritt; Strg-C beendet nur die Anzeige, der Job läuft im Hintergrund weiter, auch wenn die
SSH-Sitzung endet. Ohne Rückfrage starten: `--start`. Die Ausgabe nennt die ID des Jobs; alle Jobs zeigt
`bashclub-zsync-restore jobs`. Den Fortschritt später wieder ansehen, mit der ID in der ersten Zeile:
```bash
job=20261019-120000-ab12
bashclub-zsync-restore status "$job" --follow
```

Häufige Varianten:
- **Älterer Stand:** `--snapshot zfs-auto-snap_daily-2026-10-15-0000` stellt bis zu diesem Snapshot wieder her.
- **Neben dem Original**, um erst zu vergleichen: `--as rpool/data/vm-100-disk-9`. Mountpoint und Tag werden dann nicht
  gesetzt, die Kopie wird also nicht über das Original eingehängt und nicht mitgesichert.
- **Mit Kindern:** `--recursive`, z. B. für einen Container mit eigenen Datasets.
- **Vorhandenes Dataset ersetzen:** `--force` benennt das vorhandene in `<dataset>.before-restore-<zeit>` um, statt es
  zu überschreiben. Ohne `--force` bricht der Plan ab.
- **Erst ansehen:** `--dry-run` zeigt Plan und alle Befehle und ändert nichts.

## 3. Prüfen
Am Ende prüft der Job jedes Dataset und schreibt einen Bericht: dieselben Snapshots (GUID), der gewünschte Snapshot ist
der neueste, kein angefangener Empfang, dieselbe Datenmenge, die Properties, bei Verschlüsselung der Schlüsselstatus.
```bash
job=20261019-120000-ab12
bashclub-zsync-restore status "$job"
```
`OK` je Dataset; `WARN` oder `ERROR` nennt, was abweicht. `--scrub` beim Restore liest zusätzlich alle Daten einmal.

## 4. Danach
- **Verschlüsselt:** Den Schlüssel laden; der Bericht nennt den Befehl (`zfs load-key`).
- **VM oder Container:** Die Config der VM (`/etc/pve/qemu-server/<id>.conf`) muss es auf dem System geben. Wurde nur
  die Disk gelöscht, die VM aber nicht, startet sie direkt. Fehlt die Config, aus dem Backup von `/etc/pve` oder von Hand
  anlegen und die Disk zuweisen (`qm rescan`).
- **Replikation:** Ist das wiederhergestellte Dataset ausgewählt, repliziert der nächste Lauf inkrementell weiter, weil
  die Kette dieselbe ist.

## Ohne Restore-Werkzeug
Mit ZFS allein, auf dem Backupserver als root, mit SSH-Zugang als root zum System. Erst der älteste Snapshot
vollständig, dann alle bis zum gewünschten inkrementell. Replikat, Snapshot, Ziel und System in den ersten Zeilen:
```bash
replica=backup/zsync/pve1/rpool/data/vm-100-disk-0
snap=zfs-auto-snap_daily-2026-10-19-0000
dest=rpool/data/vm-100-disk-0
host=pve1
first=$(zfs list -H -o name -t snapshot -s createtxg "$replica" | head -n 1)
zfs send -w "$first" | ssh "root@$host" zfs receive -u "$dest"
zfs send -w -I "$first" "$replica@$snap" | ssh "root@$host" zfs receive -u "$dest"
```
`receive` bricht ab, wenn `dest` schon existiert. Anders als mit dem Werkzeug fehlen danach die Properties der Quelle
(Mountpoint, Tag, `com.sun:auto-snapshot`); sie stehen am Replikat als `bashclub:zsync-source.*` und lassen sich von
Hand setzen. Ein Abbruch beginnt von vorn, und es gibt keinen Bericht.

## Auf dem Backupserver selbst
Ohne `--from` und `--to` läuft alles auf dem Backupserver, z. B. um eine Disk zum Prüfen in einen anderen Pool zu holen.
Mit `--config` lassen sich die Namen der Quelle verwenden:
```bash
bashclub-zsync-restore dataset --config pve1 --as tank/pruefung/vm-100-disk-0 rpool/data/vm-100-disk-0
```
