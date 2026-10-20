# bashclub-zsync

[English](README.md)

Gefällt dir bashclub-zsync?

<a href="https://ko-fi.com/A0A1J73JR"><img src="docs/handbuch/kofi-button.png" alt="Unterstütze die Entwicklung" height="41"></a>

Pull-Replikation von ZFS-Datasets auf einen Backupserver: inkrementell, auch verschlüsselt (raw), fortsetzbar, mit
Snapshots, Aufbewahrung, Checkmk-Monitoring und Restore. Der Backupserver holt die Daten von der Quelle; die Quelle hat
keinen Zugriff auf das Backup.

## Handbuch

Das vollständige Handbuch, ohne Login lesbar: **https://docs.bashclub.org/s/bashclub-zsync**

Die Quelle liegt im Repository unter [`docs/handbuch`](docs/handbuch), das Handbuch wird daraus erzeugt.

| Kapitel | Inhalt |
|---|---|
| Konzept und Grundlagen | Pull statt Push, Kette und gemeinsamer Snapshot, Backup statt Spiegel, Monitoring |
| Installation, Upgrade und Migration | Paketquelle, Einrichtung mit `bashclub-zsync-setup`, Update von 1.0, neue Funktionen einschalten |
| Szenarien | LAN, lokal, Wechseldatenträger, Offsite, Kaskade, Cluster, TrueNAS u. a., je Schritt für Schritt |
| Betrieb, Monitoring und Wartung | Zustände in Checkmk und was zu tun ist, Entscheidungen mit `bashclub-zsync-maintenance` |
| Restore und Notfall | einzelne Dateien, Dataset oder VM-Disk, ganzer Server, Wechseldatenträger, Ransomware |
| Referenz | alle Parameter, Befehle, Dateien, Meldungen und Checkmk-Services |
| Fehlerbehebung und FAQ | Diagnose in fünf Schritten, typische Fehler, häufige Fragen |

## Schnellstart

Auf dem Backupserver, nach dem Einbinden der Paketquelle (siehe Handbuch, Installation):

```bash
apt install bashclub-zsync
bashclub-zsync-setup
```

Das Setup fragt Quelle und Ziel ab, richtet über einen einmaligen SSH-Zugang die Quelle ein und legt Config und Timer
an. Welche Datasets
repliziert werden, bestimmt auf der Quelle die Property `bashclub:zsync` (`all`, `subvols` oder `exclude`).

## Lizenz

Ab Version 2.0.0 steht bashclub-zsync unter der GNU General Public License, Version 3 oder später (`GPL-3.0-or-later`, Datei `LICENSE`). Versionen bis 1.0.19 wurden unter der MIT-Lizenz veröffentlicht; ihr Hinweis steht in der copyright-Datei der Pakete (`/usr/share/doc/bashclub-zsync/copyright`).
