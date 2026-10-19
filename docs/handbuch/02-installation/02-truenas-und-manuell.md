---
title: TrueNAS SCALE und manuelle Installation
audience: Admin
outline: https://docs.bashclub.org/doc/truenas-scale-und-manuelle-installation-wTJxn9uta9
outline_id: 9adbf129-5c86-474d-a6b4-6f09b1d400dc
---
## TrueNAS SCALE als Backupserver
TrueNAS erlaubt keine Pakete, und ein Update ersetzt die Systemdateien. Die Skripte liegen deshalb auf einem
Datenpool unter `scripts/bashclub-zsync`. Der Block nimmt den ersten Datenpool und die neueste veröffentlichte Version;
für einen anderen Pool vorher z. B. `pool=tank` setzen.
```bash
pool=${pool:-$(zpool list -H -o name | grep -vx boot-pool | head -n1)}
ref=$(curl -fsS 'https://code.bashclub.org/api/v1/repos/bashclub/zsync/tags?limit=50' | grep -o '"name":"v[0-9][^"]*"' | cut -d'"' -f4 | sort -V | tail -n1)
dir=$(zfs get -H -o value mountpoint "$pool")/scripts/bashclub-zsync
mkdir -p "$dir" && cd "$dir"
curl -fsSL -o bashclub-zsync "https://code.bashclub.org/bashclub/zsync/raw/tag/$ref/bashclub-zsync/usr/bin/bashclub-zsync"
curl -fsSL -o remote-snapshot-manager "https://code.bashclub.org/bashclub/zsync/raw/tag/$ref/bashclub-zsync/usr/bin/remote-snapshot-manager"
curl -fsSL -o checkzfs https://code.bashclub.org/bashclub/checkzfs/raw/branch/main/bashclub-checkzfs/usr/bin/checkzfs
chmod +x bashclub-zsync remote-snapshot-manager checkzfs
echo "$ref"
```
Die letzte Zeile zeigt die geladene Version. Für ein Update denselben Block noch einmal ausführen.

Der erste Lauf legt die Config an, danach anpassen (siehe Referenz der Parameter):
```bash
pool=${pool:-$(zpool list -H -o name | grep -vx boot-pool | head -n1)}
dir=$(zfs get -H -o value mountpoint "$pool")/scripts/bashclub-zsync
"$dir/bashclub-zsync" -c "$dir/zsync.conf"
echo "$dir/bashclub-zsync -c $dir/zsync.conf >> $dir/bashclub-zsync.log 2>&1"
```
Die letzte Zeile gibt den Befehl für den Cron-Job aus. Den Job in der Weboberfläche anlegen: *System → Advanced
Settings → Cron Jobs*.

Einschränkungen auf TrueNAS:
- **Cron statt systemd-Timer**, kein `bashclub-zsync-setup` und keine Job-Benutzer: zsync läuft als root.
- **Snapshot-Engine `internal`:** `zfs-auto-snapshot` gibt es auf TrueNAS nicht.
- **Log:** logrotate kennt den Ordner nicht. zsync rotiert das Log ab 2.0 selbst bei 10 MiB und behält 4 komprimierte
  alte Logs (`bashclub-zsync.log.1.gz` … `.4.gz`).
- **Monitoring:** checkzfs läuft, der Service der Config (`zsync <config>`) fehlt, weil der Check im Paket liegt.

## TrueNAS SCALE als Quelle
Als Quelle braucht TrueNAS nur SSH mit dem Schlüssel des Backupservers. `bashclub-zsync-source` lässt sich dort nicht
installieren; die Replikation läuft dann als root wie in 1.0 (`bashclub-zsync-setup --root`).

## Manuelle Installation auf anderen Distributionen
Ohne Paket, z. B. auf einer Distribution ohne Pakete von bashclub. Wie bei TrueNAS ohne Timer, Setup und Job-Benutzer.
```bash
ref=$(curl -fsS 'https://code.bashclub.org/api/v1/repos/bashclub/zsync/tags?limit=50' | grep -o '"name":"v[0-9][^"]*"' | cut -d'"' -f4 | sort -V | tail -n1)
curl -fsSL -o /usr/local/bin/bashclub-zsync "https://code.bashclub.org/bashclub/zsync/raw/tag/$ref/bashclub-zsync/usr/bin/bashclub-zsync"
curl -fsSL -o /usr/local/bin/remote-snapshot-manager "https://code.bashclub.org/bashclub/zsync/raw/tag/$ref/bashclub-zsync/usr/bin/remote-snapshot-manager"
curl -fsSL -o /usr/local/bin/checkzfs https://code.bashclub.org/bashclub/checkzfs/raw/branch/main/bashclub-checkzfs/usr/bin/checkzfs
chmod +x /usr/local/bin/bashclub-zsync /usr/local/bin/remote-snapshot-manager /usr/local/bin/checkzfs
echo "$ref"
```
checkzfs braucht `python3`.
