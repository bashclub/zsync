---
title: Konfigurationsparameter
audience: Admin
outline: https://docs.bashclub.org/doc/konfigurationsparameter-r8dFu8jd61
outline_id: 0b6d21b2-6201-47bc-9ae7-57f9866b9a57
---
Eine Config ist ein Shell-Skript mit Zuweisungen `name=wert`, z. B. `/etc/bashclub/pve1.conf`. Werte mit Leerzeichen
oder `|` stehen in Anführungszeichen. Die Vorlage mit allen Parametern und Kommentaren liegt in
`/etc/bashclub/zsync.conf.example`.

## Drei Arten von Defaults
- **Ohne Eintrag:** Fehlt ein Parameter in der Config, gilt der Wert in dieser Spalte. Er entspricht dem Verhalten von
  1.0, damit Configs aus 1.0 nach dem Update unverändert weiterlaufen.
- **Neue Config (Lauf):** Ruft man `bashclub-zsync -c <datei>` mit einer Datei auf, die es nicht gibt, legt zsync sie
  mit diesen Werten an und endet.
- **Setup:** `bashclub-zsync-setup` fragt die Werte ab; in der Spalte steht sein Vorschlag.

## Übersicht
| Parameter | Ohne Eintrag | Neue Config (Lauf) | Setup | seit |
|---|---|---|---|---|
| `target` | `pool/dataset` | `pool/dataset` | `<erster Pool>/zsync/<name>` | 1.0 |
| `source` | `user@host` | `user@host` | gefragt | 1.0 |
| `sshport` | `22` | `22` | `22` | 1.0 |
| `tag` | `bashclub:zsync` | `bashclub:zsync` | `bashclub:zsync` | 1.0 |
| `snapshot_filter` | `hourly\|daily\|weekly\|monthly` | ebenso | `hourly=24\|daily=30\|weekly=8\|monthly=12\|<label>=14` | 1.0, Zahlen ab 2.0 |
| `min_keep` | `3` | `3` | `3` | 1.0, veraltet |
| `zfs_auto_snapshot_keep` | `0` | `0` | `14` | 1.0 |
| `zfs_auto_snapshot_label` | `backup` | `backup` | `zsync-<backupserver>` | 1.0 |
| `zfs_auto_snapshot_engine` | `zas` | `internal` | `internal` | 1.0 |
| `zfs_auto_snapshot_label_match` | `legacy` | `strict` | `strict` | 2.0 |
| `monitor_max_age` | leer | leer | leer | 2.0 |
| `trigger` | leer (`cron`) | leer | `systemd` | 2.0 |
| `schedule` | leer | leer | `*/15 * * * *` | 2.0 |
| `run_as` | leer (root) | leer | `zsync-<name>` | 2.0 |
| `log_file` | leer (Journal) | leer | leer | 2.0 |
| `hook_timeout` | `600` | – | – | 2.0 |
| `bandwidth_limit` | leer | leer | leer | 2.0 |
| `source_bookmark` | `0` | `1` | `1` | 2.0 |
| `source_hold` | `0` | `1` | `1` | 2.0 |
| `transfer_resume` | `0` | `1` | `1` | 2.0 |
| `monitor_engine` | leer (`checkzfs`, wenn installiert, sonst `internal`) | `internal` | `internal` | 2.0 |
| `checkzfs_disabled` | `0` | `0` | `0` | 1.0 |
| `checkzfs_local` | `0` | `0` | `0` | 1.0 |
| `checkzfs_prefix` | `zsync` | `zsync` | `zsync` | 1.0 |
| `checkzfs_max_age` | `1500,6000` | ebenso | ebenso | 1.0 |
| `checkzfs_max_snapshot_count` | `150,165` | ebenso | ebenso | 1.0 |
| `checkzfs_spool` | `0` | `0` | `0` | 1.0 |
| `checkzfs_spool_maxage` | `87000` | `87000` | `87000` | 1.0 |

`–`: steht nicht in der Datei, es gilt der Wert ohne Eintrag.

## Quelle und Ziel

### `target`
Dataset auf dem Backupserver, unter dem die Replikate liegen. Ein Dataset `rpool/data` der Quelle landet in
`<target>/rpool/data`. zsync legt das Target beim ersten Lauf an (`canmount=noauto`, `com.sun:auto-snapshot=false`).
Ein Target gehört genau einer Config. Läuft die Config ohne root, braucht das Target `mountpoint=none`.

### `source`
SSH-Adresse der Quelle: `root@pve1`, `zsync-backup1-pve1@192.0.2.10` oder nur ein Hostname.
- Ab 2.0: `local` repliziert Pools desselben Hosts ohne SSH. Die Prüfung je Dataset läuft dann ebenfalls lokal
  (`checkzfs_local` gilt als gesetzt).
- Leer ist ein Fehler: der Lauf endet mit Exit-Code 1 und dem Hinweis auf `source=local`.

### `sshport`
SSH-Port der Quelle.

### `tag`
Name der ZFS-Property, mit der Datasets auf der Quelle ausgewählt werden (`all`, `subvols`), siehe
[Auswahl der Datasets](../01-konzept/04-auswahl-der-datasets.md). Mehrere Backupserver können verschiedene Tags
verwenden, z. B. `bashclub:zsync-offsite`.

## Snapshots

### `snapshot_filter`
Die Labels der Snapshots, die übertragen werden, getrennt durch `|`. Je Label die Regel für den Backupserver:
- `daily` oder `daily=source`: der Quelle folgen (löschen, was die Quelle gelöscht hat, die neuesten `min_keep`
  bleiben)
- `daily=30` (ab 2.0): die 30 neuesten Snapshots des Labels bleiben, egal was die Quelle löscht
- `daily=0` wirkt wie `daily=source`

Ein ungültiger Wert (z. B. `daily=abc`) ergibt eine Warnung; das Label folgt dann der Quelle. Das Label der
Snapshot-Engine kommt automatisch dazu, wenn `zfs_auto_snapshot_keep` größer als 1 ist.

### `min_keep`
Veraltet, wird in einer späteren Version entfernt. Mindestanzahl Snapshots je Label, die beim Folgen der Quelle auf dem
Backupserver bleiben, und zwar die neuesten. Statt dessen eine Zahl in `snapshot_filter` verwenden.

:::info
**Geändert in 2.0:** Bis 1.0.19 blieben die ältesten Snapshots stehen, wenn `min_keep` das Löschen stoppte. Ab 2.0
bleiben die neuesten.
:::

### `zfs_auto_snapshot_keep`
Anzahl der Snapshots, die zsync selbst vor der Übertragung anlegt und auf der Quelle behält. `0` oder `1` schaltet das
ab; dann überträgt zsync nur Snapshots, die es schon gibt.

### `zfs_auto_snapshot_label`
Label der Snapshots, die zsync anlegt. Es darf nicht im Label einer anderen Config auf derselben Quelle enthalten sein.
Läuft die Config ohne root, ist der Schlüssel auf der Quelle an dieses Label gebunden; nach einer Änderung den
Job-Benutzer neu anlegen (siehe [Betrieb ohne root](../02-installation/05-betrieb-ohne-root.md)).

### `zfs_auto_snapshot_engine`
Wer die Snapshots anlegt:
- `internal`: `remote-snapshot-manager` vom Backupserver aus, je Dataset direkt vor dessen Übertragung. Name
  `<label>-JJJJ-MM-TT-hhmm`.
- `zas`: `zfs-auto-snapshot` auf der Quelle, einmal je Lauf für alle Datasets. Name
  `zfs-auto-snap_<label>-JJJJ-MM-TT-hhmm`. Übergeht Datasets mit `com.sun:auto-snapshot=false`. Ab 2.0 warnt zsync,
  wenn `zfs-auto-snapshot` auf der Quelle fehlt.

### `zfs_auto_snapshot_label_match`
Ab 2.0. Welche Snapshots zum Label gehören:
- `strict`: nur das Namensschema der eingestellten Engine
- `legacy`: jeder Snapshot, dessen Name das Label enthält (Verhalten von 1.0)

## Ablauf

### `trigger`
Ab 2.0. Wer die Läufe startet:
- leer oder `cron`: Cron oder von Hand, wie in 1.0
- `systemd`: Timer `bashclub-zsync@<name>.timer` nach `schedule`, als `run_as`
- `autorun`: Wechseldatenträger, `zsync-autorun` startet den Lauf beim Anschließen; kein Timer, keine Altersprüfung
- `external`: ein anderes Werkzeug startet die Läufe (z. B. Miyagi); kein Timer, die Altersprüfung lernt das Intervall

Nach einer Änderung: `bashclub-zsync-timer sync`.

### `schedule`
Ab 2.0, nur mit `trigger=systemd`. Zeitplan im Cron-Format, mehrere getrennt durch `;`, z. B. `"0 23 * * *"`,
`"*/15 6-22 * * 1-5;0 2 * * *"` oder `@daily`. Ohne Eintrag `@daily`.

### `run_as`
Ab 2.0, nur mit `trigger=systemd`. Benutzer, als der der Timer den Lauf startet. Leer: root.
`bashclub-zsync -s` als root läuft für diese Config ebenfalls als dieser Benutzer.

### `log_file`
Ab 2.0, nur mit `trigger=systemd`. Datei, an die die Ausgabe angehängt wird. Leer: Journal
(`journalctl -u bashclub-zsync@<name>`). Liegt die Datei in einem Ordner, den logrotate nicht kennt, rotiert zsync sie
bei 10 MiB selbst.

### `hook_timeout`
Ab 2.0. Höchste Laufzeit eines Hooks in Sekunden, danach wird er beendet.

### `bandwidth_limit`
Ab 2.0. Bandbreite der Übertragung in Bytes pro Sekunde, mit Suffix `k`, `m`, `g`, `t` (Basis 1024), z. B. `10m` =
10 MiB/s, etwa 84 Mbit/s. Wirkt über `pv` auf dem Backupserver; fehlt `pv`, läuft die Übertragung ohne Limit mit
Warnung. Leer: kein Limit.

## Schutz der Kette

### `source_bookmark`
Ab 2.0. `1`: Bookmark auf den neuesten übertragenen Snapshot auf der Quelle,
`<dataset>#zsync_<backupserver>_<target mit _>`. Hat die Quelle den Snapshot gelöscht, geht die Replikation vom
Bookmark aus weiter.

:::warning
**checkzfs und Bookmarks:** Mit `monitor_engine=checkzfs` bricht checkzfs (bis Version 4.14) ab, sobald auf der Quelle
oder dem Backupserver ein Bookmark existiert (`'NoneType' object has no attribute 'add_snapshot'`). Dann fehlen alle
Services je Dataset; der Service der Config meldet weiter. Ab 2.0 prüft zsync die Snapshots auch selbst
(`monitor_engine=internal`, Default neuer Configs), dort gibt es das Problem nicht. Bestehende Configs mit checkzfs:
`monitor_engine=internal` setzen, oder `source_bookmark=0` lassen.
:::

### `source_hold`
Ab 2.0. `1`: Hold auf die Basis und alle noch zu sendenden Snapshots eines Datasets, solange es übertragen wird. Tag
wie der Bookmark. Holds eines abgebrochenen Laufs löst der nächste Lauf.

### `transfer_resume`
Ab 2.0. `1`: Übertragungen sind fortsetzbar (`zfs receive -s`). Ein abgebrochener Transfer setzt im nächsten Lauf
fort. Mit `0` verwirft zsync einen angefangenen Empfang (`zfs receive -A`) mit Warnung.

## Monitoring

### `monitor_max_age`
Ab 2.0. Höchstalter des letzten erfolgreichen Laufs für den Checkmk-Service der Config, z. B. `26h`, `90m`, `2d` oder
Sekunden. WARN darüber, CRIT beim Dreifachen. Leer: aus den letzten Läufen gelernt (oder aus dem Timer). `0`: keine
Altersprüfung. Ein ungültiger Wert wird mit Hinweis im Service ignoriert.

### `monitor_engine`
Ab 2.0. Wer die Services je Dataset (`<checkzfs_prefix>:<source>:<port>#<dataset>`) erzeugt:
- `internal`: zsync selbst, aus einer Liste der Snapshots von Quelle und Backupserver am Ende des Laufs. Eine Zeile je
  Dataset mit dem schlechteren Zustand von Quelle und Replikat; Bookmarks stören nicht.
- `checkzfs`: das Programm checkzfs (Paket `bashclub-checkzfs`), wie bis 1.0.19. Ist es nicht installiert, nimmt zsync
  `internal` und warnt.
- leer: `checkzfs`, wenn installiert, sonst `internal`.

Beide nutzen dieselben Namen und Schwellwerte (`checkzfs_*`), ein Wechsel braucht keine neue Service-Erkennung. Siehe
[Neue Funktionen einschalten](../02-installation/07-neue-funktionen-einschalten.md).

### `checkzfs_disabled`
Größer als `0` schaltet die Services je Dataset ab, mit beiden Engines. Der Service der Config bleibt (abschalten:
`touch /etc/bashclub/zsync-checkmk.disabled`).

### `checkzfs_local`
`1`: Die Services je Dataset heißen ohne Quelle (`<checkzfs_prefix>:<dataset>`), checkzfs fragt die Quelle nicht
(`--source` entfällt), und die Spool-Datei bleibt auf dem Backupserver, auch mit `checkzfs_spool=1`. Mit
`source=local` automatisch gesetzt.

### `checkzfs_prefix`
Präfix der Services je Dataset. Ab 2.0 auch der Name der Spool-Datei (`<checkzfs_spool_maxage>_<checkzfs_prefix>`) und
des Services der Config (`<checkzfs_prefix> <config>`). **Jede Replikation braucht ein eigenes Präfix**, z. B.
`zsync-<config>`: Mit demselben Präfix überschreiben sich Configs, die in denselben Spool schreiben, gegenseitig die
Datei, und ihre Services kollidieren in Checkmk. Das Setup setzt es nicht.

### `checkzfs_max_age`
Alter des neuesten gemeinsamen Snapshots je Dataset in Minuten, `warn,crit`.

### `checkzfs_max_snapshot_count`
Anzahl der Snapshots je Dataset, `warn,crit`.

### `checkzfs_spool`
Wohin die Spool-Datei geht: `0` Backupserver, `1` Quelle.

### `checkzfs_spool_maxage`
Höchstalter der Spool-Datei in Sekunden, Teil ihres Namens. Der Checkmk-Agent liefert sie nur bis zu diesem Alter aus;
danach meldet Checkmk die Services als fehlend. Etwa: stündliche Läufe `3900`, tägliche `87000`.
