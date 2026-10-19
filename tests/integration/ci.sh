#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# CI-Job auf dem Runner mit Label zfs (Test-VM): Paket aus dem ausgecheckten Stand bauen, installieren, testen.
# Aufruf im Wurzelverzeichnis des Repos: tests/integration/ci.sh
set -euo pipefail
version=$(git describe --tags --match 'v[0-9]*' --long | sed -E 's/^v//; s/-([0-9]+)-g([0-9a-f]+)$/+git\1.\2/')
rm -rf dist && mkdir dist
for f in nfpm.yaml nfpm-source.yaml nfpm-restore.yaml; do VERSION=$version nfpm pkg -f $f -p deb -t dist/ > /dev/null; done
# Sperre vor dem Installieren: ein anderer Lauf auf der VM (remote.sh) testet sonst mit diesen Paketen
exec 9> /run/lock/zsync-ci.lock
flock 9
export ZCI_LOCK_HELD=1
dpkg -i dist/*.deb > /dev/null
# Tests ohne ZFS: command=-Wrapper und Checkmk-Check
tests/remote.sh | tail -1
tests/restore-remote.sh | tail -1
tests/schedule.sh | tail -1
tests/checkmk.sh | tail -1
tests/integration/run.sh
