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

Nur ein Lauf zur Zeit: `run.sh` nimmt die Sperre `/run/lock/zsync-ci.lock`. `ci.sh` und `remote.sh` nehmen sie schon vor dem Installieren der Pakete und reichen sie mit `ZCI_LOCK_HELD=1` weiter, damit kein Lauf mit den Paketen eines anderen Branches testet.

Fälle: `replication` (Dateisystem mit Kind, Volume, raw-verschlüsselt), `engine_internal`, `rotation`,
`refquota`, `rollback` (neue Kette per Klon, alter Zweig, verschlüsselt, Kind-Datasets, Entscheidung), `broken_chain`, `orphans`, `local_mode`, `bandwidth_lock`, `bookmark` (Anfügen aus dem Bookmark, auch raw-verschlüsselt), `hold` (Basis und geplante Snapshots während des
Deltas nicht löschbar), `deleted_during` (Snapshot während der Replikation gelöscht), `resume` (abgebrochene Erstreplikation und Delta
fortgesetzt, Teilstand verworfen), `unprivileged` (Betrieb ohne root), `restricted` (Quelle mit `command=bashclub-zsync-remote`), `job_user` (Benutzer pro Replikationsjob über den Verwaltungsbenutzer), `setup` (geführtes Setup als root, als Verwaltungsbenutzer und lokal, Fragen), `disk` (Wechseldatenträger mit und ohne LUKS, Anschließen mit `zsync-autorun`), `timer` (systemd-Timer, Migration von
Cronjobs), `same_second` (zwei Labels
in derselben Sekunde), `cleanup_blocked` (Rotation am Ziel blockiert: Warnung, Exit 0), `source_unreachable` (sofort Exit 1), `zas_missing` (Warnung ohne zfs-auto-snapshot auf der Quelle),
`maintenance` (Entscheidungen: verwaistes Replikat, gerissene Kette, Altlast), `checkmk`,
`restore_access` (Pull-Benutzer und Push-Key, ausgegebene Befehle kopiert ausgeführt), `restore_dataset` (Kette unter neuem
Namen und an der alten Stelle, `--force`, `--dry-run`, Replikation danach inkrementell), `restore_reattach` (nach Rollback
auf der Quelle, `--rollback`), `restore_pull_push` (Volume und raw-verschlüsselt per Pull, Push mit Statuskopie),
`restore_resume` (Abbruch per `stop`, Holds, Fortsetzen per Resume-Token, kein zweiter Job auf dasselbe Ziel),
`restore_mount` (Clone eines Dateisystems und einer Partition im Volume, Rotation behält den Snapshot, cleanup),
`restore_server` (Full Restore mit `--map`, `--exclude`, `--snapshot`, fehlender Pool, Wizard über ein Pseudo-Terminal),
`hooks` (pre-run und post-run global und je Config, Umgebung, Fehler, nicht vertrauenswürdige Datei, Zeitlimit),
`result_busy` (`--result`, `busy` mit `--wait`, Inhibitor während des Laufs, unterbrochener Transfer im Ergebnis).

## Test-VM einrichten
Eine **VM** (kein LXC-Container: der teilt das ZFS-Modul des Hosts), Debian 13, zwei leere Platten
(je 8 GB reichen), keine wichtigen Daten. Als root:
```
# ZFS (contrib) und Werkzeuge
sed -i '/^Components:/{/contrib/!s/$/ contrib/}' /etc/apt/sources.list.d/debian.sources
apt update && apt install -y linux-headers-amd64 zfs-dkms zfsutils-linux zfs-auto-snapshot pv git curl
# bashclub-Paketquellen release und testing (bashclub-checkzfs für die Tests mit monitor_engine=checkzfs)
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
# OpenSSH ab 9.8 sperrt Adressen nach fehlgeschlagenen Anmeldungen; die Tests prüfen absichtlich abgewiesene Zugriffe
echo "PerSourcePenaltyExemptList 127.0.0.1,::1" > /etc/ssh/sshd_config.d/zsync-ci.conf
sshd -t && systemctl reload ssh
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
forgejo-runner (ab v13, ohne `register`) im Host-Modus, weil die Tests das ZFS-Modul der VM brauchen; ein Job
gleichzeitig, läuft als root, dazu `nfpm` für den Paketbau. Die Verbindung steht in
`/var/lib/forgejo-runner/config.yml` unter `server.connections` (url, uuid, Label `zfs:host`), das Token als
systemd-Credential (`LoadCredential=token:/etc/forgejo-runner/token`, Datei mit Rechten 600) per
`token_url: file:$CREDENTIALS_DIRECTORY/token`. Der Workflow-Job `integration` holt den Stand per git, baut das
Paket und führt `ci.sh` aus.

Snapshots legen die Tests mit je einer Sekunde Abstand an, wie in der Praxis; Snapshots in derselben Sekunde
prüft `same_second`.
