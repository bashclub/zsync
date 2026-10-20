---
title: Ganzen Server wiederherstellen
audience: Admin
outline: https://docs.bashclub.org/doc/ganzen-server-wiederherstellen-F5p8PbFau2
outline_id: 70bb3fc6-6bd3-4cf7-9684-ffc416f2b64d
---
Ab 2.0. Stellt alle Replikate einer Config auf einem System wieder her, z. B. auf einem neu installierten Proxmox nach
dem Verlust des alten. Eltern vor Kindern, mit den Properties der Quelle und der ganzen Snapshot-Kette. Danach kann
die Replikation auf das neue System weiterlaufen.

## 1. System vorbereiten
- Proxmox (oder Debian mit ZFS) neu installieren, am besten mit denselben Pool-Namen wie vorher (z. B. `rpool`). Dann
  passen die Storages in den VM-Configs ohne Änderung.
- Netz so einrichten, dass Backupserver und System sich erreichen.
- Zugang einrichten, Pull oder Push (siehe [Zugang](02-zugang.md)). Für ein frisches System ist Push meist einfacher:
  Auf dem System muss dann nichts installiert werden.

## 2. Plan ansehen
Mit Push auf dem Backupserver; Config und Adresse des Systems in den ersten Zeilen:
```bash
config=pve1
host=192.0.2.10
bashclub-zsync-restore server --config "$config" --to "$host" --exclude rpool/ROOT --dry-run
```
`--exclude rpool/ROOT` lässt das Root-Dateisystem aus: Das frische System hat schon eines. Der Plan zeigt jedes Dataset
mit Ziel und Snapshot; Pool-Wurzeln (z. B. `rpool` selbst) ersetzt er nie, nur ihre Kinder.

Mit Pull dasselbe auf dem System: `--from zsync-restore-pve1@backup1` statt `--config` und `--to`.

Varianten:
- **Anderer Pool-Name:** `--map rpool/data=tank/vm` stellt alles unter `rpool/data` nach `tank/vm` her.
- **Nur ein Pool:** `--pool rpool`.
- **Ein Zeitpunkt für alle:** `--snapshot zfs-auto-snap_daily-2026-10-15-0000`; Datasets ohne diesen Snapshot bekommen
  den letzten davor.
- **Vorhandene Datasets ersetzen:** `--force` benennt sie in `<dataset>.before-restore-<zeit>` um.
- **Bandbreite begrenzen:** `--bwlimit 50m`.

## 3. Wiederherstellen
Derselbe Befehl ohne `--dry-run`. Der Job läuft im Hintergrund, übersteht das Ende der SSH-Sitzung und setzt nach
einem Abbruch mit `bashclub-zsync-restore resume <job>` fort; fertige Datasets überspringt er. Fortschritt und Bericht
wie bei [Dataset wiederherstellen](03-dataset.md).

## 4. Was danach zu prüfen ist
Am Ende nennt das Werkzeug, was es nicht selbst ändert:
- **VM- und Container-Configs:** Sie liegen in `/etc/pve`, auf Proxmox in der Datenbank
  `/var/lib/pve-cluster/config.db` des Root-Dateisystems. Mit `--exclude rpool/ROOT` kommen sie nicht mit. Aus dem
  Replikat des Root-Dateisystems lässt sich die Datei holen ([Einzelne Dateien](01-einzelne-dateien.md)); wie
  Proxmox sie zurückspielt, beschreibt die Proxmox-Dokumentation zu pmxcfs. Einfacher ist eine eigene Kopie von
  `/etc/pve`, siehe [Disaster-Recovery-Plan](07-dr-plan.md).
- **Storages:** Bei anderen Pool-Namen die Einträge `zfspool` in `/etc/pve/storage.cfg` anpassen.
- **Boot:** Wurde das Root-Dateisystem mit wiederhergestellt, `proxmox-boot-tool refresh`.
- **Netz, Hostname, SSH-Schlüssel** des Systems.
- **Verschlüsselte Datasets:** Schlüssel laden, der Bericht nennt die Befehle.

## 5. Replikation wieder aufnehmen
Hat das neue System eine andere Adresse oder einen anderen SSH-Schlüssel, die Config auf dem Backupserver anpassen
(`source`) und den Zugang zur Quelle neu einrichten, wie bei der ersten Einrichtung (siehe
[Standardfall](../03-szenarien/01-standardfall.md)). Die wiederhergestellten Datasets tragen ihr Tag und ihre
Snapshots, der nächste Lauf überträgt inkrementell weiter.

Den Push-Schlüssel danach entfernen: `bashclub-zsync-restore access list` und `access remove`.
