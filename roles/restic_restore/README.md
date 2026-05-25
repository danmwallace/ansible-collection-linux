# danmwallace.linux.restic_restore

Restores the latest snapshot from a [Restic](https://restic.net/) repository
into a target directory, with handling for SELinux-enforcing hosts. It creates
the restore path, runs `restic restore latest --target <restore_path>` against a
Backblaze B2 repository, then fixes ownership recursively and restores SELinux
contexts with `restorecon`. On enforcing systems it drops to permissive for the
duration of the restore (to avoid `security.selinux` xattr errors during write)
and re-enables enforcing afterward.

The role is built around a B2 backend — the restore step exports
`B2_ACCOUNT_ID` / `B2_ACCOUNT_KEY` alongside `RESTIC_REPOSITORY` /
`RESTIC_PASSWORD`. It assumes `restic` is already installed on the target; it
does not install it.

## Requirements

- Ansible >= 2.16 (collection `requires_ansible`)
- `restic` already installed on the target host
- An existing Restic repository (B2) reachable from the host
- Repository password and B2 account credentials
- A host where `getenforce`/`setenforce`/`restorecon` exist if SELinux is in use
  (RHEL-family/Fedora); on non-SELinux hosts the enforce/restorecon tasks are
  effectively no-ops or skipped via the `getenforce` result

## Role Variables

Validated by `meta/argument_specs.yml`. All variables are **required** —
`defaults/main.yml` is empty and they are referenced directly by `tasks/main.yml`
with no defaults, so the play fails if they are unset. They are not prefixed with
the role name, which deviates from the workspace convention.

| Variable | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `restic_repository` | str | yes | — | Restic repository URL (e.g. `b2:bucket:path/`). Exported as `RESTIC_REPOSITORY`. |
| `restic_password` | str | yes | — | Repository password. Exported as `RESTIC_PASSWORD`. **Supply from vault.** |
| `b2_account_id` | str | yes | — | Backblaze B2 account/key ID. Exported as `B2_ACCOUNT_ID`. **Supply from vault.** |
| `b2_account_key` | str | yes | — | Backblaze B2 application key. Exported as `B2_ACCOUNT_KEY`. **Supply from vault.** |
| `restore_path` | str | yes | — | Directory the snapshot is restored into; created and chowned to `target_user`. |
| `target_user` | str | yes | — | User/group that owns the restore path and restored files. |

## Dependencies

None declared in `meta/main.yml`. The target host must already have `restic`
installed.

## Example Playbook

```yaml
- hosts: workstations
  become: true
  roles:
    - role: danmwallace.linux.restic_restore
      vars:
        restic_repository: "b2:homelab-backups:user-data/"
        restic_password: "{{ vault_restic_password }}"
        b2_account_id: "{{ vault_b2_account_id }}"
        b2_account_key: "{{ vault_b2_account_key }}"
        target_user: dwallace
        restore_path: "/home/dwallace/"
```

Keep credentials in an encrypted vault file:

```yaml
# group_vars/workstations/vault.yml (ansible-vault encrypted)
vault_restic_password: "your-restic-password"
vault_b2_account_id: "your-b2-account-id"
vault_b2_account_key: "your-b2-account-key"
```

## What the Role Does

1. Reads the current SELinux mode (`getenforce`) and, if `Enforcing`, sets it to
   permissive for the restore.
2. Ensures `restore_path` exists, owned by `target_user`.
3. Runs `restic restore latest --target <restore_path>`, filtering out
   `security.selinux: permission denied` noise from the output.
4. Prints the restore output, and fails the play only if the restore exited
   non-zero for a reason other than SELinux xattr errors.
5. Fixes ownership recursively under `restore_path` to `target_user`.
6. Runs `restorecon -R` over `restore_path` to restore SELinux contexts.
7. Re-enables SELinux enforcing if it was enforcing at the start.

## Notes

- **Not idempotent.** The restore is an `ansible.builtin.shell` with
  `failed_when: false` and the SELinux toggles / `restorecon` are
  `ansible.builtin.command` tasks without `changed_when` — every run reports
  changes and re-runs the restore. This is a restore tool, so re-running
  overwrites the target with the latest snapshot; treat each run as destructive
  to `restore_path`.
- Only the `latest` snapshot is restored; there is no variable to select a
  specific snapshot ID or to include/exclude paths.
- The SELinux permissive window is host-wide for the duration of the restore.

## License

MIT
