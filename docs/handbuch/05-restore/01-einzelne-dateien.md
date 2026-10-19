---
title: Einzelne Dateien zurückholen
audience: Anwender, Admin
outline:
---
Ab 2.0, auf dem Backupserver. Eine gelöschte oder überschriebene Datei kommt aus einem Snapshot zurück, ohne das ganze
Dataset wiederherzustellen. Der Snapshot wird dafür schreibgeschützt eingehängt; das Backup selbst bleibt unverändert.

## Für Anwender
Wer selbst keinen Zugang zum Backupserver hat, schickt dem Admin:
- welche Datei oder welcher Ordner, mit vollständigem Pfad
- welche VM oder welcher Container (Name oder Nummer, z. B. `100`)
- welcher Stand: das Datum, an dem die Datei noch richtig war

Der Admin legt die Datei an einen vereinbarten Ort, z. B. eine Freigabe oder einen Ordner `wiederhergestellt` neben
dem Original. So wird nichts Aktuelles überschrieben.

## Für Admins
### 1. Replikat und Snapshot finden
Die Replikate einer Config mit ihren Snapshots, hier der VM 100 von `pve1`:
```bash
conf=/etc/bashclub/pve1.conf
( . "$conf"; zfs list -H -o name -t filesystem,volume -r "$target" | grep -- '-100-disk-' )
```
Die Snapshots eines Replikats, die neuesten zuletzt (das Replikat aus der Ausgabe oben in der ersten Zeile):
```bash
replica=backup/zsync/pve1/rpool/data/vm-100-disk-0
zfs list -H -o name,creation -t snapshot -s createtxg "$replica" | tail -n 20
```

### 2. Einhängen
```bash
snap=backup/zsync/pve1/rpool/data/vm-100-disk-0@zfs-auto-snap_daily-2026-10-19-0000
bashclub-zsync-restore mount "$snap"
```
Die Ausgabe nennt den Ordner, z. B. `/run/bashclub-zsync-restore/mnt/20261019-120000` (Datum und Uhrzeit):
- **Container (Dateisystem):** der Inhalt des Containers.
- **VM-Disk (Volume):** je Partition ein Unterordner (`part1`, `part2`, …), schreibgeschützt eingehängt, ohne das
  Journal abzuspielen.
  Bei LVM, LUKS oder einem unbekannten Dateisystem zeigt es das Gerät; dann von Hand weiter (z. B. `vgchange -ay`).
- **Verschlüsselt:** nur, wenn der Schlüssel auf dem Backupserver geladen ist; sonst nennt es den Befehl
  `zfs load-key`.

### 3. Datei kopieren
Mit den gewohnten Werkzeugen, z. B. zurück auf die Quelle nach `/root`, nicht über das Original. In der ersten Zeile der Pfad aus
der Ausgabe von Schritt 2 mit der gesuchten Datei:
```bash
src=/run/bashclub-zsync-restore/mnt/20261019-120000/part1/home/user/Dokumente/Vertrag.docx
scp "$src" root@pve1:/root/
```
Bei einer Windows-VM die Datei z. B. per SMB-Freigabe oder `scp` auf einen Rechner im Netz der VM bringen.

### 4. Aufräumen
Den Klon wieder entfernen. Solange er existiert, behält die Rotation seinen Snapshot.
```bash
bashclub-zsync-restore mounts
bashclub-zsync-restore cleanup --all
```
`cleanup` entfernt nur Klone, die `mount` angelegt hat.

### Ohne Restore-Werkzeug
Für einen Container (Dateisystem) mit ZFS allein: einen schreibgeschützten Klon an einem eigenen Ort einhängen, die
Datei kopieren, den Klon wieder löschen. Snapshot und Klon in den ersten Zeilen; der Klon gehört in denselben Pool:
```bash
snap=backup/zsync/pve1/rpool/data/subvol-101-disk-0@zfs-auto-snap_daily-2026-10-19-0000
clone=backup/restore-klon
zfs clone -o readonly=on -o mountpoint=/mnt/restore-klon "$snap" "$clone"
ls /mnt/restore-klon
```
Danach:
```bash
clone=backup/restore-klon
zfs destroy "$clone"
```
Für eine VM-Disk ist der Weg mit dem Werkzeug einfacher: Es macht die Partitionen sichtbar und hängt sie ohne
Journal ein.
