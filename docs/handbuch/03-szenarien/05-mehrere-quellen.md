---
title: Mehrere Quellen auf einem Backupserver
audience: Admin
outline:
---
## Ausgangslage
Ein Backupserver sichert mehrere Quellen, z. B. die Proxmox-Server mehrerer Kunden oder Standorte. Die Replikationen
sollen sich nicht gegenseitig sehen oder stören, und jede soll in Checkmk eindeutig erscheinen.

```
kunde1-pve  ──>
kunde2-pve  ──>  backup1:  backup/zsync/kunde1-pve/…   (Benutzer zsync-kunde1-pve)
kunde3-pve  ──>            backup/zsync/kunde2-pve/…   (Benutzer zsync-kunde2-pve)
                           …
```

## Je Quelle eine Config
Je Quelle eine Replikation wie im [Standardfall](01-standardfall.md), mit eigenem Namen. Die Vorschläge des Setups
trennen die Quellen bereits:

| | je Config eigen |
|---|---|
| Config | `/etc/bashclub/<name>.conf` |
| Target | `<pool>/zsync/<name>` |
| Benutzer auf dem Backupserver | `zsync-<name>`, Rechte nur auf sein Target |
| Benutzer auf der Quelle | `zsync-<backupserver>-<name>`, gilt nur für diese Quelle |
| Timer | `bashclub-zsync@<name>.timer` |
| Präfix im Monitoring | `checkzfs_prefix=zsync-<name>` (von Hand, siehe unten) |

Ein Target gehört genau einer Config. Liegen Datasets einer anderen Config im Target, meldet zsync sie als Replikate ohne
Quelle.

## Monitoring
**Jede Replikation braucht ein eigenes `checkzfs_prefix`.** Alle Configs eines Backupservers schreiben in denselben
Spool. Mit demselben Präfix hätten sie dieselbe Spool-Datei, jeder Lauf würde die Services der anderen Configs
überschreiben, und in Checkmk kollidierten die Services. Das Setup setzt das Präfix nicht; nach dem Setup jeder Config,
vor ihrem ersten Lauf, mit dem Namen der Config in der ersten Zeile:
```bash
name=kunde1-pve
sed -i "s/^checkzfs_prefix=.*/checkzfs_prefix=zsync-$name/" "/etc/bashclub/$name.conf"
```

Prüfen, ob alle Configs ein eigenes Präfix haben (keine Ausgabe = in Ordnung):
```bash
for c in /etc/bashclub/*.conf; do p=$(sed -n 's/^checkzfs_prefix=//p' "$c" | tail -n1 | tr -d "\"'"); echo "${p:-zsync}"; done | sort | uniq -d
```
Eine Config ohne Eintrag hat das Präfix `zsync`. Die Ausgabe nennt jedes Präfix, das mehr als eine Config verwendet.

Ein Präfix nachträglich ändern: Der nächste Lauf schreibt eine neue Spool-Datei; die alte unter dem alten Namen bleibt
liegen, und Checkmk zeigt ihre Services weiter, bis sie älter als ihre Zahl im Namen ist. Deshalb nach dem nächsten
Lauf die alte Datei löschen (altes Präfix in der ersten Zeile; dort, wohin die Config schreibt, also auf dem
Backupserver oder mit `checkzfs_spool=1` auf der Quelle) und in Checkmk die Service-Erkennung ausführen:
```bash
old=zsync
rm -v /var/lib/check_mk_agent/spool/*_"$old"
```
Teilen sich noch andere Configs das alte Präfix, schreiben deren nächste Läufe ihre Datei neu.

## Rechte und Trennung
- Ein Kunde sieht nichts von den anderen: Der Benutzer auf seiner Quelle kann nur die Befehle von zsync ausführen und
  nur seine Datasets lesen. Der Backupserver hat keinen Zugang über die Replikation hinaus.
- Auf dem Backupserver hat jede Replikation Rechte nur auf ihr Target.
- Für eine Wiederherstellung per Pull bekommt jede Config einen eigenen Restore-Benutzer
  (`zsync-restore-<config>`), der nur ihre Replikate lesen darf.

## Gleiche Dataset-Namen
Mehrere Proxmox-Server haben dieselben Namen (`rpool/data/vm-100-disk-0`). Das ist kein Problem: Jede Config hat ihr
Target, die Replikate heißen `backup/zsync/kunde1-pve/rpool/data/vm-100-disk-0` und
`backup/zsync/kunde2-pve/rpool/data/vm-100-disk-0`.

## Last verteilen
Die Läufe verschiedener Configs laufen unabhängig voneinander und gleichzeitig, wenn ihre Zeitpläne sich überschneiden.
Bei vielen Quellen die Zeitpläne versetzen, z. B. `--schedule "5,20,35,50 * * * *"` für die zweite Config.
