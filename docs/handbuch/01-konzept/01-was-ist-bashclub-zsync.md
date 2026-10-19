---
title: Was ist bashclub-zsync
audience: Anwender, Admin
outline: https://docs.bashclub.org/doc/was-ist-bashclub-zsync-suiy0tdctv
outline_id: 57dbb59d-b6c5-4270-a59a-b8b10ab53f97
---
bashclub-zsync repliziert ZFS-Datasets von einem Pool in einen anderen: von der **Quelle** in einen Pool des Hosts, auf
dem zsync läuft. Es überträgt die Snapshots der Quelle und bewahrt sie dort auf. Das geht auf zwei Wegen:
- **Entfernte Quelle:** zsync holt die Daten per SSH von einem anderen Host ab. Typisch ist ein Proxmox-Server als Quelle
  und ein zweiter Server im Keller, im Rechenzentrum oder beim Kunden, der sie sichert.
- **Lokal:** zsync repliziert zwischen zwei Pools desselben Hosts (ab 2.0 mit `source=local`), z. B. auf einen
  Wechseldatenträger am Proxmox-Server oder auf einen zweiten Pool.

Das Handbuch nennt den Host, auf dem zsync läuft und die Replikate liegen, **Backupserver**, auch wenn er bei lokaler
Replikation zugleich die Quelle ist.

## Was zsync tut
- Es wählt die Datasets der Quelle über eine ZFS-Property aus (`bashclub:zsync`), nicht über eine Liste in der
  Config. Neue VMs unter einem ausgewählten Dataset werden automatisch mitgesichert.
- Es überträgt Snapshots mit `zfs send` und `zfs receive`: einmal vollständig, danach nur die Änderungen.
- Es kann vor jedem Lauf selbst Snapshots auf der Quelle anlegen und alte wieder löschen.
- Es löscht alte Snapshots auf dem Backupserver nach festen Regeln.
- Es meldet den Zustand jedes Laufs und jedes Datasets an Checkmk.

## Backup, kein Spiegel
zsync macht ein **Backup**, keinen Spiegel der Quelle. Der Unterschied zählt im Ernstfall:
- Was auf der Quelle gelöscht wird, verschwindet auf dem Backupserver nicht sofort. Ab 2.0 kann der Backupserver je
  Snapshot-Typ eine feste Anzahl Snapshots behalten, egal was auf der Quelle passiert.
- Ein Rollback oder ein verschlüsseltes Dataset auf der Quelle überschreibt das Backup nicht. Ab 2.0 bleibt die alte
  Kette erhalten, und der Admin entscheidet, was damit passiert.
- Bei einer entfernten Quelle holt der Backupserver die Daten selbst ab, die Quelle hat keinen Zugang zu ihm. Bei
  lokaler Replikation auf einen Wechseldatenträger schützt die Trennung: zsync exportiert den Pool nach dem Lauf und
  schaltet die Platte ab.

Wie das im Einzelnen funktioniert, erklärt das [Sicherheitsmodell](06-sicherheitsmodell.md).

## Was zsync nicht tut
- Es sichert keine Dateien, sondern ZFS-Datasets und -Volumes. Die Quelle braucht ZFS.
- Es sichert keine Konfiguration außerhalb von ZFS (z. B. `/etc` eines Proxmox-Hosts, wenn das Root-Dateisystem
  nicht ausgewählt ist).
- Es macht keine anwendungskonsistenten Snapshots. Ein Snapshot einer laufenden VM entspricht einem plötzlichen
  Stromausfall der VM.
- Es ersetzt nicht den Test, ob sich ein Backup zurückspielen lässt.

## Pakete
| Paket | Wohin | Wozu |
|---|---|---|
| `bashclub-zsync` | Backupserver | die Replikation, Setup, Timer, Wechseldatenträger, Wartung, Monitoring |
| `bashclub-zsync-source` | entfernte Quelle | ab 2.0, optional: eingeschränkte Benutzer und Befehle für die Replikation; bei lokaler Replikation nicht nötig |
| `bashclub-zsync-restore` | Backupserver und das System, das wiederhergestellt wird | ab 2.0: Wiederherstellung von Datasets und ganzen Servern |
| `bashclub-checkzfs` | Backupserver | empfohlen von `bashclub-zsync`: prüft das Alter der Snapshots für Checkmk, wenn `monitor_engine=checkzfs`; ab 2.0 kann zsync das selbst |

Ohne `bashclub-zsync-source` braucht eine entfernte Quelle nur ZFS und einen SSH-Zugang für den Backupserver.

:::info
**Geändert in 2.0:** Bis 1.0.19 gab es nur das Paket `bashclub-zsync`, und der Backupserver meldete sich als root auf
der Quelle an. Ab 2.0 läuft die Replikation auf Wunsch ohne root, auf dem Backupserver wie auf der Quelle (dort mit
`bashclub-zsync-source`). Bestehende Replikationen laufen nach dem Update unverändert als root weiter.
:::

## Unterstützte Plattformen
Unterstützt sind nur Versionen, die ihr Hersteller noch regulär pflegt: Proxmox VE 8 und 9, Proxmox Backup Server,
Debian 12 und 13, Ubuntu 24.04 und 26.04. TrueNAS SCALE geht als Quelle und, mit Einschränkungen, als Backupserver.
