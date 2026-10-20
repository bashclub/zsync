---
title: Diagnose
audience: Admin
outline: https://docs.bashclub.org/doc/diagnose-4ugned3rNJ
outline_id: 3781c93c-8796-4590-9d67-de1490316546
---
Der Weg von „Checkmk meldet etwas“ zur Ursache, in dieser Reihenfolge. Alle Befehle auf dem Backupserver als root.

## 1. Zustand aller Configs
```bash
bashclub-zsync -s
```
Ab 2.0. Eine Zeile je Config und je Dataset, vorne `OK`, `WARN` oder `CRIT`, mit der Ursache im Text. `-s` repliziert
nichts; es schreibt die Spool-Datei neu und fragt die Quelle nur nach den Snapshots für die Services je Dataset. Läuft
eine Config ohne root, führt root die Prüfung als ihr Benutzer aus.

Was jeder Zustand bedeutet: [Zustände und was zu tun ist](../04-betrieb/03-zustaende.md).

## 2. Log des letzten Laufs
Mit Timer, die Config in der ersten Zeile:
```bash
name=pve1
journalctl -u "bashclub-zsync@$name" -n 200 --no-pager | grep -E '\[(WARN|ERROR)\]|Configuration|Included'
```
Per Cron im Log des Cron-Jobs, meist in `/var/log/bashclub-zsync/`. Am Anfang jedes Laufs stehen die Werte der Config
(`[INFO] Configuration:`) und die ausgewählten Datasets (`Included datasets`). Jede Meldung mit Ursache:
[Meldungen](../06-referenz/08-meldungen.md).

## 3. Der Zustand, den der Lauf hinterlassen hat
Ab 2.0 schreibt jeder Lauf sein Ergebnis in den Ordner seines Benutzers. Als `key=value`, ohne die Quelle zu fragen:
```bash
conf=/etc/bashclub/pve1.conf
bashclub-zsync -c "$conf" --result
```
`rc` ist der Exit-Code, `ok_end` die Zeit des letzten erfolgreichen Laufs, `state.<zustand>` die Zahl der Datasets je
Zustand. Die Datei mit dem Zustand jedes Datasets aus dem letzten Lauf:
```bash
conf=/etc/bashclub/pve1.conf
cat /var/lib/bashclub-zsync/*/"$(readlink -m "$conf" | tr '/' '_').datasets"
```
Alle Dateien: [Dateien und Pfade](../06-referenz/06-dateien-und-pfade.md).

## 4. Debug-Lauf
Zeigt jeden Befehl, den zsync ausführt. Als der Benutzer der Config, damit Rechte und Schlüssel dieselben sind wie beim
Timer:
```bash
conf=/etc/bashclub/pve1.conf
user=$(sed -n 's/^run_as=//p' "$conf" | tr -d "\"'")
if [ -n "$user" ]; then runuser -u "$user" -- bashclub-zsync -d -c "$conf"; else bashclub-zsync -d -c "$conf"; fi
```
Läuft gerade ein Lauf derselben Config, endet dieser sofort (`Another run … is still active`). Vorher prüfen:
`bashclub-zsync busy`.

## 5. Prüfbefehle
Die Blöcke lesen Quelle, Port, Target und Benutzer aus der Config in der ersten Zeile.

**Verbindung zur Quelle**, als der Benutzer der Config, mit einem Befehl, den auch der Job-Benutzer darf:
```bash
conf=/etc/bashclub/pve1.conf
( . "$conf"; r=; [ -n "$run_as" ] && r="runuser -u $run_as --"; $r ssh -o BatchMode=yes -p "$sshport" "$source" zfs list -H -o name | head )
```
Ohne Ausgabe oder mit Fehler: siehe [Typische Fehler](02-typische-fehler.md#quelle-nicht-erreichbar).

**Kette eines Datasets**, die neuesten Snapshots auf Quelle und Backupserver mit GUID. Das Dataset auf der Quelle in der
zweiten Zeile:
```bash
conf=/etc/bashclub/pve1.conf
ds=rpool/data/vm-100-disk-0
( . "$conf"; r=; [ -n "$run_as" ] && r="runuser -u $run_as --"
  echo "Quelle:"; $r ssh -o BatchMode=yes -p "$sshport" "$source" zfs list -H -o guid,name -t snapshot -s createtxg "$ds" | tail -n 3
  echo "Backupserver:"; zfs list -H -o guid,name -t snapshot -s createtxg "$target/$ds" | tail -n 3 )
```
Der neueste Snapshot des Backupservers muss auf der Quelle mit derselben GUID stehen. Fehlt er dort, wurde auf der
Quelle zurückgerollt oder gelöscht; gibt es gar keine gleiche GUID mehr, ist die Kette gerissen.

**Pool des Backupservers:**
```bash
zpool status -x
zpool list -o name,size,alloc,free,cap
```

**Offene Entscheidungen:** `bashclub-zsync-maintenance --list`.

**Abgelehnte Befehle auf der Quelle** (ohne root, auf der **Quelle**):
```bash
journalctl -t bashclub-zsync-remote --since today --no-pager
```

## Bei Fragen an andere
Für eine Anfrage im Forum oder an den Support: die Ausgabe von `bashclub-zsync -s`, die Zeilen `[WARN]` und `[ERROR]`
des letzten Laufs, die Version (`bashclub-zsync -h 2>&1 | head -n 1`) und die Config ohne Adressen und Schlüssel.
