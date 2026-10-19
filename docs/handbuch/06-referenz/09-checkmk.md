---
title: Checkmk-Services
audience: Admin
outline:
---
Wie die Meldung an Checkmk funktioniert, erklärt das [Monitoring-Konzept](../01-konzept/07-monitoring-konzept.md).

## Services
| Service | Herkunft | seit |
|---|---|---|
| `<checkzfs_prefix>:<source>:<sshport>#<dataset>`, z. B. `zsync:root@pve1:22#rpool/data/vm-100-disk-0` | checkzfs: Alter und Anzahl der Snapshots je Dataset | 1.0 |
| `<checkzfs_prefix> <config>`, z. B. `zsync-pve1 pve1` | Zustand der Replikation einer Config | 2.0 |

Beide kommen aus derselben Spool-Datei `/var/lib/check_mk_agent/spool/<checkzfs_spool_maxage>_<checkzfs_prefix>`.
Nach dem ersten Lauf einer neuen Config die Service-Erkennung des Hosts in Checkmk ausführen.

:::warning
**checkzfs und Bookmarks:** checkzfs (bis Version 4.14) bricht ab, sobald auf der Quelle oder dem Backupserver ein
Bookmark existiert (`'NoneType' object has no attribute 'add_snapshot'`). Dann fehlen alle checkzfs-Services; der
Service der Config meldet weiter. Solange checkzfs das Monitoring macht, `source_bookmark=0` setzen. Neue Configs aus
dem Setup haben `source_bookmark=1`. Eine eigene Prüfung in zsync, die checkzfs ersetzt, ist geplant.
:::

## Zustände des Services der Config
| Zustand | Erkennung | Status |
|---|---|---|
| letzter erfolgreicher Lauf zu alt | Intervall + max(20 %, 5 min) + Dauer des letzten erfolgreichen Laufs | WARN, CRIT nach 3 Intervallen; in der Lernphase höchstens WARN |
| letzter Lauf fehlgeschlagen | Exit-Code ungleich 0 | WARN |
| keine Datasets ausgewählt | letzter Lauf ohne Dataset | WARN |
| Phase ohne Übertragung zu lang | Liste, Snapshots, Löschen, checkzfs | WARN 15 min, CRIT 1 h |
| Übertragung ohne Fortschritt | von `zfs receive` gelesene Bytes ändern sich nicht | WARN 10 min, CRIT 30 min |
| Prozess blockiert | Prozess des Laufs im Zustand D (z. B. wartet auf ZFS), mit Kernel-Funktion | WARN 5 min, CRIT 15 min |
| Lauf abgebrochen | Zustandsdatei ohne laufenden Prozess (beendet, abgestürzt, Stromausfall) | WARN bis zum nächsten Lauf |
| übersprungene Läufe | 3 oder mehr während eines aktiven Laufs | WARN |
| Kette gerissen, Replikat ohne Snapshots | Zustand je Dataset | CRIT, mit Ursache |
| Kette in Gefahr | Übertragung gescheitert, Basis ist der älteste Snapshot des Labels auf der Quelle | WARN |
| neuester Snapshot des Replikats fehlt auf der Quelle | Zustand je Dataset | WARN |
| Rotation am Ziel blockiert | ältester Snapshot der Quelle fehlt am Ziel | WARN |
| Replikat ohne Quelle oder nicht mehr ausgewählt | nach 1 Tag | WARN, bis behalten oder gelöscht |
| alte Kette nach Rollback | Zustand je Dataset | WARN, bis behalten oder gelöscht |

Weitere Hinweise im Text ohne Statuswechsel: neue Kette im letzten Lauf, behaltene Replikate und alte Ketten, Datasets
ohne passende Snapshots, Replikate ohne Quelle in der Wartezeit von einem Tag.

**Intervall:** aus dem Timer `bashclub-zsync@<name>.timer`, sonst der Median der Startabstände der letzten 10 Läufe,
oder `monitor_max_age` aus der Config. Bis 5 Abstände bekannt sind (Lernphase), höchstens WARN.
Wechseldatenträger (`trigger=autorun`) haben ohne `monitor_max_age` keine Altersprüfung.

Fälle mit Entscheidung nennen `bashclub-zsync-maintenance`.

## Zustände je Dataset
Die Namen erscheinen in `bashclub-zsync --result` als `state.<zustand>=<anzahl>`.

| Zustand | Bedeutung | Status |
|---|---|---|
| `ok` | repliziert | OK |
| `branched` | im letzten Lauf neue Kette nach Rollback angelegt | OK |
| `failed` | Übertragung gescheitert | über „letzter Lauf fehlgeschlagen“ |
| `at_risk` | Kette in Gefahr | WARN |
| `diverged` | neuester Snapshot des Replikats fehlt auf der Quelle | WARN |
| `cleanup_blocked` | Rotation am Ziel blockiert | WARN |
| `broken` | kein gemeinsamer Snapshot | CRIT |
| `empty` | Replikat ohne Snapshots | CRIT |
| `no_snapshots` | auf der Quelle keine passenden Snapshots | OK, Hinweis |
| `orphan_missing` | Dataset auf der Quelle gelöscht oder umbenannt | WARN nach 1 Tag |
| `orphan_unselected` | Dataset nicht mehr ausgewählt | WARN nach 1 Tag |
| `orphan_kept` | behalten (`bashclub:zsync-orphan=keep`) | OK, Hinweis |
| `branch` | alte Kette nach Rollback | WARN |
| `branch_kept` | alte Kette behalten | OK, Hinweis |

## Schwellwerte ändern
In `/etc/bashclub/zsync-checkmk.conf` (Sekunden bzw. Anzahl), z. B.:
```
stall_crit=3600
orphan_grace=172800
```

| Variable | Standard | Bedeutung |
|---|---|---|
| `phase_warn`, `phase_crit` | `900`, `3600` | Phase ohne Übertragung |
| `stall_warn`, `stall_crit` | `600`, `1800` | Übertragung ohne Fortschritt |
| `blocked_warn`, `blocked_crit` | `300`, `900` | Prozess im Zustand D |
| `skipped_warn` | `3` | übersprungene Läufe während eines aktiven |
| `learn_intervals` | `5` | Startabstände bis zum Ende der Lernphase |
| `orphan_grace` | `86400` | Wartezeit für Replikate ohne Quelle |

Abschalten des Services der Config: `touch /etc/bashclub/zsync-checkmk.disabled`. checkzfs abschalten:
`checkzfs_disabled=1` in der Config.

## Von Hand prüfen
```bash
bashclub-zsync -s
bashclub-zsync -c /etc/bashclub/zsync.conf -s checkmk
```
Die erste Zeile zeigt alle Configs lesbar, die zweite eine Config im Format für Checkmk.
