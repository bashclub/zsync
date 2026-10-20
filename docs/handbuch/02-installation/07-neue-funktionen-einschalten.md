---
title: Neue Funktionen einschalten
audience: Admin
outline: https://docs.bashclub.org/doc/neue-funktionen-einschalten-GfRCUQW3df
outline_id: 47f4fc6e-8cfb-4f79-97d9-1a17e6c568ea
---
Einige Funktionen von 2.0 sind für Configs aus 1.0 aus, weil sie Platz kosten oder Snapshots anders löschen. Neue
Configs aus `bashclub-zsync-setup` haben sie an. Jede lässt sich einzeln einschalten. Was sie tun, erklären die
[ZFS-Grundlagen](../01-konzept/03-zfs-grundlagen.md) und [Snapshots und Aufbewahrung](../01-konzept/05-snapshots-und-aufbewahrung.md).

| Parameter | Wirkung | Kosten |
|---|---|---|
| `monitor_engine=internal` | zsync prüft die Snapshots je Dataset selbst, statt checkzfs; dieselben Services in Checkmk | keine, checkzfs wird dafür nicht mehr gebraucht |
| `source_bookmark=1` | Replikation geht weiter, auch wenn die Quelle den letzten übertragenen Snapshot schon gelöscht hat | kein Platz, ein Bookmark je Dataset auf der Quelle |
| `source_hold=1` | Snapshots, die gerade übertragen werden, kann niemand löschen | Snapshots bleiben bis zum Ende des Datasets |
| `transfer_resume=1` | abgebrochene Übertragungen setzen im nächsten Lauf fort | der empfangene Teil belegt bis dahin Platz auf dem Backupserver |
| `snapshot_filter` mit Zahlen | der Backupserver behält eine feste Anzahl je Label, egal was die Quelle löscht | so viel Platz, wie die Snapshots belegen |

## Eingebaute Prüfung statt checkzfs
Ab 2.0. Die Services je Dataset (`<checkzfs_prefix>:<source>:<port>#<dataset>`) kommen dann von zsync selbst, mit
denselben Namen und Schwellwerten (`checkzfs_*`); eine neue Service-Erkennung in Checkmk ist nicht nötig. zsync fragt
dafür am Ende des Laufs einmal die Snapshots von Quelle und Backupserver ab, Bookmarks stören nicht. Die Config steht in
der ersten Zeile:
```bash
conf=/etc/bashclub/zsync.conf
if grep -q '^monitor_engine=' "$conf"; then sed -i 's/^monitor_engine=.*/monitor_engine=internal/' "$conf"; else echo monitor_engine=internal >> "$conf"; fi
grep '^monitor_engine=' "$conf"
```
Sofort prüfen, ohne zu replizieren: `bashclub-zsync -c "$conf" -s` zeigt die Services je Dataset und schreibt den
Spool neu.

Unterschied zu checkzfs: eine Zeile je Dataset statt zwei (Quelle und Replikat unter demselben Namen); sie zeigt den
schlechteren Zustand beider. Dazu kommen Prüfungen, die checkzfs nicht hat (Zeit seit der letzten Replikation, erwartete
Anzahl auf dem Replikat, `com.sun:auto-snapshot` am Replikat), siehe [Checkmk-Services](../06-referenz/09-checkmk.md).
`file_count` ist die Zahl auf dem Replikat, Graphen zeigen beim Umstellen einen Sprung; `checkzfs_max_snapshot_count`
gilt nur noch für die Quelle. Ohne den Eintrag nimmt zsync checkzfs, wenn es installiert ist, sonst die eingebaute
Prüfung. Rückweg: `monitor_engine=checkzfs`, vorher die Bookmarks ausschalten (unten).

## Bookmark, Hold und Resume
Alle drei auf einmal einschalten; den Bookmark nur mit der eingebauten Prüfung (oben), checkzfs bricht an Bookmarks ab.
Die Config steht in der ersten Zeile; vorhandene Einträge werden ersetzt, fehlende angehängt:
```bash
conf=/etc/bashclub/zsync.conf
for kv in source_bookmark=1 source_hold=1 transfer_resume=1; do
  k=${kv%%=*}
  if grep -q "^$k=" "$conf"; then sed -i "s|^$k=.*|$kv|" "$conf"; else echo "$kv" >> "$conf"; fi
done
grep -E '^(source_bookmark|source_hold|transfer_resume)=' "$conf"
```
Die Werte gelten ab dem nächsten Lauf. Läuft die Config ohne root, braucht der Benutzer auf der Quelle die Rechte
`hold`, `release` und `bookmark`; `bashclub-zsync-job-user` vergibt sie.

Prüfen nach dem nächsten Lauf: Auf der Quelle steht je Dataset ein Bookmark, dessen Name Backupserver und Target
enthält:
```bash
( . "$conf"; ssh -p "$sshport" "root@${source#*@}" zfs list -H -t bookmark -o name | grep "#zsync_$(hostname -s)_" | head )
```

Rückweg: dieselben Zeilen mit `0`. Soll checkzfs wieder prüfen, danach die Bookmarks dieser Config auf der Quelle
löschen, sonst bricht es weiter ab. Der Block meldet sich als root an der Quelle an und nimmt nur die Bookmarks dieses
Backupservers und Targets:
```bash
conf=/etc/bashclub/zsync.conf
( . "$conf"; ssh -p "$sshport" "root@${source#*@}" "zfs list -H -t bookmark -o name | grep '#zsync_$(hostname -s)_${target//\//_}\$' | xargs -r -n1 zfs destroy -v" )
```

## Feste Anzahl je Label
Mit Zahlen in `snapshot_filter` folgt der Backupserver nicht mehr den Löschungen der Quelle. Beim nächsten Lauf löscht
zsync, was über die Anzahl hinausgeht. Deshalb vorher ansehen, wie viele Snapshots je Label ein Replikat heute
höchstens hat:
```bash
conf=/etc/bashclub/zsync.conf
( . "$conf"; for l in ${snapshot_filter//|/ }; do l=${l%%=*}; printf '%-10s %s\n' "$l" "$(zfs list -H -t snapshot -o name -r "$target" | grep "@.*$l" | cut -d@ -f1 | sort | uniq -c | sort -rn | awk 'NR == 1 { print $1 }')"; done )
```
Die Zahlen mindestens so groß wählen, wie die Ausgabe zeigt, wenn nichts verloren gehen soll. Dann die Zeile in der
Config ersetzen, z. B.:
```bash
conf=/etc/bashclub/zsync.conf
sed -i 's/^snapshot_filter=.*/snapshot_filter="hourly=24|daily=30|weekly=8|monthly=12"/' "$conf"
grep '^snapshot_filter=' "$conf"
```
Ein Label ohne Zahl oder mit `=source` folgt weiter der Quelle. Beides lässt sich mischen, z. B.
`snapshot_filter="hourly|daily=30"`.

Rückweg: die Zahlen wieder entfernen. Was zsync inzwischen gelöscht hat, kommt nicht zurück.
