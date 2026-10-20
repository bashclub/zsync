# Change log

## [Unreleased]

### Changed
- a broken chain (no common snapshot with the source) or a replica without snapshots no longer has to block the replication: with the new setting `broken_rename=1` (new configurations; existing ones keep 0 and wait for the admin as before) the old replica stays complete as `<replica>.zsync-branch-<date>` (a case for `bashclub-zsync-maintenance`, keep or delete), the dataset is replicated again in the same run and its children (replicas of their own) go back below it; without enough space on the target nothing changes and the monitoring reports CRIT. `bashclub-zsync-maintenance` renames a broken replica the same way (`.zsync-branch-<date>`, children back after the next run) instead of `.broken-<date>`; the log names the maintenance tool instead of a manual `zfs rename` (#158)
- cascade (a second backup server or a removable disk replicates the replicas of a backup server): old chains after a rollback on the source (`<replica>.zsync-branch-<date>`) are not selected, the second stage keeps its own old chain; the snapshot engine `internal` creates no snapshots on source datasets that are replicas of bashclub-zsync (the target is marked with `bashclub:zsync-target`, inherited by the replicas) and warns, because the first stage would see them as a rollback; integration cases `cascade`, `cascade_local`, `cascade_upgrade` (also with 1.0.19 on either stage) (#147)
- the Checkmk check of the runs comes as service `<checkzfs_prefix> <config>` in the spool file of checkzfs (`<checkzfs_spool_maxage>_<checkzfs_prefix>`, one file per run with the checkzfs services) instead of a local check: written at the end of each run (also after errors), every 5 minutes during a run (watchdog, on the source only when the state changes) and with `-s`, locally or on the source like checkzfs (`checkzfs_spool`), so the services stay visible while the backup server is switched off between the runs; the package no longer links the local check and removes the link of the testing versions (#85)
- documentation: the handbook (https://docs.bashclub.org/s/bashclub-zsync, source `docs/handbuch`) replaces `DOCUMENTATION_DE.md`; a German overview is in `README.de.md`; `notizen-luks` removed, `bashclub-zsync-disk` prepares removable disks
- license: GPL-3.0-or-later instead of MIT from 2.0.0 on (both packages, SPDX headers in all files, DEP-5 copyright file `/usr/share/doc/<package>/copyright` with the MIT notice of the versions up to 1.0.19); contributions with Developer Certificate of Origin (`Signed-off-by`, CONTRIBUTING.md) (#72)

### Added
- Built-in check of the snapshots per dataset, setting `monitor_engine=checkzfs|internal` (#63, #135).
  - **Same services:** `internal` writes the services `<checkzfs_prefix>:<source>:<port>#<dataset>` with the thresholds `checkzfs_max_age` and `checkzfs_max_snapshot_count`, so switching needs no new service discovery. One line per dataset with the worse state of source and replica (checkzfs wrote two lines under the same name).
  - **Only the replicated datasets** are read: their snapshots on the source (in blocks of 100, forms the job users may run) and the target. Age and rollback count only snapshots of `snapshot_filter` and the label of zsync, as in the replication; bookmarks do not disturb it (checkzfs 4.14 stops at bookmarks: `'NoneType' object has no attribute 'add_snapshot'`).
  - **States:** age of the newest common snapshot (`checkzfs_max_age`); time since the last successful replication of the dataset with the thresholds of the age check of the configuration (`replication_age`, a dataset that is not replicated while the runs succeed); snapshots on the source (`checkzfs_max_snapshot_count`, now for the source only); snapshots on the replica against the expected count (`label=N` keeps N, other labels the count on the source, at least `min_keep`; WARN from +5, CRIT from +10); newest replica snapshot of the filter missing on the source (WARN); no common snapshot (CRIT, checkzfs left such a replica out); `com.sun:auto-snapshot` of the replica not `false` (CRIT); no replica yet (WARN). The text names both counts, e.g. `source 52, replica 61 (expected 58)`.
  - **Metrics:** `file_count` is the number of snapshots of the replica (checkzfs counted source and replica together, graphs show a step when switching); new `source_count` and `replication_age`.
  - **Excluded datasets** (deselected below a selected one, e.g. `bashclub:zsync=false`) are listed in the service of the configuration and by `-s`, without services of their own (state `excluded` in `<config>.datasets`).
  - **`-s`** shows a table for people: state, dataset, common snapshot, age, last replication, counts, text.
  - **Defaults:** configurations without the setting keep checkzfs if it is installed, otherwise `internal` (before: no services per dataset and a warning). New configurations get `internal`. `monitor_engine=checkzfs` without checkzfs falls back to `internal` with a warning.
  - **Package:** `bashclub-checkzfs` is recommended instead of required, so `bashclub-zsync` can also be installed where there is no checkzfs package (Ubuntu); apt keeps it on existing installations.
  - The Checkmk check offers `--age-limits --config <file>`, the thresholds of the age check for the internal check.
- `bashclub-zsync-maintenance` (#111):
  - **Overview first:** datasets below a case count with it; the number of cases per type is shown.
  - **Then:** all later, decide per case type (preview of the whole group with commands, what `destroy` deletes and the space used, then a confirmation) or one by one. `--decide-type <type> <option>` does the same for scripts.
  - **One query for all cases:** `bashclub-zsync` marks each case on the replica (`bashclub:zsync-case`, written only when a case arises or changes) and removes the marking when it is resolved. The tool reads all cases with one query and reads snapshots only for a decision, so it stays fast with many snapshots.
- Interface for other tools, e.g. Miyagi (#99).
  - `bashclub-zsync -c <config> --result`: the last run as `key=value` (`format=1`), with state counts, open decisions and interrupted transfers (`resume.<dataset>`), read only from the run status.
  - `bashclub-zsync busy [--wait [<seconds>]]`: is a replication, maintenance action, restore job or removable disk run active.
  - A systemd inhibitor against shutdown and sleep while a run or a restore job is active.
- Hooks before and after a run (#100).
  - Executable files in `/etc/bashclub/hooks.d/{pre-run,post-run}/` (all configurations) and `/etc/bashclub/hooks.d/<config>/{pre-run,post-run}/`, run inside the lock in lexical order; only files and folders of root that only root may write.
  - The environment has the configuration, target, source, exit code and duration; the output goes into the log.
  - A failing pre-run hook skips the run. A failing post-run hook only logs a warning.
  - Setting `hook_timeout` (600 s). Without the folders nothing changes.
- `trigger=external` for configurations started by another tool, e.g. Miyagi (#98).
  - There is no timer, `bashclub-zsync-timer migrate` takes no cron job into such a configuration, and the age check learns the interval from the previous runs.
  - `bashclub-zsync-setup --external` creates the configuration once with job users and prints the command for each run (`runuser -u zsync-<name> -- bashclub-zsync -c <config>`), so the tool no longer writes the configuration on every run.
- Restore from a removable disk on any host (#137): `bashclub-zsync-restore --root <dataset>` works without a configuration of `bashclub-zsync` (`list`, `show`, `dataset`, `reattach`, `server`, `mount`), e.g. on a new Proxmox after the loss of the backup server. On a pool imported read-only the restore sets no holds (noted in the log), `mount` mounts a file system snapshot directly (`mount -t zfs -o ro`, listed by `mounts`, removed by `cleanup`) and names the way for a volume (`dataset --as` into a writable pool). The final check accepts a `logicalreferenced` within 1 % or 1 MiB as OK with a note: metadata grows with the `ashift` of the pool, so a restore between pools of different `ashift` no longer ends as failed.
- `bashclub-zsync-restore server`: full restore of all replicas of a configuration (#59).
  - Selection: `--pool`, `--exclude` and `--map <from>=<to>` (the longest wins); `--snapshot` gives one point in time for all.
  - Pool roots are never replaced, a missing pool stops the plan, existing datasets need `--force`.
  - At the end, a list of what to check (storage.cfg, guest configurations, boot loader, network).
  - Without parameters `bashclub-zsync-restore` asks step by step and prints the complete command before it runs it (#56).
- `bashclub-zsync-restore mount <replica>@<snapshot>`, `mounts`, `cleanup`: read-only clone on the backup server for single files (#60).
  - Volumes: partitions mounted read-only without journal replay, otherwise the device.
  - Encrypted replicas only with their key loaded.
  - While a clone exists, the rotation keeps its snapshot.
- `bashclub-zsync-restore list`, `show`, `dataset`, `reattach` (#58), plus restore jobs: `jobs`, `status [--follow]`, `start`, `stop`, `resume` and `run` (#62).
  - **All commands:** pull (`--from`), push (`--to`) or on the backup server itself.
  - **`list`, `show`:** replicas and their snapshot chains, compared with the system by GUID: common snapshot, missing there, only there.
  - **`dataset`:**
    - restores the complete chain up to a chosen snapshot, also recursively and under another name (`--as`);
    - sends encrypted datasets raw and sets the original properties of the source again (mountpoint and tag only at the original place);
    - never overwrites an existing dataset; with `--force` it renames it to `<name>.before-restore-<time>`.
  - **`reattach`:** sends only the snapshots missing after the common one, so the replication then continues without a full replication. Snapshots or changes on the system after the common one need `--rollback`.
  - **Restore jobs:**
    - Every command shows the plan with sizes (`--dry-run`: also the commands) and writes a job.
    - The job runs in the background (systemd unit `bashclub-zsync-restore@<job>`, without systemd `setsid`), with progress, rate and time left.
    - Each start plans again from the system: resume token, finished datasets are skipped, 3 retries.
    - The snapshots it sends are held during the restore. A `reattach` on the backup server waits for a running replication. No second job runs on the same datasets.
    - With push, the state is copied to the system.
    - At the end, a report per dataset (GUID chain, newest snapshot, no partial receive, `logicalreferenced`, properties, key status; `--scrub` optional); exit code 0 only if everything is OK.
- package `bashclub-zsync-restore`, recommended by `bashclub-zsync`: restore toolbox, first part access (#57). Pull: `access key` on the system to restore prints the command for the backup server, `access pull` there creates the restore user `zsync-restore-<configuration>`; its key works only from the address of the system and only runs `bashclub-zsync-restore-remote` (zfs list/get/send and holds with a restore tag below the target of the configuration, no shell), ZFS allows it only `send,hold,release` there. Push: `access push <host>` creates a one-time key and prints the line for `/root/.ssh/authorized_keys` with `restrict`, `from=` and `expiry-time`, plus the command to remove it; `access test`, `access list`, `access remove`
- `bashclub-zsync -s [checkmk]`: runs checkzfs, refreshes both spool files and shows the state of a configuration (without `-c` of all configurations), without snapshots, replication, deletion or a change of the run status; exit code 0 OK, 1 WARN, 2 CRIT (#85)
- number of snapshots to keep on the backup server per label in `snapshot_filter` (`daily=30`): kept whatever happens on the source, so deleting snapshots on the source cannot shrink the backup; a label alone or `label=source` behaves as before, existing configurations are unchanged; `bashclub-zsync-setup` asks for it; `min_keep` is deprecated (#66)
- `bashclub-zsync-maintenance`: open decisions of all configurations (replicas without source, broken chains, snapshot leftovers of another name scheme), interactive with context, options, preview and confirmation, or `--list`/`--decide` for scripts; actions run only on the backup server under the lock of the configuration and are logged; the Checkmk check points to it (#67)
- `zfs-auto-snapshot` is recommended instead of required (`bashclub-zsync`: only needed for `source=local`; `bashclub-zsync-source`: recommended), with the engine `zas` a warning is logged if it is missing on the source (previously no snapshots and no message); the exit code is unchanged (#69)
- `bashclub-zsync-remote --label <label> --job-tag <tag>` (written by `bashclub-zsync-job-user add`, `bashclub-zsync-setup` and the README): the key of a job may only create and destroy the snapshots of its label, use its own hold tag and bookmark and run zfs-auto-snapshot only with its label, so a backup server that is taken over cannot destroy the other snapshots of the source; keys without these options behave as before (#71)
- original values of the source saved on each replica after every dataset (only when they changed): `mountpoint`, `canmount`, `com.sun:auto-snapshot`, `refquota` and the tag as `bashclub:zsync-source.<property>=<local|inherited|default|received>:<value>`, for a restore; README with commands to show and restore them (#54)
- job users of `bashclub-zsync-setup` (and the README for running without root) get no permissions for `mountpoint`, `canmount`, `setuid`, `exec` and `devices`, the target gets `mountpoint=none`: no replica of an unprivileged user is ever mounted by root; `zfs receive` skips these properties with "permission denied", their values are saved on the replica (#54)
- removable disks: `bashclub-zsync-disk list|create` prepares a disk (no mounted, used or system disk, serial number confirmation), GPT partition, optional LUKS2 with key file and passphrase (YubiKey), pool, udev rule for the UUID of this disk, configuration linked as `/etc/default/zsync-autorun@<label>` with `trigger=autorun`; `notizen-luks` corrected; `bashclub-zsync-setup --autorun` sets up the configuration of a removable disk (`trigger=autorun`, no timer, run as root by `zsync-autorun`, job user on the source with the key of root) (#14)
- guided setup `bashclub-zsync-setup` (interactive or with options and `--yes`): configuration with the defaults of new configurations and a systemd timer, job user `zsync-<name>` on the backup server with its own ssh-ed25519 key and permissions only on its target, job user on the source via the management user `zsync` or root (`bashclub-zsync-source`), optional tagging, connection test with the selected datasets, first run (#13)
- users per replication job on the source (package `bashclub-zsync-source`): `bashclub-zsync-job-user add|allow|remove|list` creates `zsync-<job>` with a root-owned key restricted to the address of the backup server and to `bashclub-zsync-remote`, ZFS permissions only on the datasets with the tag of the configuration (removed from all others); only `ssh-ed25519` keys; the package creates the management user `zsync` (if missing), which may only run `bashclub-zsync-job-user` with sudo; README with a copyable block (#43)
- package `bashclub-zsync-source` with `bashclub-zsync-remote`, a forced command for `authorized_keys` on the source (`restrict,from=…,command=…`): runs only the commands of bashclub-zsync, remote-snapshot-manager and checkzfs without a shell, destroys only snapshots and bookmarks, writes only into the checkmk spool, logs denied commands to syslog; README with a copyable block (#39)
- exit code rule: a failing dataset never stops the run, errors are collected and returned at the end; README section *Exit code* (#42)
- systemd timers per configuration (`bashclub-zsync@<name>.timer` / `.service`) from settings in the configuration: `trigger` (`cron` = also without the setting, unchanged; `systemd`; `autorun` for removable disks), `schedule` in cron format, `run_as`, `log_file`; the systemd generator `bashclub-zsync-generator` creates the timers, `bashclub-zsync-timer sync` activates changes, `enable`/`disable` write the configuration, `migrate [--dry-run]` takes over cron jobs incl. `/etc/cron.{hourly,daily,weekly,monthly}` (schedule, user and log file into the configuration), `list` shows trigger, schedule, user, timer, cron jobs and configurations used by `zsync-autorun@`; the package only shows a hint if cron jobs exist; the Checkmk check takes the interval from the timer and skips the age check for removable disks (#12, #44)
- operation without root on the backup server and the source with delegated ZFS permissions (`zfs allow`): replicas are received without mounting (`zfs receive -u`), the package creates the group `bashclub-zsync`, its users write the run status into their own folder below `/var/lib/bashclub-zsync` and `/run/bashclub-zsync` (sticky bit), missing write access to the run status or the checkmk spool only logs a warning; README with copyable commands for user, permissions and source (#11)
- setting `transfer_resume`: transfers are received with `zfs receive -s`, an interrupted initial replication or delta continues in the next run (`zfs send -t`), also raw encrypted; a partial state that cannot be resumed (snapshot deleted on the source, or `transfer_resume=0`) is discarded; existing configurations without the setting keep `0`, new configurations get `1` (#8)
- setting `source_hold`: holds on the base and the snapshots still to be sent while a dataset is replicated, released at its end or at the end of the run (also on errors), holds of an aborted run are released by the next one; existing configurations without the setting keep `0`, new configurations get `1` (#6)
- setting `source_bookmark`: a bookmark of the newest replicated snapshot on the source (per backup host and target), the replication continues from it if the rotation deleted the snapshot, also raw encrypted; existing configurations without the setting keep `0`, new configurations get `1` (#22)
- local mode `source=local`: replication between pools of the same host without ssh; `remote-snapshot-manager` and checkzfs run locally, datasets in the target are never selected (#26)
- setting `bandwidth_limit` (e.g. `10m`): limits the transfer with `pv` on the backup server, without `pv` the transfer runs without limit and a warning is logged; `pv` is suggested by the package (#9)
- rollback on the source (newest snapshots of a replica missing there): the replication continues on a new chain from the newest common snapshot (clone and promote, in the same run, also raw encrypted and without root), the old chain stays complete as `<replica>.zsync-branch-<date>`; nothing on the target is deleted, the Checkmk check warns until the admin keeps or deletes the old chain with `bashclub-zsync-maintenance`; the rotation keeps the snapshot the old chain starts from; replaces `target_rollback`/`target_rollback_max` of the testing versions (#5, #65)
- state per dataset for the log and the Checkmk check: no common snapshot with the source (cause: rotated out or dataset created again, CRIT), replica without snapshots (CRIT), chain at risk because the base is the oldest snapshot on the source (WARN), newest replica snapshot missing on the source (WARN), replica without source or no longer selected (WARN after one day, acknowledge with `bashclub:zsync-orphan=keep`), each with a copyable fix in the log (#21)
- the `refquota` of a filesystem on the target is raised to the value of the source (or removed, if the source has none) before each incremental replication, so a refquota raised on the source no longer makes the replication fail; it is never lowered, `quota` is not changed (#4)
- Checkmk local check `bashclub_zsync`, linked into the agent if it is installed (also later, via dpkg trigger): one service per configuration, detects a too old last successful run (interval learned from the previous runs, learning phase), failed and aborted runs, phases that take too long, transfers without progress, processes blocked in state D and skipped runs; opt-out with `/etc/bashclub/zsync-checkmk.disabled` (#15)
- run status for the monitoring in `/run/bashclub-zsync` and `/var/lib/bashclub-zsync` (#15)
- setting `monitor_max_age` for the age check of the monitoring (#15)
- setting `zfs_auto_snapshot_label_match`: with `strict` only snapshots in the name scheme of the snapshot engine belong to the label, leftovers of another engine or label are neither replicated nor used for deletion; existing configurations without the setting keep the previous behavior (`legacy`), new configurations get `strict` (#3)
- warning for snapshots that contain the label but do not match the name scheme of the snapshot engine, on the source and on the target (#3)
- warning and dataset state `cleanup_blocked` (Checkmk WARN) if the oldest source snapshot of an interval does not exist on the target, so no target snapshots of this interval are deleted; previously nothing was deleted silently and the target filled up. The exit code stays 0, the replication itself succeeded (#3, #42)
- a log file in a directory that no logrotate config mentions (e.g. on TrueNAS SCALE) is rotated by bashclub-zsync itself at 10 MiB, 4 compressed old logs are kept

### Fixed
- If the newest snapshot of a replica did not match the snapshot filter, nothing was sent, without a message: after switching the engine from `zas` to `internal` with `strict`, or (already in 1.0) after removing a label from `snapshot_filter` while the newest snapshot of a replica had it. The snapshots after this base are now taken first and then filtered (#121).
- The watchdog stops its `sleep` at the end of a run. It kept running for up to 5 minutes with the inherited file descriptors open: the output pipe of cron, or the lock of a calling `flock` (#119).
- `bashclub-zsync -s` as root for a configuration with `run_as` runs as this user: as root the source refused the key of root (checkzfs failed), and the spool file written by root could not be replaced by the next run of the user (sticky spool folder), so the monitoring stopped getting new values (#117).
- The target follows the source (`label` or `label=source`): when `min_keep` stops the deletion, the newest snapshots stay. Previously the deletion started with the newest snapshots older than the oldest source snapshot, so the oldest stayed and a gap remained (GitHub PR #3 by lgremme, #114).
- A run without any dataset selected on the source logs a warning instead of the bash error `substring expression < 0`; the Checkmk service of the configuration warns (`last run selected no dataset on the source`) (#114).
- `bashclub-zsync -s` did not run checkzfs (`run_checkzfs: command not found`), so its spool was not renewed and its services were missing from the output and the exit code (#106).
- The state of a run and the checkzfs services are in one spool file, `<maxage>_<checkzfs_prefix>` as before 2.0; the state service is named `<checkzfs_prefix> <config>`, so backup servers with different prefixes on one source stay apart. The watchdog writes the checkzfs services of the last run along, so they do not disappear during a run. The separate state files of the testing versions are removed once, on the source with `rm -f` of a spool file, now allowed in `bashclub-zsync-remote` (#106).
- The watchdog wrote locally even with the spool on the source: it now starts once the source has answered (#106).
- security: packages up to 1.0.19 created `/etc/bashclub` (configurations, run as root) and the doc folder with the owner of the build user (uid 995), which an update does not change; the package sets root as owner and removes write access of group and others (#80)
- security: `bashclub-zsync-setup`, `bashclub-zsync-timer`, the generator and `bashclub-zsync-disk` check every value before it goes into a configuration, a unit or a command on the source (host, port, datasets, tag, label, user, log file); settings are written in single quotes if needed, values with `'`, `\` or line breaks are refused (#53)
- security and log rotation: `/var/log/bashclub-zsync` belongs to root again (755, as in 1.0.19), so logrotate rotates it again (it skipped the folder while the group could write it); the run status is kept in one folder per user with the sticky bit on the base folders, root never writes into a folder another user may change, the Checkmk check keeps its own state in the folder of root, job users of `bashclub-zsync-setup` get their home in `/var/lib/bashclub-zsync-jobs`, the checkmk spool for job users gets the sticky bit; `bashclub-zsync-timer migrate <name>` takes over the cron jobs of one configuration (#52)
- security: the Checkmk check (root) no longer runs the configuration named in a status file and uses only numbers from the status files; it reads settings as text and accepts only a configuration of root that no one else may write (status files are writable for the group bashclub-zsync) (#51)
- `zsync-autorun` powers off the whole disk of the partition also for NVMe names (`nvme0n1p1`), and no longer stops before export and mail if the replication failed without checkzfs output or the power-off fails (#14)
- the socket of the shared ssh connection is named by its hash (`%C`) and kept in a private directory in `/tmp` for long home directories, so long host names or home directories no longer exceed the limit of a unix socket path (#13)
- the lock of a configuration is the configuration file itself: a lock file in `/run/lock` of another user was refused by the kernel (`protected_regular`), so runs failed after switching a configuration between root and `run_as` (#13, #52)
- a source that cannot be reached (or where `zfs get` fails) stops the run at once with an error and exit code 1; previously no dataset was replicated and the run ended with exit code 0 (#42)
- the checkzfs output for the spool on the source is sent over the ssh connection of the run instead of `scp` (#39)
- a snapshot deleted on the source during the replication (rotation without `source_hold`) is skipped with a warning and the next delta starts at the last received snapshot; previously this delta and all following deltas of the dataset failed (#7)
- snapshots are ordered by `createtxg` instead of `creation`: snapshots of different labels created in the same second were ordered ambiguously, so the initial replication could start with the newest of them and the deletion could use the wrong oldest snapshot (#30)
- only one run per configuration at a time: a second run with the same configuration is skipped with an error message instead of creating snapshots and replicating at the same time (#2)
- the checkzfs output is written to a temporary file of the run and renamed into the checkmk spool, so concurrent runs and the checkmk agent never see a partial or deleted file (#2)
- the snapshot label is not added to the snapshot filter a second time if it is already contained (#2)

### Changed
- the cron examples in the README (including TrueNAS) append to the log (`>>`), so a skipped run does not empty the log of the active run

## [v1.0.19] - 2026-10-15

### Added
- packages for Ubuntu 24.04 (noble) and 26.04 (resolute)
- installation instructions for TrueNAS SCALE
- bashclub-zsync finds remote-snapshot-manager and checkzfs in its own directory (manual installation)
- recommended packages cryptsetup and bsd-mailx for zsync-autorun

### Changed
- new configurations use the internal snapshot engine; existing configurations without this setting keep using zfs-auto-snapshot
- the version shown by `bashclub-zsync -h` is taken from the installed package
- packages are built with nfpm and published by Forgejo CI
- development moved to https://code.bashclub.org/bashclub/zsync

### Fixed
- zsync-autorun is installed executable
- zsync.conf.example is updated without a configuration file prompt

## [v1.0.6] - 2024-02-22

### Fixed
- fix scp command to move checkzfs output to spool dir on source host

## [v1.0.5] - 2024-02-22

### Fixed
- checkzfs_local parameter

## [v1.0.4] - 2024-02-22

### Added
- checkzfs_local parameter to leave --source parameter empty

### Fixed
- download link in README.md
- logrotate config

## [v1.0.3] - 2024-02-22

### Added
- sshport to checkzfs command
- checkzfs spool options to default config

## [v1.0.2] - 2024-02-21

### Fixed
- Fix checkzfs call and log message

## [v1.0.1] - 2024-02-11

### Added
- Dependency bashclub-checkzfs

## [v1.0.0] - 2024-02-07

Moved project from github.com

### Added
- pre/post-inst/rm scripts
- this changelog
- integrate checkzfs

### Changed
- start versioning with name v1.0.0