---
title: Wechseldatenträger
audience: Admin
outline: https://docs.bashclub.org/doc/wechseldatentrager-SrFfFhw8I7
outline_id: 70125d38-b2f8-4909-9cfa-76948fccaf47
---
Ab 2.0 mit `bashclub-zsync-disk` und `bashclub-zsync-setup --autorun`; `zsync-autorun` gab es schon in 1.0.

## Ausgangslage
Eine USB-Platte wird regelmäßig angeschlossen, z. B. einmal pro Woche, und danach außer Haus gebracht. Beim
Anschließen soll die Replikation von selbst laufen, danach soll die Platte abgeschaltet sein. Die Platte ist mit LUKS2
verschlüsselt, damit eine verlorene Platte keine Daten preisgibt.

Meist hängt die Platte am Proxmox-Server selbst (lokal, `source=local`); sie kann auch an einem Backupserver hängen,
der die Daten von einer entfernten Quelle holt.

```
Platte anschließen ──> udev ──> zsync-autorun@usb-backup1
   LUKS öffnen, Pool importieren, bashclub-zsync, Pool exportieren, Platte abschalten, Mail an root
```

## 1. Config der Platte
Der Name der Platte ist zugleich Name des Pools und der Config. Die Platte steht in der ersten Zeile; das Target muss im
Pool der Platte liegen:
```bash
label=usb-backup1
bashclub-zsync-setup --source local --autorun --label "zsync-$label" --target "$label/$(hostname -s)" "$label"
```
Für eine entfernte Quelle statt `local` ihren Namen angeben; der Job-Benutzer auf der Quelle bekommt dann den Schlüssel
von root, weil `zsync-autorun` als root läuft.

Eigenes Label je Platte (`zsync-usb-backup1`): Bei mehreren Platten im Wechsel löscht die Rotation der einen Platte
sonst die Snapshots, auf denen die andere aufsetzt.

Monitoring vorbereiten, wie für jede Replikation (eigenes Präfix, siehe [Standardfall](01-standardfall.md), Schritt 5):
```bash
label=usb-backup1
sed -i "s/^checkzfs_prefix=.*/checkzfs_prefix=zsync-$label/" "/etc/bashclub/$label.conf"
```

## 2. Platte vorbereiten
Geeignete Platten anzeigen (nicht eingehängt, in keinem Pool, ohne LVM, RAID oder LUKS):
```bash
bashclub-zsync-disk list
```
Dann die Platte aus der Liste vorbereiten. Die Platte steht in der ersten Zeile, z. B. `/dev/disk/by-id/usb-WD_…`;
das Werkzeug fragt zur Bestätigung ihre Seriennummer ab:
```bash
disk=/dev/disk/by-id/usb-WD_Elements_25A3_5758
label=usb-backup1
bashclub-zsync-disk create "$disk" "$label" --luks --passphrase --config "$label"
```
Es legt an:
- LUKS2 mit Schlüsseldatei `/etc/bashclub/usb-backup1.key`, mit `--passphrase` zusätzlich eine Passphrase als zweiter
  Schlüssel (z. B. ein YubiKey mit statischem Passwort: `ykman otp static --generate 2`)
- den Pool `usb-backup1`
- die udev-Regel, die nur diese Platte erkennt
- den Link `/etc/default/zsync-autorun@usb-backup1` auf die Config, mit `trigger=autorun`

**Die Schlüsseldatei außerhalb des Hosts aufbewahren.** Ohne sie und ohne Passphrase ist die Platte nicht lesbar, auch
nicht für eine Wiederherstellung.

## 3. Ablauf beim Anschließen
`zsync-autorun@usb-backup1` startet von selbst:
1. Mail an root: Replikation startet
2. LUKS öffnen, Pool importieren
3. Replikation, Log in `/var/log/bashclub-zsync/zsync-autorun_usb-backup1.log`
4. freitags bis sonntags ein Scrub des Pools
5. Pool exportieren, LUKS schließen, Platte abschalten
6. Mail an root mit Ergebnis und `zpool status`

Nach der Mail kann die Platte abgezogen werden. Für die Mail braucht der Host einen funktionierenden `mail`-Befehl
(Paket `bsd-mailx`, bei Proxmox vorhanden).

## Mehrere Platten im Wechsel
Für jede Platte Schritt 1 und 2 mit eigenem Namen (`usb-backup1`, `usb-backup2`, …). Jede hat ihre Config, ihr Label und
ihre Replikate. Die Snapshots ihres Labels legt und löscht nur der Lauf dieser Platte; der letzte übertragene bleibt
deshalb auf der Quelle, bis die Platte wiederkommt, auch nach Wochen außer Haus. Bookmarks braucht es dafür nicht.

## Monitoring
Configs mit `trigger=autorun` haben keine Altersprüfung, weil niemand weiß, wann die Platte wieder kommt. Soll Checkmk
warnen, wenn eine Platte zu lange nicht angeschlossen war, ein Höchstalter in die Config schreiben, z. B. 8 Tage bei
wöchentlichem Wechsel:
```bash
label=usb-backup1
echo 'monitor_max_age=8d' >> "/etc/bashclub/$label.conf"
```
Die Spool-Datei liegt auf dem Host; damit die Services erhalten bleiben, während die Platte weg ist, muss
`checkzfs_spool_maxage` länger sein als die Zeit bis zum nächsten Anschließen, z. B. `checkzfs_spool_maxage=777600`
(9 Tage).

## Wiederherstellen von der Platte
Damit beim Anschließen keine Replikation startet, den automatischen Lauf bis zum nächsten Neustart abschalten, dann die
Platte anschließen, öffnen und den Pool importieren:
```bash
label=usb-backup1
systemctl mask --runtime "zsync-autorun@$label.service"
```
Nach dem Anschließen:
```bash
label=usb-backup1
cryptsetup open "$(blkid -t LABEL="$label" -o device | head -n1)" "$label" --key-file "/etc/bashclub/$label.key"
zpool import "$label"
```
Danach wie im Bereich Restore und Notfall beschrieben. Zum Schluss:
```bash
label=usb-backup1
zpool export "$label"
cryptsetup close "$label"
systemctl unmask --runtime "zsync-autorun@$label.service"
```
