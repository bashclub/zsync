---
title: Betrieb ohne root
audience: Admin
outline:
---
Ab 2.0 läuft eine Replikation auf Wunsch ohne root, auf dem Backupserver wie auf der Quelle. Neue Replikationen
richtet `bashclub-zsync-setup` so ein. Dieser Artikel stellt eine bestehende Config um, die als root läuft. Warum sich
das lohnt, steht im [Sicherheitsmodell](../01-konzept/06-sicherheitsmodell.md).

## Vorher
- Die Config, z. B. `/etc/bashclub/zsync.conf`, hat `source=root@pve1`. Der Backupserver meldet sich als root an der
  Quelle an und hat dort alle Rechte.
- Der Lauf startet als root, per Cron oder Timer.

## Nachher
- Auf dem Backupserver läuft die Config als `zsync-<name>` (z. B. `zsync-zsync`), mit eigenem Schlüssel und ZFS-Rechten
  nur auf ihr Target. Das Target hat `mountpoint=none`.
- Auf der Quelle meldet sie sich als `zsync-<backupserver>-<name>` an (Paket `bashclub-zsync-source`). Der Schlüssel
  gilt nur von der Adresse des Backupservers, nur für die Befehle von zsync und nur für die ausgewählten Datasets.
- Der Lauf startet per systemd-Timer als dieser Benutzer.

Dieselben Namen und Rechte vergibt `bashclub-zsync-setup` bei neuen Replikationen.

## Voraussetzungen
- Auf der Quelle ist die Paketquelle von bashclub eingerichtet (siehe [Installation](01-installation.md)), damit
  `bashclub-zsync-source` installiert werden kann.
- Der Backupserver erreicht die Quelle noch als root, so wie die Config es heute tut.
- Kein Lauf der Config ist aktiv.

## Umstellen
Alle Blöcke als root auf dem Backupserver. Der erste Block legt den Namen der Config fest, die übrigen lesen alles
Weitere aus der Config. Sie müssen in derselben Shell laufen.

1. Namen festlegen und die Werte der Config lesen:
```bash
name=zsync
conf=/etc/bashclub/$name.conf
. "$conf"
job=$(echo "$name" | tr 'A-Z_.' 'a-z--' | tr -cd 'a-z0-9-' | cut -c1-26)
source_job=$(echo "$(hostname -s)-$name" | tr 'A-Z_.' 'a-z--' | tr -cd 'a-z0-9-' | cut -c1-26)
user=zsync-$job
source_host=${source#*@}
echo "Benutzer hier: $user, auf $source_host: zsync-$source_job, Target: $target"
```

2. Benutzer auf dem Backupserver mit eigenem Schlüssel und Rechten nur auf das Target. Das Target bekommt
   `mountpoint=none`: Kein Replikat, das ein Benutzer ohne root empfangen hat, wird je von root eingehängt.
```bash
install -d -m 755 /var/lib/bashclub-zsync-jobs
id "$user" > /dev/null 2>&1 || useradd --system --home-dir "/var/lib/bashclub-zsync-jobs/$job" --create-home --shell /bin/bash --groups bashclub-zsync --comment "bashclub-zsync job $name" "$user"
test -f "/var/lib/bashclub-zsync-jobs/$job/.ssh/id_ed25519" || runuser -u "$user" -- bash -c 'install -d -m 700 ~/.ssh && ssh-keygen -q -t ed25519 -N "" -C "$(id -un)@$(hostname -s)" -f ~/.ssh/id_ed25519'
zfs set mountpoint=none "$target"
zfs allow -u "$user" create,receive,mount,destroy,rollback,clone,promote,rename,hold,release,userprop,aclinherit,aclmode,acltype,atime,checksum,compression,context,copies,dedup,defcontext,dnodesize,filesystem_limit,fscontext,logbias,nbmand,overlay,primarycache,quota,readonly,recordsize,redundant_metadata,refquota,refreservation,relatime,reservation,rootcontext,secondarycache,snapdev,snapdir,snapshot_limit,special_small_blocks,sync,volmode,volsize,vscan,xattr "$target"
```

3. Auf der Quelle `bashclub-zsync-source` installieren und den Job-Benutzer anlegen. Er bekommt den Schlüssel aus
   Schritt 2, gilt nur von der Adresse des Backupservers (so wie die Quelle sie sieht) und darf nur Snapshots seines
   Labels löschen:
```bash
key=$(cat "/var/lib/bashclub-zsync-jobs/$job/.ssh/id_ed25519.pub")
ssh -p "$sshport" "root@$source_host" "apt-get install -y bashclub-zsync-source > /dev/null && bashclub-zsync-job-user add --label $zfs_auto_snapshot_label --job-tag zsync_$(hostname -s)_${target//\//_} $source_job \${SSH_CLIENT%% *} $key && bashclub-zsync-job-user allow $source_job $tag"
```

4. Die Config auf die Benutzer umstellen und die Verbindung als neuer Benutzer testen. Die Ausgabe listet die
   ausgewählten Datasets der Quelle:
```bash
sed -i "s|^source=.*|source=zsync-$source_job@$source_host|" "$conf"
runuser -u "$user" -- ssh -p "$sshport" -o StrictHostKeyChecking=accept-new "zsync-$source_job@$source_host" zfs get -H -o name,value -t filesystem,volume "$tag"
```

5. Den Lauf auf den Timer als dieser Benutzer umstellen. Ein Cron-Job wird dabei übernommen (siehe
   [Cron auf systemd-Timer](04-cron-auf-timer.md)), sein Zeitplan bleibt:
```bash
bashclub-zsync-timer migrate "$name"
bashclub-zsync-timer enable "$name" --user "$user"
```

6. Spool für Checkmk, damit der Benutzer die Ausgabe von checkzfs schreiben darf. Auf dem Backupserver
   (`checkzfs_spool=0`):
```bash
install -d -m 3775 -g bashclub-zsync /var/lib/check_mk_agent/spool
```
   Mit `checkzfs_spool=1` derselbe Befehl auf der Quelle:
```bash
ssh -p "$sshport" "root@$source_host" install -d -m 3775 -g bashclub-zsync /var/lib/check_mk_agent/spool
```

## Prüfen
Einen Lauf starten und das Journal ansehen:
```bash
systemctl start "bashclub-zsync@$name.service"
journalctl -u "bashclub-zsync@$name" -n 30 --no-pager
bashclub-zsync -c "$conf" -s
```
Im Log steht kein `[ERROR]`, und die Statusausgabe zeigt den letzten Lauf als erfolgreich.

Meldungen `permission denied` beim Empfang einzelner Properties (z. B. `mountpoint`) sind gewollt: Der Benutzer darf
sie nicht setzen. Ihre Werte der Quelle stehen am Replikat als `bashclub:zsync-source.<property>`.

## Wenn sich etwas ändert
- **Weitere Datasets ausgewählt:** Die Rechte folgen dem Tag nicht von selbst. Auf der Quelle als root:
  `bashclub-zsync-job-user allow <job> <tag>` (die Werte zeigt Schritt 1).
- **Label oder Target geändert:** Schritt 3 noch einmal ausführen; der Schlüssel ist an Label und Target gebunden.
- **Andere Adresse des Backupservers:** ebenfalls Schritt 3.

## Rückweg
Die Config wieder als root laufen lassen. Die Benutzer bleiben bestehen und stören nicht:
```bash
name=zsync
conf=/etc/bashclub/$name.conf
. "$conf"
sed -i "s|^source=.*|source=root@${source#*@}|" "$conf"
bashclub-zsync-timer enable "$name" --user root
```
`mountpoint=none` am Target bleibt; es schadet auch als root nicht.
