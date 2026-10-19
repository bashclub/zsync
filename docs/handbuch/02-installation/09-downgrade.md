---
title: Downgrade auf 1.0
audience: Admin
outline: https://docs.bashclub.org/doc/downgrade-auf-10-QO6QO9qRzO
outline_id: b261119a-a2e9-476f-b0ee-a369512f595b
---
Ein Downgrade ist nicht vorgesehen, aber möglich: Die Paketquelle `release` behält die Versionen 1.0.18 und 1.0.19.
Die Replikate und ihre Snapshots bleiben dabei unverändert; 1.0.19 repliziert weiter, ab dem neuesten gemeinsamen
Snapshot.

## Was 1.0.19 nicht versteht
Configs, die nur Parameter aus 1.0 verwenden oder die neuen Parameter nur mit ihren Defaults, laufen mit 1.0.19
unverändert. Diese Werte muss der Admin vorher zurückbauen:

| Wert aus 2.0 | Folge mit 1.0.19 | Zurückbauen |
|---|---|---|
| Zahlen in `snapshot_filter` (`daily=30`) | kein Snapshot passt mehr, es wird nichts übertragen | Labels ohne Zahl |
| `trigger=systemd` | das Paket entfernt die Timer, die Config läuft nicht mehr | Cron-Job |
| Job-Benutzer (`source=zsync-…@`, `run_as`) | `bashclub-zsync-remote` auf der Quelle lehnt die Befehle von 1.0 ab | `source=root@…`, ohne `run_as` |
| `source=local` | 1.0 hält `local` für einen Hostnamen | nicht möglich, die Config bleibt auf 2.0 angewiesen |

Alles andere ignoriert 1.0.19: Bookmarks, Holds, Resume, Label-Abgleich, Hooks. `zfs_auto_snapshot_engine=internal`
kennt auch 1.0.19.

## Durchführung
1. Je Config die Werte zurückbauen. Der Block nimmt eine Config (erste Zeile), entfernt die Zahlen aus
   `snapshot_filter`, stellt auf root um und stoppt den Timer:
```bash
name=zsync
conf=/etc/bashclub/$name.conf
. "$conf"
sed -i -E '/^snapshot_filter=/s/=(source|[0-9]+)([|"'"'"']|$)/\2/g' "$conf"
sed -i "s|^source=zsync-[^@]*@|source=root@|" "$conf"
sed -i '/^run_as=/d' "$conf"
if [[ $trigger == systemd ]]; then bashclub-zsync-timer disable "$name"; fi
grep -E '^(source|snapshot_filter|trigger)=' "$conf"
```
   Root muss sich auf der Quelle anmelden dürfen (der Schlüssel von root des Backupservers in
   `/root/.ssh/authorized_keys` der Quelle), sonst wie in [Installation](01-installation.md) mit `ssh-copy-id`.

2. Je Config einen Cron-Job anlegen. Wurde die Config aus Cron auf den Timer umgestellt, die alte Zeile wieder
   einschalten, siehe [Cron auf systemd-Timer](04-cron-auf-timer.md), Abschnitt Rückweg. Sonst einen neuen Job, hier
   täglich um 23 Uhr:
```bash
echo "0 23 * * * root /usr/bin/bashclub-zsync -c $conf >> /var/log/bashclub-zsync/$name.log" > "/etc/cron.d/bashclub-zsync-$name"
```

3. Das Paket auf 1.0.19 zurücksetzen:
```bash
apt update && apt install -y --allow-downgrades bashclub-zsync=1.0.19
```
   `bashclub-zsync-restore` und auf der Quelle `bashclub-zsync-source` können bleiben; sie stören 1.0.19 nicht.

4. Einen Lauf starten und das Log prüfen:
```bash
bashclub-zsync -c "$conf"
```

## Danach
- In Checkmk fehlt der Service der Config (`zsync <config>`); bei der nächsten Service-Erkennung entfernen. Die
  Services von checkzfs bleiben.
- Was 2.0 angelegt hat, bleibt liegen: alte Ketten nach einem Rollback (`*.zsync-branch-*`), Bookmarks auf der Quelle,
  die Markierungen `bashclub:zsync-*` an den Replikaten, die Ordner unter `/var/lib/bashclub-zsync`. 1.0.19 beachtet
  sie nicht.
- Die Lizenz von 1.0.19 ist MIT, ab 2.0 GPL-3.0-or-later.
