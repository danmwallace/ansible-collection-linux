# danmwallace.linux.mikrotik_backup

Pulls nightly backup files from [MikroTik RouterOS](https://mikrotik.com/software)
devices over SFTP, using a dedicated SSH identity and pinned host keys. The role
only **collects**: an on-device scheduler must already write
`<identity>-<YYYYMMDD>.backup` (encrypted binary backup) and
`<identity>-<YYYYMMDD>.rsc` (`/export`) into a directory on the device, such as
`disk1/backups` on a USB disk. A generated script
(`/usr/local/libexec/mikrotik-backup/run`), driven by a systemd timer, fetches
**today's** pair from each device into `/var/lib/mikrotik-backup/<name>/`
(directories `0700`, files `0600`) and prunes old local copies.

Files land in a local directory that is meant to be picked up by
[`danmwallace.linux.restic_backup`](../restic_backup/README.md), which ships
them to the NAS with snapshot history. A device failure never stops the other
devices from being pulled, but it does skip the Uptime Kuma push and makes the
service exit non-zero.

## Requirements

- Ansible >= 2.16
- A Fedora (or other RHEL-family) target with systemd; the role installs
  `openssh-clients` via the `package` module
- SSH reachability from the target to each device (firewall and
  `/ip service set ssh address=...` must allow it)
- On each RouterOS device, a read-only backup account that authorises this
  host's public key — see [Device bootstrap](#device-bootstrap)
- An on-device script and scheduler that write the backup pair before the
  pull runs (default 00:30 on the device, pull at 01:00)

## Role Variables

| Variable | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `mikrotik_backup_devices` | list of dict | yes | `[]` | RouterOS devices to pull from. Each entry: `name` (local subdirectory and SSH alias suffix `mikrotik-backup-<name>`, required), `host` (hostname or IP, required), `host_key` (pinned host key as `"<type> <base64>"` without a hostname, required), `identity` (file prefix written by the device job, required), `user` (optional, falls back to `mikrotik_backup_default_user`), `port` (optional, falls back to `mikrotik_backup_default_port`), `remote_dir` (optional, falls back to `mikrotik_backup_default_remote_dir`). `name` and `identity` may only contain letters, digits, `.`, `_` and `-`. |
| `mikrotik_backup_default_user` | str | no | `backup` | Device user for entries without a `user` key. |
| `mikrotik_backup_default_port` | int | no | `22` | SSH port for entries without a `port` key. |
| `mikrotik_backup_default_remote_dir` | str | no | `disk1/backups` | Remote directory for entries without a `remote_dir` key. Relative to the RouterOS file root. |
| `mikrotik_backup_dir` | str | no | `/var/lib/mikrotik-backup` | Local directory receiving one subdirectory per device. Add it to `restic_backup_paths`. |
| `mikrotik_backup_retention_days` | int | no | `14` | Local copies older than this many days are deleted, per device, after that device's pull succeeds. |
| `mikrotik_backup_allow_previous_day` | bool | no | `false` | When today's pair is missing or incomplete, accept yesterday's pair instead of failing the device. |
| `mikrotik_backup_ssh_key_path` | str | no | `/etc/mikrotik-backup/id_ed25519` | Private key path for the dedicated SSH identity. The public key is written next to it with a `.pub` suffix. |
| `mikrotik_backup_verify_connectivity` | bool | no | `true` | During the role run, open an SFTP session to every device and fail with the public key to authorise if any cannot be reached. |
| `mikrotik_backup_schedule` | str | no | `"*-*-* 01:00:00"` | systemd `OnCalendar` expression for the timer. |
| `mikrotik_backup_randomized_delay` | str | no | `5m` | systemd `RandomizedDelaySec` for the timer. |
| `mikrotik_backup_kuma_push_url` | str | no | `""` | Uptime Kuma push URL, without a query string. Pinged only after every device succeeded. Empty disables it. **Supply from vault.** |

## Dependencies

None declared in `meta/main.yml`. In practice the pulled directory is only
off-host once `danmwallace.linux.restic_backup` backs it up; the two roles are
independent and ordered by their timers.

## Example Playbook

```yaml
- hosts: util01
  become: true
  roles:
    - role: danmwallace.linux.mikrotik_backup
    - role: danmwallace.linux.restic_backup
```

With `host_vars/util01.yml`:

```yaml
mikrotik_backup_devices:
  - name: home-01
    host: 10.10.99.1
    host_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI..."
    identity: home-01
  - name: home-sw01
    host: 10.10.99.2
    host_key: "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ..."
    identity: home-sw01
    remote_dir: backups  # no USB disk: the device job writes to flash
mikrotik_backup_kuma_push_url: "{{ vault_mikrotik_backup_kuma_push_url }}"

restic_backup_paths:
  - /var/lib/mikrotik-backup
```

## What the Role Does

1. Asserts `mikrotik_backup_devices` is non-empty, has unique names, uses only
   safe characters in `name`, `identity` and `remote_dir`, and that every
   `host_key` looks like `"<type> <base64>"`.
2. Installs `openssh-clients` (for `sftp`).
3. Creates `/etc/mikrotik-backup`, the key directory,
   `/usr/local/libexec/mikrotik-backup` and `mikrotik_backup_dir` (mode
   `0700`), then one `0700` subdirectory per device.
4. Generates a dedicated ed25519 SSH keypair at `mikrotik_backup_ssh_key_path`
   if it doesn't already exist.
5. Pins each device's host key into `/etc/mikrotik-backup/known_hosts` under
   the alias `mikrotik-backup-<name>`.
6. Writes one `Host mikrotik-backup-<name>` alias per device to
   `/etc/ssh/ssh_config.d/60-mikrotik-backup.conf`, binding the dedicated key
   with `IdentitiesOnly yes`, `BatchMode yes`, the pinned host key file and
   `StrictHostKeyChecking yes`.
7. Writes `/etc/mikrotik-backup/mikrotik-backup.env` (mode `0600`) with
   `MIKROTIK_BACKUP_KUMA_PUSH_URL`.
8. Writes the pull script to `/usr/local/libexec/mikrotik-backup/run` (mode
   `0700`) — see [What the pull script does](#what-the-pull-script-does).
9. When `mikrotik_backup_verify_connectivity` is true, opens an SFTP session to
   every device and `cd`s into its remote directory (read-only, never changes
   anything). If any device fails, the role reads the public key and fails with
   the failing devices, their SSH error and the key to authorise.
10. Installs and enables `mikrotik-backup.service` (oneshot) and
    `mikrotik-backup.timer`, reloading systemd first via the `Reload systemd`
    handler.

### What the pull script does

1. Sets `umask 077` and takes an exclusive `flock` so overlapping runs bail out.
2. Reads today's date once (`date +%Y%m%d`, host local time) so every device is
   checked against the same day even if the run crosses midnight.
3. For each device, in order:
   1. Removes leftover `.partial` files.
   2. Runs one `sftp -b <batchfile>` session that requests
      `<remote_dir>/<identity>-<today>.backup` and `.rsc` by exact name into
      hidden `.partial` files.
   3. If the SSH session itself fails, logs the error and the public key path
      to authorise, and marks the device failed.
   4. If either file is missing or empty, logs which one, discards the partials
      and — only when `mikrotik_backup_allow_previous_day` is true — retries with
      yesterday's date. Otherwise the device is marked failed.
   5. On success, sets both files to `0600` and renames them into place
      atomically, then deletes that device's `*.backup` / `*.rsc` copies older
      than `mikrotik_backup_retention_days`.
4. If any device failed, logs `failed devices: ...` to stderr and exits `1`
   without pinging Uptime Kuma.
5. Otherwise, if `MIKROTIK_BACKUP_KUMA_PUSH_URL` is set, pings it with
   `?status=up&msg=OK`.

All output goes to the journal: `journalctl -u mikrotik-backup.service`.

## Device bootstrap

On each RouterOS device (in safe mode), create a restricted backup account and
authorise the key this role generated. Copy
`/etc/mikrotik-backup/id_ed25519.pub` from the target to the device first
(for example with Winbox's Files window), then:

```routeros
/user group add name=backup policy=ssh,ftp,read comment="mikrotik_backup SFTP pull"
/user add name=backup group=backup address=192.168.70.11/32 password=<long random string>
/user ssh-keys import public-key-file=id_ed25519.pub user=backup
/ip service set ssh address=<existing>,192.168.70.11/32
```

Get the device's host key for `host_key` from a trusted network and strip the
hostname:

```bash
ssh-keyscan -t ed25519 10.10.99.1 2>/dev/null | cut -d' ' -f2,3
```

If the device only offers RSA (RouterOS's default host key type), use
`-t rsa`, or switch it with `/ip ssh set host-key-type=ed25519` before
collecting the key.

## Notes

- **Timer ordering.** The chain is device job at 00:30 → this pull at 01:00
  (plus up to `mikrotik_backup_randomized_delay`) → `restic_backup` at 01:30
  (plus its own delay). Keep the device clocks on NTP and in the same timezone
  as the target: the filename date is computed by the device, the expected date
  by the target.
- **Add the directory to restic.** Nothing leaves the host until
  `mikrotik_backup_dir` is in `restic_backup_paths`. Local retention is short
  on purpose; restic holds the history.
- **RouterOS SFTP behaviour.** Paths are relative to the RouterOS file root
  (`disk1/backups`, not `/disk1/backups`). Directory listings come back in no
  useful order, so the script never parses `ls`; it asks for exact filenames.
  The account needs the `ftp` policy for SFTP file access, which on RouterOS
  also allows writing and deleting files — the address restriction and key-only
  login are what keep that account contained.
- **Freshness is strict by default.** If the device job did not run today (USB
  unmounted, clock wrong), the device fails and Kuma goes red, even if older
  files exist. `mikrotik_backup_allow_previous_day: true` tolerates one missed
  night.
- **Pruning waits for success.** A device that keeps failing keeps its last
  local copies instead of aging them all out.
- **Removing a device** drops its SSH alias and pull, but its pinned entry in
  `/etc/mikrotik-backup/known_hosts` and its local directory stay until removed
  by hand.
- `mikrotik_backup_verify_connectivity: false` lets the role converge before a
  device is bootstrapped; the nightly run will fail (and log the key path) until
  it is.

## License

MIT
