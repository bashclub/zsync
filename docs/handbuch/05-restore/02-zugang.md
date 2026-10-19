---
title: Zugang für eine Wiederherstellung
audience: Admin
outline:
---
Ab 2.0. Ein Restore braucht eine Verbindung zwischen Backupserver und dem System, das wiederhergestellt wird. Welche
Richtung, entscheidet das Netz:

| | Pull | Push |
|---|---|---|
| wer verbindet sich | das System mit dem Backupserver | der Backupserver mit dem System |
| Benutzer | Restore-Benutzer `zsync-restore-<config>` auf dem Backupserver | root auf dem System |
| darf | nur die Replikate einer Config lesen | auf dem System schreiben (es soll ja wiederhergestellt werden) |
| gilt | bis er entfernt wird | 3 Tage (einstellbar), dann verfällt der Schlüssel |
| passt für | Quelle wiederherstellen, wenn sie den Backupserver erreicht | frisches Proxmox oder Rettungssystem, das den Backupserver nicht erreichen soll |

Beim Pull kann das System kein Backup ändern oder löschen. Beim Push bekommt nur dieses eine System für kurze Zeit
einen Schlüssel, nie den einer Replikation.

Auf dem System wird für Pull das Paket gebraucht (Paketquelle wie in der
[Installation](../02-installation/01-installation.md)):
```bash
apt install -y bashclub-zsync-restore
```

## Pull einrichten
1. Auf dem **System, das wiederhergestellt wird**: Schlüssel anlegen und den Befehl für den Backupserver ausgeben. Der
   Name des Backupservers in der ersten Zeile; damit nennt die Ausgabe die Adresse, mit der das System beim
   Backupserver ankommt:
```bash
backupserver=backup1
bashclub-zsync-restore access key "$backupserver"
```
2. Auf dem **Backupserver** als root den ausgegebenen Befehl ausführen (`bashclub-zsync-restore access pull …`) und die
   Config wählen. Er legt den Benutzer `zsync-restore-<config>` an: Sein Schlüssel gilt nur von der Adresse des Systems,
   er darf nur `zfs list`, `zfs get`, `zfs send` und Holds unter dem Target der Config.
3. Auf dem **System** den ausgegebenen Verbindungstest ausführen.

Mit NAT dazwischen sieht der Backupserver eine andere Adresse als das System; dann im Befehl aus Schritt 1 die Adresse
ersetzen, die der Backupserver sieht.

Danach auf dem System z. B.:
```bash
from=zsync-restore-pve1@backup1
bashclub-zsync-restore list --from "$from"
```

## Push einrichten
Auf dem **Backupserver** als root, die Adresse des Systems in der ersten Zeile:
```bash
host=192.0.2.10
bashclub-zsync-restore access push "$host"
```
Die Ausgabe nennt drei Befehle:
- die Zeile für `/root/.ssh/authorized_keys` auf dem System, mit `restrict`, `from=<Backupserver>` und
  `expiry-time` (braucht OpenSSH 8.2 oder neuer; Proxmox, Debian 12 und neuer haben das)
- den Verbindungstest auf dem Backupserver
- den Befehl, der die Zeile nach dem Restore auf dem System wieder entfernt

Länger gültig: `--days 7`.

## Übersicht und Aufräumen
Auf dem Backupserver:
```bash
bashclub-zsync-restore access list
```
Einen Restore-Benutzer oder Push-Schlüssel entfernen (Name aus der Liste in der ersten Zeile):
```bash
name=zsync-restore-pve1
bashclub-zsync-restore access remove "$name"
```
Abgelehnte Befehle des Restore-Benutzers stehen im Syslog des Backupservers:
`journalctl -t bashclub-zsync-restore-remote`.
