# Tests

`run.sh` führt `bashclub-zsync` ohne ZFS aus: `zfs`, `ssh`, `scp`, `checkzfs`, `remote-snapshot-manager`
und `zfs-auto-snapshot` sind Stubs (`stubs/`), die jeden Aufruf protokollieren. Befehle für die Quelle
führt der ssh-Stub lokal mit denselben Stubs aus. Die Antworten von `zfs` kommen aus den Szenarien
(`scenarios/`). Ein Szenario kann `before_run`/`after_run` definieren (Argument: Arbeitsverzeichnis),
z. B. hält `9-locked.sh` damit die Sperre eines anderen Laufs. Ergebnis je Szenario: `.calls`, `.log`,
`.conf`, `.spool` und `.files` (Dateien im Spool und Reste in /tmp).

Damit lässt sich eine Änderung am Skript gegen den vorherigen Stand prüfen: Die Liste der ausgeführten
Befehle (`*.calls`) muss gleich bleiben, Abweichungen im Log (`*.log`) müssen gewollt sein.

```
git show main:bashclub-zsync/usr/bin/bashclub-zsync > /tmp/zsync-main
podman run --rm -v "$PWD:/src:ro,Z" -v /tmp:/out:Z docker.io/library/debian:13 bash -c \
  '/src/tests/run.sh /tmp/zsync-main /out/zsync-old && /src/tests/run.sh /src/bashclub-zsync/usr/bin/bashclub-zsync /out/zsync-new'
diff -r /tmp/zsync-old /tmp/zsync-new
```
