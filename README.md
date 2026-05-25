# Ansible Collection — danmwallace.linux

Roles for cross-distro Linux host configuration in the homelab: obtaining SSL
certificates via the Cloudflare DNS-01 challenge, wiring those certificates into
an already-installed [Cockpit](https://cockpit-project.org/), restoring data from
[Restic](https://restic.net/) repositories, and turning a Raspberry Pi into a
portable network diagnostics toolkit. The roles target Ubuntu/Debian and Fedora
hosts and lean on `community.general` and `ansible.posix` for the distro-specific
plumbing (UFW, package management, etc.).

## Requirements

- Ansible >= 2.16 (collection `requires_ansible` in `meta/runtime.yml`)
- Collection dependencies (from `galaxy.yml`):
  - `community.general >= 8.0.0`
  - `ansible.posix >= 1.5.0`
- Target-host prerequisites vary by role — see each role README.

## Installation

```bash
ansible-galaxy collection install danmwallace.linux
```

Or pin it in `requirements.yml`:

```yaml
collections:
  - name: danmwallace.linux
    version: ">=1.0.0"
```

## Roles

| Role | Description |
| --- | --- |
| [`danmwallace.linux.cloudflare_ssl`](roles/cloudflare_ssl/README.md) | Obtain Let's Encrypt certificates via the Cloudflare DNS-01 challenge with certbot. |
| [`danmwallace.linux.cockpit`](roles/cockpit/README.md) | Configure TLS for an already-installed Cockpit using Let's Encrypt certificates. |
| [`danmwallace.linux.raspberry_pi_network_toolkit`](roles/raspberry_pi_network_toolkit/README.md) | Configure a Raspberry Pi (or Debian/Ubuntu host) as a portable network diagnostics and reconnaissance toolkit. |
| [`danmwallace.linux.restic_restore`](roles/restic_restore/README.md) | Restore the latest snapshot from a Restic repository, handling SELinux contexts and ownership. |

## Example Playbook

```yaml
- hosts: servers
  become: true
  roles:
    - role: danmwallace.linux.cloudflare_ssl
    - role: danmwallace.linux.cockpit
```

## License

MIT
