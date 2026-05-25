# danmwallace.linux.cockpit

Configures TLS for an already-installed [Cockpit](https://cockpit-project.org/)
by copying a Let's Encrypt certificate and key into Cockpit's certificate
directory (`/etc/cockpit/ws-certs.d` by default), then enabling and starting the
`cockpit` service. It also installs a certbot renewal hook so the certificate is
re-copied and Cockpit restarted after each renewal. On Ubuntu/Debian it sets
`cockpit-ws` ownership on the cert files and opens TCP 9090 in UFW.

This role does **not** install Cockpit, and it does **not** obtain the
certificate — it expects both to already be in place. Pair it with
`danmwallace.linux.cloudflare_ssl` (or any certbot flow) to produce the
certificate first.

## Requirements

- Ansible >= 2.16 (collection `requires_ansible`)
- `community.general` (for the UFW task on Ubuntu)
- Target host: Fedora, Ubuntu, or Debian with **Cockpit already installed**
- A Let's Encrypt certificate already present at
  `{{ cockpit_letsencrypt_cert_path }}` (i.e. `fullchain.pem` and `privkey.pem`)

## Role Variables

Validated by `meta/argument_specs.yml`. All variables have defaults.

| Variable | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `cockpit_hostname` | str | no | `{{ inventory_hostname }}` | Hostname used to name the copied cert/key files (`<hostname>.crt` / `.key`) and the default LE cert path. |
| `cockpit_letsencrypt_cert_path` | str | no | `/etc/letsencrypt/live/{{ cockpit_hostname }}` | Source directory holding `fullchain.pem` and `privkey.pem`. |
| `cockpit_cert_path` | str | no | `/etc/cockpit/ws-certs.d` | Directory Cockpit reads its TLS material from; the cert/key are copied here. |

## Dependencies

None declared in `meta/main.yml`. In practice the target host must already have
Cockpit installed and a Let's Encrypt certificate present at
`cockpit_letsencrypt_cert_path` — typically produced by
`danmwallace.linux.cloudflare_ssl`.

## Example Playbook

```yaml
- hosts: management
  become: true
  roles:
    - role: danmwallace.linux.cloudflare_ssl
    - role: danmwallace.linux.cockpit
      vars:
        cockpit_hostname: cockpit.example.com
```

## What the Role Does

1. Ensures the Cockpit certificate directory (`cockpit_cert_path`) exists.
2. Copies `fullchain.pem` to `<cockpit_cert_path>/<cockpit_hostname>.crt` and
   `privkey.pem` to `<cockpit_cert_path>/<cockpit_hostname>.key` from
   `cockpit_letsencrypt_cert_path` (remote-to-remote copy).
3. On Ubuntu/Debian, sets `cockpit-ws:cockpit-ws` ownership on the cert and key.
4. Installs a certbot post-renewal hook at
   `/etc/letsencrypt/renewal-hooks/post/001-restart-cockpit.sh` that re-copies
   the cert/key and restarts Cockpit (the Ubuntu/Debian variant also re-applies
   `cockpit-ws` ownership).
5. Enables and starts the `cockpit` service.
6. On Ubuntu, opens TCP 9090 in UFW (notifies the `Restart cockpit` handler).

A `Restart cockpit` handler restarts the service; it is notified only by the
Ubuntu UFW rule task.

## Notes

- Cockpit listens on TCP **9090**. Only the Ubuntu path opens the firewall; on
  Fedora/Debian, open 9090 yourself if a firewall is active.
- The renewal hook is written per-distro (`when: Fedora` vs `when:
  Ubuntu/Debian`), so a single host installs only the hook variant matching its
  distribution.

## License

MIT
