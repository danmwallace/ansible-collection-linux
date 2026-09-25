# danmwallace.linux.cloudflare_ssl

Obtains a Let's Encrypt certificate for the managed host using the
[Cloudflare DNS-01 challenge](https://certbot-dns-cloudflare.readthedocs.io/).
It installs the `certbot` CLI and the `certbot-dns-cloudflare` plugin, writes
the Cloudflare API token to `/root/.secrets/cloudflare.ini` (mode `0400`), then
runs `certbot certonly --dns-cloudflare` for the requested domain names.
Because validation happens over DNS, the host never needs ports 80/443
exposed. The role also enables and starts the certbot CLI package's own
systemd renewal timer, so certificates keep renewing without any further
Ansible runs.

Supports Ubuntu/Debian (apt) and Fedora Server (dnf).

## Requirements

- Ansible >= 2.16 (collection `requires_ansible`)
- Target host: Ubuntu/Debian or Fedora Server
- A domain managed in Cloudflare, plus a Cloudflare API token scoped to **DNS
  edit** for that zone
- Outbound network access to Let's Encrypt and the Cloudflare API
- A molecule scenario (`molecule/default`) exists for this role, but firewalld/
  systemd-timer behavior aside, most of what it can verify in a container is
  package installation and the credentials file — the renewal timer itself is
  exercised on live hosts.

## Role Variables

Validated by `meta/argument_specs.yml`. All variables are prefixed with the role
name (`cloudflare_ssl_*`) per the workspace convention.

| Variable | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `cloudflare_ssl_email` | str | yes | _(none)_ | Email passed to `certbot --email` for the ACME account / expiry notices. **Supply from vault.** |
| `cloudflare_ssl_api_token` | str | yes | _(none)_ | Cloudflare API token with DNS edit scope; written into `cloudflare.ini`. **Supply from vault.** |
| `cloudflare_ssl_domains` | list | no | `["{{ inventory_hostname }}"]` | Names requested in the certificate. The **first entry** names the lineage (passed as `--cert-name`), so the certificate lands in `/etc/letsencrypt/live/<first entry>/`. |
| `cloudflare_ssl_manage_renewal_timer` | bool | no | `true` | Enable and start the packaged certbot renewal timer (`certbot-renew.timer` on RedHat-family, `certbot.timer` on Debian-family). Leave `true` unless another mechanism owns renewal. |
| `cloudflare_ssl_debian_packages` | list | no | `[certbot, python3-certbot-dns-cloudflare]` | Apt packages installed on Ubuntu/Debian. |
| `cloudflare_ssl_fedora_packages` | list | no | `[certbot, python3-certbot-dns-cloudflare]` | Dnf packages installed on Fedora. |

## Dependencies

None declared in `meta/main.yml`.

## Example Playbook

```yaml
- hosts: web
  become: true
  roles:
    - role: danmwallace.linux.cloudflare_ssl
      vars:
        cloudflare_ssl_email: "{{ vault_cloudflare_ssl_email }}"
        cloudflare_ssl_api_token: "{{ vault_cloudflare_ssl_api_token }}"
        cloudflare_ssl_domains:
          - "{{ inventory_hostname }}"
```

Keep the real values in an encrypted vault file and map them to the role's
input variables (as shown above):

```yaml
# group_vars/web/vault.yml (ansible-vault encrypted)
vault_cloudflare_ssl_email: "sysadmin@example.com"
vault_cloudflare_ssl_api_token: "your-cloudflare-dns-edit-token"
```

## What the Role Does

1. Asserts `cloudflare_ssl_email`, `cloudflare_ssl_api_token` and
   `cloudflare_ssl_domains` are all set.
2. Installs `certbot` and the Cloudflare DNS plugin — apt on Ubuntu/Debian,
   dnf on Fedora.
3. Creates `/root/.secrets` (mode `0700`).
4. Renders `cloudflare.ini.j2` to `/root/.secrets/cloudflare.ini` (mode
   `0400`) containing the API token.
5. Runs `certbot certonly --dns-cloudflare --cert-name <cloudflare_ssl_domains[0]>
   --domains <cloudflare_ssl_domains joined>`, writing the certificate to
   `/etc/letsencrypt/live/<cloudflare_ssl_domains[0]>/`.
6. Enables and starts the packaged certbot renewal timer when
   `cloudflare_ssl_manage_renewal_timer` is `true`.

## Notes

- **On Fedora the renewal timer ships in the `certbot` package, not
  `python3-certbot`.** Installing only `python3-certbot` gives you the
  library and a `certbot-3` binary with no timer unit at all — the
  certificate is issued once and then silently never renews. This is exactly
  how srv01's Cockpit certificate expired: it was issued in 2025-08 and never
  renewed again. `cloudflare_ssl_fedora_packages` therefore installs
  `certbot`, and `cloudflare_ssl_manage_renewal_timer` enables its timer.
- **Issuance is idempotent, renewal is the timer's job.** The `certbot
  certonly` task is guarded by `creates: /etc/letsencrypt/live/<lineage>/cert.pem`,
  so it only ever runs once per lineage — a second Ansible run reports `ok`
  and does not touch the certificate. All subsequent renewal happens off the
  systemd timer (`certbot-renew.timer` / `certbot.timer`), independently of
  Ansible. To force re-issuance, remove that path on the target first.
- **`cloudflare_ssl_domains[0]` must match the consuming role's certificate
  name.** For Cockpit, that means `cloudflare_ssl_domains[0]` must equal
  `cockpit_hostname` — `danmwallace.linux.cockpit`'s deploy hook only acts
  when `$RENEWED_LINEAGE` equals its own `cockpit_letsencrypt_cert_path`. If
  the two names diverge, the hook's guard never matches and it silently does
  nothing on renewal.

## License

MIT
