---
title: Werkzeuge auf dem Backupserver
audience: Admin
outline: https://docs.bashclub.org/doc/werkzeuge-auf-dem-backupserver-LFmM5DHoVU
outline_id: 66243eb9-7381-492f-8978-b5e13a1a943a
---
Alle Werkzeuge laufen als root. Ein Aufruf mit falschen Optionen zeigt die Hilfe und endet mit Exit-Code 2, ein
Fehler mit Exit-Code 1.

## `bashclub-zsync-setup`
Ab 2.0. Richtet eine neue Replikation ein: Config, Benutzer auf beiden Seiten, Timer. Fragt jeden Wert, der nicht als
Option kommt; der Vorschlag steht in Klammern. Eine bestehende Config überschreibt es nie.

```
bashclub-zsync-setup [options] <name>
```

| Option | Wirkung | Vorschlag |
|---|---|---|
| `<name>` | Config `/etc/bashclub/<name>.conf`, Timer `bashclub-zsync@<name>`; Buchstaben, Ziffern, `_ . -` | – |
| `-s`, `--source <host>` | Quelle (Name oder Adresse), `local` für Pools dieses Hosts | – |
| `-p`, `--port <port>` | SSH-Port der Quelle | `22` |
| `-t`, `--target <dataset>` | Target auf diesem Host | `<erster Pool>/zsync/<name>` |
| `--tag <property>` | Tag der Datasets auf der Quelle | `bashclub:zsync` |
| `--tag-datasets "<ds> …"` | setzt das Tag (`all`) auf diese Datasets der Quelle; nur mit Anmeldung als root | – |
| `--schedule "<cron>"` | Zeitplan | `*/15 * * * *` |
| `--keep <n>` | Snapshots je Label auf der Quelle (Engine `internal`) | `14` |
| `--label <label>` | Label der Snapshots von zsync | `zsync-<dieser Host>` |
| `--filter "<labels>"` | Labels und wie viele davon hier bleiben | `hourly=24\|daily=30\|weekly=8\|monthly=12\|<label>=<keep>` |
| `--login auto\|zsync\|root` | Anmeldung an der Quelle für die Einrichtung (`auto`: erst `zsync`, dann root) | `auto` |
| `--root` | ohne Job-Benutzer, als root wie vor 2.0 | – |
| `--autorun` | Config für einen Wechseldatenträger (`trigger=autorun`, kein Timer, läuft als root) | – |
| `--external` | ein anderes Werkzeug startet die Läufe (`trigger=external`, kein Timer); zeigt den Befehl dafür | – |
| `--run` | ersten Lauf sofort starten | – |
| `-y`, `--yes` | keine Fragen, Vorschläge für alles nicht Angegebene | – |

Ablauf: Werte prüfen, Zusammenfassung zeigen und bestätigen lassen, Anmeldung an der Quelle prüfen (installiert dort
`bashclub-zsync-source`, wenn es sich als root anmelden darf), Config schreiben, Target anlegen (`mountpoint=none`),
Job-Benutzer `zsync-<name>` mit Schlüssel und `zfs allow` anlegen, Job-Benutzer auf der Quelle anlegen,
Verbindungstest mit Liste der ausgewählten Datasets, Timer aktivieren.

Mit `--source local` läuft die Replikation als root, ohne Job-Benutzer.

## `bashclub-zsync-timer`
Ab 2.0. Verwaltet die systemd-Timer der Configs.

```
bashclub-zsync-timer list
bashclub-zsync-timer enable <name> [<schedule>] [--user <user>] [--log <file>]
bashclub-zsync-timer disable <name>
bashclub-zsync-timer sync [--dry-run]
bashclub-zsync-timer migrate [--dry-run] [<name>]
```

| Befehl | Wirkung |
|---|---|
| `list` | alle Configs mit Auslöser, Zeitplan, Benutzer, Zustand des Timers, Cron-Jobs und Wechseldatenträgern |
| `enable` | schreibt `trigger=systemd` und die angegebenen Werte in die Config, dann `sync`. Ohne Zeitplan bleibt der der Config, sonst `@daily` |
| `disable` | schreibt `trigger=cron` in die Config, dann `sync` (der Timer stoppt) |
| `sync` | liest alle Configs und startet, ändert oder stoppt ihre Timer |
| `migrate` | übernimmt Cron-Jobs, die `bashclub-zsync -c /etc/bashclub/<name>.conf` aufrufen, ohne `-c` die Config `zsync.conf` (auch in `/etc/cron.{hourly,daily,weekly,monthly}`): Zeitplan, Benutzer und Logdatei in die Config, Cron-Zeile auskommentiert, dann `sync` |

Die Timer erzeugt der systemd-Generator `bashclub-zsync-generator` beim Booten und bei `systemctl daemon-reload` aus
den Configs mit `trigger=systemd`. Ein Timer startet einen verpassten Lauf nach dem Booten nach (`Persistent=true`) und
nie einen zweiten, solange einer läuft.

## `bashclub-zsync-disk`
Ab 2.0. Bereitet einen Wechseldatenträger vor.

```
bashclub-zsync-disk list
bashclub-zsync-disk create <disk> <label> [--luks] [--passphrase] [--config <name>] [--yes --serial <serial>]
```

| Option | Wirkung |
|---|---|
| `list` | Platten, die sich eignen: nicht eingehängt, in keinem Pool, ohne LVM, RAID oder LUKS |
| `<disk>` | ganze Platte, z. B. `/dev/disk/by-id/usb-…` (siehe `list`) |
| `<label>` | Name des Pools (und des LUKS-Volumes), z. B. `usb-backup1` |
| `--luks` | LUKS2 mit Schlüsseldatei `/etc/bashclub/<label>.key` (eine Kopie außerhalb des Hosts aufbewahren) |
| `--passphrase` | zusätzlich eine Passphrase als zweiter Schlüssel, z. B. ein YubiKey mit statischem Passwort |
| `--config <name>` | Config der Platte: wird als `/etc/default/zsync-autorun@<label>` verlinkt und auf `trigger=autorun` gesetzt; ihr Target muss im Pool `<label>` liegen |
| `--yes --serial <serial>` | ohne Fragen; die Seriennummer muss zur Platte passen |

Ohne `--yes` muss die Seriennummer der Platte eingetippt werden. Die udev-Regel
`/etc/udev/rules.d/90-zsync-autorun-<label>.rules` erkennt nur diese Platte (UUID).

## `zsync-autorun`
Läuft beim Anschließen eines vorbereiteten Wechseldatenträgers (systemd-Dienst `zsync-autorun@<label>`, gestartet von
der udev-Regel) mit der Config `/etc/default/zsync-autorun@<label>`:
1. Mail an root: Replikation startet
2. LUKS öffnen (Schlüsseldatei `/etc/bashclub/<label>.key`), Pool importieren
3. `bashclub-zsync -d` mit der Config, Log in `/var/log/bashclub-zsync/zsync-autorun_<label>.log`
4. freitags bis sonntags ein Scrub des Pools
5. Pool exportieren, LUKS schließen, Platte abschalten
6. Mail an root mit dem Ergebnis und `zpool status`

## `bashclub-zsync-maintenance`
Ab 2.0. Entscheidungen auf dem Backupserver, siehe [Sicherheitsmodell](../01-konzept/06-sicherheitsmodell.md).

```
bashclub-zsync-maintenance
bashclub-zsync-maintenance --list [--tsv]
bashclub-zsync-maintenance --decide <case> <option> [--dry-run]
bashclub-zsync-maintenance --decide-type <type> <option> [--dry-run]
```
- Ohne Optionen: Übersicht aller offenen Fälle, dann „alle später“, je Fall-Typ (mit Vorschau der ganzen Gruppe) oder
  einzeln (Kontext, Optionen, Vorschau).
- `--list`: offene Fälle; `--tsv` eine Zeile je Fall mit ID, Config, Typ, Dataset, seit, Detail, belegtem Platz.
- `--decide`, `--decide-type`: ohne Fragen; `--dry-run` zeigt nur die Befehle.

| Typ | Fall | Optionen |
|---|---|---|
| `orphan` | Replikat ohne Dataset auf der Quelle oder nicht mehr ausgewählt | `keep` (`bashclub:zsync-orphan=keep`), `delete`, `later` |
| `broken` | kein gemeinsamer Snapshot mit der Quelle, oder Replikat ohne Snapshots | `rename` (das alte bleibt, der nächste Lauf überträgt neu), `delete`, `later` |
| `leftovers` | Snapshots des Labels in fremdem Namensschema auf dem Replikat | `delete`, `later` |
| `branch` | alte Kette nach einem Rollback oder einer gerissenen Kette (`<replikat>.zsync-branch-<datum>`) | `keep`, `delete`, `later` |

Jede Aktion läuft unter der Sperre ihrer Config, nie während eines Laufs, und steht mit Zeit und Benutzer in
`/var/log/bashclub-zsync/maintenance.log` und im Syslog. Fälle aus Läufen vor 2.0 erscheinen nach dem nächsten Lauf
der Config.
