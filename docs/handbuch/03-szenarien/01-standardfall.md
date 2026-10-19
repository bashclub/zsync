---
title: "Standardfall: Proxmox-Server → Backupserver im LAN"
audience: Admin
outline: https://docs.bashclub.org/doc/standardfall-proxmox-server-backupserver-im-lan-DW3L4WTeQM
outline_id: e33bab36-c948-47e9-aeda-3e8b4f460adb
---
## Ausgangslage
- **Quelle:** ein Proxmox-Server, hier `pve1`, mit den Disks der VMs und Container unter `rpool/data`.
- **Backupserver:** ein zweiter Server mit ZFS-Pool, im selben Netz, mit `bashclub-zsync` (siehe
  [Installation](../02-installation/01-installation.md)).
- **Ziel:** alle 15 Minuten ein Backup aller VM-Disks, auf dem Backupserver 24 stündliche, 30 tägliche, 8 wöchentliche
  und 12 monatliche Snapshots, unabhängig davon, was auf der Quelle passiert. Ohne root auf beiden Seiten, mit
  Checkmk-Überwachung.

```
pve1 (Quelle)                               backup1 (Backupserver)
  rpool/data            <── SSH als ────    bashclub-zsync@pve1.timer (alle 15 min)
    vm-100-disk-0           zsync-backup1-pve1      als zsync-pve1
    subvol-101-disk-0   ── zfs send ──>     backup/zsync/pve1/rpool/data/…
```

## 1. Pakete
Auf der Quelle die Paketquelle von bashclub einrichten (Schritt 1 und 2 der Installation) und `bashclub-zsync-source`
installieren:
```bash
apt install -y bashclub-zsync-source
```

## 2. Zugang für das Setup
Der Backupserver braucht einmalig einen Zugang zur Quelle, um sie einzurichten: als root oder als Verwaltungsbenutzer
`zsync`. Bei Proxmox darf sich root meist mit Passwort anmelden; dann auf dem **Backupserver**, mit dem Namen der
Quelle in der ersten Zeile:
```bash
source=pve1
test -f /root/.ssh/id_ed25519 || ssh-keygen -q -t ed25519 -N "" -f /root/.ssh/id_ed25519
ssh-copy-id -i /root/.ssh/id_ed25519.pub "root@$source"
```
Ohne root-Anmeldung den Weg über `zsync` aus der [Installation](../02-installation/01-installation.md), Schritt 4.

## 3. Datasets auswählen
Auf der **Quelle**: die Disks aller VMs und Container unter `rpool/data`, aber nicht `rpool/data` selbst:
```bash
zfs set bashclub:zsync=subvols rpool/data
```
Vor dem Setup, denn es vergibt die Rechte auf der Quelle für die Datasets, die jetzt ausgewählt sind.

## 4. Replikation einrichten
Auf dem **Backupserver**. Der Name der Config ist der Name der Quelle; das Setup fragt nach allen Werten und schlägt
sinnvolle vor (Enter übernimmt sie):
```bash
source=pve1
bashclub-zsync-setup --source "$source" "$source"
```
Die Vorschläge:

| Frage | Vorschlag |
|---|---|
| Target | `<erster Pool>/zsync/pve1` |
| Tag | `bashclub:zsync` |
| Zeitplan | `*/15 * * * *` (alle 15 Minuten) |
| Snapshots je Label auf der Quelle | `14` |
| Label der Snapshots von zsync | `zsync-<backupserver>` |
| Aufbewahrung hier | `hourly=24\|daily=30\|weekly=8\|monthly=12\|zsync-<backupserver>=14` |

Nach der Zusammenfassung und `y` legt das Setup an:
- `/etc/bashclub/pve1.conf` mit den Defaults neuer Configs (Engine `internal`, `strict`, Bookmark, Hold, Resume,
  eingebaute Prüfung der Snapshots)
- das Target mit `mountpoint=none`
- den Benutzer `zsync-pve1` mit eigenem Schlüssel und Rechten nur auf das Target
- auf der Quelle den Benutzer `zsync-<backupserver>-pve1`, eingeschränkt auf die Adresse des Backupservers, die Befehle
  von zsync und die ausgewählten Datasets
- den Timer `bashclub-zsync@pve1.timer`

Am Ende listet es die ausgewählten Datasets der Quelle.

Ohne Fragen, z. B. für mehrere Server: `bashclub-zsync-setup --yes --source pve1 pve1` übernimmt alle Vorschläge.
Alle Optionen: [Werkzeuge auf dem Backupserver](../06-referenz/03-werkzeuge-backupserver.md).

## 5. Monitoring vorbereiten
Jede Replikation braucht ein eigenes `checkzfs_prefix`. Es bestimmt den Namen der Spool-Datei und der Services in
Checkmk. Zwei Replikationen mit demselben Präfix überschreiben sich gegenseitig die Spool-Datei, und in Checkmk
kollidieren ihre Services. Das Setup setzt es nicht. Mit dem Namen der Config in der ersten Zeile:
```bash
name=pve1
conf=/etc/bashclub/$name.conf
sed -i "s/^checkzfs_prefix=.*/checkzfs_prefix=zsync-$name/" "$conf"
grep -E '^(checkzfs_prefix|monitor_engine)=' "$conf"
```
Die Snapshots je Dataset prüft zsync bei neuen Configs selbst (`monitor_engine=internal`, ab 2.0); checkzfs ist dafür
nicht nötig.

## 6. Erster Lauf und Prüfung
Den ersten Lauf starten und verfolgen (Strg-C beendet nur die Anzeige). Die Erstreplikation überträgt alles und dauert
je nach Datenmenge Stunden; die folgenden Läufe übertragen nur Änderungen. Danach läuft die Replikation alle
15 Minuten per Timer.
```bash
systemctl start --no-block bashclub-zsync@pve1.service
journalctl -u bashclub-zsync@pve1 -f
```
Danach die Replikate und den Zustand:
```bash
conf=/etc/bashclub/pve1.conf
( . "$conf"; zfs list -r -o name,used "$target" )
bashclub-zsync -c "$conf" -s
```
`-s` zeigt `OK` mit der Zeit des letzten erfolgreichen Laufs und dem Intervall aus dem Timer, z. B.
`interval 15m from bashclub-zsync@pve1.timer`.

## 7. Monitoring
Die Spool-Datei liegt auf dem Backupserver (`checkzfs_spool=0`). Damit der Benutzer `zsync-pve1` sie schreiben darf,
legt das Setup den Spool mit der Gruppe `bashclub-zsync` an, wenn der Checkmk-Agent installiert ist. Wird der Agent
erst später installiert, danach:
```bash
install -d -m 3775 -g bashclub-zsync /var/lib/check_mk_agent/spool
```
In Checkmk für den Backupserver die Service-Erkennung
ausführen und übernehmen:
- `zsync-pve1 pve1`: der Zustand der Replikation
- `zsync-pve1:zsync-<backupserver>-pve1@pve1:22#rpool/data/…`: je Dataset Alter und Anzahl der Snapshots

Die Spool-Datei heißt `/var/lib/check_mk_agent/spool/87000_zsync-pve1`.

Sollen die Services an der Quelle hängen (z. B. weil der Backupserver nicht immer läuft), siehe
[Backupserver nur zur Replikation eingeschaltet](07-backupserver-zeitweise.md).

## Neue VMs
Neue Disks unter `rpool/data` erben das Tag. Damit der Benutzer auf der Quelle sie lesen darf, braucht er die Rechte
auf ihnen; ein Dataset, das unter einem ausgewählten Dataset neu entsteht, erbt sie. Wer weitere Datasets **an anderer
Stelle** auswählt, ruft danach auf der Quelle `bashclub-zsync-job-user allow` auf (siehe
[Programme auf der Quelle](../06-referenz/04-programme-quelle.md)).

## Typische Fehler
| Meldung | Ursache und Abhilfe |
|---|---|
| Setup: `no login on pve1 to set it up` | Schritt 2 fehlt: kein Schlüssel für root oder `zsync` auf der Quelle |
| Setup: `bashclub-zsync-source could not be installed on pve1` | auf der Quelle fehlt die Paketquelle von bashclub (Schritt 1) |
| Setup: `no dataset on pve1 has bashclub:zsync set yet` | Schritt 3 fehlt; nachholen und auf der Quelle `bashclub-zsync-job-user allow <job> bashclub:zsync` |
| Lauf: `source … is not reachable` | Quelle aus, Adresse geändert oder `from=` passt nicht; `journalctl -t bashclub-zsync-remote` auf der Quelle |
| `permission denied` bei `mountpoint`, `canmount` … | gewollt: der Benutzer darf diese Properties nicht setzen, die Werte stehen am Replikat |
