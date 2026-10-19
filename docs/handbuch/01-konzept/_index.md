---
title: Konzept und Grundlagen
audience: Anwender, Admin
outline: https://docs.bashclub.org/doc/konzept-und-grundlagen-dKqLsQ1g1M
outline_id: 41703fee-7de0-45eb-b98a-5c6577fe3673
---
Dieser Bereich erklärt, was bashclub-zsync tut und warum es so gebaut ist. Wer zsync einrichtet oder betreibt, sollte
ihn einmal gelesen haben. Die Anleitungen in den anderen Bereichen setzen diese Begriffe voraus.

- [Was ist bashclub-zsync](01-was-ist-bashclub-zsync.md): Zweck, Abgrenzung, Pakete
- [Architektur und Ablauf eines Laufs](02-architektur.md): Pull, SSH, lokaler Modus, die Schritte eines Laufs
- [ZFS-Grundlagen für zsync](03-zfs-grundlagen.md): Snapshot, GUID, Kette, Bookmark, Hold, Resume
- [Auswahl der Datasets](04-auswahl-der-datasets.md): das Tag `bashclub:zsync` und seine Vererbung
- [Snapshots und Aufbewahrung](05-snapshots-und-aufbewahrung.md): Snapshot-Engines, Labels, wie lange was bleibt
- [Sicherheitsmodell](06-sicherheitsmodell.md): Rechte, Schutz vor Ransomware, wer was entscheidet
- [Monitoring-Konzept](07-monitoring-konzept.md): wie Checkmk vom Zustand der Replikation erfährt
- [Glossar](08-glossar.md)

Das Handbuch beschreibt Version 2.0. Funktionen, die mit 2.0 oder später kamen, nennen ihre Version („ab 2.0“).
Hinweisboxen „Geändert in 2.0“ zeigen, wo sich der Betrieb gegenüber 1.0 ändert.
