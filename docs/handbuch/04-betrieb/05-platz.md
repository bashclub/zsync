---
title: Platz planen
audience: Admin
outline: https://docs.bashclub.org/doc/platz-planen-ubxZd4nXfe
outline_id: cfa74a15-4e96-44e3-86e4-60f752400620
---
## Was Platz braucht
- **Die Daten selbst:** etwa so viel wie auf der Quelle (`refer` der Datasets); die Kompression der Quelle bleibt
  erhalten, weil zsync raw überträgt.
- **Snapshots:** je Snapshot die Blöcke, die sich seitdem geändert haben. Je mehr Snapshots und je höher die
  Änderungsrate, desto mehr. Siehe [Aufbewahrungsstufen](../03-szenarien/09-aufbewahrung.md).
- **Alte Ketten nach einem Rollback** (ab 2.0): Bis der Admin entscheidet, belegen sie zusätzlich ihren Platz.
- **Replikate ohne Quelle:** bleiben, bis der Admin sie löscht.
- **Angefangene Übertragungen** (`transfer_resume=1`): der empfangene Teil, bis der nächste Lauf fortsetzt.

## Nachsehen
Je Config: belegt gesamt, davon Snapshots:
```bash
for conf in /etc/bashclub/*.conf; do ( . "$conf"; zfs list -H -o name,used,usedbysnapshots,avail "$target" 2>/dev/null ); done
```
Die größten Replikate einer Config:
```bash
conf=/etc/bashclub/pve1.conf
( . "$conf"; zfs list -r -t filesystem,volume -o name,used,usedbysnapshots,refer -s used "$target" | tail -n 10 )
```
Was alte Ketten, Replikate ohne Quelle und Altlasten belegen, zeigt `bashclub-zsync-maintenance --list` in der Spalte
`USED`.

Füllstand des Pools:
```bash
zpool list -o name,size,alloc,free,cap,frag
```
ZFS wird ab etwa 80 % Füllstand langsamer. Checkmk überwacht den Pool mit dem Standard-Check `zfs`.

## Platz schaffen
1. Offene Fälle entscheiden: alte Ketten, Replikate ohne Quelle, Altlasten löschen
   ([bashclub-zsync-maintenance](04-wartung.md)).
2. Weniger Snapshots behalten: die Zahlen in `snapshot_filter` senken. Der nächste Lauf löscht, was darüber hinausgeht.
3. Größere Platten oder ein weiterer Pool; Replikate umziehen wie in
   [Umzug von Replikaten](../02-installation/08-umzug.md).

## refquota
Eine `refquota` der Quelle übernimmt das Replikat bei der Erstreplikation. Ab 2.0 hebt zsync sie auf dem Replikat an,
wenn sie auf der Quelle wächst, damit die Replikation nicht am Kontingent scheitert. Es senkt sie nie, und `quota`
bleibt unberührt.

## Platz für Wechseldatenträger
Ein Wechseldatenträger muss alle ausgewählten Datasets mit ihren Snapshots aufnehmen. Vor dem Kauf auf dem Backupserver
oder der Quelle nachsehen, was die Replikate heute belegen, und etwa die Hälfte als Reserve für das Wachstum und die
Snapshots zwischen zwei Wechseln dazurechnen.
