---
title: Snapshots und Aufbewahrung
audience: Admin
outline: https://docs.bashclub.org/doc/snapshots-und-aufbewahrung-qczGuG3x3D
outline_id: fae1fb59-1221-4f17-8301-be3ab598cc72
---
zsync überträgt nur Snapshots. Woher sie kommen, welche davon übertragen werden und wie lange sie auf dem
Backupserver bleiben, regeln wenige Parameter der Config.

## Woher die Snapshots kommen
Es gibt zwei Wege, die sich kombinieren lassen:
- **Snapshots der Quelle:** Ein Werkzeug auf der Quelle legt regelmäßig Snapshots an, meist `zfs-auto-snapshot` mit den
  Labels `frequent`, `hourly`, `daily`, `weekly`, `monthly`. zsync überträgt die, deren Label in `snapshot_filter`
  steht.
- **Snapshots von zsync:** Mit `zfs_auto_snapshot_keep` größer als 1 legt zsync vor jeder Übertragung selbst einen
  Snapshot mit dem Label `zfs_auto_snapshot_label` (Standard `backup`) an und behält auf der Quelle so viele davon.
  Das Label wird automatisch mit übertragen.

## Snapshot-Engines
Die Snapshots von zsync legt eine von zwei Engines an (`zfs_auto_snapshot_engine`):

| Engine | Wo sie läuft | Name der Snapshots |
|---|---|---|
| `internal` | `remote-snapshot-manager` vom Backupserver aus, je Dataset | `backup-2026-10-19-2300` |
| `zas` | `zfs-auto-snapshot` auf der Quelle, einmal für alle Datasets | `zfs-auto-snap_backup-2026-10-19-2300` |

`internal` braucht auf der Quelle nichts außer ZFS. `zas` braucht das Paket `zfs-auto-snapshot` auf der Quelle; fehlt
es, warnt zsync ab 2.0, dass keine Snapshots entstehen. `zas` übergeht außerdem Datasets mit
`com.sun:auto-snapshot=false`, wie `zfs-auto-snapshot` selbst; `internal` beachtet diese Property nicht.

:::info
**Geändert in 2.0:** Neue Configs verwenden `internal`. Bestehende Configs ohne den Parameter bleiben bei `zas`, wie
in 1.0. `zfs-auto-snapshot` ist ab 2.0 nur noch empfohlen, nicht mehr Pflicht.
:::

## Welche Snapshots zum Label gehören
Ab 2.0, Parameter `zfs_auto_snapshot_label_match`:
- `strict`: nur Snapshots im Namensschema der eingestellten Engine, z. B. `backup-2026-10-19-2300` bei `internal`.
- `legacy`: jeder Snapshot, dessen Name das Label enthält, wie in 1.0.

Neue Configs verwenden `strict`, bestehende ohne den Parameter bleiben bei `legacy`. Mit `legacy` stören Altlasten:
Ein Snapshot `zfs-auto-snap_backup-…`, der nach einem Wechsel von `zas` auf `internal` liegen geblieben ist, gilt als
ältester Snapshot des Labels. Fehlt er auf dem Backupserver, löscht zsync dort keine Snapshots des Labels mehr, und die
Platte läuft voll. Ab 2.0 warnt zsync in beiden Modi vor solchen Snapshots und meldet die blockierte Rotation an
Checkmk.

Ein Label darf nicht im Label einer anderen Config auf derselben Quelle enthalten sein (z. B. `zsync` und
`zsync-offsite`): im Modus `legacy` hielte jede Config die Snapshots der anderen für ihre eigenen.

## Welche Snapshots übertragen werden
`snapshot_filter` listet die Labels, getrennt durch `|`, z. B. `snapshot_filter="hourly|daily|weekly|monthly"`. Ein
Snapshot gehört zu einem Label, wenn sein Name das Label nach dem `@` enthält. Snapshots ohne passendes Label, etwa
manuelle, werden weder übertragen noch auf dem Backupserver gelöscht.

## Wie lange Snapshots auf dem Backupserver bleiben
Je Label in `snapshot_filter` gilt eine von zwei Regeln:

**Feste Anzahl (ab 2.0):** `daily=30` behält die 30 neuesten Snapshots des Labels auf dem Backupserver, egal was die
Quelle löscht. Das ist der Schutz gegen ein Löschen auf der Quelle, auch durch einen Angreifer:
```
snapshot_filter="hourly=24|daily=30|weekly=8|monthly=12"
```
Grenze: Wer die Quelle kontrolliert, kann viele neue Snapshots eines Labels anlegen und so die älteren aus der Anzahl
drängen.

**Der Quelle folgen:** `daily` oder `daily=source` löscht auf dem Backupserver, was die Quelle gelöscht hat: alle
Snapshots des Labels, die älter sind als der älteste dieses Labels auf der Quelle. Mindestens die neuesten `min_keep`
(Standard 3) bleiben. Das ist das Verhalten von 1.0; es gilt als veraltet und wird in einer späteren Version entfernt.

:::info
**Geändert in 2.0:** Bestehende Configs mit Labels ohne Zahl folgen weiter der Quelle, nach dem Update ändert sich
nichts. `bashclub-zsync-setup` schreibt für neue Configs Zahlen. Wer umstellen will, ergänzt die Zahlen in
`snapshot_filter`; beim nächsten Lauf löscht zsync, was über die Anzahl hinausgeht.

Bis 1.0.19 blieben beim Folgen der Quelle die **ältesten** Snapshots stehen, wenn `min_keep` das Löschen stoppte.
Ab 2.0 bleiben die neuesten.
:::

Das Label der Snapshot-Engine (`zfs_auto_snapshot_label`) folgt der Quelle, außer es steht mit einer Zahl in
`snapshot_filter`, z. B. `snapshot_filter="daily=30|backup=14"`.

## Was die Rotation nie löscht
- Snapshots, von denen ein Klon abhängt: ab 2.0 die alte Kette nach einem Rollback auf der Quelle und Klone von
  `bashclub-zsync-restore mount`.
- Snapshots mit anderem Label oder ohne Label.
- Replikate, deren Dataset es auf der Quelle nicht mehr gibt (siehe [Auswahl der Datasets](04-auswahl-der-datasets.md)).

## Die Aufbewahrung auf der Quelle
zsync löscht auf der Quelle nur die Snapshots seiner eigenen Engine, über `zfs_auto_snapshot_keep`. Die Snapshots von
`zfs-auto-snapshot` mit den Labels `hourly`, `daily` usw. verwaltet dessen eigene Konfiguration auf der Quelle. Der
Backupserver kann mehr Snapshots behalten als die Quelle, aber nur Snapshots, die es auf der Quelle einmal gab und die
übertragen wurden, bevor die Quelle sie gelöscht hat.
