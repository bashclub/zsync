---
title: Upgrade auf 2.0
audience: Admin
outline: https://docs.bashclub.org/doc/upgrade-auf-20-LsQWHO6pdo
outline_id: 9394557c-2b9d-4b20-8bb7-ff61c05711e5
---
Das Update von 1.0 auf 2.0 ist ein normales Paketupdate. Bestehende Replikationen laufen danach ohne Eingriff weiter:
mit derselben Config, demselben Cron-Job, als root, mit denselben Snapshots. Neue Funktionen, die den Betrieb ändern
könnten, sind für bestehende Configs aus, bis der Admin sie einschaltet.

## Was das Update tut
Auf dem Backupserver:
- sichert `/etc/bashclub/zsync.conf` als `/etc/bashclub/zsync.conf.backup_<datum>` (wie in 1.0)
- korrigiert den Besitzer von `/etc/bashclub`: Pakete bis 1.0.19 legten den Ordner mit dem Benutzer des Paketbaus an
  (uid 995). Danach gehört er root, und nur root darf schreiben. Die Configs laufen als root, deshalb ist das eine
  Sicherheitskorrektur.
- legt die Gruppe `bashclub-zsync` und die Ordner für den Zustand der Läufe an (`/var/lib/bashclub-zsync`,
  `/run/bashclub-zsync`)
- installiert `bashclub-zsync-restore` als empfohlenes Paket mit
- zeigt einen Hinweis, wenn es Cron-Jobs von zsync findet: systemd-Timer sind jetzt möglich. Der Hinweis ändert nichts.

## Was das Update bewusst nicht tut
- Es ändert keine Config und keinen Cron-Job.
- Es stellt nicht auf Benutzer ohne root um.
- Es ändert nichts auf der Quelle. Die Quelle braucht für 2.0 kein Update.
- Es schaltet keine neue Funktion ein, die Platz kostet oder Snapshots anders löscht. Fehlt ein neuer Parameter in
  einer Config, gilt das Verhalten von 1.0:

| Parameter | ohne Eintrag (bestehende Configs) | neue Configs aus `bashclub-zsync-setup` |
|---|---|---|
| `zfs_auto_snapshot_engine` | `zas` | `internal` |
| `zfs_auto_snapshot_label_match` | `legacy` | `strict` |
| `snapshot_filter` | Labels ohne Zahl: der Quelle folgen | feste Anzahl je Label |
| `source_bookmark`, `source_hold`, `transfer_resume` | `0` | `1` |
| `monitor_engine` | checkzfs, wenn installiert, sonst `internal` | `internal` |
| `trigger` | `cron` | `systemd` |
| `run_as` | root | eigener Benutzer |

## Was sich ab dem ersten Lauf ändert
Diese Änderungen gelten auch für bestehende Configs. Sie machen Fehler sichtbar, die 1.0 still übergangen hat, oder
verhindern Datenverlust.

:::info
**Nur ein Lauf je Config:** Startet ein Lauf, während derselbe noch läuft, endet der zweite sofort mit `[ERROR]` und
Exit-Code 1. Bis 1.0.19 liefen beide gleichzeitig und störten sich. Wer im Log solche Fehler sieht, startet die
Config zu oft für ihre Laufzeit.
:::

:::info
**Quelle nicht erreichbar:** Der Lauf endet sofort mit Exit-Code 1. Bis 1.0.19 endete er mit 0, obwohl nichts
repliziert wurde.
:::

:::info
**Rollback auf der Quelle:** Fehlen die neuesten Snapshots eines Replikats auf der Quelle, setzt zsync die
Replikation auf einer neuen Kette fort und behält die alte als `<replikat>.zsync-branch-<datum>`. Das kostet Platz,
bis der Admin mit `bashclub-zsync-maintenance` entscheidet. Bis 1.0.19 brach die Replikation dieses Datasets bei jedem
Lauf mit `[ERROR]` ab.
:::

:::info
**Neue Meldungen im Monitoring:** Die Spool-Datei enthält zusätzlich den Service der Config (`zsync <config>`). Er
erscheint bei der nächsten Service-Erkennung in Checkmk. Er meldet auch Zustände, die es schon vor dem Update gab:
Replikate ohne Quelle (nach einem Tag), gerissene Ketten, blockierte Rotation durch Snapshots in fremdem Namensschema.
Nach dem Update ist deshalb mit einmaligen Warnungen zu rechnen.
:::

Weitere Änderungen ohne Folgen für den Betrieb:
- Beim Folgen der Quelle bleiben, wenn `min_keep` das Löschen stoppt, die neuesten Snapshots, bis 1.0.19 die ältesten.
- Wird ein Snapshot während der Übertragung auf der Quelle gelöscht, überspringt zsync ihn mit Warnung; bis 1.0.19
  scheiterte das Dataset bis zum nächsten Lauf.
- Ist auf der Quelle eine `refquota` gewachsen, hebt zsync sie auf dem Replikat an, statt am Kontingent zu scheitern.
- An jedem Replikat stehen die Originalwerte der Quelle als `bashclub:zsync-source.*`, für eine Wiederherstellung.
- Ein Log in einem Ordner, den logrotate nicht kennt, rotiert zsync bei 10 MiB selbst.
- Die Lizenz ist ab 2.0 GPL-3.0-or-later statt MIT.

## Durchführung
1. Auf dem Backupserver prüfen, dass gerade kein Lauf aktiv ist (keine Ausgabe = keiner):
```bash
pgrep -af 'bashclub-zsync -c'
```
2. Update einspielen:
```bash
apt update && apt install -y bashclub-zsync
```
3. Den nächsten regulären Lauf abwarten oder eine Config von Hand starten, z. B. `/etc/bashclub/zsync.conf`:
```bash
conf=/etc/bashclub/zsync.conf
bashclub-zsync -c "$conf"
```

## Prüfung danach
Der Zustand aller Configs, so wie ihn Checkmk sieht (Exit-Code 0 OK, 1 WARN, 2 CRIT):
```bash
bashclub-zsync -s
```
- **OK** mit „learning“: Der Service lernt das Intervall noch aus den nächsten Läufen. Das ist normal.
- **WARN/CRIT** mit Hinweis auf `bashclub-zsync-maintenance`: ein Fall, den es schon vor dem Update gab. Mit
  `bashclub-zsync-maintenance` ansehen und entscheiden, oder „später“ wählen.

In Checkmk die Service-Erkennung des Hosts ausführen, der die Spool-Datei bekommt (Backupserver bei
`checkzfs_spool=0`, Quelle bei `checkzfs_spool=1`), und den neuen Service `zsync <config>` übernehmen.

## Danach: freiwillige Umstellungen
Jede ist einzeln möglich und hat einen Rückweg:
- [Cron auf systemd-Timer](04-cron-auf-timer.md)
- [Betrieb ohne root](05-betrieb-ohne-root.md)
- [Snapshot-Engine und Label-Abgleich](06-snapshot-engine-und-labels.md)
- [Neue Funktionen einschalten](07-neue-funktionen-einschalten.md), darunter die eingebaute Prüfung der Snapshots
  statt checkzfs (`monitor_engine=internal`)

Zurück auf 1.0: [Downgrade](09-downgrade.md).
