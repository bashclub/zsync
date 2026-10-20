---
title: Typische Fehler
audience: Admin
outline: https://docs.bashclub.org/doc/typische-fehler-NDgF47RAAw
outline_id: c48a50ef-2136-403d-8547-774efcf5e594
---
Die häufigsten Fehlerbilder mit Ursache und Abhilfe. Wie man die Ursache eingrenzt, zeigt die
[Diagnose](01-diagnose.md); die genaue Meldung im Log steht in [Meldungen](../06-referenz/08-meldungen.md).

## Quelle nicht erreichbar
**Bild:** `[ERROR] source … is not reachable or zfs failed there`, Checkmk: letzter Lauf fehlgeschlagen, später zu alt.

Der Verbindungstest aus der [Diagnose](01-diagnose.md) (Abschnitt Prüfbefehle) zeigt, woran es liegt:
- **Zeitüberschreitung, `No route to host`:** Quelle aus, Netz, Firewall, falscher Port (`sshport`).
- **`Permission denied (publickey)`:** Der Schlüssel des Benutzers der Config fehlt auf der Quelle, oder die Adresse des
  Backupservers hat sich geändert. Auf der Quelle steht dann im SSH-Log
  `Authentication tried for … with correct key but not from a permitted host`: Der Schlüssel des Job-Benutzers gilt nur
  von der eingetragenen Adresse (`from=`). Abhilfe: den Job-Benutzer mit der neuen Adresse anlegen, siehe
  [Betrieb ohne root](../02-installation/05-betrieb-ohne-root.md), Abschnitt „Wenn sich etwas ändert“.
- **`Host key verification failed`:** Die Quelle wurde neu installiert oder hat einen neuen Schlüssel. Den alten Eintrag
  entfernen und neu bestätigen, als der Benutzer der Config:
  `runuser -u zsync-pve1 -- ssh-keygen -R pve1`, danach einmal `runuser -u zsync-pve1 -- ssh pve1 true` und den
  Schlüssel bestätigen.
- **Verbindung klappt, aber `zfs` scheitert:** ZFS-Modul auf der Quelle nicht geladen oder Pool nicht importiert.

## Befehl auf der Quelle abgelehnt
**Bild:** im Log `bashclub-zsync-remote: command not allowed: …`, Exit-Code 126; auf der Quelle in
`journalctl -t bashclub-zsync-remote` eine Zeile `denied for zsync-… from …: …`.

Der Job-Benutzer darf nur die Befehle von zsync ausführen. Ursachen:
- **Versionen passen nicht zusammen:** Ein neueres `bashclub-zsync` auf dem Backupserver nutzt einen Befehl, den ein
  älteres `bashclub-zsync-source` auf der Quelle noch nicht kennt. Abhilfe: auf der Quelle
  `apt update && apt install -y bashclub-zsync-source`.
- **Befehl von Hand:** Eine Shell oder andere Befehle über den Job-Benutzer sind gewollt verboten. Für Arbeiten auf der
  Quelle den eigenen Zugang nehmen.

## Keine Rechte ohne root
**Bild:** `permission denied` bei `zfs receive`, `zfs hold`, `zfs bookmark`, `zfs set` oder beim Anlegen einer neuen
Kette (`clone`, `promote`, `rename`).

- **Auf der Quelle** fehlen dem Job-Benutzer die Rechte auf neu ausgewählte Datasets, meist weil sie an anderer Stelle
  ausgewählt wurden als beim Einrichten. Auf der Quelle: `bashclub-zsync-job-user allow <job> <tag>` (Job und Tag zeigt
  `bashclub-zsync-job-user list`).
- **Auf dem Backupserver** fehlen dem Benutzer der Config Rechte auf dem Target. Welche er hat: `zfs allow <target>`;
  welche er braucht, steht in [Betrieb ohne root](../02-installation/05-betrieb-ohne-root.md), Schritt „Umstellen“.
- **`mountpoint`, `canmount`, `setuid`, `exec`, `devices`** darf der Benutzer bewusst nicht setzen. Die Meldung dazu ist
  gewollt; die Werte der Quelle stehen am Replikat (`bashclub:zsync-source.*`).

## Kein gemeinsamer Snapshot, Kette gerissen
**Bild:** Checkmk CRIT `full replication needed for … datasets`, im Log `No matching snapshot (guid: …) found on source filesystem` oder
`no common snapshot with the source`.

Die Quelle hat alle Snapshots gelöscht, die auch das Replikat hat, meist weil der Backupserver länger nicht repliziert
hat, als die Quelle ihre Snapshots behält. Oder das Dataset wurde auf der Quelle gelöscht und neu angelegt (z. B. eine
VM-Disk nach einem Restore aus einem anderen Backup).

Ohne `broken_rename=1` überträgt zsync dann nicht selbst neu, weil das das alte Replikat ersetzen würde (siehe
[ZFS-Grundlagen](../01-konzept/03-zfs-grundlagen.md)). Abhilfe mit `bashclub-zsync-maintenance`: `rename` behält das
alte Replikat unter neuem Namen, der nächste Lauf überträgt vollständig neu; `delete` löscht es. Siehe
[Entscheidungen](../04-betrieb/04-wartung.md). Ab 2.0 macht zsync das mit `broken_rename=1` (Default neuer Configs)
selbst, sofern der Platz reicht.

Vorbeugen: `source_bookmark=1` (der Bookmark hält die Kette, auch wenn die Snapshots weg sind) und genug Snapshots auf
der Quelle für die längste Pause des Backupservers.

## Snapshots in fremdem Namensschema
**Bild:** Checkmk WARN `rotation on the target blocked`, im Log `the oldest source snapshot of interval … does not exist on …` oder
`snapshots … contain the label …, but do not match the name scheme`.

Snapshots mit dem Label im Namen, aber von einem anderen Werkzeug oder aus der Zeit vor einem Wechsel der Engine. Die
Rotation auf dem Backupserver hält dann für das Label an, und der Platz wächst. Abhilfe:
- `zfs_auto_snapshot_label_match=strict`, dann zählen fremde Namen nicht mehr
- die Altlasten auf der Quelle und am Replikat löschen, wie in
  [Snapshot-Engine und Label-Abgleich](../02-installation/06-snapshot-engine-und-labels.md) beschrieben; am Replikat mit
  `bashclub-zsync-maintenance` (Fall `leftovers`)

## Unterbrochene Übertragung
**Bild:** Übertragung bricht ab (Netz, Neustart, Lauf beendet); Checkmk zeigt den Lauf als abgebrochen.

Mit `transfer_resume=1` (Default neuer Configs) setzt der nächste Lauf an der Abbruchstelle fort; im Log steht dann die
Fortsetzung, und `--result` nennt das Dataset unter `resume.<dataset>`. Gelingt das nicht, z. B. weil der Snapshot auf
der Quelle inzwischen gelöscht ist, verwirft zsync den Teil mit Warnung und überträgt neu. Mit `transfer_resume=0`
verwirft zsync angefangene Empfänge immer.

Bleibt ein Teil stehen, von Hand verwerfen, mit dem Replikat in der ersten Zeile:
```bash
replica=backup/zsync/pve1/rpool/data/vm-100-disk-0
token=$(zfs get -H -o value receive_resume_token "$replica")
if [ -n "$token" ] && [ "$token" != "-" ]; then zfs receive -A "$replica"; else echo "kein angefangener Empfang"; fi
```

## Lauf übersprungen
**Bild:** `[ERROR] Another run with configuration … is still active (pid …). Skipping this run.`, Checkmk WARN ab 3
übersprungenen Läufen.

Ein Lauf dauert länger als der Abstand zum nächsten Start. Das ist kein Fehler des Backups, aber ein Zeichen, dass der
Zeitplan zu eng ist oder ein Lauf hängt:
- `bashclub-zsync busy` zeigt, was läuft
- hängt er, nennt Checkmk die Phase und bei einem blockierten Prozess die Kernel-Funktion; siehe
  [Zustände](../04-betrieb/03-zustaende.md)
- sonst den Zeitplan strecken (`schedule`) oder die Bandbreite prüfen

Die Sperre gibt das Betriebssystem frei, sobald der Prozess endet, auch nach einem Absturz. Eine alte Sperre von Hand
zu löschen ist nie nötig.

## Spool nicht schreibbar
**Bild:** `[WARN] … is not writable for …, … is not stored.` oder
`mv: cannot move '…/.<maxage>_<prefix>.…' to '…': Operation not permitted`; Checkmk zeigt alte oder keine Services.

- Der Ordner des Spools lässt den Benutzer der Config nicht schreiben. Auf dem Host, der die Datei bekommt:
  `install -d -m 3775 -g bashclub-zsync /var/lib/check_mk_agent/spool`
- Die Datei gehört einem anderen Benutzer, meist root nach der Umstellung auf Betrieb ohne root. Abhilfe in
  [Betrieb ohne root](../02-installation/05-betrieb-ohne-root.md), Schritt 6.

## Services je Dataset fehlen
**Bild:** In Checkmk fehlen die Services `<prefix>:<source>#<dataset>`, der Service der Config ist da.

- Mit `monitor_engine=checkzfs` und Bookmarks bricht checkzfs ab (`'NoneType' object has no attribute 'add_snapshot'`
  im Log). Abhilfe: `monitor_engine=internal`, siehe
  [Neue Funktionen einschalten](../02-installation/07-neue-funktionen-einschalten.md).
- `checkzfs_disabled=1` steht in der Config.
- Die Service-Erkennung in Checkmk wurde nach dem ersten Lauf nicht ausgeführt.
- Zwei Configs mit demselben `checkzfs_prefix` überschreiben sich die Spool-Datei; siehe
  [Mehrere Quellen](../03-szenarien/05-mehrere-quellen.md#monitoring).

## Platz wird knapp
Alte Ketten nach einem Rollback, Replikate ohne Quelle und blockierte Rotation belegen Platz, bis jemand entscheidet.
Was wie viel belegt und wie man Platz schafft: [Platz planen](../04-betrieb/05-platz.md).
