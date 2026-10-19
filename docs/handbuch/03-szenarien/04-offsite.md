---
title: Offsite über WAN oder VPN
audience: Admin
outline: https://docs.bashclub.org/doc/offsite-uber-wan-oder-vpn-Lnusi8cT24
outline_id: e0b79f1e-d687-4e0f-ab2f-e80c82a8ab27
---
## Ausgangslage
Der Backupserver steht an einem anderen Standort, z. B. im Rechenzentrum oder bei einem zweiten Kunden, und erreicht
die Quelle über das Internet (SSH-Port weitergeleitet) oder über ein VPN. Die Leitung ist langsam oder wird tagsüber
gebraucht.

```
pve1 (Standort A)  ── VPN / Internet ──  backup-offsite (Standort B)
                    <── SSH, Port 22 oder weitergeleitet ──
```

Einrichtung wie im [Standardfall](01-standardfall.md), mit diesen Unterschieden.

## Port und Adresse
Ist SSH der Quelle über einen anderen Port erreichbar, ihn beim Setup angeben (`--port`). Der Schlüssel des
Job-Benutzers gilt nur von der Adresse, mit der der Backupserver bei der Quelle ankommt (`from=`); das Setup trägt sie
selbst ein, so wie die Quelle sie sieht. Hinter NAT ist das die öffentliche Adresse des Standorts B.
```bash
source=pve1.example.org
bashclub-zsync-setup --source "$source" --port 2222 --schedule "0 22 * * *" "$(echo "$source" | cut -d. -f1)"
```
Ändert sich die Adresse des Backupservers (neuer Anschluss, dynamische IP), lehnt die Quelle ab; dann den Job-Benutzer
neu anlegen wie in [Betrieb ohne root](../02-installation/05-betrieb-ohne-root.md), Schritt 3. Bei dynamischen Adressen
besser ein VPN mit fester Adresse.

Danach wie im [Standardfall](01-standardfall.md), Schritt 5 und 6: Monitoring vorbereiten (eigenes `checkzfs_prefix`,
`source_bookmark=0`), dann den ersten Lauf starten.

## Bandbreite begrenzen
Ab 2.0. `pv` auf dem Backupserver installieren und das Limit in die Config schreiben, hier 10 MiB/s (etwa 84 Mbit/s):
```bash
apt install -y pv
conf=/etc/bashclub/pve1.conf
grep -q '^bandwidth_limit=' "$conf" && sed -i 's/^bandwidth_limit=.*/bandwidth_limit=10m/' "$conf" || echo 'bandwidth_limit=10m' >> "$conf"
```
Das Limit gilt je Übertragung; zsync überträgt die Datasets nacheinander. Die Übertragung ist bereits komprimiert (raw),
und SSH wählt eine schnelle Verschlüsselung (AES-GCM, wenn beide CPUs AES können).

## Zeitplan
Für eine langsame Leitung nachts, z. B. täglich um 22 Uhr (`--schedule "0 22 * * *"`), oder mehrmals außerhalb der
Arbeitszeit: `"0 22 * * *;0 2 * * *"`. Ein Lauf, der länger dauert als bis zum nächsten Start, ist kein Problem: Der
Timer startet keinen zweiten.

## Unterbrechungen
Ab 2.0 setzt `transfer_resume=1` (Default neuer Configs) eine abgebrochene Übertragung im nächsten Lauf fort, statt neu
zu beginnen. Das zählt vor allem bei der Erstreplikation großer Disks, die über eine langsame Leitung Tage dauern kann.
`source_bookmark=1` würde die Kette halten, wenn der Backupserver länger nicht repliziert hat, als die Quelle ihre
Snapshots behält; solange checkzfs das Monitoring macht, bleibt es aus (siehe [Standardfall](01-standardfall.md),
Schritt 5). Dann die Snapshots auf der Quelle lange genug behalten (`--keep`, Aufbewahrung von `zfs-auto-snapshot`).

## Erstreplikation vor Ort
Bei sehr großen Datenmengen die Erstreplikation im LAN machen und den Backupserver danach an den anderen Standort
bringen:
1. Backupserver im LAN der Quelle einrichten und replizieren wie im [Standardfall](01-standardfall.md).
2. Timer stoppen, Backupserver umziehen.
3. Auf der Quelle den Job-Benutzer für die neue Adresse neu anlegen ([Betrieb ohne root](../02-installation/05-betrieb-ohne-root.md),
   Schritt 3), in der Config bei Bedarf `source` und `sshport` anpassen.
4. Timer wieder starten; ab jetzt gehen nur noch die Änderungen über die Leitung.

Alternativ die Replikate per Wechseldatenträger übertragen, wie in
[Umzug von Replikaten](../02-installation/08-umzug.md#auf-einen-neuen-backupserver).

## Monitoring
Steht der Checkmk-Server am Standort A, lieber die Spool-Datei auf die Quelle schreiben (`checkzfs_spool=1`): Dann
hängen die Services an `pve1`, und Checkmk sieht sie auch, wenn der Offsite-Standort nicht erreichbar ist. Der
Job-Benutzer muss dort in den Spool schreiben dürfen, auf der Quelle:
```bash
install -d -m 3775 -g bashclub-zsync /var/lib/check_mk_agent/spool
```
Mehrere Backupserver für dieselbe Quelle brauchen dann verschiedene `checkzfs_prefix`, siehe
[Mehrere Quellen auf einem Backupserver](05-mehrere-quellen.md#monitoring).
