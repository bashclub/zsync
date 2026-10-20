---
title: Disaster-Recovery-Plan und Restore-Übung
audience: Admin
outline: https://docs.bashclub.org/doc/disaster-recovery-plan-und-restore-ubung-WCPByig2OB
outline_id: bd0b5040-bb2d-47f5-9cb3-3af147e91278
---
Ein Backup ist erst dann eins, wenn der Restore geübt ist. Dieser Artikel ist eine Vorlage für den eigenen Plan und
eine Übung, die nichts an Quelle und Backup ändert.

## Was im Plan stehen sollte
Je Quelle, ausgedruckt oder an einem Ort, der den Ausfall übersteht:
- Backupserver, Config und Target (`/etc/bashclub/<config>.conf`, `target=`)
- Pool-Namen und Aufbau der Quelle: `zpool status`, `zfs list -o name,mountpoint`
- welche Datasets wichtig sind und in welcher Reihenfolge sie zurück müssen
- wo die Schlüssel verschlüsselter Datasets liegen; ohne sie ist das Backup nicht lesbar
- Proxmox: eine Kopie von `/etc/pve` (VM-Configs, Storages), z. B. regelmäßig auf den Backupserver kopiert
- Netz: Adressen, über die Backupserver und Ersatzsystem sich erreichen
- wer entscheidet und wer ausführt

Eine Kopie von `/etc/pve` auf dem Backupserver, z. B. täglich per Cron, mit der Quelle in der ersten Zeile:
```bash
source=root@pve1
dir=/root/pve-config/${source#*@}
mkdir -p "$dir" && ssh "$source" tar -C /etc -czf - pve > "$dir/pve-$(date +%F).tar.gz" && ls -l "$dir" | tail -n 3
```

## Übung: Restore auf dem Backupserver
Stellt eine Disk mit ihrer ganzen Kette in einen eigenen Bereich des Backupservers her, prüft sie und räumt wieder auf.
Quelle und Replikate bleiben unverändert. Config, Replikat und Pool für die Übung in den ersten Zeilen:
```bash
config=pve1
dataset=rpool/data/vm-100-disk-0
pool=backup
bashclub-zsync-restore dataset --config "$config" --as "$pool/restore-test/${dataset##*/}" "$dataset" --dry-run
```
Ist der Plan plausibel: derselbe Befehl ohne `--dry-run`, mit `--start` und `--scrub`. `--as` legt fehlende Eltern
selbst an. Der Bericht am Ende muss `OK` zeigen. Danach:
- **Container:** einhängen und Stichproben ansehen ([Einzelne Dateien](01-einzelne-dateien.md)).
- **VM:** auf Proxmox als Testmaschine ohne Netz starten, oder wie oben einhängen.

Aufräumen, mit dem Pool der Übung in der ersten Zeile:
```bash
pool=backup
zfs destroy -rnv "$pool/restore-test"
```
Die Ausgabe zeigt, was gelöscht würde; stimmt sie, dieselbe Zeile ohne `n`.

Die Übung mindestens einmal im Jahr und nach größeren Änderungen wiederholen und das Ergebnis mit Datum im Plan
festhalten.
