# Ansible Role: ansible_common_cockpit

Deploy and configure Cockpit web-based system management interface with SSL certificate support.

## Description

This role deploys [Cockpit](https://cockpit-project.org/), a web-based interface for managing Linux servers. Cockpit provides an easy-to-use dashboard for system monitoring, service management, storage administration, and more.

## Requirements

- Ansible 2.15+
- Target OS: Ubuntu 20.04+, Debian 11+, Fedora 38+
- Port 9090 accessible

## Role Variables

### Optional Variables

```yaml
# Cockpit SSL certificate directory
common_cockpit_cert_dir: "/etc/cockpit/ws-certs.d"

# Certificate paths (if using custom SSL)
cockpit_cert_file: "/path/to/cert.pem"
cockpit_key_file: "/path/to/privkey.pem"
```

## Dependencies

None.

## Example Playbook

```yaml
---
- name: Deploy Cockpit
  hosts: servers
  become: true
  roles:
    - ansible_common
    - ansible_common_cockpit
```

## What This Role Does

1. Installs Cockpit package and dependencies
2. Enables and starts cockpit.socket
3. Configures SSL certificates (if provided)
4. Opens firewall port (if firewall active)

## Cockpit Features

- **System Monitoring**: CPU, memory, disk, network usage
- **Service Management**: Systemd service control
- **Storage Administration**: Disk and partition management
- **Container Management**: Podman/Docker container control
- **Terminal Access**: Web-based terminal
- **Log Viewer**: System journal logs
- **User Management**: User and group administration

## Access

After deployment:
- HTTP: `http://server-ip:9090`
- HTTPS: `https://server-hostname:9090`

Login with any sudo-enabled system user account.

## Security Notes

- Use SSL certificates in production
- Restrict firewall access to trusted networks
- Use strong passwords for user accounts

## Tags

- `cockpit` - Cockpit tasks
- `monitoring` - Monitoring tasks

## License

MIT

## Author

Dan Wallace
