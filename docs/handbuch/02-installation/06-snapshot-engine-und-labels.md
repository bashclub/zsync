---
title: Snapshot-Engine und Label-Abgleich
audience: Admin
outline:
---
Configs aus 1.0 ohne die Parameter `zfs_auto_snapshot_engine` und `zfs_auto_snapshot_label_match` verwenden nach dem
Update weiter die Engine `zas` und den Label-Abgleich `legacy`. Neue Configs verwenden `internal` und `strict`. Was die
Werte bedeuten, steht unter [Snapshots und Aufbewahrung](../01-konzept/05-snapshots-und-aufbewahrung.md).

Der Artikel betrifft nur Configs, in denen zsync selbst Snapshots anlegt (`zfs_auto_snapshot_keep` größer als 1).

## Warum umstellen
- **`internal`** braucht auf der Quelle kein `zfs-auto-snapshot` und legt den Snapshot je Dataset direkt vor dessen
  Übertragung an.
- **`strict`** zählt nur Snapshots im Namensschema der Engine zum Label. Altlasten eines anderen Schemas blockieren dann
  nicht mehr die Rotation auf dem Backupserver.

## Vorher
```
zfs_auto_snapshot_keep=3
zfs_auto_snapshot_label="backup"
```
Kein Eintrag für Engine und Abgleich: Die Snapshots heißen `zfs-auto-snap_backup-2026-10-19-2300`.

## Nachher
```
zfs_auto_snapshot_engine="internal"
zfs_auto_snapshot_label_match="strict"
```
Neue Snapshots heißen `backup-2026-10-19-2300`. Die alten `zfs-auto-snap_backup-…` gehören nicht mehr zum Label; zsync
warnt vor ihnen und löscht sie nicht.

## Umstellen
Alle Blöcke als root auf dem Backupserver. Die Config steht in der ersten Zeile des ersten Blocks, die weiteren Blöcke
brauchen dieselbe Shell.

1. Beide Werte in die Config schreiben (ersetzt vorhandene Einträge, sonst angehängt):
```bash
conf=/etc/bashclub/zsync.conf
for kv in zfs_auto_snapshot_engine=internal zfs_auto_snapshot_label_match=strict; do
  k=${kv%%=*}
  if grep -q "^$k=" "$conf"; then sed -i "s|^$k=.*|$kv|" "$conf"; else echo "$kv" >> "$conf"; fi
done
grep -E '^zfs_auto_snapshot_(engine|label_match)=' "$conf"
```

2. Einen Lauf abwarten oder von Hand starten. Er legt den ersten Snapshot im neuen Schema an und überträgt ihn. Danach
   ist er der gemeinsame Snapshot mit der Quelle:
```bash
bashclub-zsync -c "$conf"
```
   Im Log stehen jetzt Warnungen zu Snapshots des Labels in einem anderen Namensschema. Das sind die alten.

3. Erst danach die alten Snapshots auf der Quelle löschen. Wer sie vorher löscht, kann den letzten gemeinsamen Snapshot
   verlieren. Der Block meldet sich als root an der Quelle an, liest Port und Label aus der Config und zeigt zuerst
   nur, was gelöscht würde:
```bash
( . "$conf"; ssh -p "$sshport" "root@${source#*@}" "zfs list -H -t snapshot -o name | grep '@zfs-auto-snap_${zfs_auto_snapshot_label}-' | xargs -r -n1 zfs destroy -nv" )
```
   Stimmt die Liste, löschen:
```bash
( . "$conf"; ssh -p "$sshport" "root@${source#*@}" "zfs list -H -t snapshot -o name | grep '@zfs-auto-snap_${zfs_auto_snapshot_label}-' | xargs -r -n1 zfs destroy -v" )
```

4. Die alten Snapshots auf dem Backupserver löscht nach dem nächsten Lauf `bashclub-zsync-maintenance`: Fall
   „snapshots of the label in another name scheme“, Option `delete`. Es zeigt vorher, was gelöscht wird:
```bash
bashclub-zsync-maintenance
```

Wird `zfs-auto-snapshot` auf der Quelle sonst nicht gebraucht (keine anderen Labels wie `hourly` oder `daily`), lässt
es sich dort entfernen.

## Nur den Label-Abgleich umstellen
Wer bei `zas` bleibt, kann trotzdem `strict` einschalten. Dann zählen nur noch Snapshots im Schema
`zfs-auto-snap_<label>-JJJJ-MM-TT-hhmm` zum Label:
```bash
conf=/etc/bashclub/zsync.conf
kv=zfs_auto_snapshot_label_match=strict; k=${kv%%=*}
if grep -q "^$k=" "$conf"; then sed -i "s|^$k=.*|$kv|" "$conf"; else echo "$kv" >> "$conf"; fi
```

## Prüfen
```bash
bashclub-zsync -c "$conf" -s
```
Nach Schritt 4 meldet der Service der Config keine Snapshots in fremdem Namensschema mehr.

## Rückweg
Vor Schritt 3 jederzeit: die beiden Zeilen wieder auf `zas` und `legacy` setzen. Danach überträgt zsync wieder ab dem
neuesten gemeinsamen Snapshot, egal in welchem Schema er heißt.
```bash
conf=/etc/bashclub/zsync.conf
for kv in zfs_auto_snapshot_engine=zas zfs_auto_snapshot_label_match=legacy; do
  k=${kv%%=*}
  if grep -q "^$k=" "$conf"; then sed -i "s|^$k=.*|$kv|" "$conf"; else echo "$kv" >> "$conf"; fi
done
```
