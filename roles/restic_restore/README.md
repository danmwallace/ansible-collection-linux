# Ansible Role: ansible_restic_restore

Restore data from Restic backup repositories to target systems.

## Description

This role restores files and directories from [Restic](https://restic.net/) backup repositories. Restic is a fast, secure, and efficient backup program that supports multiple storage backends including local, S3, B2, Azure, and more.

## Requirements

- Ansible 2.15+
- Target OS: Ubuntu 20.04+, Debian 11+, Fedora 38+
- Restic repository already exists with backups
- Access credentials for the backup repository

## Role Variables

### Required Variables

```yaml
# Restic repository location
restic_repository: "b2:bucket-name:path/"

# Restic repository password
restic_password: "{{ vault_restic_password }}"

# User to restore files for
target_user: "username"

# Path to restore files to
restore_path: "/home/{{ target_user }}/"
```

### Backend-Specific Variables

#### Backblaze B2

```yaml
b2_account_id: "{{ vault_b2_account_id }}"
b2_account_key: "{{ vault_b2_account_key }}"
```

#### AWS S3

```yaml
aws_access_key_id: "{{ vault_aws_access_key_id }}"
aws_secret_access_key: "{{ vault_aws_secret_access_key }}"
```

### Optional Variables

```yaml
# Specific snapshot to restore (default: latest)
restic_snapshot_id: "latest"

# Specific files/paths to restore
restic_restore_include:
  - "Documents/"
  - "Pictures/"

# Files/paths to exclude from restore
restic_restore_exclude:
  - ".cache/"
  - "Downloads/"
```

## Dependencies

None.

## Example Playbook

```yaml
---
- name: Restore user data from backup
  hosts: workstations
  become: true
  roles:
    - role: ansible_restic_restore
```

### With Group Variables (Recommended)

```yaml
# inventories/lab/group_vars/desktop/restic.yml
restic_repository: "b2:homelab-backups:user-data/"
restic_password: "{{ vault_restic_password }}"
b2_account_id: "{{ vault_b2_account_id }}"
b2_account_key: "{{ vault_b2_account_key }}"
target_user: "dwallace"
restore_path: "/home/{{ target_user }}/"

# inventories/lab/group_vars/desktop/vault.yml (encrypted)
vault_restic_password: "your-restic-password"
vault_b2_account_id: "your-b2-account-id"
vault_b2_account_key: "your-b2-account-key"
```

## What This Role Does

1. **Installs Restic**: Ensures restic is installed on target system
2. **Configures Environment**: Sets up backend credentials (B2, S3, etc.)
3. **Verifies Repository**: Checks repository accessibility
4. **Restores Data**: Restores files from backup to specified path
5. **Sets Permissions**: Ensures restored files have correct ownership

## Restic Repository Types

### Backblaze B2

```yaml
restic_repository: "b2:bucket-name:path/to/repo"
b2_account_id: "{{ vault_b2_account_id }}"
b2_account_key: "{{ vault_b2_account_key }}"
```

### Amazon S3

```yaml
restic_repository: "s3:s3.amazonaws.com/bucket-name/path"
aws_access_key_id: "{{ vault_aws_access_key }}"
aws_secret_access_key: "{{ vault_aws_secret_key }}"
```

### Local/SFTP

```yaml
restic_repository: "/mnt/backup/restic-repo"
# or
restic_repository: "sftp:user@host:/path/to/repo"
```

## Restore Scenarios

### Full Restore (All Files)

```yaml
# Restores everything from latest snapshot
target_user: "username"
restore_path: "/home/{{ target_user }}/"
```

### Selective Restore

```yaml
# Restore only specific directories
restic_restore_include:
  - "Documents/"
  - "Pictures/"
  - ".config/app/"
```

### Specific Snapshot

```yaml
# Restore from a specific snapshot ID
restic_snapshot_id: "a1b2c3d4"
```

## Tags

- `restore` - Restore operations
- `backup` - Backup-related tasks

## Security Notes

- Store all credentials in Ansible Vault
- Use repository password with high entropy
- Limit backend access permissions
- Secure restored files with appropriate ownership
- Verify backup integrity before restore

## Common Commands

```bash
# List snapshots
restic -r b2:bucket:path snapshots

# List files in snapshot
restic -r b2:bucket:path ls latest

# Restore specific files
restic -r b2:bucket:path restore latest --target /tmp/restore --include Documents/

# Verify repository
restic -r b2:bucket:path check
```

## Troubleshooting

### Repository Not Found

1. Verify repository URL is correct
2. Check backend credentials
3. Ensure repository was initialized
4. Test network connectivity to backend

### Permission Denied

1. Check target directory permissions
2. Verify user exists on system
3. Ensure ansible user has sudo access
4. Review file ownership after restore

### Slow Restore

1. Check network bandwidth
2. Consider restoring to local storage first
3. Use selective restore for specific files
4. Verify backend isn't rate-limiting

## Best Practices

1. **Test Restores**: Regularly test restore process
2. **Verify Data**: Check restored files are complete
3. **Secure Credentials**: Always use Ansible Vault
4. **Document Snapshots**: Keep record of important snapshots
5. **Incremental Restores**: Restore only what's needed

## Integration with Backup Role

This restore role pairs with a backup role:

```yaml
# Backup playbook
- hosts: workstations
  roles:
    - ansible_restic_backup

# Restore playbook
- hosts: workstations
  roles:
    - ansible_restic_restore
```

## License

MIT

## Author

Dan Wallace

## See Also

- [Restic Documentation](https://restic.readthedocs.io/)
- [Restic GitHub](https://github.com/restic/restic)
- [Backblaze B2 with Restic](https://restic.readthedocs.io/en/stable/030_preparing_a_new_repo.html#backblaze-b2)
