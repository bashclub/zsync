---
title: Zustände und was zu tun ist
audience: Admin
outline: https://docs.bashclub.org/doc/zustande-und-was-zu-tun-ist-GJ2iPyVoCa
outline_id: 5b0b4ba5-c658-4d13-a574-05197373f16e
---
Was der Checkmk-Service der Config (`<präfix> <config>`) meldet und was zu tun ist. Der Text des Services nennt das
betroffene Dataset und die Ursache. Die genaue Meldung im Log steht in [Meldungen](../06-referenz/08-meldungen.md).

## Läufe
**Letzter erfolgreicher Lauf zu alt (WARN, CRIT)**
Es lief länger kein erfolgreicher Lauf. Nachsehen, ob Läufe stattfinden und woran sie scheitern:
```bash
name=pve1
systemctl list-timers "bashclub-zsync@$name.timer"
journalctl -u "bashclub-zsync@$name" -n 50 --no-pager
```
Häufig: Quelle nicht erreichbar, Timer gestoppt, Backupserver war aus.

**Letzter Lauf fehlgeschlagen (WARN)**
Mindestens ein Dataset wurde nicht repliziert. Der Service nennt, wie viele; das Log die Ursache (`[ERROR]`).

**Keine Datasets ausgewählt (WARN)**
Auf der Quelle hat kein Dataset das Tag, siehe [Auswahl der Datasets](../01-konzept/04-auswahl-der-datasets.md).

**Phase zu lang, Übertragung ohne Fortschritt, Prozess blockiert (WARN, CRIT)**
Ein Lauf hängt. Der Service nennt Phase, Dataset und bei einem blockierten Prozess die Kernel-Funktion, auf die er
wartet. Häufig: Netz weg während einer Übertragung, Platte des Backupservers voll oder defekt, ZFS hängt. Prüfen:
```bash
zpool status -x
zpool list
```
Hängt nur das Netz, beendet SSH die Verbindung nach einer Weile selbst; mit `transfer_resume=1` setzt der nächste Lauf
fort. Einen hängenden Lauf von Hand beenden: `systemctl stop bashclub-zsync@pve1.service`.

**Lauf abgebrochen (WARN)**
Der Prozess eines Laufs verschwand ohne Ergebnis (beendet, Absturz, Stromausfall). Der nächste Lauf räumt auf (Holds,
angefangener Empfang mit Resume); die Warnung verschwindet mit ihm.

**Läufe übersprungen (WARN)**
Der Timer oder Cron wollte starten, während ein Lauf noch lief. Ab 3 übersprungenen Läufen läuft ein Lauf deutlich
länger als das Intervall: Zeitplan strecken, Bandbreite prüfen oder nach einem Hänger sehen.

## Datasets
**Kette gerissen, Replikat ohne Snapshots (CRIT)**
Es gibt keinen gemeinsamen Snapshot mehr mit der Quelle; zsync kann dieses Dataset nicht mehr inkrementell
übertragen. Ursache laut Service: Die Quelle hat alle Snapshots rotiert, die das Replikat hat (zu lange keine
Replikation), oder das Dataset wurde auf der Quelle neu angelegt. Entscheiden mit
[bashclub-zsync-maintenance](04-wartung.md): `rename` behält das alte Replikat, der nächste Lauf überträgt neu.

**Kette in Gefahr (WARN)**
Die letzte Übertragung scheiterte, und ihre Basis ist der älteste Snapshot des Labels auf der Quelle. Scheitert auch
der nächste Lauf und rotiert die Quelle dazwischen, reißt die Kette. Jetzt die Ursache der gescheiterten Übertragung
beheben.

**Neuester Snapshot des Replikats fehlt auf der Quelle (WARN)**
Auf der Quelle wurde zurückgerollt oder der neueste Snapshot gelöscht, und zsync konnte keine neue Kette anlegen
(meist fehlende Rechte ohne root: `clone`, `promote`, `rename`). Das Log nennt die Befehle.

**Alte Kette nach einem Rollback (WARN)**
Nach einem Rollback auf der Quelle hat zsync auf einer neuen Kette weiterrepliziert und die alte behalten. Prüfen, ob
der Rollback gewollt war. Dann mit `bashclub-zsync-maintenance` behalten (Archiv) oder löschen. War er nicht gewollt
(Angriff), enthält die alte Kette die Stände vor dem Rollback; siehe [Ransomware und Angriffe](../05-restore/06-ransomware.md).

**Rotation am Ziel blockiert (WARN)**
Der älteste Snapshot eines Labels auf der Quelle fehlt am Ziel; zsync löscht für dieses Label auf dem Backupserver
nichts mehr, und der Platz wächst. Meist ein Snapshot in fremdem Namensschema; Abhilfe in
[Snapshot-Engine und Label-Abgleich](../02-installation/06-snapshot-engine-und-labels.md).

**Replikat ohne Quelle (WARN nach einem Tag)**
Das Dataset gibt es auf der Quelle nicht mehr, oder es ist nicht mehr ausgewählt. Gewollt (VM gelöscht)? Dann mit
`bashclub-zsync-maintenance` behalten oder löschen. Nicht gewollt? Auf der Quelle nachsehen, ob die VM noch existiert
und das Tag noch erbt.

Hinweise ohne Warnung: behaltene Replikate und Ketten, neue Kette im letzten Lauf, Datasets ohne passende Snapshots,
Replikate ohne Quelle in der Wartezeit.

## Services je Dataset
**Alle Services je Dataset fehlen**, im Log steht `'NoneType' object has no attribute 'add_snapshot'`: checkzfs bricht
ab, weil auf der Quelle oder dem Backupserver ein Bookmark existiert. Abhilfe: `monitor_engine=internal`, siehe
[Neue Funktionen einschalten](../02-installation/07-neue-funktionen-einschalten.md).

- **Kein Replikat gefunden:** Das Dataset ist ausgewählt, aber noch nicht repliziert, meist vor der Erstreplikation.
- **Neuester Snapshot des Replikats fehlt auf der Quelle (CRIT):** Rollback auf der Quelle; siehe oben, alte Kette.
- **Kein gemeinsamer Snapshot (CRIT, nur `monitor_engine=internal`):** Kette gerissen, siehe oben.
- **Alter des neuesten Snapshots zu hoch:** Für dieses Dataset kam länger nichts an. Zusammen mit einem Problem im
  Service der Config ansehen.
- **Zu viele Snapshots:** Die Aufbewahrung behält mehr, als `checkzfs_max_snapshot_count` erlaubt, oder die Rotation
  ist blockiert. Siehe [Aufbewahrungsstufen](../03-szenarien/09-aufbewahrung.md).
