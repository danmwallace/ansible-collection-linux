# danmwallace.linux.restic_backup

Runs nightly [Restic](https://restic.net/) backups of application data to an
SFTP repository on a NAS, over a dedicated SSH identity. Before each backup,
it dumps Postgres and MariaDB containers (via `podman exec`) and SQLite
databases (via the online `.backup` command) into
`/var/lib/restic-backup/dumps`, so live data directories never need to be
copied directly. The backup itself, retention (`restic forget`), and a
weekly prune + integrity check run from a generated script
(`/usr/local/libexec/restic-backup/run`) driven by a systemd timer.

The role initialises the repository on first run (`restic init`, only when
`restic cat config` returns exit code 10 — "does not exist"). The backup
service itself never initialises a repository, so if the repository
disappears out from under it, the next run fails loudly instead of quietly
starting a fresh, empty one.

## Requirements

- Ansible >= 2.16
- `community.general` (installed by the collection's `dependencies`, used
  transitively) and `ansible.posix`
- A Podman host if `restic_backup_postgres_dumps` or
  `restic_backup_mariadb_dumps` are used (dumps run via `podman exec`)
- Network reachability to `restic_backup_nas_host` over SSH/SFTP, and an
  account already provisioned there — see [NAS bootstrap](#nas-bootstrap)
- `restic` and `sqlite` are installed by the role itself (via the
  `package` module); no pre-installation needed

## Role Variables

| Variable | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `restic_backup_password` | str | yes | — | Repository encryption password. Letters and digits only. **Supply from vault.** |
| `restic_backup_nas_host` | str | yes | — | Hostname or IP of the SFTP server. |
| `restic_backup_nas_host_key` | str | yes | — | Pinned SSH host key of the SFTP server, as `"<type> <base64>"` without a hostname. |
| `restic_backup_nas_user` | str | no | `restic-{{ inventory_hostname }}` | Remote user this host authenticates as. |
| `restic_backup_nas_base_path` | str | no | `/mnt/ssd-mirror/backups/restic` | Remote directory containing one repository directory per host. |
| `restic_backup_repository` | str | no | `sftp:restic-backup-nas:{{ restic_backup_nas_base_path }}/{{ inventory_hostname }}` | restic repository URL. The host alias `restic-backup-nas` is defined by this role. |
| `restic_backup_ssh_key_path` | str | no | `/etc/restic-backup/id_ed25519` | Private key path for the dedicated SSH identity. The public key is written next to it with a `.pub` suffix. |
| `restic_backup_paths` | list of str | no | `[]` | Directories to back up. `/var/lib/restic-backup/dumps` is always added. |
| `restic_backup_excludes` | list of str | no | `[]` | restic exclude patterns, one per entry. |
| `restic_backup_postgres_dumps` | list of dict | no | `[]` | Postgres containers to dump with `pg_dumpall` before each backup. Each entry: `container` (Podman container name, required), `user` (Postgres superuser inside the container, required). |
| `restic_backup_mariadb_dumps` | list of dict | no | `[]` | MariaDB containers to dump with `mariadb-dump`. Each entry: `container` (Podman container name, required). The root password is read from `MARIADB_ROOT_PASSWORD` inside the container. |
| `restic_backup_sqlite_dbs` | list of str | no | `[]` | SQLite databases captured with the online `.backup` command. Plain paths must exist; entries containing `*` or `?` are expanded as shell globs at run time and may match nothing. |
| `restic_backup_keep_daily` | int | no | `7` | Daily snapshots kept by `restic forget`. |
| `restic_backup_keep_weekly` | int | no | `4` | Weekly snapshots kept by `restic forget`. |
| `restic_backup_keep_monthly` | int | no | `6` | Monthly snapshots kept by `restic forget`. |
| `restic_backup_prune_weekday` | int | no | `7` | ISO weekday (1 Monday to 7 Sunday) on which `restic prune` and `restic check` run. |
| `restic_backup_check_subset` | str | no | `"5%"` | Value passed to `restic check --read-data-subset`. |
| `restic_backup_schedule` | str | no | `"*-*-* 01:30:00"` | systemd `OnCalendar` expression for the timer. |
| `restic_backup_randomized_delay` | str | no | `30m` | systemd `RandomizedDelaySec` for the timer. |
| `restic_backup_kuma_push_url` | str | no | `""` | Uptime Kuma push URL, without a query string. Pinged only after a fully successful run. Empty disables it. **Supply from vault.** |

## Dependencies

None declared in `meta/main.yml`. The target host needs Podman if any
Postgres or MariaDB dumps are configured; there is no dependency on another
role to provide it.

## Example Playbook

```yaml
- hosts: app_servers
  become: true
  roles:
    - role: danmwallace.linux.restic_backup
      vars:
        restic_backup_password: "{{ vault_restic_backup_password }}"
        restic_backup_nas_host: nas.lan
        restic_backup_nas_host_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI..."
        restic_backup_paths:
          - /opt/podman/wsb
        restic_backup_postgres_dumps:
          - container: wsb-db
            user: postgres
        restic_backup_sqlite_dbs:
          - /opt/podman/mini-maintenance/data/*.db
        restic_backup_kuma_push_url: "{{ vault_restic_backup_kuma_push_url }}"
```

## What the Role Does

1. Asserts `restic_backup_password`, `restic_backup_nas_host`,
   `restic_backup_nas_host_key` and `restic_backup_paths` are all set.
2. Installs `restic` (and `sqlite` if `restic_backup_sqlite_dbs` is
   non-empty).
3. Creates `/etc/restic-backup`, `/usr/local/libexec/restic-backup`,
   `/var/lib/restic-backup` and `/var/cache/restic-backup` (mode `0700`).
4. Generates a dedicated ed25519 SSH keypair at `restic_backup_ssh_key_path`
   (default `/etc/restic-backup/id_ed25519`) if it doesn't already exist.
5. Pins the NAS host key into `/etc/restic-backup/known_hosts` under the
   alias `restic-backup-nas`.
6. Writes the SSH alias `restic-backup-nas` to
   `/etc/ssh/ssh_config.d/60-restic-backup.conf`, binding the dedicated key,
   the pinned host key file, and strict host key checking.
7. Writes `/etc/restic-backup/restic-backup.env` (mode `0600`) with
   `RESTIC_REPOSITORY`, `RESTIC_PASSWORD`, `RESTIC_CACHE_DIR` and
   `RESTIC_BACKUP_KUMA_PUSH_URL`.
8. Writes `/etc/restic-backup/excludes.txt` from
   `restic_backup_excludes`.
9. Writes the backup script to `/usr/local/libexec/restic-backup/run`
   (mode `0700`) — see [What the backup script does](#what-the-backup-script-does).
10. Runs `restic cat config` to check whether the repository is reachable.
    If it fails with any exit code other than `0` (reachable) or `10`
    (repository does not exist), the role reads the host's public key and
    fails with a message telling you which key to authorise on the NAS.
11. If the repository does not exist (`restic cat config` exit code `10`),
    runs `restic init` to create it. This is the **only** place the
    repository is initialised — the backup script never does this.
12. Installs and enables the `restic-backup.service` (oneshot) and
    `restic-backup.timer` systemd units, reloading systemd first via the
    `Reload systemd` handler.

### What the backup script does

The generated `/usr/local/libexec/restic-backup/run` script (run by the
timer):

1. Takes an exclusive lock (`flock`) so overlapping runs bail out instead of
   racing.
2. Runs `restic unlock` to clear stale locks from a prior interrupted run.
3. Recreates `/var/lib/restic-backup/dumps` (and `dumps/sqlite`) from
   scratch.
4. Dumps each configured Postgres container with `pg_dumpall` and each
   MariaDB container with `mariadb-dump`, gzipped to
   `dumps/<container>.sql.gz`.
5. Backs up each configured SQLite database with `sqlite3 ... .backup`,
   writing to `dumps/sqlite/<name>`, where `<name>` is the database's
   absolute path with the leading `/` stripped and remaining `/` replaced
   with `_` (e.g. `/opt/podman/app/data.db` becomes
   `opt_podman_app_data.db`).
6. Runs `restic backup --one-file-system --tag nightly` over
   `restic_backup_paths` plus the dump directory, excluding
   `/etc/restic-backup/excludes.txt`.
7. Runs `restic forget` with the configured daily/weekly/monthly retention.
8. On `restic_backup_prune_weekday` (ISO weekday, default `7` = Sunday),
   also runs `restic prune` and
   `restic check --read-data-subset=<restic_backup_check_subset>`.
9. If `RESTIC_BACKUP_KUMA_PUSH_URL` is set, pings it (appending
   `?status=up&msg=OK`) — only after every prior step has succeeded, since
   the script runs under `set -euo pipefail`.

A `Reload systemd` handler fires when the systemd unit files change, so a
new schedule or service definition takes effect without a manual
`daemon-reload`.

## NAS bootstrap

Before a host's first run, it needs an account and repository directory on
the TrueNAS SFTP server. That side is provisioned with
`tools/truenas-restic-bootstrap.py`, which lives in the control repo
(`ansible-homelab-cfg`) — not in this collection, and not yet present as of
this release (it lands with the control-repo work that consumes this role).
Run it from that repo once it exists:

```bash
tools/truenas-restic-bootstrap.py [--dry-run] host=/path/to/key.pub ...
```

It creates the `restic-<inventory_hostname>` user and that host's
repository directory under `restic_backup_nas_base_path`, authorising the
host's dedicated SSH public key — the file this role writes at
`restic_backup_ssh_key_path` + `.pub` (default
`/etc/restic-backup/id_ed25519.pub`). Run it (with `--dry-run` first to
preview) before the role's first run against a new host; if it hasn't been
run yet, step 10 above fails with the exact public key you need to
authorise.

## Restore runbook

All of the following read `/etc/restic-backup/restic-backup.env` to export
`RESTIC_REPOSITORY` and `RESTIC_PASSWORD` (and the Kuma URL, harmlessly)
into the shell, so the `restic` CLI can talk to the repository directly:

```bash
sudo bash -c 'set -a; . /etc/restic-backup/restic-backup.env; set +a; restic snapshots'
sudo bash -c 'set -a; . /etc/restic-backup/restic-backup.env; set +a; restic restore latest --target /tmp/restore --include /opt/podman/<app>'
sudo bash -c 'set -a; . /etc/restic-backup/restic-backup.env; set +a; restic dump latest /var/lib/restic-backup/dumps/<container>.sql.gz' | gunzip | podman exec -i <container> psql -U <user> -d postgres
```

- The first command lists available snapshots.
- The second restores a specific path from the latest snapshot into
  `/tmp/restore`.
- The third restores a Postgres dump by streaming it straight into `psql`
  inside the target container — no restore-to-disk step needed. For a
  MariaDB dump, pipe the decompressed `.sql.gz` into `podman exec -i
  <container> mariadb -u<user> -p<password>` (or `mysql`) instead of
  `psql`.
- SQLite dumps live under `dumps/sqlite/<name>`; restore them with
  `restic dump latest /var/lib/restic-backup/dumps/sqlite/<name>` and
  overwrite the live database file (with the app stopped).

## Gotchas

- `restic_backup_password` must be letters and digits only. It is written
  unquoted into a systemd `EnvironmentFile`
  (`/etc/restic-backup/restic-backup.env`); other characters (spaces,
  `#`, quotes) can break how systemd parses the file.
- Don't put SQLite paths or globs in `restic_backup_paths` or
  `restic_backup_excludes`. They're dumped separately into
  `dumps/sqlite/`, which is already covered by the dump directory that's
  always included in the backup. In `restic_backup_sqlite_dbs`, only
  entries containing `*` or `?` are treated as shell globs (expanded with
  `nullglob`, so they can silently match nothing); everything else —
  including a literal `[` — is a literal path, and the run fails if it
  doesn't exist.
- A missing or deleted repository is never silently recreated by the
  backup service. Only a role run re-initialises it (on `restic cat
  config` exit code `10`). This is deliberate: if the repository
  disappears, backups fail loudly instead of quietly starting over with an
  empty one.
- `restic_backup_kuma_push_url` must be the push URL **without** its query
  string — no `?status=up&msg=OK`. The run script appends that itself, and
  only after every step in the backup has succeeded.
- Weekday `7` (Sunday, ISO weekday) is the default
  `restic_backup_prune_weekday`, when `restic prune` and `restic check
  --read-data-subset=<restic_backup_check_subset>` run in addition to the
  nightly backup and `forget`.

## License

MIT
