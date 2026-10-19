---
title: Installation, Upgrade und Migration
audience: Admin
outline:
---
Dieser Bereich bringt bashclub-zsync auf die Systeme und bestehende Installationen auf 2.0.

**Neu installieren**
- [Installation](01-installation.md): Paketquelle, Backupserver, Quelle, System für eine Wiederherstellung
- [TrueNAS SCALE und manuelle Installation](02-truenas-und-manuell.md)

**Von 1.0 auf 2.0**
- [Upgrade auf 2.0](03-upgrade-auf-2-0.md): was das Update tut, was es bewusst nicht tut, Prüfung danach

Nach dem Upgrade läuft alles wie bisher. Die folgenden Umstellungen sind freiwillig und einzeln möglich, jede mit
Prüfung und Rückweg:
- [Cron auf systemd-Timer](04-cron-auf-timer.md)
- [Betrieb ohne root](05-betrieb-ohne-root.md)
- [Snapshot-Engine und Label-Abgleich](06-snapshot-engine-und-labels.md)
- [Neue Funktionen einschalten](07-neue-funktionen-einschalten.md): Bookmarks, Holds, Resume, Aufbewahrung je Label

**Sonstiges**
- [Umzug von Replikaten auf einen anderen Pool](08-umzug.md)
- [Downgrade auf 1.0](09-downgrade.md)
