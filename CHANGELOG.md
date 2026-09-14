# Changelog

All notable changes to this collection will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this collection adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
