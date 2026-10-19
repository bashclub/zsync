---
title: "Lokale Replikation: Pool zu Pool"
audience: Admin
outline: https://docs.bashclub.org/doc/lokale-replikation-pool-zu-pool-HJgL3Q9SLd
outline_id: 8f475607-8e2c-49a6-a817-8031c2a163d9
---
Ab 2.0.

## Ausgangslage
Ein Host mit zwei Pools, z. B. ein Proxmox-Server mit `rpool` (SSD) und `tank` (große Platten). Die Disks der VMs aus
`rpool/data` sollen als Backup mit eigener Aufbewahrung auf `tank` liegen. Kein zweiter Server, kein SSH.

```
pve1
  rpool/data/vm-100-disk-0   ── zfs send | zfs receive ──>   tank/zsync/local/rpool/data/vm-100-disk-0
```

Das schützt vor dem Ausfall eines Pools und vor versehentlichem Löschen, aber nicht vor dem Verlust des Hosts oder vor
jemandem, der ihn übernimmt. Dafür zusätzlich ein [Wechseldatenträger](03-wechseldatentraeger.md) oder eine
[Offsite-Replikation](04-offsite.md).

## Einrichten
Datasets auswählen und die Replikation einrichten, alles auf dem Host. Der Ziel-Pool steht in der ersten Zeile:
```bash
pool=tank
zfs set bashclub:zsync=subvols rpool/data
bashclub-zsync-setup --source local --target "$pool/zsync/local" local
```
Mit `--source local` läuft die Replikation als root, ohne Job-Benutzer und ohne `bashclub-zsync-source`. Das Setup
fragt Zeitplan und Aufbewahrung wie im [Standardfall](01-standardfall.md).

Danach wie im [Standardfall](01-standardfall.md), Schritt 5 und 6: Monitoring vorbereiten (eigenes
`checkzfs_prefix`), dann den ersten Lauf starten.

Datasets im Target werden nie ausgewählt, auch wenn das Target das Tag erbt. Liegt das Target im selben Pool wie die
Quelle, schützt es nur vor versehentlichem Löschen, nicht vor dem Ausfall des Pools.

## Prüfen
```bash
journalctl -u bashclub-zsync@local -n 50 --no-pager
bashclub-zsync -c /etc/bashclub/local.conf -s
```
Das Log beginnt mit `Local mode: replicating datasets of this host without ssh (source=local)`.

## Monitoring
Wie im [Standardfall](01-standardfall.md): Spool auf dem Host, mit eigenem Präfix Service `zsync-local local`. Die Prüfung je Dataset vergleicht ohne SSH.
