---
title: Proxmox-Cluster und HA
audience: Admin
outline: https://docs.bashclub.org/doc/proxmox-cluster-und-ha-t92ge8lGKD
outline_id: ccd8900a-62bf-4396-bb6e-a501cb249b9b
---
## Ausgangslage
Ein Proxmox-Cluster mit lokalem ZFS auf jedem Knoten (`pve1`, `pve2`, `pve3`). Die Disks einer VM liegen auf dem Knoten,
auf dem sie läuft. VMs werden zwischen Knoten verschoben, von Hand oder durch HA.

## Einrichten
Je Knoten eine Config, wie im [Standardfall](01-standardfall.md):
```bash
for source in pve1 pve2 pve3; do
  bashclub-zsync-setup --yes --source "$source" "$source"
  sed -i "s/^checkzfs_prefix=.*/checkzfs_prefix=zsync-$source/" "/etc/bashclub/$source.conf"
  sed -i "s/^source_bookmark=.*/source_bookmark=0/" "/etc/bashclub/$source.conf"
  systemctl start --no-block "bashclub-zsync@$source.service"
done
```
Vorher auf jedem Knoten `bashclub-zsync-source` installieren, `rpool/data` auswählen und den Zugang für das Setup
einrichten. Jede Config hat ihr eigenes Target (`<pool>/zsync/pve1`, …).

Jede Config bekommt ein eigenes `checkzfs_prefix` (`zsync-pve1`, …), damit sich ihre Spool-Dateien und Services in
Checkmk nicht überschreiben.

## Wenn eine VM den Knoten wechselt
Die Disks der VM verschwinden auf dem alten Knoten und entstehen auf dem neuen:
- Auf dem neuen Knoten erbt die Disk das Tag von `rpool/data` und wird im nächsten Lauf **vollständig** übertragen
  (Erstreplikation), in das Target des neuen Knotens.
- Das Replikat unter dem Target des alten Knotens bleibt, mit allen Snapshots. Nach einem Tag meldet Checkmk es als
  Replikat ohne Quelle. Mit `bashclub-zsync-maintenance` behalten oder löschen.

Bei häufigen Migrationen kostet das Platz und Übertragungszeit. Werden die VMs mit der Proxmox-Speicherreplikation
(`pvesr`) zwischen den Knoten gespiegelt, gibt es ihre Disks auf mehreren Knoten; dann nur auf einem Knoten auswählen,
sonst sichert der Backupserver sie mehrfach.

## Konsistenz
Die Snapshots sind absturzkonsistent: Eine laufende VM sieht im Backup aus wie nach einem Stromausfall. Für Datenbanken
deren eigene Sicherung zusätzlich verwenden. Konsistente Snapshots über den QEMU Guest Agent sind für eine spätere
Version geplant.
