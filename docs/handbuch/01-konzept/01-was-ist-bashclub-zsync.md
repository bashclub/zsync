---
title: Was ist bashclub-zsync
audience: Anwender, Admin
outline:
---
bashclub-zsync repliziert ZFS-Datasets von einem Server (der **Quelle**) auf einen **Backupserver**. Es überträgt die
Snapshots der Quelle und bewahrt sie auf dem Backupserver auf. Typisch ist ein Proxmox-Server als Quelle und ein
zweiter Server im Keller, im Rechenzentrum oder beim Kunden als Backupserver.

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
- Der Backupserver holt die Daten selbst ab. Die Quelle hat keinen Zugang zum Backupserver.

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
| `bashclub-zsync-source` | Quelle | ab 2.0, optional: eingeschränkte Benutzer und Befehle für die Replikation |
| `bashclub-zsync-restore` | Backupserver und das System, das wiederhergestellt wird | ab 2.0: Wiederherstellung von Datasets und ganzen Servern |
| `bashclub-checkzfs` | Backupserver | wird mit `bashclub-zsync` installiert: prüft das Alter der Snapshots für Checkmk |

Ohne `bashclub-zsync-source` braucht die Quelle nur ZFS und einen SSH-Zugang für den Backupserver.

:::info
**Geändert in 2.0:** Bis 1.0.19 gab es nur das Paket `bashclub-zsync`, und der Backupserver meldete sich als root auf
der Quelle an. Ab 2.0 geht beides auch ohne root, mit `bashclub-zsync-source` auf der Quelle. Bestehende
Replikationen laufen nach dem Update unverändert als root weiter.
:::

## Unterstützte Plattformen
Unterstützt sind nur Versionen, die ihr Hersteller noch regulär pflegt: Proxmox VE 8 und 9, Proxmox Backup Server,
Debian 12 und 13, Ubuntu 24.04 und 26.04. TrueNAS SCALE geht als Quelle und, mit Einschränkungen, als Backupserver.
