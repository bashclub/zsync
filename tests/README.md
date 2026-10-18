# Tests

`run.sh` führt `bashclub-zsync` ohne ZFS aus: `zfs`, `ssh`, `scp`, `checkzfs`, `remote-snapshot-manager`
und `zfs-auto-snapshot` sind Stubs (`stubs/`), die jeden Aufruf protokollieren. Befehle für die Quelle
führt der ssh-Stub lokal mit denselben Stubs aus. Die Antworten von `zfs` kommen aus den Szenarien
(`scenarios/`). Ein Szenario kann `before_run`/`after_run` definieren (Argument: Arbeitsverzeichnis),
z. B. hält `9-locked.sh` damit die Sperre eines anderen Laufs. Mit `PV=1` steht ein `pv`-Stub bereit. Ergebnis je Szenario: `.calls`, `.log`,
`.conf`, `.spool`, `.files` (Dateien im Spool und Reste in /tmp) und `.status` (Status-Dateien für das
Monitoring).

Damit lässt sich eine Änderung am Skript gegen den vorherigen Stand prüfen: Die Liste der ausgeführten
Befehle (`*.calls`) muss gleich bleiben, Abweichungen im Log (`*.log`) müssen gewollt sein.

```
git show main:bashclub-zsync/usr/bin/bashclub-zsync > /tmp/zsync-main
podman run --rm -v "$PWD:/src:ro,Z" -v /tmp:/out:Z docker.io/library/debian:13 bash -c \
  '/src/tests/run.sh /tmp/zsync-main /out/zsync-old && /src/tests/run.sh /src/bashclub-zsync/usr/bin/bashclub-zsync /out/zsync-new'
diff -r /tmp/zsync-old /tmp/zsync-new
```

`checkmk.sh` testet den Checkmk-Check mit Status-Dateien und einem nachgebauten `/proc` (Lernphase, Alter,
Hänger, D-Zustand, Abbruch, übersprungene Läufe): `tests/checkmk.sh` (ohne root, ohne ZFS).

`restore-remote.sh` testet `bashclub-zsync-restore-remote` (command= des Restore-Benutzers auf dem Backupserver)
ebenso: lesende Befehle unter `--root` laufen, alles außerhalb, schreibende Befehle und Shell-Versuche werden
abgewiesen: `tests/restore-remote.sh` (ohne root, ohne ZFS).

`remote.sh` testet `bashclub-zsync-remote` (command= auf der Quelle) mit einem zfs-Stub: erlaubte Befehle
und abgewiesene Versuche (Shell, Datasets löschen, fremde Optionen und Pfade). Dass jeder Befehl von
`bashclub-zsync` durchgeht, zeigt `run.sh` mit `ZTEST_WRAPPER`: der ssh-Stub führt dann alles über den Wrapper
aus, das Ergebnis muss mit dem Lauf ohne Wrapper übereinstimmen:
```
podman run --rm -v "$PWD:/src:ro,Z" -v /tmp:/out:Z docker.io/library/debian:13 bash -c \
  '/src/tests/run.sh /src/bashclub-zsync/usr/bin/bashclub-zsync /out/zsync-plain && ZTEST_WRAPPER=/src/bashclub-zsync-source/usr/bin/bashclub-zsync-remote /src/tests/run.sh /src/bashclub-zsync/usr/bin/bashclub-zsync /out/zsync-wrapped'
diff -r /tmp/zsync-plain /tmp/zsync-wrapped
```

Echte ZFS-Tests auf einer Test-VM: [integration/README.md](integration/README.md).
