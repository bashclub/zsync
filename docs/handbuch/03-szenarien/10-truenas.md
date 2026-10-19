---
title: TrueNAS SCALE
audience: Admin
outline: https://docs.bashclub.org/doc/truenas-scale-Lx9QrXsOD6
outline_id: cbf37f27-c836-43cf-9ce7-3fa6e32e8805
---
TrueNAS SCALE kann Quelle oder Backupserver sein. Pakete lassen sich dort nicht installieren; das schränkt beides ein.

## TrueNAS als Quelle
Der Backupserver (Debian, Proxmox) holt die Daten wie von jeder anderen Quelle per SSH. `bashclub-zsync-source` gibt
es auf TrueNAS nicht, die Replikation läuft deshalb als root wie in 1.0:
1. In TrueNAS den SSH-Dienst einschalten und dem Benutzer root den öffentlichen Schlüssel des Backupservers geben
   (`cat /root/.ssh/id_ed25519.pub` auf dem Backupserver; anlegen wie in [Installation](../02-installation/01-installation.md),
   Schritt 4). Die Menüs dafür hängen von der Version von TrueNAS ab.
2. Datasets auf TrueNAS auswählen (Shell in TrueNAS), z. B. alle unter `tank/vms`:
   `zfs set bashclub:zsync=subvols tank/vms`
3. Auf dem Backupserver:
```bash
source=truenas1
bashclub-zsync-setup --source "$source" --root "$source"
```
4. Danach wie im [Standardfall](01-standardfall.md), Schritt 5 und 6: Monitoring vorbereiten (eigenes `checkzfs_prefix`,
   `source_bookmark=0`), dann den ersten Lauf starten.

**Snapshots:** Die Engine `internal` braucht auf TrueNAS nichts. Periodische Snapshots von TrueNAS heißen meist
`auto-JJJJ-MM-TT_hh-mm`; sollen sie übertragen werden, das Label `auto` in `snapshot_filter` aufnehmen, z. B.
`snapshot_filter="auto=30|zsync-backup1=14"`.

**Monitoring:** Die Spool-Datei auf dem Backupserver lassen (`checkzfs_spool=0`); auf TrueNAS läuft kein Checkmk-Agent
mit Spool.

## TrueNAS als Backupserver
Siehe [TrueNAS SCALE und manuelle Installation](../02-installation/02-truenas-und-manuell.md): Skripte auf einem Dataset,
Cron statt Timer, als root, ohne Setup, ohne Service der Config im Monitoring. Die Config von Hand anlegen; die Werte
stehen in der [Referenz](../06-referenz/01-konfigurationsparameter.md).
