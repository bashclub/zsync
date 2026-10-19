---
title: Architektur und Ablauf eines Laufs
audience: Admin
outline: https://docs.bashclub.org/doc/architektur-und-ablauf-eines-laufs-VB3ib7hvH6
outline_id: 0051873a-13d4-4e92-bcc2-a270992603da
---
## Pull: der Backupserver holt ab
zsync läuft auf dem Backupserver. Er meldet sich per SSH an der Quelle an, liest die Liste der Datasets und holt die
Snapshots ab (`zfs send` auf der Quelle, `zfs receive` auf dem Backupserver). Die Quelle startet nichts und braucht
keinen Zugang zum Backupserver.

Warum Pull: Wer die Quelle übernimmt, etwa mit Ransomware, findet dort keinen Schlüssel für den Backupserver. Er kann
die Backups weder lesen noch löschen. Bei Push läge dieser Schlüssel auf der Quelle.

```
Quelle (z. B. Proxmox)                Backupserver
  ZFS-Datasets mit                      bashclub-zsync
  bashclub:zsync=all   <── SSH ──────   Config /etc/bashclub/<name>.conf
                       ── zfs send ──>  zfs receive in <target>/<dataset>
```

Ein Backupserver kann mehrere Quellen sichern, mit einer Config je Quelle. Eine Quelle kann von mehreren
Backupservern gesichert werden, die sich nicht in die Quere kommen.

## Die Config
Jede Replikation hat eine Config in `/etc/bashclub/`, z. B. `/etc/bashclub/pve1.conf`. Die wichtigsten Werte:
- `source`: SSH-Adresse der Quelle, z. B. `root@pve1` (oder `local`, siehe unten)
- `target`: Dataset auf dem Backupserver, unter dem die Replikate liegen, z. B. `backup/pve1`
- `tag`: die Property, mit der Datasets auf der Quelle ausgewählt werden (`bashclub:zsync`)
- `snapshot_filter`: welche Snapshots übertragen werden und wie viele auf dem Backupserver bleiben

Ein Dataset `rpool/data/vm-100-disk-0` der Quelle landet mit `target=backup/pve1` als
`backup/pve1/rpool/data/vm-100-disk-0` auf dem Backupserver. Ein Target gehört genau einer Config.

Ab 2.0 legt `bashclub-zsync-setup` neue Configs geführt an, mit Benutzern ohne root und einem Timer.

## Lokaler Modus
Ab 2.0 repliziert `source=local` Pools desselben Hosts ohne SSH, z. B. von `rpool` auf einen zweiten Pool oder auf
einen Wechseldatenträger, der am Proxmox-Server selbst hängt (siehe [Was ist bashclub-zsync](01-was-ist-bashclub-zsync.md)).
Datasets im Target werden dabei nie ausgewählt, auch wenn das Target im selben Pool liegt und das Tag erbt.

## Ablauf eines Laufs
Ein Lauf ist ein Aufruf von `bashclub-zsync -c <config>`, von Hand, per Cron oder (ab 2.0) per systemd-Timer.

1. **Sperre:** Pro Config läuft nur ein Lauf gleichzeitig (ab 2.0). Ein zweiter wird mit Fehlermeldung übersprungen.
2. **Hooks vor dem Lauf** (ab 2.0, optional): eigene Skripte; schlägt einer fehl, entfällt der Lauf.
3. **Liste:** zsync fragt die Quelle nach allen Datasets mit dem Tag. Ist die Quelle nicht erreichbar, endet der Lauf
   sofort mit Exit-Code 1.
4. **Snapshots:** Ist die Snapshot-Engine eingeschaltet, legt sie auf der Quelle neue Snapshots an und löscht alte
   (siehe [Snapshots und Aufbewahrung](05-snapshots-und-aufbewahrung.md)). Die Engine `zas`
   (`zfs-auto-snapshot` auf der Quelle) tut das hier einmal für alle Datasets, die Engine `internal`
   (`remote-snapshot-manager` von zsync) je Dataset direkt vor dessen Transfer.
5. **Je Dataset:**
   - **Transfer:** Gibt es das Replikat noch nicht, wird es vollständig übertragen (Erstreplikation). Sonst gehen nur
     die Snapshots seit dem letzten gemeinsamen Snapshot über (inkrementell).
   - **Originalwerte:** Ab 2.0 merkt sich das Replikat die Properties der Quelle, die die Replikation ändert (z. B.
     `mountpoint`), für eine spätere Wiederherstellung.
   - **Rotation:** Alte Snapshots auf dem Backupserver werden nach den Regeln von `snapshot_filter` gelöscht.
   - Ein Fehler bei einem Dataset bricht den Lauf nicht ab. Die anderen Datasets laufen weiter.
6. **Abgleich:** Ab 2.0 meldet zsync Replikate, deren Dataset es auf der Quelle nicht mehr gibt oder das nicht mehr
   ausgewählt ist. Es löscht sie nie.
7. **Monitoring:** Die Snapshots je Dataset prüft checkzfs oder ab 2.0 zsync selbst (`monitor_engine`). Ab 2.0 schreibt
   zsync zusätzlich den Zustand des Laufs und jedes Datasets für Checkmk (siehe
   [Monitoring-Konzept](07-monitoring-konzept.md)).
8. **Hooks nach dem Lauf** (ab 2.0, optional).

Der Exit-Code ist 0, wenn alle Datasets repliziert wurden, sonst 1. Warnungen, etwa eine blockierte Rotation, ändern
den Exit-Code nicht; sie stehen im Log und im Monitoring.

## Was wo liegt
| Was | Wo |
|---|---|
| Configs | `/etc/bashclub/*.conf` |
| Vorlage mit allen Parametern | `/etc/bashclub/zsync.conf.example` |
| Logs (Cron) | `/var/log/bashclub-zsync/`, mit systemd-Timer im Journal |
| Zustand der Läufe (ab 2.0) | `/var/lib/bashclub-zsync/<benutzer>/`, während eines Laufs `/run/bashclub-zsync/<benutzer>/` |
| Spool für Checkmk | `/var/lib/check_mk_agent/spool/` auf dem Backupserver oder der Quelle |
