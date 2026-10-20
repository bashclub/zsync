---
title: Nach einem Rollback wieder anfügen
audience: Admin
outline: https://docs.bashclub.org/doc/nach-einem-rollback-wieder-anfugen-IEksYfJn1d
outline_id: 3b00c1ce-ddea-4d03-a3f5-460a7e7da3eb
---
Ab 2.0. Hat die Quelle ein Dataset auf einen älteren Snapshot zurückgesetzt oder ihre neuesten Snapshots verloren, hat
der Backupserver noch die neueren. `reattach` schickt nur diese fehlenden Snapshots zurück auf die Quelle, ab dem
neuesten gemeinsamen. Danach ist die Kette auf beiden Seiten wieder dieselbe, und die Replikation läuft ohne
Erstreplikation und ohne neue Kette weiter.

Typische Fälle:
- Eine VM wurde auf der Quelle versehentlich auf den Stand von letzter Woche zurückgesetzt; der Backupserver hat den
  von gestern.
- Nach einem Angriff wurde die Quelle auf einen Stand vor dem Angriff zurückgesetzt, und es sollen die neueren,
  noch sauberen Snapshots aus dem Backup dazukommen.

Anders als `dataset` überträgt `reattach` nur Daten, keine Properties; das Dataset auf der Quelle behält seine.

## 1. Replikation anhalten
Zwischen Rollback und `reattach` darf kein Lauf der Replikation kommen, sonst legt er auf dem Backupserver eine neue
Kette an (siehe [Wartung](../04-betrieb/04-wartung.md)). Deshalb den Timer der Config auf dem Backupserver anhalten, mit
dem Namen der Config in der ersten Zeile:
```bash
name=pve1
systemctl stop "bashclub-zsync@$name.timer"
```
Läuft die Config per Cron, ihren Cron-Eintrag auskommentieren und danach wieder einkommentieren.

## 2. Ansehen
Auf der Quelle, mit dem Restore-Benutzer der Config (siehe [Zugang](02-zugang.md)):
```bash
from=zsync-restore-pve1@backup1
bashclub-zsync-restore show --from "$from" rpool/data/vm-100-disk-0
```
Die Zeilen mit `+` fehlen auf der Quelle und kommen mit `reattach` dazu. Zeilen mit `!` gibt es nur auf der Quelle.

## 3. Anfügen
Die VM vorher herunterfahren. Dann:
```bash
from=zsync-restore-pve1@backup1
bashclub-zsync-restore reattach --from "$from" rpool/data/vm-100-disk-0
```
Wie bei `dataset` zeigt es den Plan und fragt, ob es den Job starten soll; der Bericht am Ende prüft, ob der neueste
Snapshot angekommen ist.

Der Plan bricht ab, wenn die Quelle nach dem gemeinsamen Snapshot eigene Snapshots oder Änderungen hat; die Meldung
nennt, wie viel. `--rollback` verwirft sie und setzt vorher auf den gemeinsamen Snapshot zurück. Das löscht auf der
Quelle, deshalb erst mit `--dry-run` ansehen.

Mit `--snapshot <name>` endet die Kette bei einem älteren Snapshot, z. B. dem letzten vor einem Angriff.

## 4. Replikation fortsetzen
```bash
name=pve1
systemctl start "bashclub-zsync@$name.timer"
```
Der nächste Lauf findet die Snapshots des Backupservers auf der Quelle und überträgt inkrementell weiter.
