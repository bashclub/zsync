---
title: Backupserver nur zur Replikation eingeschaltet
audience: Admin
outline: https://docs.bashclub.org/doc/backupserver-nur-zur-replikation-eingeschaltet-6LZfqwlQ6g
outline_id: 67937742-02c8-45a9-82eb-775dc5747bfb
---
Ab 2.0.

## Ausgangslage
Der Backupserver läuft nur, solange er repliziert: Er wird geweckt (BIOS-Wecker, Wake-on-LAN, IPMI oder ein Werkzeug wie
Miyagi), repliziert und schaltet sich wieder ab. Das spart Strom und verkleinert die Zeit, in der er angreifbar ist.
Checkmk soll den Zustand trotzdem jederzeit zeigen.

## Monitoring auf der Quelle
Die Spool-Datei geht auf die Quelle (`checkzfs_spool=1`). Dort bleiben die Services sichtbar, während der Backupserver
aus ist. Bleibt ein Lauf aus, wird die Datei älter als ihre Zahl im Namen, und Checkmk meldet die Services als fehlend.
`checkzfs_spool_maxage` deshalb etwas länger als den Abstand zweier Läufe wählen, z. B. `90000` bei täglichem Lauf.

In der Config der Replikation (hier `pve1`), auf dem Backupserver:
```bash
conf=/etc/bashclub/pve1.conf
for kv in checkzfs_spool=1 checkzfs_spool_maxage=90000; do
  k=${kv%%=*}
  if grep -q "^$k=" "$conf"; then sed -i "s|^$k=.*|$kv|" "$conf"; else echo "$kv" >> "$conf"; fi
done
```
Auf der Quelle muss der Job-Benutzer in den Spool schreiben dürfen:
```bash
install -d -m 3775 -g bashclub-zsync /var/lib/check_mk_agent/spool
```
Die Altersprüfung des Services `zsync-pve1 pve1` lernt den Abstand der Läufe selbst; fester Wert mit `monitor_max_age`, z. B.
`monitor_max_age=26h`.

## Wer startet die Läufe
**Mit Timer:** Der Timer startet einen Lauf, den er verpasst hat, weil der Host aus war, gleich nach dem Booten nach
(`Persistent=true`). Der Backupserver muss also nur zur richtigen Zeit geweckt werden.

**Mit einem Werkzeug:** Startet ein Werkzeug die Läufe (z. B. Miyagi), die Config mit `--external` einrichten. Das Setup
legt dann keinen Timer an und zeigt den Befehl, den das Werkzeug je Lauf ausführt:
```bash
source=pve1
bashclub-zsync-setup --source "$source" --external "$source"
```
Ausgabe am Ende, z. B.: `runuser -u zsync-pve1 -- bashclub-zsync -c /etc/bashclub/pve1.conf`.

Monitoring vorbereiten wie im [Standardfall](01-standardfall.md), Schritt 5 (eigenes `checkzfs_prefix`).

## Ausschalten erst, wenn nichts mehr läuft
Ab 2.0 zeigt `bashclub-zsync busy`, ob noch eine Replikation, eine Wartungsaktion, ein Restore-Job oder ein
Wechseldatenträger aktiv ist, und wartet mit `--wait`, bis alles fertig ist. Der Ablauf eines Werkzeugs nach dem
Wecken:
```bash
runuser -u zsync-pve1 -- bashclub-zsync -c /etc/bashclub/pve1.conf; bashclub-zsync busy --wait 3600 && poweroff
```
Während eines Laufs blockiert ein systemd-Inhibitor zusätzlich Herunterfahren und Ruhezustand
(`systemd-inhibit --list`). root kann ihn übergehen; deshalb vorher `busy` fragen.

Das Ergebnis des letzten Laufs für das Werkzeug, z. B. um eine Meldung zu schicken:
```bash
bashclub-zsync -c /etc/bashclub/pve1.conf --result
```
Alle Keys: [bashclub-zsync](../06-referenz/02-bashclub-zsync.md).

## Hooks
Eigene Schritte vor oder nach jedem Lauf, z. B. eine Meldung an ein Werkzeug, ohne zsync zu ändern: Dateien in
`/etc/bashclub/hooks.d/pre-run/` und `post-run/`, siehe [bashclub-zsync](../06-referenz/02-bashclub-zsync.md#hooks).
