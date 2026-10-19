---
title: Verschlüsselte Datasets
audience: Admin
outline: https://docs.bashclub.org/doc/verschlusselte-datasets-SWOgIcZkWy
outline_id: b3ce5bef-62e9-410e-a1a3-7e837c004245
---
## Ausgangslage
Auf der Quelle sind Datasets mit ZFS-Verschlüsselung angelegt (`encryption=on`), z. B. die Disks einer VM mit
sensiblen Daten. Der Backupserver soll sie sichern, ohne sie lesen zu können.

## So funktioniert es
zsync überträgt immer raw (`zfs send -w`). Verschlüsselte Datasets kommen verschlüsselt an, der Schlüssel verlässt die
Quelle nie. Es ist nichts einzustellen; die Einrichtung ist dieselbe wie im [Standardfall](01-standardfall.md).

Auf dem Backupserver zeigt das Replikat `keystatus=unavailable`. Das ist richtig so:
```bash
conf=/etc/bashclub/pve1.conf
( . "$conf"; zfs get -r -t filesystem,volume -o name,value keystatus "$target" | grep -v -- '-$' )
```
Inkrementelle Übertragungen, Bookmarks, Resume und eine neue Kette nach einem Rollback funktionieren auch raw.

## Den Schlüssel sichern
Ohne Schlüssel ist auch das Backup wertlos. Den Schlüssel (Passphrase oder Schlüsseldatei, `keylocation`) getrennt von
Quelle und Backupserver aufbewahren, z. B. im Passwortmanager. Welche Datasets welchen Schlüssel brauchen, zeigt die
Verschlüsselungswurzel auf der Quelle:
```bash
zfs get -r -t filesystem,volume -o name,value encryptionroot,keyformat,keylocation | grep -v -- '-$'
```

## Wiederherstellen
- **Dataset zurück auf die Quelle oder einen neuen Server:** `bashclub-zsync-restore dataset` überträgt raw. Danach den
  Schlüssel laden; der Bericht des Restore-Jobs nennt den Befehl (`zfs load-key`).
- **Einzelne Dateien auf dem Backupserver:** `bashclub-zsync-restore mount` braucht den Schlüssel auf dem Backupserver
  (`zfs load-key` am Replikat). Danach `zfs unload-key`, damit der Backupserver die Daten nicht dauerhaft lesen kann.

## Was zu beachten ist
- Wird der Schlüssel auf der Quelle geändert (`zfs change-key`), übernimmt das Replikat den neuen mit der nächsten
  Übertragung; bis dahin gilt dort der alte. ZFS ändert dabei nur den Schlüssel, der den Datenschlüssel umhüllt: Danach
  öffnet der neue Schlüssel alle Snapshots, auch die alten. Den alten Schlüssel aufbewahren, bis der nächste Lauf
  durch ist.
- Ohne root darf der Job-Benutzer auf dem Backupserver keine Schlüssel laden; das ist gewollt.
