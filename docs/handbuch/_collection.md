---
title: bashclub-zsync
audience: Anwender, Admin
outline: https://docs.bashclub.org/collection/bashclub-zsync-MKfiJIBPou
outline_id: af914add-61f3-42bd-bd03-32dcb155f1bb
---
**bashclub-zsync** repliziert ZFS-Datasets und -Volumes von Pool zu Pool – von einer Quelle per SSH oder lokal zwischen
Pools desselben Hosts, z. B. auf Wechseldatenträger. Es arbeitet als Backup, nicht als Spiegel: Der Backupserver holt
die Daten selbst ab, behält Snapshots nach eigenen Regeln und schützt sie vor Löschung, Rollback und Verschlüsselung auf
der Quelle. Dazu gehören Snapshots auf der Quelle, systemd-Timer, Betrieb ohne root, Monitoring in Checkmk und eine
Toolbox für die Wiederherstellung. Freie Software unter GPL-3.0-or-later.

Dieses Handbuch beschreibt Version 2.0. Funktionen, die mit 2.0 oder später kamen, nennen ihre Version („ab 2.0“).

## Kapitel
1. [Konzept und Grundlagen](01-konzept/_index.md) – was zsync tut und warum es so gebaut ist
2. [Installation, Upgrade und Migration](02-installation/_index.md) – Pakete, Upgrade von 1.0, neue Funktionen
   einschalten
3. [Szenarien](03-szenarien/_index.md) – Anleitungen für gängige Fälle, vom Standardfall bis zur Kaskade
4. [Betrieb, Monitoring und Wartung](04-betrieb/_index.md) – Alltag, Checkmk, Entscheidungen, Platz, Updates
5. [Restore und Notfall](05-restore/_index.md) – vom einzelnen Ordner bis zum ganzen Server, Ransomware, DR-Plan
6. [Referenz](06-referenz/_index.md) – Parameter, Programme, Dateien, Properties, Meldungen, Checkmk-Services
7. [Fehlerbehebung und FAQ](07-fehlerbehebung/_index.md) – Diagnose, typische Fehler, häufige Fragen

Neu hier: mit dem [Konzept](01-konzept/_index.md) anfangen, dann der
[Standardfall](03-szenarien/01-standardfall.md). Von 1.0: [Upgrade auf 2.0](02-installation/03-upgrade-auf-2-0.md).

## Kontakt

| ![](https://code.bashclub.org/bashclub/zsync/raw/branch/main/docs/handbuch/logo-spille-it.png) | ![](https://code.bashclub.org/bashclub/zsync/raw/branch/main/docs/handbuch/logo-bashclub.png) |
|:---:|:---:|
| **Spille IT Solutions** | **bashclub** |
| Thorsten Spille, bashclub-Kernteam, Maintainer von bashclub-zsync | Community rund um Proxmox, ZFS und Linux, entstanden bei der sysops GmbH |
| Kommerzieller Support, Einrichtung und Wartung | Videos: [YouTube-Kanal sysopstv](https://www.youtube.com/@sysopstv) |
| [spille-it.de](https://spille-it.de) | [code.bashclub.org](https://code.bashclub.org/bashclub/zsync) |
| [kontakt@spille-it.de](mailto:kontakt@spille-it.de) | [github.com/bashclub](https://github.com/bashclub) |

**Fehler, Fragen, Wünsche:** Issues im Repository [code.bashclub.org/bashclub/zsync](https://code.bashclub.org/bashclub/zsync). Zum
Kommentieren ist ein Konto bei code.bashclub.org nötig, die Anmeldung geht auch mit einem GitHub-Konto.

**Unterstützen**

| ![](https://code.bashclub.org/bashclub/zsync/raw/branch/main/docs/handbuch/kofi-block.png) |
|:---:|
| [ko-fi.com/thorakel](https://ko-fi.com/A0A1J73JR) |

Die Artikel entstehen im Repository unter `docs/handbuch` und werden von dort hierher veröffentlicht. Korrekturen bitte
als Issue oder Pull Request.
