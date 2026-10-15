# Change log

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