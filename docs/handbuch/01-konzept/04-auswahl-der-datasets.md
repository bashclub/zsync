---
title: Auswahl der Datasets
audience: Admin
outline:
---
Welche Datasets der Quelle repliziert werden, steht nicht in der Config, sondern an den Datasets selbst: in der
ZFS-Property `bashclub:zsync` (oder dem Namen, den `tag` in der Config setzt). ZFS vererbt sie an alle Kinder. Wer
unter einem ausgewählten Dataset eine neue VM anlegt, hat sie damit automatisch im Backup.

## Die Werte
| Wert | Wirkung |
|---|---|
| `all` | das Dataset selbst und alle Kinder |
| `subvols` | nur die Kinder, nicht das Dataset selbst |
| jeder andere Wert, z. B. `none` | nicht replizieren; an einem Kind gesetzt, nimmt es dieses Kind (und seine Kinder) aus |
| nicht gesetzt | nicht replizieren |

`subvols` passt für Proxmox: `rpool/data` selbst enthält keine Daten, nur die Disks der VMs darunter. Mit `all`
entsteht auf dem Backupserver zusätzlich ein Replikat von `rpool/data`, das bei einer Wiederherstellung mit dem
`rpool/data` des neuen Systems kollidiert.

## Beispiele
Die Disks aller VMs und Container von `rpool/data` sichern:
```bash
ds=rpool/data
zfs set bashclub:zsync=subvols "$ds"
```

Eine einzelne Disk davon ausnehmen (der Name ist ein Beispiel):
```bash
ds=rpool/data/vm-999-disk-0
zfs set bashclub:zsync=none "$ds"
```

Prüfen, was ausgewählt ist (Spalte `SOURCE`: `local` = hier gesetzt, `inherited from …` = geerbt):
```bash
zfs get -t filesystem,volume -o name,value,source bashclub:zsync
```

Eine Auswahl zurücknehmen, damit das Dataset wieder vom Elternteil erbt:
```bash
ds=rpool/data/vm-999-disk-0
zfs inherit bashclub:zsync "$ds"
```

## Mehrere Backupserver
Jede Config kann ein eigenes Tag verwenden, z. B. `tag=bashclub:zsync-offsite`. So sichert der Backupserver im Haus
alles, der Offsite-Server nur einen Teil.

## Wenn nichts ausgewählt ist
Ab 2.0 schreibt zsync dann eine Warnung ins Log, und Checkmk meldet für die Config WARN („last run selected no dataset
on the source“). Der Lauf selbst endet ohne Fehler.

## Datasets, die nicht mehr ausgewählt sind
Ab 2.0 erkennt zsync Replikate auf dem Backupserver, deren Dataset es auf der Quelle nicht mehr gibt (gelöscht oder
umbenannt) oder das nicht mehr ausgewählt ist. Diese Replikate werden nicht mehr aktualisiert und **nie automatisch
gelöscht**. Nach einem Tag meldet Checkmk WARN, bis der Admin entschieden hat:
- behalten, als Archiv ohne Warnung: `bashclub-zsync-maintenance` mit `keep` (setzt `bashclub:zsync-orphan=keep`)
- löschen: `bashclub-zsync-maintenance` mit `delete`

Der Tag Wartezeit gibt Raum für Umbenennungen und Umzüge. Ein Target gehört genau einer Config: Datasets einer
anderen Config im selben Target zählen sonst als Replikate ohne Quelle.

:::info
**Geändert in 2.0:** Bis 1.0.19 blieben solche Replikate stillschweigend liegen. Ab 2.0 meldet Checkmk sie. Nach dem
Update kann es deshalb einmalig Warnungen für alte Replikate geben; die Entscheidung trifft der Admin mit
`bashclub-zsync-maintenance`.
:::
