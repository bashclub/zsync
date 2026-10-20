---
title: Restore vom Wechseldatenträger
audience: Admin
outline: https://docs.bashclub.org/doc/restore-vom-wechseldatentrager-eJPwM06mRw
outline_id: 3c9be128-6a2a-4d07-969b-b5e8a8896f70
---
Ab 2.0. Die Platte eines [Wechseldatenträgers](../03-szenarien/03-wechseldatentraeger.md) lässt sich am Backupserver
auslesen oder an jedem anderen Host mit ZFS, z. B. an einem frisch installierten Proxmox, wenn der Backupserver selbst
verloren ist. Die Platte wird dafür **nur lesend** geöffnet und importiert: Auf ihr ändert sich nichts.

## Was man braucht
- die Platte und ihren Schlüssel: die Schlüsseldatei `/etc/bashclub/<label>.key` oder die Passphrase; wo beides liegt,
  steht im [Disaster-Recovery-Plan](08-dr-plan.md)
- auf dem Host ZFS, `cryptsetup` und `bashclub-zsync-restore`, mit der Paketquelle wie in der
  [Installation](../02-installation/01-installation.md):
```bash
apt install -y bashclub-zsync-restore cryptsetup
```
`bashclub-zsync` und eine Config braucht es nicht.

## 1. Am Backupserver: automatischen Lauf abschalten
Nur am Backupserver, der die Config der Platte hat; sonst startet beim Anschließen eine Replikation. Das Label der
Platte in der ersten Zeile:
```bash
label=usb-backup1
systemctl mask --runtime "zsync-autorun@$label.service"
```

## 2. Platte öffnen und lesend importieren
Platte anschließen. Label und Schlüsseldatei in den ersten Zeilen:
```bash
label=usb-backup1
key=/etc/bashclub/$label.key
cryptsetup open --readonly "$(blkid -t LABEL="$label" -o device | head -n1)" "$label" --key-file "$key"
zpool import -o readonly=on "$label"
```
Ohne Schlüsseldatei `--key-file "$key"` weglassen, dann fragt `cryptsetup` nach der Passphrase. Gibt es auf dem Host
schon einen Pool mit demselben Namen, die Platte unter anderem Namen importieren, z. B.
`zpool import -o readonly=on "$label" usb-restore`.

## 3. Replikate ansehen
Die Replikate liegen unter dem Target der Config, auf der Platte meist `<label>/<Name des Backupservers>`:
```bash
label=usb-backup1
zfs list -o name -d 2 "$label"
```
Mit dem Target in der ersten Zeile:
```bash
root=usb-backup1/backup1
bashclub-zsync-restore list --root "$root"
```

## 4. Wiederherstellen
Wie in den anderen Artikeln, mit `--root` statt `--config`:
- **Dataset oder VM-Disk** auf diesem Host, z. B. an ihren alten Platz auf einem neuen Proxmox:
```bash
root=usb-backup1/backup1
bashclub-zsync-restore dataset --root "$root" rpool/data/vm-100-disk-0
```
  Auf ein anderes System per Push: zusätzlich `--to <system>`, siehe [Zugang](02-zugang.md) und
  [Dataset oder VM-Disk wiederherstellen](04-dataset.md).
- **Ganzer Server:** `bashclub-zsync-restore server --root "$root"`, mit `--to`, `--map` und `--exclude` wie in
  [Ganzen Server wiederherstellen](06-server.md).
- **Einzelne Dateien:** `bashclub-zsync-restore mount <replikat>@<snapshot>` hängt bei einem Dateisystem den Snapshot
  direkt ein, ohne Klon. Eine VM-Disk (Volume) lässt sich auf der lesenden Platte nicht einhängen; sie zuerst mit
  `dataset --root "$root" --as <pool>/<name>` in einen beschreibbaren Pool holen und dort einhängen, siehe
  [Einzelne Dateien](01-einzelne-dateien.md).

Holds auf die Snapshots setzt das Werkzeug auf der lesenden Platte nicht; das Log nennt das. Die Platte ändert sich
ohnehin nicht, und keine Rotation läuft auf ihr.

## 5. Zum Schluss
Eingehängte Snapshots entfernen, Platte exportieren und schließen:
```bash
label=usb-backup1
bashclub-zsync-restore cleanup --all
zpool export "$label"
cryptsetup close "$label"
```
Am Backupserver den automatischen Lauf wieder einschalten:
```bash
label=usb-backup1
systemctl unmask --runtime "zsync-autorun@$label.service"
```
