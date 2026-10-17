# Contributing

Contributions are welcome as issues and pull requests on https://code.bashclub.org/bashclub/zsync.

## License and Developer Certificate of Origin
bashclub-zsync is licensed under the GNU General Public License, version 3 or later (`GPL-3.0-or-later`). By
contributing you agree that your contribution is published under this license.

Every commit needs a `Signed-off-by` line (`git commit -s`), with which you certify the
[Developer Certificate of Origin 1.1](https://developercertificate.org/): you wrote the contribution or have the right
to submit it under the license of the project.

New files start with the license identifier:
~~~
# SPDX-License-Identifier: GPL-3.0-or-later
~~~

## Changes
- Existing installations keep running as before after an update: new behavior that could interrupt a replication
  only with a setting (see the `CHANGELOG.md` entries).
- Each change has a test: `tests/run.sh` (stubs, compare with `tests/compare.sh`), `tests/checkmk.sh`,
  `tests/remote.sh`, `tests/schedule.sh` and the ZFS integration tests in `tests/integration/`.
