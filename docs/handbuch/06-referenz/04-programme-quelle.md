---
title: Programme auf der Quelle
audience: Admin
outline:
---
Ab 2.0, Paket `bashclub-zsync-source`. Ohne das Paket meldet sich der Backupserver als root an der Quelle an, wie in
1.0. Warum die Programme so gebaut sind, steht im [Sicherheitsmodell](../01-konzept/06-sicherheitsmodell.md).

## `bashclub-zsync-remote`
Erzwungener Befehl (`command=`) im Schlüssel eines Job-Benutzers in `authorized_keys`:
```
restrict,from="192.0.2.20",command="/usr/bin/bashclub-zsync-remote --label zsync-backup1 --job-tag zsync_backup1_backup_pve1" ssh-ed25519 AAAA...
```
Es führt nur die Befehle aus, die bashclub-zsync, `remote-snapshot-manager` und checkzfs an die Quelle schicken, und
zwar ohne Shell:
- `zfs list`, `zfs get` und `zfs send` der Datasets
- `zfs snapshot`, `zfs destroy`, `zfs hold`, `zfs release`, `zfs bookmark` nur für Snapshots und Bookmarks, nie für
  Datasets
- `zfs-auto-snapshot` mit dem Label des Jobs (Engine `zas`)
- Schreiben und Löschen der Spool-Datei im Checkmk-Spool
- einige feste Abfragen (Betriebssystem, AES-Unterstützung der CPU)

| Option | Wirkung |
|---|---|
| `--label <label>` | nur Snapshots dieses Labels anlegen und löschen: `<label>-JJJJ-MM-TT-hhmm` (`internal`) oder `zfs-auto-snap_<label>-…` (`zas`) |
| `--job-tag <tag>` | nur dieser Hold-Tag und dieser Bookmark (`zsync_<backupserver>_<target mit _>`) |

Ohne diese Optionen sind alle Snapshots, Holds und Bookmarks der erlaubten Datasets erlaubt (Schlüssel aus Testversionen
vor 2.0). `bashclub-zsync-job-user add` und `bashclub-zsync-setup` setzen beide Optionen.

Abgelehnte Befehle enden mit Exit-Code 126 und stehen im Syslog:
```bash
journalctl -t bashclub-zsync-remote
```

Zum Testen ohne SSH, als root auf der Quelle:
```bash
SSH_ORIGINAL_COMMAND='zfs list -H -o name' bashclub-zsync-remote
```

## `bashclub-zsync-job-user`
Legt die Benutzer der Replikationen auf der Quelle an. Läuft als root oder per sudo als Verwaltungsbenutzer `zsync`.

```
bashclub-zsync-job-user add [--label <label>] [--job-tag <tag>] <job> <from> <ssh-ed25519 public key>
bashclub-zsync-job-user allow <job> <tag>
bashclub-zsync-job-user remove <job>
bashclub-zsync-job-user list
```

| Befehl | Wirkung |
|---|---|
| `add` | legt `zsync-<job>` an oder aktualisiert ihn. Sein Schlüssel gilt nur von `<from>` (Adressen oder Netze, mit Komma getrennt, wie `from=` in `authorized_keys`) und nur für `bashclub-zsync-remote` mit `--label` und `--job-tag`. Die Datei `authorized_keys` gehört root. |
| `allow` | ZFS-Rechte für `zsync-<job>` auf die Datasets, an denen das Tag lokal gesetzt ist; von allen anderen entfernt. Nach dem Auswählen weiterer Datasets erneut ausführen. |
| `remove` | entfernt Rechte und Benutzer |
| `list` | Job-Benutzer mit Adresse und Datasets |

Nur `ssh-ed25519`-Schlüssel werden angenommen. Die Rechte sind `send,snapshot,destroy,mount,hold,release,bookmark`;
`destroy` greift durch `bashclub-zsync-remote` nur für Snapshots und Bookmarks des Jobs.

## Verwaltungsbenutzer `zsync`
Das Paket legt den Benutzer `zsync` an (Home `/var/lib/zsync`), falls es ihn noch nicht gibt. Er hat kein Passwort,
meldet sich nur mit einem Schlüssel in `/var/lib/zsync/.ssh/authorized_keys` an und darf per sudo nur
`/usr/sbin/bashclub-zsync-job-user` ausführen (`/etc/sudoers.d/bashclub-zsync-source`). So kann
`bashclub-zsync-setup` die Quelle ohne root einrichten.

Die Gruppe `bashclub-zsync` enthält die Job-Benutzer, z. B. für den Checkmk-Spool auf der Quelle:
```bash
install -d -m 3775 -g bashclub-zsync /var/lib/check_mk_agent/spool
```
