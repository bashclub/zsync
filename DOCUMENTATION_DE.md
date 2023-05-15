# Konfiguration auf dem Zielserver

1. Öffnen Sie eine SSH-Verbindung zum Zielserver, entweder über die Befehlszeile oder ein SSH-Tool wie PuTTY.

2. Stellen Sie sicher, dass der Zielserver die erforderlichen Voraussetzungen erfüllt. Dazu gehören das Vorhandensein der benötigten Befehle (`zfs`, `ssh`, `grep`) und die korrekte Konfiguration der Pfade (`PATH`-Variable im Script).

3. Erstellen Sie eine Konfigurationsdatei für das Script. Standardmäßig wird die Datei `/etc/bashclub/zsync.conf` verwendet. Sie können jedoch einen anderen Pfad angeben, indem Sie den Parameter `-c` beim Aufruf des Scripts verwenden. Zusätzlich können Sie weitere Konfigurationsdateien erstellen, um unterschiedliche Replikationen einzurichten. Zum Beispiel: `/usr/bin/bashclub-zsync -c /pfad/zur/konfiguration1.conf`, `/usr/bin/bashclub-zsync -c /pfad/zur/konfiguration2.conf`

4. Öffnen Sie die Konfigurationsdatei mit einem Texteditor und passen Sie die folgenden Einstellungen an:

   - `source`: Geben Sie den Pfad des Quell-ZFS-Dateisystems auf dem Quellserver an, von dem die Daten repliziert werden sollen. Beispiel: `source=pool/dataset`
   - `target`: Geben Sie die SSH-Adresse des Quellservers an, von dem die Daten repliziert werden sollen. Beispiel: `target=user@host`
   - `sshport`: Geben Sie den SSH-Port des Quellservers an. Standardmäßig ist dies `22`, aber Sie können ihn entsprechend anpassen.
   - `tag`: Geben Sie den ZFS-Tag an, der verwendet werden soll, um die zu replizierenden Dateisysteme oder Volumes zu identifizieren. Beispiel: `tag=bashclub:zsync`
   - `snapshot_filter`: Geben Sie eine Pipe-separierte Liste von Snapshot-Namenfiltern an, die bestimmen, welche Snapshots repliziert werden sollen. Beispiel: `snapshot_filter="hourly|daily|weekly|monthly"`
   - `min_keep`: Geben Sie die Mindestanzahl von Snapshots pro Filter an, die beibehalten werden sollen. Beispiel: `min_keep=3`

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