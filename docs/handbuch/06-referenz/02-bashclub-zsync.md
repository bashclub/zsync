---
title: bashclub-zsync
audience: Admin
outline:
---
## `bashclub-zsync`
Das Programm der Replikation auf dem Backupserver.

```
bashclub-zsync [-h] [-d] [-c CONFIG] [-s [checkmk]] [--result]
bashclub-zsync busy [--wait [SECONDS]]
```

| Option | Wirkung |
|---|---|
| `-c CONFIG` | Config, Standard `/etc/bashclub/zsync.conf`. Gibt es die Datei nicht, legt zsync sie an und endet. |
| `-d` | ausführliches Log (`[DEBUG]`) |
| `-s` | ab 2.0: Zustand anzeigen und Spool schreiben, ohne Replikation (siehe unten) |
| `-s checkmk` | ab 2.0: dasselbe in der Rohausgabe für Checkmk |
| `--result` | ab 2.0: Ergebnis des letzten Laufs als `key=value` (siehe unten) |
| `busy` | ab 2.0: Ist etwas aktiv? (siehe unten) |
| `-h` | Hilfe mit der installierten Version |

### Ein Lauf
`bashclub-zsync -c /etc/bashclub/pve1.conf` repliziert alle ausgewählten Datasets einmal. Ablauf:
[Architektur und Ablauf eines Laufs](../01-konzept/02-architektur.md).

Ausgabe: eine Zeile je Meldung mit Zeit und Stufe `[INFO]`, `[WARN]`, `[ERROR]`, mit `-d` auch `[DEBUG]`. Per Cron
leitet man sie in eine Datei um (immer mit `>>`, siehe Hinweis unten), mit Timer landet sie im Journal oder in
`log_file`.

**Exit-Code**
- `0`: alle Datasets repliziert. Warnungen ändern den Exit-Code nicht.
- `1`: mindestens ein Dataset nicht repliziert, oder der Lauf endete sofort: Config fehlerhaft (`source` leer), Quelle
  nicht erreichbar, ein Hook vor dem Lauf schlug fehl, oder derselbe Lauf ist schon aktiv.

Ein Fehler bei einem Dataset bricht den Lauf nicht ab; alle anderen werden repliziert.

:::info
**Geändert in 2.0:** Pro Config läuft nur ein Lauf gleichzeitig; ein zweiter endet sofort mit `[ERROR]` und
Exit-Code 1. Ist die Quelle nicht erreichbar, endet der Lauf mit 1 statt mit 0. Mit `>` statt `>>` in einem Cron-Job
leert ein übersprungener Lauf das Log des aktiven.
:::

### Statusausgabe `-s`
Ab 2.0. Zeigt den Zustand so, wie Checkmk ihn sieht, und schreibt die Spool-Datei neu. Repliziert nichts, legt keine
Snapshots an, löscht nichts und ändert den Zustand der Läufe nicht. checkzfs läuft dabei.

```bash
bashclub-zsync -s
```
- ohne `-c`: alle Configs in `/etc/bashclub`, Exit-Code der schlechtesten
- Exit-Code `0` OK, `1` WARN, `2` CRIT
- als root für eine Config mit `run_as`: läuft als dieser Benutzer, mit seinem Schlüssel für die Quelle

### Ergebnis `--result`
Ab 2.0. Das Ergebnis des letzten Laufs einer Config als `key=value`, eine Zeile je Wert, für Skripte und Werkzeuge wie
Miyagi. Liest nur den Zustand der Läufe; startet nichts und fragt die Quelle nicht.

```bash
bashclub-zsync -c /etc/bashclub/zsync.conf --result
```

| Key | Bedeutung |
|---|---|
| `format` | Version des Formats, immer die erste Zeile (`1`) |
| `config` | Pfad der Config |
| `running` | `1`, wenn gerade ein Lauf aktiv ist |
| `rc` | Exit-Code des letzten Laufs |
| `start`, `end`, `duration` | letzter Lauf, Unix-Zeit und Sekunden |
| `datasets`, `datasets_failed` | Anzahl Datasets und davon fehlgeschlagen |
| `ok_start`, `ok_end`, `ok_duration` | letzter erfolgreicher Lauf |
| `state.<zustand>` | Anzahl Datasets je Zustand, siehe [Checkmk-Services](09-checkmk.md) |
| `decisions` | offene Fälle für `bashclub-zsync-maintenance` |
| `resume_datasets`, `resume.<dataset>=1` | unterbrochene Übertragungen, die der nächste Lauf fortsetzt |

Unbekannte Werte fehlen. Neue Keys können dazukommen; ein Skript soll nur die lesen, die es kennt.

### `busy`
Ab 2.0. Prüft, ob etwas aktiv ist: eine Replikation, eine Aktion von `bashclub-zsync-maintenance`, ein Restore-Job oder
ein Lauf für einen Wechseldatenträger.

```bash
bashclub-zsync busy
bashclub-zsync busy --wait 3600
```
- Exit-Code `0`: nichts aktiv. `1`: etwas aktiv, die Ausgabe nennt es.
- `--wait [SECONDS]`: wartet, bis nichts mehr aktiv ist; mit Sekunden höchstens so lange, dann Exit-Code `1`.

Solange ein Lauf oder ein Restore-Job aktiv ist, blockiert ein systemd-Inhibitor Herunterfahren und Ruhezustand
(`systemd-inhibit --list`). root kann ihn übergehen; ein Werkzeug sollte deshalb vorher `busy` fragen:
```bash
bashclub-zsync -c /etc/bashclub/zsync.conf && bashclub-zsync busy --wait 3600 && poweroff
```

### Hooks
Ab 2.0. Ausführbare Dateien in `/etc/bashclub/hooks.d/pre-run/` und `post-run/` (alle Configs) sowie
`/etc/bashclub/hooks.d/<config>/pre-run/` und `post-run/` (eine Config) laufen vor und nach dem Lauf, in
lexikalischer Reihenfolge, als der Benutzer des Laufs.
- Nur Dateien und Ordner von root, die nur root schreiben darf; sonst entfällt der Lauf mit Fehler.
- `pre-run`: Exit-Code ungleich 0 überspringt den Lauf (`[ERROR]`, Exit-Code 1).
- `post-run`: läuft nach jedem Lauf, auch nach einem Fehler; ein Fehler ergibt nur eine Warnung.
- Umgebung: `ZSYNC_CONFIG`, `ZSYNC_NAME`, `ZSYNC_TARGET`, `ZSYNC_SOURCE`, `ZSYNC_PHASE`, nach dem Lauf `ZSYNC_RC` und
  `ZSYNC_DURATION`.
- Abbruch nach `hook_timeout` Sekunden.

## `remote-snapshot-manager`
Die Snapshot-Engine `internal`. bashclub-zsync ruft es selbst auf; von Hand nur zum Testen.

```
remote-snapshot-manager -d <dataset> -k <keep> -l <label> [-f <dateformat>] [-v] [-h <host>] [-p <port>]
```
Legt `<dataset>@<label>-<datum>` an (Datum nach `-f`, Standard `%Y-%m-%d-%H%M`) und löscht die ältesten Snapshots des
Labels über `<keep>` hinaus. Mit `-h` auf einem anderen Host per SSH. Gibt es den Snapshot dieser Minute schon, endet es
mit `Error: Failed to create snapshot.`; zsync überträgt dann die vorhandenen.
