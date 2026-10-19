---
title: Ransomware und Angriffe
audience: Admin
outline:
---
Was zu tun ist, wenn eine Quelle verschlüsselt oder übernommen wurde. Warum das Backup den Angriff übersteht, erklärt
das [Sicherheitsmodell](../01-konzept/06-sicherheitsmodell.md).

## 0. Ruhe bewahren, Quelle isolieren
Die Quelle vom Netz trennen, aber nicht neu installieren und nichts löschen: Sie zeigt, wie der Angreifer
hereingekommen ist. Danach als Erstes die Replikation anhalten.

## 1. Replikation anhalten
Neue Snapshots der Quelle enthalten jetzt verschlüsselte Daten. Sie verdrängen nach der Aufbewahrung irgendwann die
sauberen, wenn die Replikation weiterläuft. Deshalb auf dem Backupserver sofort die Configs der betroffenen Quelle
anhalten, mit dem Namen der Config in der ersten Zeile:
```bash
name=pve1
systemctl stop "bashclub-zsync@$name.timer"
systemctl list-timers "bashclub-zsync@$name.timer" --all --no-pager
```
Läuft die Config per Cron, den Eintrag auskommentieren. Ein Lauf, der gerade läuft, darf zu Ende laufen.

Nichts auf dem Backupserver löschen und nicht `bashclub-zsync-maintenance` mit Löschen bestätigen, solange der
Angriff nicht verstanden ist.

## 2. Backupserver prüfen
Pull heißt: Auf der Quelle liegt kein Schlüssel zum Backupserver. Trotzdem prüfen, ob der Angreifer auch dort war:
- Anmeldungen: `last`, `journalctl -u ssh`
- Änderungen an Replikaten oder Snapshots außerhalb von zsync: `zpool history <pool> | tail -n 50`

Auf den übrigen Quellen zeigt `journalctl -t bashclub-zsync-remote` abgelehnte Befehle, also Versuche, über den
zsync-Benutzer mehr zu tun als erlaubt.

## 3. Letzten sauberen Snapshot finden
Die Snapshots eines Replikats mit ihrer Größe; ein plötzlicher Sprung bei `written` zeigt meist den Zeitpunkt der
Verschlüsselung. Das Replikat in der ersten Zeile:
```bash
replica=backup/zsync/pve1/rpool/data/vm-100-disk-0
zfs list -H -o name,creation,written -t snapshot -s createtxg "$replica" | tail -n 30
```
Einen Kandidaten ansehen, ohne etwas zu ändern: [einhängen](01-einzelne-dateien.md) und Dateien prüfen.

## 4. Quelle wiederherstellen
Die Quelle nicht weiterverwenden, sondern neu aufsetzen oder ein anderes System nehmen. Dann:
- [Ganzen Server wiederherstellen](05-server.md) mit `--snapshot <letzter sauberer>`, oder
- einzelne Datasets mit [Dataset wiederherstellen](03-dataset.md) und `--snapshot`.

Push von einem frischen System aus ist hier die sichere Wahl: Das System bekommt nur einen Schlüssel, der nach wenigen
Tagen verfällt, und kann den Backupserver nie erreichen.

Wird die alte Quelle doch weiterbenutzt (z. B. nur eine VM war betroffen): die Disk auf der Quelle auf einen sauberen
Snapshot zurücksetzen oder per [Reattach](04-reattach.md) mit `--snapshot` und `--rollback` auf den letzten sauberen
Stand bringen.

## 5. Replikation wieder aufnehmen
Erst wenn die Quelle sauber ist. Nach einem Rollback auf der Quelle legt der nächste Lauf eine neue Kette an; die alte
mit den verschlüsselten Snapshots bleibt als `<replikat>.zsync-branch-<datum>`. Sie mit `bashclub-zsync-maintenance`
erst löschen, wenn die Analyse abgeschlossen ist (siehe [Wartung](../04-betrieb/04-wartung.md)).
```bash
name=pve1
systemctl start "bashclub-zsync@$name.timer"
```
