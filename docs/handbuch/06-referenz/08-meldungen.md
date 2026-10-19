---
title: Meldungen
audience: Admin
outline:
---
Die Meldungen von `bashclub-zsync` mit Ursache und Abhilfe, in der Reihenfolge eines Laufs. `<dataset>` steht für den
Namen auf der Quelle, `<replikat>` für das Dataset auf dem Backupserver.

- **`[ERROR]`** betrifft den Lauf oder ein Dataset: Der Exit-Code ist 1, wenn ein Dataset nicht repliziert wurde.
- **`[WARN]`** braucht Aufmerksamkeit, aber die Replikation selbst ist gelungen; der Exit-Code bleibt 0. Wichtige
  Warnungen meldet auch Checkmk.

Fehlerbilder mit ausführlicher Abhilfe stehen im Bereich Fehlerbehebung.

## Start des Laufs
**`[ERROR] Another run with configuration … is still active (pid …). Skipping this run.`**
Ab 2.0. Derselbe Lauf ist noch aktiv; dieser endet sofort. Kommt das regelmäßig vor, startet der Cron-Job oder Timer
öfter, als ein Lauf dauert. Checkmk warnt ab 3 übersprungenen Läufen.

**`[WARN] flock (util-linux) not found, running without protection against concurrent runs.`**
`flock` fehlt (ungewöhnlich, z. B. bei manueller Installation). `apt install util-linux`.

**`[WARN] … cannot be used by <benutzer> (missing, of another user, or … not in the group bashclub-zsync), no run status for the monitoring.`**
Ab 2.0. Der Benutzer des Laufs kann seinen Ordner unter `/run/bashclub-zsync` oder `/var/lib/bashclub-zsync` nicht
anlegen. Der Lauf repliziert, der Checkmk-Service bekommt aber keinen Zustand. Abhilfe: den Benutzer in die Gruppe
`bashclub-zsync` aufnehmen (`usermod -aG bashclub-zsync <benutzer>`) oder die Ordner neu anlegen lassen
(`apt install --reinstall bashclub-zsync`).

**`[WARN] checkzfs is disabled. for monitoring please install: …`**
checkzfs ist nicht installiert. Auf Systemen mit Paket kommt es mit `bashclub-zsync`; bei manueller Installation siehe
[TrueNAS SCALE und manuelle Installation](../02-installation/02-truenas-und-manuell.md).

**`[ERROR] source is empty. For local replication without ssh use source=local`**
`source` fehlt in der Config. Für Pools desselben Hosts `source=local` setzen, sonst die Adresse der Quelle.

**`[ERROR] … is not a folder of root that only root may write, its hooks are not run.`** und
**`[ERROR] … is not an executable file of root that only root may write, it is not run.`**
Ab 2.0. Ein Hook oder sein Ordner gehört nicht root oder ist für andere schreibbar. Der Lauf entfällt. Abhilfe:
`chown root:root` und `chmod 755` für Ordner und Hook.

**`[ERROR] a pre-run hook failed, the run is skipped.`**
Ab 2.0. Ein Hook vor dem Lauf endete mit einem Exit-Code ungleich 0; seine Ausgabe steht davor im Log.

**`[WARN] a post-run hook failed, the exit code of the run stays …`**
Ab 2.0. Ein Hook nach dem Lauf schlug fehl; der Lauf selbst ist davon nicht betroffen.

## Verbindung und Auswahl
**`[ERROR] source … (port …) is not reachable or zfs failed there (exit code …), nothing is replicated.`**
Die Quelle antwortet nicht oder `zfs get` scheitert dort. Ab 2.0 endet der Lauf sofort mit Exit-Code 1 (bis 1.0.19 mit
0). Prüfen als der Benutzer des Laufs: `ssh -p <port> <source> zfs list` (bei `run_as` mit
`runuser -u <benutzer> --`). Häufige Ursachen: Host aus, Schlüssel fehlt, `from=` passt nicht mehr zur Adresse des
Backupservers (`journalctl -t bashclub-zsync-remote` auf der Quelle).

**`[ERROR] zfs get … failed (exit code …), nothing is replicated.`**
Wie oben, im lokalen Modus (`source=local`).

**`[WARN] no dataset on … is selected for the replication, nothing is replicated. …`**
Ab 2.0. Kein Dataset der Quelle hat das Tag mit `all` oder `subvols`, siehe
[Auswahl der Datasets](../01-konzept/04-auswahl-der-datasets.md). Checkmk meldet WARN.

## Einstellungen
**`[WARN] Invalid number of snapshots to keep in snapshot_filter: … (a number or source), the target follows the source for ….`**
Ab 2.0. Ein Eintrag in `snapshot_filter` hat hinter `=` weder eine Zahl noch `source`. Das Label folgt der Quelle, bis
der Eintrag korrigiert ist.

**`[WARN] Unknown value zfs_auto_snapshot_label_match=…, using legacy.`**
Ab 2.0. Erlaubt sind `strict` und `legacy`.

**`[WARN] Invalid value bandwidth_limit=… (e.g. 10m), running without bandwidth limit.`**
Ab 2.0. Erlaubt ist eine Zahl mit optionalem Suffix `k`, `m`, `g`, `t`.

**`[WARN] pv not found, running without bandwidth limit. Install pv to limit the bandwidth.`**
Ab 2.0. `apt install pv` auf dem Backupserver.

**`[WARN] zfs-auto-snapshot is not installed on the source, the snapshot engine zas creates no snapshots. …`**
Ab 2.0. Die Engine `zas` braucht `zfs-auto-snapshot` auf der Quelle. Dort installieren oder auf die Engine `internal`
wechseln, siehe [Snapshot-Engine und Label-Abgleich](../02-installation/06-snapshot-engine-und-labels.md).

## Je Dataset: Snapshots und Übertragung
**`[WARN] <dataset> - snapshots on the source contain the label …, but do not match the name scheme of the snapshot engine … (e.g. left over after switching the engine). …`**
Ab 2.0. Altlasten auf der Quelle, meist nach einem Wechsel der Engine. Die Meldung nennt sie mit Namen; löschen, wie in
[Snapshot-Engine und Label-Abgleich](../02-installation/06-snapshot-engine-und-labels.md) beschrieben.

**`[WARN] <dataset> - resuming the transfer failed (e.g. the snapshot was deleted on the source), discarding the partial state.`**
Ab 2.0. Eine unterbrochene Übertragung ließ sich nicht fortsetzen; zsync verwirft den Teil und überträgt neu.

**`[WARN] <dataset> - <replikat> contains the partial state of an interrupted transfer, discarding it (transfer_resume=0).`**
Ab 2.0. Wie oben, mit ausgeschaltetem Resume.

**`[ERROR] discarding the partial state of … failed.`**
`zfs receive -A` scheiterte. Von Hand: `zfs receive -A <replikat>`.

**`[ERROR] initial replication to … failed.`**
Die Erstreplikation scheiterte; die Ursache steht in den Zeilen davor (Platz, Rechte, Verbindung). Der nächste Lauf
versucht es erneut, mit `transfer_resume=1` ab der Abbruchstelle.

**`[ERROR] setting refquota of … failed.`**
Ab 2.0. Das Anheben der `refquota` auf dem Replikat scheiterte; ohne root fehlt evtl. das Recht `refquota`.

**`[WARN] <dataset> - <snapshot> was deleted on the source during the replication, continuing with the next snapshot.`**
Ab 2.0. Die Rotation auf der Quelle hat einen Snapshot während der Übertragung gelöscht; zsync überspringt ihn.
`source_hold=1` verhindert das.

**`[ERROR] incremental replication to … failed.`**
Eine inkrementelle Übertragung scheiterte; die Ursache steht in den Zeilen davor.

**`[WARN] <dataset> - creating the bookmark … failed, the replication continues without it.`**
Ab 2.0. Ohne root fehlt evtl. das Recht `bookmark` auf der Quelle (`bashclub-zsync-job-user allow`).

**`[WARN] <dataset> - saving the original properties of the source on … failed (bashclub:zsync-source.*).`**
Ab 2.0. Die Originalwerte für eine Wiederherstellung fehlen am Replikat; ohne root fehlt evtl. das Recht `userprop`.

## Je Dataset: Kette
**`[WARN] <dataset> - the newest snapshots of <replikat> do not exist on the source anymore (rollback or deleted there). The replication continues on a new chain from …, the old chain … stays as …`**
Ab 2.0. Rollback auf der Quelle. Die alte Kette bleibt als `<replikat>.zsync-branch-<datum>`; entscheiden mit
`bashclub-zsync-maintenance`.

**`[ERROR] <dataset> - … or … exists already (an earlier attempt was not completed), …`**
Ab 2.0. Ein früherer Versuch, die neue Kette anzulegen, wurde nicht fertig. Die genannten Datasets ansehen und das
nicht Benötigte entfernen.

**`[ERROR] <dataset> - cloning … failed, nothing was changed.`**, **`promoting … failed …`**,
**`renaming failed: …`**, **`moving … below the new chain failed: …`**
Ab 2.0. Ein Schritt beim Anlegen der neuen Kette scheiterte, meist fehlende Rechte ohne root (`clone`, `promote`,
`rename`). Die Meldung nennt die Befehle, um von Hand abzuschließen.

**`[WARN] <dataset> - marking … failed (bashclub:zsync-branch).`**
Ab 2.0. Die alte Kette ist angelegt, aber nicht markiert; `bashclub-zsync-maintenance` zeigt sie dann nicht.

**`[ERROR] <dataset> - the newest snapshot on … does not exist on the source anymore (rollback or deleted on the source). Newest common snapshot: …`**
Rollback auf der Quelle, und die neue Kette ließ sich nicht anlegen (siehe die Meldungen davor).

**`[ERROR] <dataset> - the replication failed and its base … is the oldest snapshot of interval … on the source: the next rotation breaks the chain.`**
Ab 2.0. Kette in Gefahr: Scheitert auch der nächste Lauf, gibt es keinen gemeinsamen Snapshot mehr. Ursache der
gescheiterten Übertragung jetzt beheben. Mit `source_bookmark=1` geht es auch danach weiter.

**`[ERROR] No matching snapshot (guid: …) found on source filesystem. …`** zusammen mit
**`[ERROR] <dataset> - no common snapshot with the source: …`**
Kette gerissen: Die Quelle hat alle Snapshots gelöscht, die das Replikat hat, oder das Dataset wurde auf der Quelle neu
angelegt. Nur eine neue Erstreplikation hilft. Mit `bashclub-zsync-maintenance` das Replikat umbenennen (behalten) oder
löschen; der nächste Lauf überträgt neu.

**`[ERROR] No snapshot found on … to add incremental snapshots to. …`** zusammen mit
**`[ERROR] <dataset> - to keep the empty replica rename it, …`**
Das Replikat hat keinen Snapshot. Wie oben mit `bashclub-zsync-maintenance` entscheiden.

## Je Dataset: Rotation
**`[WARN] <dataset> - the oldest source snapshot of interval … (…) does not exist on …, no snapshots of this interval are deleted on the target.`**
Ab 2.0. Die Rotation auf dem Backupserver ist für dieses Label blockiert, meist durch einen Snapshot in fremdem
Namensschema auf der Quelle. Checkmk meldet WARN, bis er weg ist. Mit `zfs_auto_snapshot_label_match=strict` zählt er
nicht mehr.

**`[WARN] <dataset> - snapshots on the target contain the label …, but do not match the name scheme of the snapshot engine …. …`**
Ab 2.0. Altlasten auf dem Replikat; im Modus `strict` löscht zsync sie nicht. Löschen mit
`bashclub-zsync-maintenance` (Fall `leftovers`).

## Abgleich am Ende
**`[WARN] <replikat> is the old chain after a rollback on the source: …. Keep or delete it: bashclub-zsync-maintenance`**
Ab 2.0. Eine alte Kette wartet auf die Entscheidung.

**`[WARN] <replikat> … and is not replicated anymore (…). Keep it: zfs set bashclub:zsync-orphan=keep … - check the deletion: zfs destroy -rnv …`**
Ab 2.0. Replikat ohne Dataset auf der Quelle oder nicht mehr ausgewählt. Behalten oder löschen mit
`bashclub-zsync-maintenance`.

**`[WARN] marking the open decision on … failed (bashclub:zsync-case), bashclub-zsync-maintenance does not show it.`**
Ab 2.0. Ohne root fehlt evtl. das Recht `userprop` auf dem Target.

## Monitoring
**`[WARN] … is not writable for …, … is not stored.`**
Ab 2.0. Der Benutzer des Laufs darf nicht in den Checkmk-Spool schreiben. Abhilfe auf dem betreffenden Host:
`install -d -m 3775 -g bashclub-zsync /var/lib/check_mk_agent/spool`.

**`mv: cannot move '…/.<maxage>_<prefix>.…' to '…': Operation not permitted`**
Die Spool-Datei gehört einem anderen Benutzer, meist root nach der Umstellung auf Betrieb ohne root. Abhilfe: der Datei
den Benutzer des Laufs geben, siehe [Betrieb ohne root](../02-installation/05-betrieb-ohne-root.md) Schritt 6.
