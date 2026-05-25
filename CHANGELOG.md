# Changelog

All notable changes to this collection will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this collection adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - TBD

### Added

- Initial release of `danmwallace.linux`.
- Roles migrated from the legacy `ansible-homelab-roles` repo:
  - `cloudflare_ssl` (formerly `ansible_ssl_cloudflare`) — issue/renew TLS certs via Cloudflare DNS challenge.
  - `cockpit` (formerly `ansible_common_cockpit`) — install and configure the Cockpit web admin UI.
  - `restic_restore` (formerly `ansible_restic_restore`) — restore data from a Restic repository.
  - `raspberry_pi_network_toolkit` — Raspberry Pi network diagnostic + service tooling.
