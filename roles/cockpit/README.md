# danmwallace.linux.cockpit

Configures TLS for an already-installed [Cockpit](https://cockpit-project.org/)
by copying a Let's Encrypt certificate and key into Cockpit's certificate
directory (`/etc/cockpit/ws-certs.d` by default), then enabling and starting
the Cockpit unit. It installs a certbot **deploy** renewal hook
(`renewal-hooks/deploy/10-cockpit.sh`) so the certificate is re-copied and
Cockpit restarted after each renewal, and removes any legacy `post` hook this
role previously installed. It also scopes access to Cockpit's web console
(TCP 9090) via UFW on Ubuntu or firewalld rich rules on RedHat-family hosts.

This role does **not** install Cockpit, and it does **not** obtain the
certificate — it expects both to already be in place. Pair it with
`danmwallace.linux.cloudflare_ssl` (or any certbot flow) to produce the
certificate first.

## Requirements

- Ansible >= 2.16 (collection `requires_ansible`)
- `community.general` (for the UFW task on Ubuntu) and `ansible.posix` (for
  the firewalld tasks on RedHat-family)
- Target host: Fedora, Ubuntu, or Debian with **Cockpit already installed**
- A Let's Encrypt certificate already present at
  `{{ cockpit_letsencrypt_cert_path }}` (i.e. `fullchain.pem` and
  `privkey.pem`)
- **Gathered facts.** `cockpit_cert_owner`'s default is templated off
  `ansible_facts.os_family`. A play with `gather_facts: false` and no facts
  cached from elsewhere fails with an undefined-variable error when
  rendering that default — it does not silently fall back to one OS branch.
- A molecule scenario (`molecule/default`) exists for this role. firewalld
  cannot run inside the container it uses, so the rich-rule and
  blanket-service tasks are verified on live hosts instead.

## Role Variables

Validated by `meta/argument_specs.yml`. All variables have defaults.

| Variable | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `cockpit_hostname` | str | no | `{{ inventory_hostname }}` | Hostname used to name the copied cert/key files (`<hostname>.crt` / `.key`) and the default LE cert path. |
| `cockpit_letsencrypt_cert_path` | path | no | `/etc/letsencrypt/live/{{ cockpit_hostname }}` | Source directory holding `fullchain.pem` and `privkey.pem`. |
| `cockpit_cert_path` | path | no | `/etc/cockpit/ws-certs.d` | Directory Cockpit reads its TLS material from; the cert/key are copied here. |
| `cockpit_cert_owner` | str | no | `cockpit-ws` on Debian-family, `root` elsewhere | Owner of the certificate and key in `cockpit_cert_path`. Templated off `ansible_facts.os_family` — requires gathered facts. |
| `cockpit_cert_group` | str | no | `{{ cockpit_cert_owner }}` | Group of the certificate and key in `cockpit_cert_path`. |
| `cockpit_cert_mode` | str | no | `"0600"` | Mode applied to the certificate and key in `cockpit_cert_path`. |
| `cockpit_service_name` | str | no | `cockpit.socket` | systemd unit managed and restarted after a certificate change. `cockpit.service` is static on Fedora, so the socket is the correct unit. |
| `cockpit_allowed_cidrs` | list | no | `[]` | Source **CIDRs** allowed to reach Cockpit on TCP 9090 through **firewalld** (RedHat-family hosts). Each entry becomes a rich rule. Empty leaves the firewall untouched. |
| `cockpit_remove_blanket_firewalld_service` | bool | no | `true` | Disables the zone-wide `cockpit` firewalld service (RedHat-family), so only the `cockpit_allowed_cidrs` rich rules grant access. Acts only when `cockpit_allowed_cidrs` is non-empty. |
| `cockpit_allowed_cidr` | str | no | `"10.0.0.0/8"` | Source **CIDR** (singular) allowed to reach Cockpit on port 9090 via **UFW** (Ubuntu only). |

### The `cockpit_allowed_cidr` / `cockpit_allowed_cidrs` trap

These two variables look almost identical and are easy to swap by accident —
doing so has very different consequences:

- `cockpit_allowed_cidr` — **singular**, a plain `str`, applies only to
  **UFW on Ubuntu**, and defaults to `"10.0.0.0/8"` (a wide-open RFC-1918
  block, opened on every Ubuntu run unless you narrow it).
- `cockpit_allowed_cidrs` — **plural**, a `list`, applies only to
  **firewalld on RedHat-family**, and defaults to `[]` (nothing opened at
  all until you populate it).

Setting the singular var on a Fedora host, or the plural var on Ubuntu, does
nothing — you're configuring the firewall backend the host doesn't use.

## Dependencies

None declared in `meta/main.yml`. In practice the target host must already
have Cockpit installed and a Let's Encrypt certificate present at
`cockpit_letsencrypt_cert_path` — typically produced by
`danmwallace.linux.cloudflare_ssl`.

## Example Playbook

```yaml
- hosts: management
  become: true
  roles:
    - role: danmwallace.linux.cloudflare_ssl
      vars:
        cloudflare_ssl_domains:
          - cockpit.example.com
    - role: danmwallace.linux.cockpit
      vars:
        cockpit_hostname: cockpit.example.com
        cockpit_allowed_cidrs:
          - 192.168.70.0/24
          - 10.10.99.0/24
```

## What the Role Does

1. Ensures the Cockpit certificate directory (`cockpit_cert_path`) exists.
2. Copies `fullchain.pem` to `<cockpit_cert_path>/<cockpit_hostname>.crt` and
   `privkey.pem` to `<cockpit_cert_path>/<cockpit_hostname>.key` from
   `cockpit_letsencrypt_cert_path` (remote-to-remote copy), owned per
   `cockpit_cert_owner` / `cockpit_cert_group` / `cockpit_cert_mode`.
3. Ensures the certbot deploy hook directory
   (`/etc/letsencrypt/renewal-hooks/deploy`) exists.
4. Installs the templated deploy hook at
   `/etc/letsencrypt/renewal-hooks/deploy/10-cockpit.sh` (mode `0755`).
5. Removes the legacy post-renewal hook at
   `/etc/letsencrypt/renewal-hooks/post/001-restart-cockpit.sh`, which the
   deploy hook supersedes.
6. Enables and starts `cockpit_service_name` (`cockpit.socket` by default).
7. On RedHat-family hosts with `cockpit_allowed_cidrs` set, adds one
   firewalld rich rule per CIDR permitting TCP 9090.
8. On RedHat-family hosts with `cockpit_allowed_cidrs` set and
   `cockpit_remove_blanket_firewalld_service` true, disables the zone-wide
   `cockpit` firewalld service.
9. On Ubuntu, opens TCP 9090 in UFW from `cockpit_allowed_cidr` (notifies the
   `Restart cockpit` handler).

A `Restart cockpit` handler restarts `cockpit_service_name`; it is notified
by the cert/key copy tasks and by the Ubuntu UFW rule task.

## Notes

- **The deploy hook only fires on an actual renewal, and only for this
  host's own lineage.** `10-cockpit.sh` checks `$RENEWED_LINEAGE` against
  `cockpit_letsencrypt_cert_path` and exits 0 immediately if they don't
  match, so certbot renewing an unrelated certificate on the same host never
  touches Cockpit's files or restarts the service.
- **`cockpit_allowed_cidrs` defaults to empty, so upgrading this role never
  opens a port by itself.** The firewalld rich-rule and blanket-service tasks
  are both gated on `cockpit_allowed_cidrs | length > 0`; leave it unset and
  this role makes no firewall changes on RedHat-family hosts.
- **`cockpit_remove_blanket_firewalld_service` revokes web-console access
  for anyone outside `cockpit_allowed_cidrs`.** firewalld ships a zone-wide
  `cockpit` service (all sources, port 9090) that an additive rich rule
  cannot narrow — as long as it stays enabled, the rich rules add nothing.
  With `cockpit_remove_blanket_firewalld_service: true` (the default) and
  `cockpit_allowed_cidrs` non-empty, that blanket service is disabled, so an
  administrator connecting from outside the allowed CIDRs loses Cockpit's
  web console. **SSH access to the host is unaffected** — this only touches
  the firewalld `cockpit` service, never `sshd`.
- The role manages `cockpit.socket`, not `cockpit.service`: on Fedora,
  `cockpit.service` is a static unit that cannot be enabled directly, so the
  socket is the unit to enable/start/restart.
- `cockpit_cert_owner` requires gathered facts to render its default — a
  play that disables fact gathering and has no cached facts fails with an
  undefined-variable error rather than quietly picking the wrong owner.

## License

MIT
