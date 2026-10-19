---
title: Updates und Härtung
audience: Admin
outline:
---
## Updates
Die Pakete kommen aus der Paketquelle `release`. Ein Update während eines Laufs schadet nicht: Der laufende Prozess
arbeitet mit der alten Version zu Ende, der nächste startet mit der neuen. Wer sicher gehen will, wartet, bis nichts
läuft:
```bash
bashclub-zsync busy --wait 3600 && apt update && apt upgrade -y
```
Auf der Quelle `bashclub-zsync-source` mit den übrigen Paketen aktualisieren.

Was eine neue Version ändert, steht im CHANGELOG und im Handbuch („ab …“, „Geändert in …“). Neue Funktionen, die den
Betrieb ändern könnten, sind für bestehende Configs aus, bis der Admin sie einschaltet.

`testing` enthält den neuesten Stand aus der Entwicklung, ohne Freigabe. Nur zum Testen verwenden, nicht auf
Backupservern im Betrieb.

## Logs
- Mit Timer: im Journal, die Größe begrenzt journald.
- Logdateien in `/var/log/bashclub-zsync/`: logrotate wöchentlich, 12 komprimierte Generationen.
- Logdateien anderswo (`log_file`, TrueNAS): zsync rotiert sie bei 10 MiB selbst, 4 komprimierte Generationen.

## Den Backupserver härten
Der Backupserver ist das wertvollste System: Wer ihn übernimmt, hat alle Backups.
- **Eigenes Netz oder Firewall:** eingehend nur SSH von den Admin-Arbeitsplätzen und der Checkmk-Agent vom
  Checkmk-Server. Die Quellen brauchen keinen Zugang zum Backupserver (Pull).
- **Keine weiteren Dienste**, keine Freigaben (SMB, NFS) der Replikate.
- **Eigene Zugangsdaten:** kein gemeinsames root-Passwort mit den Quellen, keine Schlüssel der Quellen auf dem
  Backupserver, die ihm Zugang geben.
- **SSH:** Anmeldung nur mit Schlüssel, root nicht direkt (`PermitRootLogin prohibit-password` oder `no`).
- **Betrieb ohne root** (Default neuer Replikationen): Die Replikationen laufen als eigene Benutzer mit Rechten nur auf
  ihr Target. Bestehende Configs umstellen: [Betrieb ohne root](../02-installation/05-betrieb-ohne-root.md).
- **Feste Aufbewahrung je Label** (`daily=30` statt `daily`): Löschen auf der Quelle verkleinert das Backup nicht.
- **Zweite Kopie** außer Haus: [Kaskade](../03-szenarien/06-kaskade.md) oder [Wechseldatenträger](../03-szenarien/03-wechseldatentraeger.md).

## Die Quelle härten
- `bashclub-zsync-source`: Der Backupserver meldet sich als Job-Benutzer an, der nur die Befehle von zsync ausführen
  darf, nur von seiner Adresse.
- Ist die Umstellung erledigt, den Schlüssel von root des Backupservers aus `/root/.ssh/authorized_keys` der Quelle
  entfernen. Das Setup braucht ihn nur zum Einrichten; weitere Replikationen lassen sich über den Verwaltungsbenutzer
  `zsync` einrichten.
- Abgelehnte Befehle prüfen: `journalctl -t bashclub-zsync-remote`.
