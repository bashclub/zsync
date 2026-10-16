# Change log

## [Unreleased]

### Added
- package `bashclub-zsync-source` with `bashclub-zsync-remote`, a forced command for `authorized_keys` on the source (`restrict,from=…,command=…`): runs only the commands of bashclub-zsync, remote-snapshot-manager and checkzfs without a shell, destroys only snapshots and bookmarks, writes only into the checkmk spool, logs denied commands to syslog; README with a copyable block (#39)
- exit code rule: a failing dataset never stops the run, errors are collected and returned at the end; README section *Exit code* (#42)
- systemd timers per configuration (`bashclub-zsync@<name>.timer` / `.service`) and the tool `bashclub-zsync-timer` (`enable` with schedule, user and log file as drop-ins, `disable`, `list`, `migrate [--dry-run]` for cron jobs incl. `/etc/cron.{hourly,daily,weekly,monthly}`, keeping schedule, user and log file); the package only shows a hint if cron jobs exist; the Checkmk check takes the interval from the timer (#12)
- operation without root on the backup server and the source with delegated ZFS permissions (`zfs allow`): replicas are received without mounting (`zfs receive -u`), the package creates the group `bashclub-zsync` and makes `/var/log/bashclub-zsync`, `/var/lib/bashclub-zsync` and `/run/bashclub-zsync` (tmpfiles.d) writable for it, missing write access to the run status or the checkmk spool only logs a warning; README with copyable commands for user, permissions and source (#11)
- setting `transfer_resume`: transfers are received with `zfs receive -s`, an interrupted initial replication or delta continues in the next run (`zfs send -t`), also raw encrypted; a partial state that cannot be resumed (snapshot deleted on the source, or `transfer_resume=0`) is discarded; existing configurations without the setting keep `0`, new configurations get `1` (#8)
- setting `source_hold`: holds on the base and the snapshots still to be sent while a dataset is replicated, released at its end or at the end of the run (also on errors), holds of an aborted run are released by the next one; existing configurations without the setting keep `0`, new configurations get `1` (#6)
- setting `source_bookmark`: a bookmark of the newest replicated snapshot on the source (per backup host and target), the replication continues from it if the rotation deleted the snapshot, also raw encrypted; existing configurations without the setting keep `0`, new configurations get `1` (#22)
- local mode `source=local`: replication between pools of the same host without ssh; `remote-snapshot-manager` and checkzfs run locally, datasets in the target are never selected (#26)
- setting `bandwidth_limit` (e.g. `10m`): limits the transfer with `pv` on the backup server, without `pv` the transfer runs without limit and a warning is logged; `pv` is suggested by the package (#9)
- settings `target_rollback` (default `0` = off) and `target_rollback_max` (default `24`): roll the replica back to the newest common snapshot if its newest snapshot does not exist on the source anymore, and continue from there (#5)
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