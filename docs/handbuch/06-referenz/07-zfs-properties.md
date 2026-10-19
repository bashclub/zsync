---
title: ZFS-Properties
audience: Admin
outline:
---
User-Properties von bashclub-zsync. Sie stehen an den Datasets und lassen sich mit `zfs get` lesen.

## Auf der Quelle
| Property | Werte | Bedeutung |
|---|---|---|
| `bashclub:zsync` (oder der Name aus `tag`) | `all`, `subvols`, anderes | wählt Datasets für die Replikation aus, siehe [Auswahl der Datasets](../01-konzept/04-auswahl-der-datasets.md) |
| `com.sun:auto-snapshot` | `true`, `false` | Property von `zfs-auto-snapshot`: `false` nimmt ein Dataset von dessen Snapshots aus, auch von denen der Engine `zas` |

Alle ausgewählten Datasets:
```bash
zfs get -t filesystem,volume -o name,value,source bashclub:zsync
```

## Auf dem Backupserver
| Property | Wo | Bedeutung |
|---|---|---|
| `com.sun:auto-snapshot=false` | Target | zsync setzt sie, damit kein `zfs-auto-snapshot` auf dem Backupserver Snapshots der Replikate anlegt |
| `bashclub:zsync-source.<property>` | Replikat | ab 2.0: Wert einer Property auf der Quelle, die die Replikation ändert oder weglässt, als `<local\|inherited\|default\|received>:<wert>`; betrifft `mountpoint`, `canmount`, `com.sun:auto-snapshot`, `refquota`, das Tag und ohne root alle Properties, die der Benutzer nicht setzen darf |
| `bashclub:zsync-orphan=keep` | Replikat | ab 2.0: Replikat ohne Quelle als Archiv behalten, ohne Warnung; gesetzt von `bashclub-zsync-maintenance` (`keep`) |
| `bashclub:zsync-branch` | alte Kette | ab 2.0: `<datum>;<grund>` an `<replikat>.zsync-branch-<datum>`, der alten Kette nach einem Rollback auf der Quelle |
| `bashclub:zsync-case` | Replikat | ab 2.0: offener Fall für `bashclub-zsync-maintenance`, `<typ>;<seit>;<config>;<detail>`; zsync setzt und entfernt sie selbst |
| `bashclub:zsync-restore-clone` | Klon | ab 2.0: Snapshot, aus dem `bashclub-zsync-restore mount` den Klon gemacht hat |

Die Originalwerte der Quelle für die Replikate von `/etc/bashclub/zsync.conf`:
```bash
conf=/etc/bashclub/zsync.conf
( . "$conf"; zfs get -H -o name,property,value -s local -r all "$target" | grep 'bashclub:zsync-source\.' )
```

Offene Fälle aller Configs:
```bash
bashclub-zsync-maintenance --list
```

## Die ZFS-Properties, die zsync auf Replikaten setzt
- `canmount=noauto` an Dateisystemen: Replikate hängen sich beim Booten nicht ein.
- `mountpoint`: wird nicht übertragen; Replikate erben ihn vom Target. Ohne root hat das Target `mountpoint=none`.
- `refquota`: vor jeder inkrementellen Übertragung auf den Wert der Quelle angehoben (oder entfernt, wenn die Quelle
  keine hat), nie verringert. `quota` bleibt unberührt.
- Das Tag und `com.sun:auto-snapshot` werden nicht übertragen (`zfs receive -x`).
