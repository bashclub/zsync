---
title: Restore und Notfall
audience: Anwender, Admin
outline: https://docs.bashclub.org/doc/restore-und-notfall-yTXNsMeTmk
outline_id: 3b71ae51-78d2-44c4-bff8-7fa4998ffdd2
---
Daten aus dem Backup zurückholen, vom einzelnen Ordner bis zum ganzen Server, und was im Notfall zu tun ist. Die
Werkzeuge kommen ab 2.0 mit dem Paket `bashclub-zsync-restore`; alle Befehle stehen in der
[Referenz](../06-referenz/05-bashclub-zsync-restore.md).

**Für Anwender und Admins**
- [Einzelne Dateien zurückholen](01-einzelne-dateien.md)

**Für Admins**
- [Zugang für eine Wiederherstellung](02-zugang.md): Pull oder Push
- [Dataset oder VM-Disk wiederherstellen](03-dataset.md)
- [Nach einem Rollback wieder anfügen](04-reattach.md)
- [Ganzen Server wiederherstellen](05-server.md)

**Notfall**
- [Ransomware und Angriffe](06-ransomware.md)
- [Disaster-Recovery-Plan und Restore-Übung](07-dr-plan.md)

Jeder Restore zeigt zuerst einen Plan und überschreibt nie ein vorhandenes Dataset. Ohne Bestätigung oder `--start`
passiert nichts.
