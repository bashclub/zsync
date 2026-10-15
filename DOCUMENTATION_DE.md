# Konfiguration auf dem Zielserver

1. Öffnen Sie eine SSH-Verbindung zum Zielserver, entweder über die Befehlszeile oder ein SSH-Tool wie PuTTY.

2. Stellen Sie sicher, dass der Zielserver die erforderlichen Voraussetzungen erfüllt. Dazu gehören das Vorhandensein der benötigten Befehle (`zfs`, `ssh`, `grep`) und die korrekte Konfiguration der Pfade (`PATH`-Variable im Script).

3. Erstellen Sie eine Konfigurationsdatei für das Script. Standardmäßig wird die Datei `/etc/bashclub/zsync.conf` verwendet. Sie können jedoch einen anderen Pfad angeben, indem Sie den Parameter `-c` beim Aufruf des Scripts verwenden. Zusätzlich können Sie weitere Konfigurationsdateien erstellen, um unterschiedliche Replikationen einzurichten. Zum Beispiel: `/usr/bin/bashclub-zsync -c /pfad/zur/konfiguration1.conf`, `/usr/bin/bashclub-zsync -c /pfad/zur/konfiguration2.conf`

4. Öffnen Sie die Konfigurationsdatei mit einem Texteditor und passen Sie die folgenden Einstellungen an:

   - `source`: Geben Sie den SSH-Adresse des Quellservers an, von dem die Daten repliziert werden sollen. Beispiel: `source=user@host`
   - `target`: Geben Sie die Pfad des Ziel-ZFS-Dateisystems auf dem Zielserver an, zu dem die Daten repliziert werden sollen. Beispiel: `target=pool/dataset`
   - `sshport`: Geben Sie den SSH-Port des Quellservers an. Standardmäßig ist dies `22`, aber Sie können ihn entsprechend anpassen.
   - `tag`: Geben Sie den ZFS-Tag an, der verwendet werden soll, um die zu replizierenden Dateisysteme oder Volumes zu identifizieren. Beispiel: `tag=bashclub:zsync`
   - `snapshot_filter`: Geben Sie eine Pipe-separierte Liste von Snapshot-Namenfiltern an, die bestimmen, welche Snapshots repliziert werden sollen. Beispiel: `snapshot_filter="hourly|daily|weekly|monthly"`
   - `min_keep`: Geben Sie die Mindestanzahl von Snapshots pro Filter an, die beibehalten werden sollen. Beispiel: `min_keep=3`
   - `zfs_auto_snapshot_keep`: Aktiviert das erzeugen eines Snapshots auf der Quelle vor der Replikation, gibt die Anzahl der Snapshots an, die behalten werden sollen. Beispiel: `zfs_auto_snapshot_keep=0` => Deaktiviert die Funktion, `zfs_auto_snapshot_keep=7` behält 7 Snapshots. 
   - `zfs_auto_snapshot_label`: Definniert das Label des Snapshots, Default-Wert ist `backup` (ergibt: zfs-auto-snap_backup-YYYY-MM-dd-hhmm). Beispiel: `zfs_auto_snapshot_label=backup`
   - `bandwidth_limit`: Bandbreitenlimit der Übertragung in Bytes pro Sekunde mit Einheit `k`, `m`, `g` (1024er-Basis), z. B. `10m` = 10 MiB/s (ca. 84 Mbit/s). Wird auf dem Backupserver mit `pv` umgesetzt (`apt install pv`); ohne `pv` ohne Limit mit Warnung im Log. Leer = kein Limit.
   - `target_rollback`: `1` = fehlt der neueste Snapshot des Replikats auf der Quelle (Rollback oder dort gelöscht), wird das Replikat auf den neuesten gemeinsamen Snapshot zurückgerollt (`zfs rollback -r`, neuere Snapshots des Replikats werden gelöscht) und ab dort angefügt. `0` (Default) = das Dataset wird nicht mehr repliziert, bis es von Hand behoben ist.
   - `target_rollback_max`: höchstens so viele Snapshots darf ein Rollback auf dem Ziel löschen, sonst nur Fehlermeldung mit dem Befehl zum manuellen Rollback. Default `24`.
   - `monitor_max_age`: maximales Alter des letzten erfolgreichen Laufs für den Checkmk-Check `bashclub_zsync`, z. B. `26h`, `90m` oder Sekunden. Leer = aus den Startzeiten der letzten Läufe ermittelt, `0` = keine Altersprüfung (z. B. Wechseldatenträger). Details: README, Abschnitt „Monitoring with Checkmk“.
   - `zfs_auto_snapshot_label_match`: `strict` = zum Label gehören nur Snapshots im Namensschema der Snapshot-Engine (`internal`: `<label>-YYYY-MM-DD-HHMM`, `zas`: `zfs-auto-snap_<label>-YYYY-MM-DD-HHMM`), `legacy` = jeder Snapshot, dessen Name das Label enthält. Neue Konfigurationen nutzen `strict`, bestehende ohne diese Einstellung bleiben bei `legacy`. Ein Label darf nicht im Label einer anderen Konfiguration derselben Quelle enthalten sein (z. B. `zsync` und `zsync-miyagi`). Details und Befehle zum Wechsel von `zas` auf `internal`: README, Abschnitt „Snapshot label and snapshot engine“.

   Wiederholen Sie diese Schritte für jede zusätzliche Konfigurationsdatei, um unterschiedliche Replikationen einzurichten.

5. Speichern Sie die Konfigurationsdateien.

6. Überprüfen Sie, ob der Zielserver die erforderlichen ZFS-Datasets oder Volumes enthält, auf die die Daten repliziert werden sollen. Stellen Sie sicher, dass die Namen der Datasets/Volumes dem ZFS-Tag entsprechen, den Sie in den Konfigurationsdateien festgelegt haben.

7. Um das Script automatisch auszuführen, erstellen Sie eine Cronjob-Konfigurationsdatei im Verzeichnis `/etc/cron.d/`. Öffnen Sie eine neue Datei mit einem Texteditor und geben Sie die gewünschte Ausführungszeit und den Befehl ein. Beispiel:

   a) Erstellen Sie das Verzeichnis `/var/log/bashclub-zsync`, falls es noch nicht existiert. Verwenden Sie den Befehl: 
   ```plaintext
   sudo mkdir -p /var/log/bashclub-zsync
   ```

   b) Öffnen Sie die Cronjob-Konfigurationsdatei mit dem Befehl:
   ```plaintext
   sudo nano /etc/cron.d/bashclub-zsync-cronjob
   ```

   c) Fügen Sie den folgenden Inhalt in die Datei ein:
   ```plaintext
   SHELL=/bin/bash
   PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
   0 * * * * root /usr/bin/bashclub-zsync -c /etc/bashclub/zsync.conf >> /var/log/bashclub-zsync/zsync.log 2>&1
   ```

   In diesem Beispiel wird das Script einmal pro Stunde ausgeführt. Der Befehl `/usr/bin/bashclub-zsync -c /etc/bashclub/zsync.conf` wird als root-Benutzer ausgeführt, und die Ausgabe wird in die Datei `/var/log/bashclub-zsync/zsync.log` umgeleitet.

   d) Speichern Sie die Datei und schließen Sie den Texteditor.

Das Script wird nun automatisch gemäß dem angegebenen Intervall ausgeführt, und die Ausgabe wird im angegebenen Logfile gespeichert. Stellen Sie sicher, dass die Dateiberechtigungen für die Cronjob-Konfigurationsdatei korrekt sind, damit sie von Cron erkannt wird.

# Konfiguration auf dem Quellserver

Um ZFS-Dateisysteme und Volumes für die Replikation mit dem bashclub-zsync-Script zu markieren, verwenden Sie das ZFS-Attribut "bashclub:zsync" auf dem Quellserver. Dieses Attribut kann mit dem Parameter "value" konfiguriert werden, der die Werte "subvols", "all" oder "exclude" haben kann.

Hier ist eine Anleitung zur Konfiguration auf dem Quellserver:

1. Identifizieren Sie das ZFS-Dateisystem oder Volume, das Sie für die Replikation markieren möchten.

2. Setzen Sie das ZFS-Attribut "bashclub:zsync" mit dem gewünschten Value-Parameter-Wert. Verwenden Sie den Befehl:
   ```plaintext
   zfs set bashclub:zsync=<value> <datensatz>
   ```
   Ersetzen Sie `<value>` durch einen der folgenden Werte: "subvols", "all" oder "exclude". Ersetzen Sie `<datensatz>` durch den Namen des ZFS-Datensatzes.

   - "subvols": Markiert nur Volumes und Dateisysteme in der Hierarchie unterhalb des Datensatzes, für den das Attribut gesetzt ist (schließt den Wurzel-Datensatz aus).
   - "all": Markiert alle Volumes und Dateisysteme im ZFS-Datensatz einschließlich des Wurzel-Datensatzes.
   - "exclude": Schließt Volumes und Dateisysteme im ZFS-Datensatz aus, für den das Attribut gesetzt ist.

   Durch die Markierung mit dem Attribut "bashclub:zsync" wird das betreffende ZFS-Dateisystem oder -Volume für die Replikation mit dem bashclub-zsync-Script berücksichtigt.

Bitte beachten Sie, dass die genaue Syntax und Verwendung des Befehls je nach dem von Ihnen verwendeten Betriebssystem oder der ZFS-Version variieren kann. Stellen Sie sicher, dass Sie über ausreichende Berechtigungen verfügen, um die Konfiguration auf dem Quellserver vorzunehmen.
Um mehrere Replikationen zu unterschiedlichen Hosts mit dem bashclub-zsync-Script auf dem Zielserver zu ermöglichen, können Sie den Namen des ZFS-Attributs "bashclub:zsync" in der Scriptkonfiguration mit dem Parameter "tag" anpassen. Dadurch können Sie verschiedene Replikationen zu unterschiedlichen Hosts einrichten und steuern. Öffnen Sie das bashclub-zsync-Script auf dem Zielserver, suchen Sie nach dem "tag"-Parameter und ändern Sie den Wert in den gewünschten Namen für das ZFS-Attribut. Speichern Sie das Script nach der Änderung. Stellen Sie sicher, dass Sie über ausreichende Berechtigungen verfügen, um das Script zu bearbeiten und die Konfiguration auf dem Zielserver vorzunehmen.