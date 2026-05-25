# danmwallace.linux.cloudflare_ssl

Obtains a Let's Encrypt certificate for the managed host using the
[Cloudflare DNS-01 challenge](https://certbot-dns-cloudflare.readthedocs.io/).
It installs certbot and the `certbot-dns-cloudflare` plugin, writes the
Cloudflare API token to `/root/.secrets/cloudflare.ini` (mode `0400`), then runs
`certbot certonly --dns-cloudflare` for `inventory_hostname`. Because validation
happens over DNS, the host never needs ports 80/443 exposed. Certificates land in
the standard certbot location, `/etc/letsencrypt/live/<inventory_hostname>/`.

Supports Ubuntu/Debian (apt, `certbot`) and Fedora Server (dnf, `certbot-3`). The
commented-out `rpm_ostree_pkg` block hints at Fedora Atomic/IoT support that is
not currently wired up.

## Requirements

- Ansible >= 2.16 (collection `requires_ansible`)
- Target host: Ubuntu/Debian or Fedora Server
- A domain managed in Cloudflare, plus a Cloudflare API token scoped to **DNS
  edit** for that zone
- Outbound network access to Let's Encrypt and the Cloudflare API

## Role Variables

Validated by `meta/argument_specs.yml`. Note these variables are **not** prefixed
with the role name (`cloudflare_ssl_*`), which deviates from the workspace
convention — they are consumed verbatim by the tasks and the `cloudflare.ini.j2`
template, so renaming requires editing the role.

| Variable | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `vault_cloudflare_dns_api_token` | str | yes | _(empty)_ | Cloudflare API token with DNS edit scope; written into `cloudflare.ini`. **Supply from vault.** |
| `vault_cloudflare_dns_email` | str | yes | _(empty)_ | Email passed to `certbot --email` for the ACME account / expiry notices. **Supply from vault.** |
| `common_debian_packages` | list | no | `[python3-certbot, python3-certbot-dns-cloudflare]` | Apt packages installed on Ubuntu/Debian. |
| `common_fedora_packages` | list | no | `[python3-certbot, python3-certbot-dns-cloudflare]` | Dnf packages installed on Fedora. |

The certificate is always requested for `inventory_hostname`; there is no
variable to override the domain or request a wildcard.

## Dependencies

None declared in `meta/main.yml`.

## Example Playbook

```yaml
- hosts: web
  become: true
  roles:
    - role: danmwallace.linux.cloudflare_ssl
      vars:
        vault_cloudflare_dns_email: "{{ vault_cloudflare_dns_email }}"
        vault_cloudflare_dns_api_token: "{{ vault_cloudflare_dns_api_token }}"
```

Keep the real values in an encrypted vault file:

```yaml
# group_vars/web/vault.yml (ansible-vault encrypted)
vault_cloudflare_dns_email: "sysadmin@example.com"
vault_cloudflare_dns_api_token: "your-cloudflare-dns-edit-token"
```

## What the Role Does

1. Installs certbot and the Cloudflare DNS plugin — apt on Ubuntu/Debian, dnf on
   Fedora.
2. Creates `/root/.secrets` (mode `0700`).
3. Renders `cloudflare.ini.j2` to `/root/.secrets/cloudflare.ini` (mode `0400`)
   containing the API token.
4. Runs `certbot certonly --dns-cloudflare` for `inventory_hostname`
   (`certbot-3` on Fedora, `certbot` on Ubuntu/Debian), writing the certificate
   to `/etc/letsencrypt/live/<inventory_hostname>/`.

## Notes

- **Not idempotent on the issuance step.** The certbot tasks use
  `ansible.builtin.shell` with no `changed_when`/`creates`, so they report
  `changed` and re-invoke certbot on every run. certbot itself is a no-op when
  the cert is still valid, but the task will not pass a clean second-run check.
- Renewal is left to certbot's own systemd timer; this role does not install a
  separate renewal unit. The companion `danmwallace.linux.cockpit` role installs
  a post-renewal hook for Cockpit.

## License

MIT
