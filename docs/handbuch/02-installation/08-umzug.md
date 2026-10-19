---
title: Umzug von Replikaten auf einen anderen Pool
audience: Admin
outline:
---
Die Replikate einer Config ziehen mit allen Snapshots in ein neues Target um, auf einen anderen Pool desselben
Backupservers oder auf einen neuen Backupserver. Die Kette mit der Quelle bleibt erhalten: Danach überträgt zsync wie
gewohnt nur die Änderungen, keine neue Erstreplikation.

## Was dabei zu beachten ist
- Während des Umzugs darf kein Lauf der Config starten.
- Der Umzug überträgt alle Snapshots und Properties der Replikate, auch die Markierungen von zsync
  (`bashclub:zsync-source.*`, offene Fälle) und verschlüsselte Datasets raw.
- Er braucht einen eigenen Snapshot über alle Replikate. Dieser muss vor dem nächsten Lauf wieder weg: zsync würde ihn
  sonst für den neuesten Stand halten, der auf der Quelle fehlt, und eine neue Kette anlegen.
- Bookmark und Hold auf der Quelle tragen Backupserver und Target im Namen. Nach dem Umzug legt zsync neue an. Die
  alten Bookmarks bleiben auf der Quelle liegen und stören nicht.

## Auf einen anderen Pool desselben Backupservers
Alle Blöcke als root auf dem Backupserver, in derselben Shell. Der erste Block legt Config und neues Target fest.

1. Config und neues Target festlegen, Läufe anhalten und prüfen, dass keiner aktiv ist:
```bash
name=zsync
new_target=tank/zsync/zsync
conf=/etc/bashclub/$name.conf
. "$conf"
old_target=$target
if [[ $trigger == systemd ]]; then systemctl stop "bashclub-zsync@$name.timer"; fi
bashclub-zsync busy --wait 3600 && echo "kein Lauf aktiv, alt: $old_target, neu: $new_target"
```
   Läuft die Config per Cron, die Zeile in der Crontab vorher auskommentieren.

2. Snapshot über alle Replikate anlegen und alles in das neue Target übertragen. Das Elternteil des neuen Targets muss
   existieren, das Target selbst nicht:
```bash
zfs create -p -o canmount=noauto "${new_target%/*}"
zfs snapshot -r "$old_target@zsync-move"
zfs send -R -w "$old_target@zsync-move" | zfs receive -u "$new_target"
```

3. Den Snapshot des Umzugs auf beiden Seiten entfernen und das Ergebnis vergleichen. Die Ausgabe zeigt für alt und
   neu dieselbe Zahl Datasets und Snapshots:
```bash
zfs destroy -r "$old_target@zsync-move"
zfs destroy -r "$new_target@zsync-move"
for t in "$old_target" "$new_target"; do echo "$t: $(zfs list -H -r -o name "$t" | wc -l) Datasets, $(zfs list -H -r -t snapshot -o name "$t" | wc -l) Snapshots"; done
```

4. Die Config auf das neue Target umstellen. Läuft sie ohne root, bekommt ihr Benutzer die Rechte auf das neue Target:
```bash
sed -i "s|^target=.*|target=$new_target|" "$conf"
if [[ -n $run_as && $run_as != root ]]; then zfs allow -u "$run_as" "$(zfs allow "$old_target" | awk '/^\t*user /{ print $3; exit }')" "$new_target"; fi
grep '^target=' "$conf"
```

5. Läuft die Config ohne root, ist ihr Schlüssel auf der Quelle an das Target gebunden (Hold und Bookmark). Dann den
   Job-Benutzer auf der Quelle neu anlegen, wie in [Betrieb ohne root](05-betrieb-ohne-root.md) Schritt 3:
```bash
if [[ -n $run_as && $run_as != root ]]; then
  source_host=${source#*@}; source_job=${source%%@*}; source_job=${source_job#zsync-}
  key=$(cat "$(getent passwd "$run_as" | cut -d: -f6)/.ssh/id_ed25519.pub")
  ssh -p "$sshport" "root@$source_host" "bashclub-zsync-job-user add --label $zfs_auto_snapshot_label --job-tag zsync_$(hostname -s)_${new_target//\//_} $source_job \${SSH_CLIENT%% *} $key && bashclub-zsync-job-user allow $source_job $tag"
fi
```

6. Einen Lauf starten und prüfen. Im Log steht eine inkrementelle Übertragung („Replicating delta“), keine
   Erstreplikation und keine neue Kette:
```bash
if [[ $trigger == systemd ]]; then systemctl start "bashclub-zsync@$name.service"; journalctl -u "bashclub-zsync@$name" -n 40 --no-pager; else bashclub-zsync -c "$conf"; fi
bashclub-zsync -c "$conf" -s
```
   Danach den Timer wieder einschalten (oder die Cron-Zeile):
```bash
if [[ $trigger == systemd ]]; then systemctl start "bashclub-zsync@$name.timer"; fi
```

7. Das alte Target erst löschen, wenn einige Läufe erfolgreich waren. Zuerst ansehen, was gelöscht würde:
```bash
zfs destroy -rnv "$old_target"
```

## Auf einen neuen Backupserver
Derselbe Weg mit zwei Unterschieden:
- Schritt 2 überträgt per SSH, als root vom alten zum neuen Backupserver:
  `zfs send -R -w "$old_target@zsync-move" | ssh root@<neuer-backupserver> zfs receive -u "$new_target"`
- Statt Schritt 4 und 5 richtet `bashclub-zsync-setup` auf dem neuen Backupserver die Config mit dem übertragenen
  Target ein (`--target`), mit eigenen Benutzern auf beiden Seiten. Danach auf dem alten Backupserver die Config
  stilllegen (Timer `disable` oder Cron-Zeile entfernen) und den alten Job-Benutzer auf der Quelle entfernen:
  `bashclub-zsync-job-user remove <job>`.

## Rückweg
Bis Schritt 7 bleibt das alte Target unverändert erhalten. Zurück: in der Config wieder das alte Target eintragen
(`sed -i "s|^target=.*|target=$old_target|" "$conf"`), ohne root Schritt 5 mit dem alten Target, und das neue Target
löschen.
