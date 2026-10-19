---
title: Szenarien
audience: Admin
outline:
---
Vollständige Anleitungen für gängige Aufbauten: Ausgangslage, Skizze, Schritte, Prüfung, Monitoring und typische Fehler.
Jedes Szenario setzt die [Installation](../02-installation/01-installation.md) voraus.

**Grundfälle**
- [Standardfall: Proxmox-Server → Backupserver im LAN](01-standardfall.md)
- [Lokale Replikation: Pool zu Pool](02-lokal.md)
- [Wechseldatenträger](03-wechseldatentraeger.md)

**Entfernt und mehrfach**
- [Offsite über WAN oder VPN](04-offsite.md)
- [Mehrere Quellen auf einem Backupserver](05-mehrere-quellen.md)
- [Kaskade: Backupserver → Offsite-Backupserver](06-kaskade.md)
- [Backupserver nur zur Replikation eingeschaltet](07-backupserver-zeitweise.md)

**Besondere Daten und Systeme**
- [Verschlüsselte Datasets](08-verschluesselung.md)
- [Aufbewahrungsstufen](09-aufbewahrung.md)
- [TrueNAS SCALE](10-truenas.md)
- [Proxmox-Cluster und HA](11-proxmox-cluster.md)
