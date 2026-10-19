---
title: Dateien und Pfade
audience: Admin
outline: https://docs.bashclub.org/doc/dateien-und-pfade-4gGcPbjeil
outline_id: 7df552c3-633f-489d-a7e3-2ba2708316e7
---
## Backupserver: Konfiguration
| Pfad | Inhalt |
|---|---|
| `/etc/bashclub/<name>.conf` | Configs; nur root darf sie schreiben (der Ordner gehört root, `go-w`) |
| `/etc/bashclub/zsync.conf.example` | Vorlage mit allen Parametern; das Paket ersetzt sie bei jedem Update |
| `/etc/bashclub/zsync.conf.backup_<datum>` | Sicherung von `zsync.conf` bei jedem Update des Pakets |
| `/etc/bashclub/hooks.d/{pre-run,post-run}/` | ab 2.0: Hooks für alle Configs |
| `/etc/bashclub/hooks.d/<config>/{pre-run,post-run}/` | ab 2.0: Hooks für eine Config |
| `/etc/bashclub/zsync-checkmk.conf` | ab 2.0: Schwellwerte des Checkmk-Services (siehe [Checkmk-Services](09-checkmk.md)) |
| `/etc/bashclub/zsync-checkmk.disabled` | ab 2.0: gibt es die Datei, entfällt der Service der Config |
| `/etc/bashclub/<label>.key` | Schlüsseldatei eines LUKS-Wechseldatenträgers |
| `/etc/default/zsync-autorun@<label>` | Config eines Wechseldatenträgers (Link auf die Config) |
| `/etc/udev/rules.d/90-zsync-autorun-<label>.rules` | ab 2.0: startet `zsync-autorun@<label>` beim Anschließen dieser Platte |
| `/etc/udev/rules.d/90-automount-zsync.rules.example` | Vorlage einer udev-Regel von Hand |

## Backupserver: Zustand und Logs
Der Name der Config wird zur ID, indem `/` zu `_` wird: `/etc/bashclub/pve1.conf` → `_etc_bashclub_pve1.conf`.
Ab 2.0 hat jeder Benutzer, der zsync laufen lässt, einen eigenen Ordner (`root` oder z. B. `zsync-pve1`).

| Pfad | Inhalt |
|---|---|
| `/run/bashclub-zsync/<benutzer>/<id>.state` | während eines Laufs: Prozess, Phase, Dataset |
| `/var/lib/bashclub-zsync/<benutzer>/<id>.last` | Ergebnis des letzten und des letzten erfolgreichen Laufs |
| `…/<id>.history` | Startzeiten der letzten Läufe (für das gelernte Intervall) |
| `…/<id>.skipped` | Zeiten übersprungener Läufe |
| `…/<id>.datasets` | Zustand je Dataset aus dem letzten Lauf |
| `…/<id>.checkzfs` | letzte Ausgabe von checkzfs (der Watchdog schreibt sie während des Laufs mit) |
| `…/<id>.resume` | Datasets mit unterbrochener Übertragung |
| `…/<id>.check` | Zustand des Checkmk-Checks (Fortschritt, blockierte Prozesse), im Ordner des Benutzers, der den Check ausführt |
| `/var/log/bashclub-zsync/` | Logs von Cron-Jobs, `maintenance.log`, `zsync-autorun_<label>.log`; logrotate wöchentlich, 12 Stück |
| `/var/lib/bashclub-zsync-jobs/<job>/` | ab 2.0: Home der Job-Benutzer mit ihrem SSH-Schlüssel |

Die Basisordner `/run/bashclub-zsync` und `/var/lib/bashclub-zsync` gehören root und der Gruppe `bashclub-zsync`
(`1775`): Mitglieder legen ihren eigenen Ordner an, niemand ändert den eines anderen.

## Backupserver: Programme und Units
| Pfad | Inhalt |
|---|---|
| `/usr/bin/bashclub-zsync`, `remote-snapshot-manager`, `zsync-autorun` | seit 1.0 |
| `/usr/bin/bashclub-zsync-setup`, `-timer`, `-disk`, `-maintenance` | ab 2.0 |
| `/usr/lib/bashclub-zsync/schedule.sh` | gemeinsame Funktionen für Zeitpläne |
| `/usr/lib/systemd/system/bashclub-zsync@.service`, `bashclub-zsync@.timer` | ab 2.0: Dienst und Timer je Config |
| `/usr/lib/systemd/system-generators/bashclub-zsync-generator` | ab 2.0: erzeugt die Timer aus den Configs |
| `/etc/systemd/system/zsync-autorun@.service` | Dienst für Wechseldatenträger |
| `/usr/lib/tmpfiles.d/bashclub-zsync.conf` | legt `/run/bashclub-zsync` beim Booten an |
| `/usr/share/bashclub-zsync/checkmk/bashclub_zsync` | ab 2.0: der Check des Services der Config |
| `/usr/share/doc/bashclub-zsync/copyright` | Lizenz |

## Checkmk-Spool
`/var/lib/check_mk_agent/spool/<checkzfs_spool_maxage>_<checkzfs_prefix>`, z. B. `87000_zsync`, auf dem Backupserver
oder (mit `checkzfs_spool=1`) auf der Quelle. Läuft die Config ohne root, braucht der Ordner die Gruppe
`bashclub-zsync` und die Rechte `3775`, und die Datei muss dem Benutzer gehören.

## Quelle
| Pfad | Inhalt |
|---|---|
| `/usr/bin/bashclub-zsync-remote` | ab 2.0: erzwungener Befehl der Job-Benutzer |
| `/usr/sbin/bashclub-zsync-job-user` | ab 2.0: legt Job-Benutzer an |
| `/etc/sudoers.d/bashclub-zsync-source` | ab 2.0: `zsync` darf nur `bashclub-zsync-job-user` |
| `/var/lib/zsync/` | Home des Verwaltungsbenutzers `zsync` |
| `/var/lib/bashclub-zsync-source/` | Homes der Job-Benutzer |

## Restore
Siehe [bashclub-zsync-restore](05-bashclub-zsync-restore.md#dateien).
