# Changelog

All notable changes to this collection will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this collection adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
