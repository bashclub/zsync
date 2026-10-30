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
Quelle nie. Die Einrichtung ist dieselbe wie im [Standardfall](01-standardfall.md); was bei einem Schlüsselwechsel
passiert, legt `key_change` fest (unten).

Jedes Replikat ist auf dem Backupserver eine eigene Verschlüsselungswurzel, auch wenn es auf der Quelle den Schlüssel
seines Elternteils erbt: zsync überträgt jedes Dataset einzeln. `keylocation` steht auf dem Backupserver immer auf
`prompt`; eine Schlüsseldatei gibt man beim Laden an (`zfs load-key -L file:///pfad <replikat>`).

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

## Schlüssel wechseln
`zfs change-key` auf der Quelle verschlüsselt die Daten nicht neu; es ändert nur den Schlüssel, der den Datenschlüssel
umhüllt. Die nächste Übertragung eines Datasets bringt den neuen Schlüssel auf sein Replikat. Danach öffnet nur noch der
neue Schlüssel das Replikat, mit allen Snapshots, auch den alten. Ein Angreifer mit root auf der Quelle könnte so das
Backup sperren, ohne etwas zu löschen. Deshalb erkennt zsync ab 2.0 einen Wechsel vor der Übertragung, `key_change`
in der Config legt fest, was dann passiert:

| `key_change` | Verhalten | Kosten |
|---|---|---|
| `rename` (neue Configs) | altes Replikat bleibt als `<replikat>.zsync-branch-<datum>` mit dem alten Schlüssel, das Dataset wird im selben Lauf neu übertragen | eine Vollübertragung und Platz für beide, bis die alte Kette gelöscht wird |
| `block` | nicht übertragen, CRIT, Entscheidung in `bashclub-zsync-maintenance` (`transfer` oder `rename`) | die Replikation des Datasets steht, bis entschieden ist |
| `transfer` (Configs aus 1.0) | übertragen, das Replikat ist danach nur noch mit dem neuen Schlüssel lesbar; Warnung | keine |

Ein Klon oder eine Gabel auf dem Backupserver hilft nicht: Er gehört zur selben Verschlüsselungswurzel wie das
Replikat und wird mit umgeschlüsselt. Nur eine eigene, neu übertragene Kette behält den alten Schlüssel.

Ein gewollter Wechsel:
1. Auf der Quelle `zfs change-key`, den neuen Schlüssel sichern.
2. Mit `rename`: Nach dem nächsten Lauf liegt die alte Kette daneben. Sie mit `bashclub-zsync-maintenance` löschen,
   wenn die neue vollständig ist. Mit `block`: den Fall `key` mit `transfer` entscheiden.
3. Den alten Schlüssel aufbewahren, bis jedes Replikat den neuen hat. Ein Dataset bekommt ihn erst mit seiner nächsten
   Übertragung, ein Kind ohne neuen Snapshot behält bis dahin den alten. Prüfen, ohne den Schlüssel zu laden; die
   Schleife fragt je Verschlüsselungswurzel unter dem Target nach der Passphrase:
```bash
conf=/etc/bashclub/pve1.conf
( . "$conf"; zfs get -H -r -t filesystem,volume -o name,value encryptionroot "$target" | awk '$1 == $2 { print $1 }' | while read -r r; do printf '%s: ' "$r"; zfs load-key -n "$r" < /dev/tty > /dev/null && echo passt || echo "passt nicht"; done )
```

Grenzen: zsync erkennt den Wechsel an `keyformat`, `pbkdf2iters` und `pbkdf2salt`. Eine Schlüsseldatei
(`keyformat=raw` oder `hex`), die gegen eine andere getauscht wird, sieht es nicht. Wer root auf der Quelle hat, kann
auch die Ausgabe von `zfs` fälschen; die Prüfung schützt vor einem Wechsel, nicht vor jeder Manipulation der Quelle.

## Wiederherstellen
- **Dataset zurück auf die Quelle oder einen neuen Server:** `bashclub-zsync-restore dataset` überträgt raw. Danach den
  Schlüssel laden; der Bericht des Restore-Jobs nennt den Befehl (`zfs load-key`).
- **Einzelne Dateien auf dem Backupserver:** `bashclub-zsync-restore mount` braucht den Schlüssel auf dem Backupserver
  (`zfs load-key` am Replikat). Danach `zfs unload-key`, damit der Backupserver die Daten nicht dauerhaft lesen kann.

## Was zu beachten ist
- Auf dem Backupserver nie `zfs change-key` an einem Replikat ausführen, auch nicht `change-key -i`, um es unter ein
  anderes Replikat zu hängen. Ändert sich danach der Schlüssel auf der Quelle, meldet der Empfang Erfolg, aber das
  Replikat lässt sich mit keinem Schlüssel mehr einhängen.
- Ohne root darf der Job-Benutzer auf dem Backupserver keine Schlüssel laden; das ist gewollt.
