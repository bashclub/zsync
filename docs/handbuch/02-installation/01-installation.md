---
title: Installation
audience: Admin
outline: https://docs.bashclub.org/doc/installation-O8tObXzYn1
outline_id: a4bf0750-a8f9-4ee6-8cbd-a847b52eee15
---
## Unterstützte Plattformen
| Plattform | Codename | Installation |
|---|---|---|
| Proxmox VE 9, Debian 13 | `trixie` | Paket |
| Proxmox VE 8, Proxmox Backup Server 3, Debian 12 | `bookworm` | Paket |
| Ubuntu 24.04 | `noble` | Paket |
| Ubuntu 26.04 | `resolute` | Paket |
| TrueNAS SCALE | – | [manuell auf einem Dataset](02-truenas-und-manuell.md) |

Unterstützt sind nur Versionen, die ihr Hersteller noch regulär pflegt. Ältere Versionen (z. B. Debian 11) bekommen
keine Pakete und keine Anpassungen.

## Was wohin gehört
| System | Paket | Pflicht? |
|---|---|---|
| Backupserver | `bashclub-zsync` (bringt `bashclub-zsync-restore` mit) | ja |
| Quelle | `bashclub-zsync-source` | ab 2.0, für den Betrieb ohne root; `bashclub-zsync-setup` installiert es selbst, wenn es sich als root anmelden darf |
| System, das wiederhergestellt wird | `bashclub-zsync-restore` | nur für eine Wiederherstellung per Pull |

Die Quelle braucht sonst nur ZFS und SSH. `bashclub-zsync-setup` richtet die Quelle über SSH ein.

## 1. Komponente contrib (nur Debian)
`zfsutils-linux` liegt bei Debian in der Komponente `contrib`. Proxmox und Ubuntu haben alles Nötige schon
eingeschaltet, dort diesen Schritt überspringen. Der Block ergänzt `contrib` in beiden Formaten der Paketquellen
(`debian.sources` und `sources.list`), wo es fehlt:
```bash
f=/etc/apt/sources.list.d/debian.sources
if [ -f "$f" ]; then sed -i '/^Components:/{/contrib/!s/$/ contrib/}' "$f"; fi
f=/etc/apt/sources.list
if [ -f "$f" ]; then sed -i -E '/^deb .*debian\.org/{/ contrib( |$)/!s/$/ contrib/}' "$f"; fi
```

## 2. Paketquelle von bashclub
Auf jedem System, das ein Paket von bashclub bekommt. Der Codename kommt aus `/etc/os-release`, die Befehle lassen
sich unverändert kopieren. Wer die Paketquelle schon hat (z. B. `/etc/apt/sources.list.d/bashclub.list` aus einer
Installation von 1.0), überspringt diesen Schritt.

```bash
apt update && apt install -y wget gnupg
wget -O- https://apt.bashclub.org/gpg/bashclub.pub | gpg --dearmor > /usr/share/keyrings/bashclub-archive-keyring.gpg
cat > /etc/apt/sources.list.d/bashclub.sources << EOF
Types: deb
URIs: https://apt.bashclub.org/release
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: main
Signed-By: /usr/share/keyrings/bashclub-archive-keyring.gpg
EOF
apt update
```

Neben `release` gibt es `testing` mit dem jeweils neuesten Stand aus der Entwicklung. Für den Betrieb immer `release`.

## 3. Backupserver
```bash
apt install -y bashclub-zsync
```
Mit installiert werden `bashclub-zsync-restore` (Wiederherstellung) und, als Empfehlung, `bashclub-checkzfs` (nur für
`monitor_engine=checkzfs`; ab 2.0 prüft zsync die Snapshots selbst), `zfs-auto-snapshot`, `cryptsetup` und ein
`mail`-Befehl. Die letzten beiden braucht nur `zsync-autorun` für Wechseldatenträger. Für ein Bandbreitenlimit
zusätzlich `pv`:
```bash
apt install -y pv
```

## 4. Quelle
Für den Betrieb ohne root (ab 2.0, Standard bei neuen Replikationen) auf der Quelle, nach Schritt 1 und 2:
```bash
apt install -y bashclub-zsync-source
```
Das Paket legt den Verwaltungsbenutzer `zsync` an. Er darf per sudo nur Job-Benutzer für Replikationen anlegen und
sich nur mit einem SSH-Schlüssel anmelden.

Damit `bashclub-zsync-setup` die Quelle einrichten kann, braucht der Backupserver einmalig einen Zugang: entweder als
root oder als `zsync`. Für den Zugang als `zsync` auf dem **Backupserver** den Schlüssel von root anlegen und ausgeben:
```bash
test -f /root/.ssh/id_ed25519 || ssh-keygen -q -t ed25519 -N "" -f /root/.ssh/id_ed25519
cat /root/.ssh/id_ed25519.pub
```
Die ausgegebene Zeile auf der **Quelle** in die erste Zeile dieses Blocks einsetzen und ausführen:
```bash
key='ssh-ed25519 AAAA... root@backup'
install -d -m 700 -o zsync -g zsync /var/lib/zsync/.ssh
echo "$key" >> /var/lib/zsync/.ssh/authorized_keys
chown zsync:zsync /var/lib/zsync/.ssh/authorized_keys
chmod 600 /var/lib/zsync/.ssh/authorized_keys
```
Wer stattdessen root nutzen will: Darf sich root auf der Quelle mit Passwort anmelden (Standard bei Proxmox), kopiert
auf dem Backupserver `ssh-copy-id` den Schlüssel. Die Adresse der Quelle steht in der ersten Zeile:
```bash
source=pve1
test -f /root/.ssh/id_ed25519 || ssh-keygen -q -t ed25519 -N "" -f /root/.ssh/id_ed25519
ssh-copy-id -i /root/.ssh/id_ed25519.pub "root@$source"
```

Die eigentliche Einrichtung einer Replikation beschreibt der Bereich Szenarien.

## 5. System für eine Wiederherstellung
Nur für eine Wiederherstellung per Pull, nach Schritt 1 und 2:
```bash
apt install -y bashclub-zsync-restore
```

## Prüfen
```bash
dpkg -l 'bashclub-*' | grep ^ii
bashclub-zsync -h 2>&1 | head -n 1
```
Die zweite Zeile zeigt die installierte Version, z. B. `bashclub-zsync Version v2.0.0`.
