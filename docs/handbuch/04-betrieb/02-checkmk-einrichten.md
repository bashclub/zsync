---
title: Checkmk einrichten
audience: Admin
outline:
---
Wie die Meldung funktioniert, erklärt das [Monitoring-Konzept](../01-konzept/07-monitoring-konzept.md); alle Services
und Schwellwerte stehen in der Referenz [Checkmk-Services](../06-referenz/09-checkmk.md).

## Voraussetzungen
- Auf dem Host, der die Spool-Datei bekommt, läuft der Checkmk-Agent und ist in Checkmk eingetragen.
- Jede Replikation hat ein eigenes `checkzfs_prefix` (siehe [Mehrere Quellen](../03-szenarien/05-mehrere-quellen.md#monitoring)).
- `source_bookmark=0`: checkzfs bricht ab, sobald es Bookmarks gibt (siehe
  [Standardfall](../03-szenarien/01-standardfall.md), Schritt 5).
- Läuft die Config ohne root, darf ihr Benutzer in den Spool schreiben (auf dem Host, der die Datei bekommt):
```bash
install -d -m 3775 -g bashclub-zsync /var/lib/check_mk_agent/spool
```

## Wohin: Backupserver oder Quelle
| | `checkzfs_spool=0` (Default) | `checkzfs_spool=1` |
|---|---|---|
| Spool-Datei auf | dem Backupserver | der Quelle |
| Services in Checkmk am Host | Backupserver | Quelle |
| passt, wenn | der Backupserver immer läuft | der Backupserver nur zeitweise läuft oder Checkmk die Quelle besser erreicht |

## Services übernehmen
Nach dem ersten Lauf liegt die Datei im Spool, z. B. `/var/lib/check_mk_agent/spool/87000_zsync-pve1`. Prüfen, was der
Agent liefert, auf dem Host mit der Datei:
```bash
cat /var/lib/check_mk_agent/spool/*_zsync*
```
Dann in Checkmk für diesen Host die Service-Erkennung ausführen und die neuen Services übernehmen:
- `<präfix> <config>`, z. B. `zsync-pve1 pve1`: Zustand der Replikation
- `<präfix>:<source>:<port>#<dataset>`: je Dataset Alter und Anzahl der Snapshots (checkzfs)

## Wie alt die Datei werden darf
Die Zahl vorn im Dateinamen ist `checkzfs_spool_maxage` in Sekunden. Ist die Datei älter, liefert der Agent sie nicht mehr
aus, und Checkmk meldet die Services als fehlend (je nach Regel UNKNOWN oder vanished). Sie muss länger sein als der
längste Abstand zwischen zwei Läufen:

| Läufe | `checkzfs_spool_maxage` |
|---|---|
| alle 15 Minuten, stündlich | `3900` |
| täglich | `87000` (Default) |
| wöchentlich (Wechseldatenträger) | `777600` (9 Tage) |

Eine Änderung benennt die Datei um; die alte unter dem alten Namen danach löschen.

## Benachrichtigung
Den Service `<präfix> <config>` in die Benachrichtigungsregeln für Backups aufnehmen. Er meldet alle Probleme der
Replikation, auch Hänger während eines Laufs, und nennt die Abhilfe. Die checkzfs-Services je Dataset melden zusätzlich,
wenn einzelne Datasets veralten.

Beim ersten Einrichten meldet der Service der Config Zustände, die es schon vorher gab (z. B. alte Replikate ohne
Quelle). Das ist gewollt; siehe [Zustände und was zu tun ist](03-zustaende.md).

## Schwellwerte
Für alle Configs eines Backupservers in `/etc/bashclub/zsync-checkmk.conf`, z. B. für lange Übertragungen über eine
langsame Leitung:
```bash
cat > /etc/bashclub/zsync-checkmk.conf << 'EOF'
stall_warn=1800
stall_crit=7200
EOF
```
Das Höchstalter des letzten Laufs je Config steht in der Config selbst (`monitor_max_age`). Alle Variablen:
[Checkmk-Services](../06-referenz/09-checkmk.md).

## Abschalten
- Service der Config auf diesem Backupserver: `touch /etc/bashclub/zsync-checkmk.disabled`
- checkzfs für eine Config: `checkzfs_disabled=1` in der Config
