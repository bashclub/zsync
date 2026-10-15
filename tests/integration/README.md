# ZFS-Integrationstests

Echte Replikation mit ZFS auf einer Test-VM: jeder Fall bekommt frische Pools `zci-src` und `zci-dst`
auf zwei eigenen Platten, repliziert mit dem installierten Paket über `root@localhost` (bzw. `source=local`)
und prüft das Ergebnis am Ziel. Am Ende werden die Pools zerstört.

| Datei | Zweck |
|---|---|
| `run.sh [fall …]` | Fälle auf der Test-VM ausführen (als root), Logs in `/var/log/zsync-ci/<fall>.log` |
| `lib.sh` | Pools, Configs, Prüfungen |
| `remote.sh <root@host> [fall …]` | vom Entwicklungsrechner: Paket aus dem Arbeitsstand bauen (nfpm-Container), auf der VM installieren, testen |
| `ci.sh` | CI-Job auf dem Runner mit Label `zfs`: Paket bauen (nfpm), installieren, testen |

Fälle: `replication` (Dateisystem mit Kind, Volume, raw-verschlüsselt), `engine_internal`, `rotation`,
`refquota`, `rollback`, `broken_chain`, `orphans`, `local_mode`, `bandwidth_lock`, `checkmk`.

## Test-VM einrichten
Eine **VM** (kein LXC-Container: der teilt das ZFS-Modul des Hosts), Debian 13, zwei leere Platten
(je 8 GB reichen), keine wichtigen Daten. Als root:
```
# ZFS (contrib) und Werkzeuge
sed -i '/^Components:/{/contrib/!s/$/ contrib/}' /etc/apt/sources.list.d/debian.sources
apt update && apt install -y linux-headers-amd64 zfs-dkms zfsutils-linux zfs-auto-snapshot pv git curl
# bashclub-Paketquellen release und testing (Abhängigkeit bashclub-checkzfs)
wget -qO- https://apt.bashclub.org/gpg/bashclub.pub | gpg --dearmor > /usr/share/keyrings/bashclub-archive-keyring.gpg
for r in release testing; do cat > /etc/apt/sources.list.d/bashclub-$r.sources << EOT
Types: deb
URIs: https://apt.bashclub.org/$r
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: main
Signed-By: /usr/share/keyrings/bashclub-archive-keyring.gpg
EOT
done
apt update && apt install -y bashclub-zsync
# zfs-auto-snapshot nicht zeitgesteuert laufen lassen (die Tests erzeugen Snapshots gezielt)
sed -i 's/^\([^#].*zfs-auto-snapshot.*\)$/# zsync-ci: \1/' /etc/cron.d/zfs-auto-snapshot
chmod -x /etc/cron.{hourly,daily,weekly,monthly}/zfs-auto-snapshot
# ssh auf localhost für source=root@localhost
test -f /root/.ssh/id_ed25519 || ssh-keygen -q -t ed25519 -N '' -f /root/.ssh/id_ed25519
echo "from=\"127.0.0.1,::1\" $(cat /root/.ssh/id_ed25519.pub)" >> /root/.ssh/authorized_keys
ssh -o StrictHostKeyChecking=accept-new root@localhost true
ssh -o StrictHostKeyChecking=accept-new root@127.0.0.1 true
```
Danach `/etc/zsync-ci.conf` mit den beiden Testplatten (`ls -l /dev/disk/by-id/`), nur diese und Pools mit
Präfix `zci-` werden angefasst:
```
ZCI_DISK_SRC=/dev/disk/by-id/<platte-1>
ZCI_DISK_DST=/dev/disk/by-id/<platte-2>
ZCI_POOL_SRC=zci-src
ZCI_POOL_DST=zci-dst
```
`run.sh` prüft vor jedem Lauf, dass beide Platten per by-id existieren und zu keinem fremden Pool gehören.

## Runner
forgejo-runner im Host-Modus (die Tests brauchen das ZFS-Modul der VM) mit Label `zfs`, ein Job gleichzeitig,
läuft als root; dazu `nfpm` für den Paketbau. Registrierung: Token der Organisation in `/root/forgejo-runner-token`,
dann `/root/forgejo-runner-register.sh`.

Snapshots legen die Tests mit je einer Sekunde Abstand an: `creation` ist sekundengenau, und zsync sortiert
danach (Gleichstand: #30).
