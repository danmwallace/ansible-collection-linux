# Changelog

All notable changes to this collection will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this collection adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- `restic_backup`: no longer fails on image-based hosts (bootc,
  rpm-ostree). There `ansible_facts.pkg_mgr` is `atomic_container`, and the
  role's `package` tasks dispatched to the deprecated
  `community.general.atomic_container` module ("missing required arguments:
  backend, image"). The new `restic_backup_install_packages` (default:
  `false` when `pkg_mgr` is `atomic_container`, else `true`) skips the
  installs; the role then checks that `restic` (and `sqlite3` / `btrfs` when
  used) is on the `PATH` and fails naming what the OS image must provide.

## [1.8.0] - 2026-11-12

### Added

- `git_repo_sync`: one GitHub deploy key per repo, a clone through a
  role-owned ssh config (`~/.ssh/git-repo-sync.conf`, read via
  `core.sshCommand`), and a per-repo login service that either pulls
  (fast-forward only, skipped when the clone is dirty) or syncs (commit,
  fetch, rebase only when origin moved, push). It never forces: offline, a
  rebase/merge/cherry-pick in progress or an unmerged index is a quiet skip,
  and a conflict aborts the rebase, undoes the sync's own commit and sends a
  desktop notification. An optional timer (`interval`) syncs between logins,
  and per-repo `git_exclude` lines go into `.git/info/exclude`. The play
  stops with the `gh repo deploy-key add` commands when GitHub doesn't know a
  key yet. Covered by `tests/test-sync.sh` (16 cases) and a molecule
  scenario with a check-mode step and idempotence.
- `syncthing`: a user's Syncthing paired with an always-on hub (a NAS, say),
  both sides configured through the REST API: the hub at a fixed address,
  global discovery and relays off, each folder shared with the hub with a
  managed `.stignore` block. It reads before it writes, never moves an
  existing folder, refuses overlapping folders, reports changes in check
  mode, and keeps every API key out of the output at any verbosity
  (`tests/check-verbose-log.sh`). A CA-signed hub certificate is validated
  normally; only a self-signed one is pinned. Molecule runs a laptop and a
  stand-in HTTPS hub and checks that a file actually syncs.

### Changed

- `community.general` floor raised from 8.0.0 to 8.1.0 for
  `community.general.git_config_info`, used by `git_repo_sync`.

## [1.7.0] - 2026-11-09

### Added

- `nm_bridge`: declare NetworkManager bridge connections and their ethernet or VLAN
  ports from one `nm_bridge_bridges` list. Profiles are persisted with `nmcli con
  modify` (via `community.general.nmcli`, so existing UUIDs survive) and applied
  with `nmcli device reapply`; the role never runs `con up` on an active bridge,
  because recreating the kernel device orphans every libvirt tap attached to it.
  Written to capture srv01's hand-made `virbr0` (static management address) and
  L2-only `vlan70` bridges after a DHCP lease failure on 2026-09-28 recreated
  `virbr0` and took two guests offline.
- `restic_backup`: a `restore` entry point (`include_role` with
  `tasks_from: restore`) restores the contents of a path in a named snapshot
  into a target directory through the role's own SSH alias and key. It skips
  the `security.selinux` xattr and relabels with `restorecon` instead of
  switching SELinux to permissive, can `chown -R` the result, and fails when
  restic fails or when the restore matched no files (restic exits 0 then).
  Covered by the molecule scenario: path mapping, a subset restore with an
  owner, an include that matches nothing, a missing snapshot, and a restore
  with no snapshot named.
- `restic_backup`: `restic_backup_timer_enabled` (default `true`). `false`
  installs the units with the timer disabled and stopped, for a reinstalled
  host whose home has not been restored yet.
- `restic_backup` README: "Restoring" and "Reinstalling a host".

## [1.6.1] - 2026-09-26

### Fixed

- `cloudflare_ssl`: `--check` against a host that does not yet have `certbot`
  installed failed at the renewal timer task (`Could not find the requested
  service certbot-renew.timer: host`), because check mode only reports the
  package install rather than performing it, so the unit file never exists for
  the timer task to enable. The timer task is now skipped in check mode when
  either package task would have newly installed. Real applies were unaffected
  (the package is actually installed first); found during the live rollout
  after 1.6.0.

## [1.6.0] - 2026-09-24

### Added

- `cloudflare_ssl`: `cloudflare_ssl_domains` requests names other than the inventory
  hostname (the first entry names the lineage), and `cloudflare_ssl_manage_renewal_timer`
  enables the packaged certbot renewal timer.
- `cockpit`: `cockpit_allowed_cidrs` opens TCP 9090 through firewalld with one rich rule
  per CIDR, empty by default; `cockpit_service_name`, `cockpit_cert_owner`,
  `cockpit_cert_group` and `cockpit_cert_mode`; `cockpit_remove_blanket_firewalld_service`
  disables the zone-wide `cockpit` firewalld service once `cockpit_allowed_cidrs` is set;
  `cockpit_firewalld_zone` (str, default `""` = the host's default zone) targets the rich
  rules and blanket-service removal at a specific zone, since a host whose interfaces are
  bound to a non-default zone otherwise gets rich rules in an unused zone while the real
  zone-wide allow survives.
- First molecule scenarios for both roles.

### Fixed

- `cloudflare_ssl`: install the `certbot` CLI package, which ships
  `certbot-renew.timer`. With only `python3-certbot` installed there was no timer, so
  certificates were issued once and never renewed — srv01's Cockpit certificate expired
  on 2026-08-02 as a result.
- `cockpit`: renewals are delivered by a `renewal-hooks/deploy` hook guarded on
  `RENEWED_LINEAGE` instead of a `renewal-hooks/post` hook that ran after every attempt;
  the legacy hook is removed. The role manages `cockpit.socket` instead of the static
  `cockpit.service`, and sets certificate ownership through variables rather than a
  Debian-only chown task.

## [1.5.0] - 2026-09-13

### Added

- `mikrotik_backup` role: nightly SFTP pull of on-device MikroTik RouterOS backup and
  export files, with Uptime Kuma monitoring.
- `libvirt_usb_reattach` role: udev rule per USB device (matched by serial) starts a
  oneshot unit that live detach/attaches the device to its libvirt domain when the
  domain's bus/device binding has gone stale after a replug or reset.
- `restic_backup`: `restic_backup_btrfs_snapshot_subvolumes` backs up from read-only
  btrfs snapshots mounted over the original paths in a private mount namespace.
- `restic_backup`: `restic_backup_skip_when_unreachable` exits 0 without a Kuma ping
  when the NAS cannot be reached, for roaming hosts.
- `restic_backup`: `restic_backup_require_ac_power` and `restic_backup_keep_hourly`.

### Fixed

- `restic_backup`: prune and check run at most once per day on the prune weekday, so
  hosts with more than one run a day no longer prune repeatedly.
- `restic_backup`: check mode on a host without the units no longer fails at the timer task.

## [1.4.0] - 2026-09-12

### Added

- `restic_backup` role: nightly restic backups of application data to an SFTP
  repository with Postgres, MariaDB and SQLite dumps, retention, weekly prune and
  integrity check, and an optional Uptime Kuma push ping. Initialises the repository
  on first run; the backup service never does, so a deleted repository fails loudly.

## [1.1.0] - 2026-05-28

### Changed

- Relicensed from GPL-2.0-or-later to MIT.
- Added `meta/argument_specs.yml` and regenerated role + collection READMEs to the
  standardized house style.
- Idempotency hardening across the roles.

### Known issues

- The collection lints under the `basic` profile. `raspberry_pi_network_toolkit`
  still carries `var-naming[no-role-prefix]` warnings; its production-profile
  cleanup is deferred (see `.ansible-lint`).

## [1.0.0] - 2026-05-01

### Added

- Initial release of `danmwallace.linux`.
- Roles migrated from the legacy `ansible-homelab-roles` repo:
  - `cloudflare_ssl` (formerly `ansible_ssl_cloudflare`) — issue/renew TLS certs via Cloudflare DNS challenge.
  - `cockpit` (formerly `ansible_common_cockpit`) — install and configure the Cockpit web admin UI.
  - `restic_restore` (formerly `ansible_restic_restore`) — restore data from a Restic repository.
  - `raspberry_pi_network_toolkit` — Raspberry Pi network diagnostic + service tooling.
