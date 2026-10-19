---
title: Entscheidungen mit bashclub-zsync-maintenance
audience: Admin
outline:
---
Ab 2.0. zsync löscht keine Replikate und ersetzt keine Ketten von selbst. Fälle, die eine Entscheidung brauchen,
meldet es an Checkmk und markiert sie am Replikat. `bashclub-zsync-maintenance` zeigt sie und führt die Entscheidung
aus. Warum: [Sicherheitsmodell](../01-konzept/06-sicherheitsmodell.md).

## Die Fälle
| Typ | Fall | Optionen |
|---|---|---|
| `orphan` | Replikat ohne Dataset auf der Quelle oder nicht mehr ausgewählt | `keep`, `delete`, `later` |
| `broken` | kein gemeinsamer Snapshot mit der Quelle, oder Replikat ohne Snapshots | `rename`, `delete`, `later` |
| `leftovers` | Snapshots des Labels in fremdem Namensschema am Replikat | `delete`, `later` |
| `branch` | alte Kette nach einem Rollback auf der Quelle | `keep`, `delete`, `later` |

- `keep`: behalten als Archiv, ohne weitere Warnung (`bashclub:zsync-orphan=keep`)
- `delete`: das Replikat mit allen Snapshots und Kindern löschen (`zfs destroy -r`)
- `rename`: das alte Replikat in `<replikat>.broken-<datum>` umbenennen; der nächste Lauf überträgt neu. Das umbenannte
  erscheint nach einem Tag als Replikat ohne Quelle und wird dann behalten oder gelöscht.
- `later`: nichts tun, der Fall bleibt offen und Checkmk warnt weiter

## Geführt
```bash
bashclub-zsync-maintenance
```
1. Übersicht aller offenen Fälle aller Configs, mit belegtem Platz. Datasets unter einem Fall desselben Typs zählen zu
   ihm (`+3 datasets below`): `delete` und `rename` nehmen sie mit, `keep` erben sie.
2. Auswahl:
   - **all: later** (Standard): nichts ändern
   - **per case type:** eine Option für alle Fälle eines Typs; vorher eine Vorschau der ganzen Gruppe (alle Befehle, was
     `destroy` löscht, belegter Platz) und eine Bestätigung
   - **one by one:** je Fall Kontext, Optionen und Vorschau, dann Bestätigung

Vor dem Löschen zeigt die Vorschau, was ZFS löschen würde (`zfs destroy -nv`). Ohne Bestätigung geschieht nichts.

## Ohne Fragen
Offene Fälle auflisten, eine Zeile je Fall mit ID:
```bash
bashclub-zsync-maintenance --list
```
Einen Fall entscheiden, zuerst als Probelauf (die ID steht in der ersten Zeile):
```bash
case=1a2b3c4d
bashclub-zsync-maintenance --decide "$case" keep --dry-run
bashclub-zsync-maintenance --decide "$case" keep
```
Alle Fälle eines Typs, z. B. alle Snapshot-Altlasten löschen:
```bash
bashclub-zsync-maintenance --decide-type leftovers delete --dry-run
bashclub-zsync-maintenance --decide-type leftovers delete
```
Für Skripte: `--list --tsv` mit ID, Config, Typ, Dataset, seit, Detail, belegtem Platz, je Zeile ein Fall.

## Sicherheit
- Jede Aktion läuft unter der Sperre ihrer Config, nie während eines Laufs. Läuft gerade einer, meldet das Werkzeug das;
  später noch einmal entscheiden.
- Jede Entscheidung steht mit Zeit und Benutzer in `/var/log/bashclub-zsync/maintenance.log` und im Syslog.
- Ein fehlgeschlagener Fall hält eine Gruppe nicht auf; er bleibt offen.
- Das Werkzeug läuft nur auf dem Backupserver. Die Quelle kann keine Entscheidung auslösen.

## Fälle aus der Zeit vor 2.0
zsync markiert die Fälle ab 2.0 am Replikat. Fälle, die schon vor dem Update bestanden, erscheinen nach dem nächsten
Lauf der Config. Bis dahin weist das Werkzeug darauf hin.
