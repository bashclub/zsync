---
title: bashclub-zsync-restore
audience: Admin
outline: https://docs.bashclub.org/doc/bashclub-zsync-restore-BRl8mQarwX
outline_id: 09ac581e-94b0-453c-9be1-388d9a24326e
---
Ab 2.0, Paket `bashclub-zsync-restore`. Stellt Replikate wieder her. Anleitungen dazu stehen im Bereich Restore und
Notfall; hier nur die Befehle.

## `bashclub-zsync-restore`
```
bashclub-zsync-restore
bashclub-zsync-restore <befehl> [--from <user>@<backupserver>[:<port>] | --to <system>[:<port>]] [--config <name> | --root <dataset>] …
```
Ohne Befehl fragt es Schritt für Schritt (Weg, Config, was, Dataset, Snapshot, Name) und zeigt am Ende den
vollständigen Befehl, bevor es ihn ausführt.

### Verbindung
| Option | Weg | wo aufrufen |
|---|---|---|
| `--from zsync-restore-<config>@<backupserver>` | Pull: das System liest vom Backupserver | auf dem System, das wiederhergestellt wird |
| `--to <system>` | Push: der Backupserver schreibt auf `root@<system>` mit dem Push-Schlüssel | auf dem Backupserver |
| keine | beides auf diesem Host, z. B. in einen anderen Pool | auf dem Backupserver |
| `--config <name>` | Replikate dieser Config; erlaubt Namen wie auf der Quelle | – |
| `--root <dataset>` | ab 2.0: Replikate unter diesem Dataset, ohne Config, z. B. auf einem Wechseldatenträger an einem anderen Host; nicht mit `--from` | – |

Ein Replikat heißt mit seinem vollen Namen auf dem Backupserver, mit `--config` oder `--root` auch mit seinem Namen auf
der Quelle. Auf einem nur lesend importierten Pool setzt der Restore keine Holds und nennt das im Log; siehe
[Restore vom Wechseldatenträger](../05-restore/03-wechseldatentraeger.md).

### Ansehen
| Befehl | Wirkung |
|---|---|
| `list` | Replikate mit Snapshots, neuestem Snapshot, Verschlüsselung und ihrem Zustand auf dem System |
| `show <replikat>` | Kette im Vergleich mit dem System per GUID (`=` beide, `+` fehlt auf dem System, `!` nur auf dem System) und der passende Befehl |

### Wiederherstellen
| Befehl | Wirkung |
|---|---|
| `dataset <replikat>` | stellt das Dataset mit der ganzen Kette wieder her, mit den Originalwerten der Quelle |
| `reattach <replikat>` | sendet nur die Snapshots nach dem gemeinsamen, die auf dem System fehlen; die Replikation geht danach ohne Erstreplikation weiter |
| `server` | alle Replikate einer Config, Eltern zuerst; am Ende eine Liste, was danach zu prüfen ist |

| Option | bei | Wirkung |
|---|---|---|
| `--recursive` | `dataset`, `reattach` | mit allen Kindern |
| `--snapshot <name>` | alle | bis zu diesem Snapshot statt bis zum neuesten; bei `server` ein Zeitpunkt für alle (je Dataset dieser oder der neueste nicht neuere) |
| `--as <dataset>` | `dataset` | unter anderem Namen; Mountpoint und Tag werden dann nicht gesetzt |
| `--force` | `dataset`, `server` | ein vorhandenes Dataset wird in `<dataset>.before-restore-<zeit>` umbenannt; ohne `--force` bricht der Plan ab, nie wird etwas überschrieben |
| `--rollback` | `reattach` | Snapshots und Änderungen auf dem System nach dem gemeinsamen Snapshot werden verworfen (der Plan listet sie) |
| `--pool <pool>` | `server` | nur diese Pools, mehrfach möglich |
| `--map <von>=<nach>` | `server` | unter anderem Namen, das längste `<von>` gewinnt, z. B. `--map rpool/data=tank/vm` |
| `--exclude <dataset>` | `server` | ohne dieses Dataset und seine Kinder (Name auf der Quelle, z. B. `rpool/ROOT`) |
| `--bwlimit <rate>` | alle | Bandbreite, z. B. `50m` (braucht `pv`) |
| `--scrub` | alle | Scrub der Pools nach dem Restore |
| `--dry-run` | alle | zeigt Plan und Befehle, ändert nichts |
| `--start` | alle | startet den Job ohne Rückfrage |

Verschlüsselte Datasets werden raw übertragen; den Schlüssel danach laden (der Bericht nennt den Befehl). Pool-Wurzeln
werden nie ersetzt; ein Pool, der auf dem System fehlt, stoppt den Plan.

### Jobs
Jeder Restore ist ein Job, der im Hintergrund läuft (systemd-Dienst `bashclub-zsync-restore@<job>`, ohne systemd mit
`setsid`).

| Befehl | Wirkung |
|---|---|
| `jobs` | alle Jobs |
| `status [<job>] [--follow]` | Fortschritt (Bytes, Rate, Restzeit) und Bericht; `--follow` zeichnet neu bis zum Ende, Strg-C beendet nur die Anzeige |
| `start <job>` | Job im Hintergrund starten |
| `stop <job>` | Job anhalten |
| `resume <job>` | Job fortsetzen: plant neu vom Stand des Systems, setzt Übertragungen per Resume-Token fort, überspringt fertige Datasets |
| `run <job>` | Job im Vordergrund (von `start` benutzt) |

Fehlgeschlagene Übertragungen werden dreimal wiederholt (nach 30, 60, 120 Sekunden). Während des Jobs halten Holds die
gesendeten Snapshots. Am Ende prüft der Job jedes Dataset (GUIDs, neuester Snapshot, kein angefangener Empfang,
`logicalreferenced`, Properties, Schlüsselstatus) und schreibt einen Bericht mit OK, WARN oder ERROR. Exit-Code 0 nur,
wenn alles OK ist. Bei `logicalreferenced` gilt eine Abweichung bis 1 % oder 1 MiB als OK mit Hinweis: Die Metadaten
wachsen mit dem `ashift` des Pools, z. B. von einer USB-Platte mit ashift 14 auf ein System mit 12.

### Einzelne Dateien
Auf dem Backupserver.

| Befehl | Wirkung |
|---|---|
| `mount <replikat>@<snapshot>` | schreibgeschützter Klon in `<pool>/zsync-restore-clones`, eingehängt unter `/run/bashclub-zsync-restore/mnt/<klon>`; bei einem Volume seine Partitionen (ohne Journal-Replay) |
| `mounts` | die Klone und die direkt eingehängten Snapshots |
| `cleanup <klon>` oder `cleanup --all` | aushängen und löschen, nur Klone von `mount` |

Auf einem nur lesend importierten Pool ist kein Klon möglich: `mount` hängt bei einem Dateisystem den Snapshot direkt
ein (`mount -t zfs -o ro`), ein Volume lehnt es ab und nennt den Weg über `dataset --as` in einen beschreibbaren Pool.

Solange ein Klon existiert, behält die Rotation seinen Snapshot.

### Zugang
| Befehl | wo | Wirkung |
|---|---|---|
| `access key [<backupserver>]` | System | Schlüssel dieses Hosts für Pull (wird angelegt), zeigt den Befehl für den Backupserver |
| `access pull [--config <name>] [--name <name>] <from> '<schlüssel>'` | Backupserver | Restore-Benutzer `zsync-restore-<name>`: darf von `<from>` nur die Replikate der Config lesen (`send`, `hold`, `release`) |
| `access push [--days <n>] [--from <adresse>] <host>` | Backupserver | Einmal-Schlüssel für einen Restore nach `root@<host>`, gültig `<n>` Tage (3); zeigt die Zeile für `/root/.ssh/authorized_keys` dort (`restrict`, `from=`, `expiry-time`, OpenSSH 8.2 oder neuer) |
| `access list` | Backupserver | Restore-Benutzer und Push-Schlüssel |
| `access remove <benutzer\|push-schlüssel>` | Backupserver | entfernt sie, bei Push mit dem Befehl für das System |
| `access test <user>@<host>[:<port>]` | beide | Verbindungstest |

### Dateien
- Jobs, Logs und Berichte: `/var/lib/bashclub-zsync-restore/jobs/`, Log auch im Journal
  (`journalctl -u bashclub-zsync-restore@<job>`)
- Push-Schlüssel: `/var/lib/bashclub-zsync-restore/keys/`
- Zustand laufender Jobs: `/run/bashclub-zsync-restore/`, bei Push auch `/run/bashclub-zsync-restore.state` auf dem
  System
- Homes der Restore-Benutzer: `/var/lib/bashclub-zsync-restore-users/`

## `bashclub-zsync-restore-remote`
Erzwungener Befehl (`command=`) des Restore-Benutzers auf dem Backupserver, von `access pull` eingetragen. Erlaubt nur
`zfs list`, `zfs get` und `zfs send` unterhalb des Targets der Config und Holds mit einem Restore-Tag, ohne Shell.
Abgelehnte Befehle enden mit Exit-Code 126 und stehen im Syslog: `journalctl -t bashclub-zsync-restore-remote`.
