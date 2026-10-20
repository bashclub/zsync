#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Baut das Paket aus dem Arbeitsstand (nfpm-Container wie in der CI), installiert es auf der Test-VM
# und führt dort die Integrationstests aus.
# Aufruf: tests/integration/remote.sh <root@host> [fall ...]
set -eu
host=$1; shift
repo=$(cd "$(dirname "$0")/../.." && pwd)
version=$(git -C "$repo" describe --tags --match 'v[0-9]*' --long | sed -E 's/^v//; s/-([0-9]+)-g([0-9a-f]+)$/+git\1.\2/')
git -C "$repo" diff --quiet HEAD || version="$version.dirty"
dist=$(mktemp -d); trap 'rm -rf "$dist"' EXIT
for f in nfpm.yaml nfpm-source.yaml nfpm-restore.yaml; do
  podman run --rm -e VERSION="$version" -v "$repo:/src:ro,Z" -v "$dist:/dist:Z" -w /src docker.io/goreleaser/nfpm \
    pkg -f $f -p deb -t /dist/ > /dev/null
done
ssh "$host" 'rm -rf /root/zsync-ci && mkdir -p /root/zsync-ci'
scp -q "$dist"/*.deb "$host":/root/zsync-ci/
scp -qr "$repo/tests/integration" "$host":/root/zsync-ci/
# 1.0.19 für die Kaskade beim Update (case_cascade_upgrade)
ssh "$host" mkdir -p /root/zsync-ci/integration/legacy
git -C "$repo" show v1.0.19:bashclub-zsync/usr/bin/bashclub-zsync | ssh "$host" "cat > /root/zsync-ci/integration/legacy/bashclub-zsync-1.0.19 && chmod +x /root/zsync-ci/integration/legacy/bashclub-zsync-1.0.19"
# Sperre vor dem Installieren: ein laufender CI-Job testet sonst mit diesen Paketen
ssh "$host" "exec 9> /run/lock/zsync-ci.lock; flock 9; export ZCI_LOCK_HELD=1; dpkg -i /root/zsync-ci/*.deb > /dev/null && /root/zsync-ci/integration/run.sh $*"
