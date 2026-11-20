# danmwallace.linux.cockpit

Configures TLS for an already-installed [Cockpit](https://cockpit-project.org/)
by copying a Let's Encrypt certificate and key into Cockpit's certificate
directory (`/etc/cockpit/ws-certs.d` by default), then enabling and starting
the Cockpit unit. It installs a certbot **deploy** renewal hook
(`renewal-hooks/deploy/10-cockpit.sh`) so the certificate is re-copied and
Cockpit restarted after each renewal, and removes any legacy `post` hook this
role previously installed. It also scopes access to Cockpit's web console
(TCP 9090) to `cockpit_allowed_cidrs`, via UFW on Ubuntu or firewalld rich rules
on RedHat-family hosts, and **refuses to run** on those hosts if that list is
empty rather than leave 9090 open to every source.

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
- A molecule scenario (`molecule/default`) exists for this role. Its Fedora
  container runs firewalld (with `NET_ADMIN`/`NET_RAW`), so the rich rules,
  blanket-service removal and the empty-allowlist failure are all verified
  there. The UFW path has no molecule platform.

## Role Variables

Validated by `meta/argument_specs.yml`. `cockpit_allowed_cidrs` must be set
on Ubuntu and RedHat-family hosts unless `cockpit_manage_firewall` is false.

| Variable | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `cockpit_hostname` | str | no | `{{ inventory_hostname }}` | Hostname used to name the copied cert/key files (`<hostname>.crt` / `.key`) and the default LE cert path. |
| `cockpit_letsencrypt_cert_path` | path | no | `/etc/letsencrypt/live/{{ cockpit_hostname }}` | Source directory holding `fullchain.pem` and `privkey.pem`. |
| `cockpit_cert_path` | path | no | `/etc/cockpit/ws-certs.d` | Directory Cockpit reads its TLS material from; the cert/key are copied here. |
| `cockpit_cert_owner` | str | no | `cockpit-ws` on Debian-family, `root` elsewhere | Owner of the certificate and key in `cockpit_cert_path`. Templated off `ansible_facts.os_family` — requires gathered facts. |
| `cockpit_cert_group` | str | no | `{{ cockpit_cert_owner }}` | Group of the certificate and key in `cockpit_cert_path`. |
| `cockpit_cert_mode` | str | no | `"0600"` | Mode applied to the certificate and key in `cockpit_cert_path`. |
| `cockpit_service_name` | str | no | `cockpit.socket` | systemd unit managed and restarted after a certificate change. `cockpit.service` is static on Fedora, so the socket is the correct unit. |
| `cockpit_allowed_cidrs` | list | **yes**, while `cockpit_manage_firewall` is true | `[]` | Source CIDRs (IPv4 or IPv6) allowed to reach Cockpit on TCP 9090. Each entry becomes a firewalld rich rule (RedHat-family) or a UFW allow rule (Ubuntu). Empty fails the role early. |
| `cockpit_manage_firewall` | bool | no | `true` | Manage the host firewall for 9090. `false` skips the allowlist check and every firewall task. Use it only when something else scopes 9090. |
| `cockpit_remove_blanket_firewalld_service` | bool | no | `true` | Disables the zone-wide `cockpit` firewalld service (RedHat-family), so only the `cockpit_allowed_cidrs` rich rules grant access. |
| `cockpit_firewalld_zone` | str | no | `""` | firewalld zone the rich rules and blanket-service removal act on. Empty means firewalld's default zone. |
| `cockpit_allowed_cidr` | str | no | *(unset)* | **Deprecated.** Single CIDR, formerly UFW-only with a `10.0.0.0/8` default. If set, it is appended to `cockpit_allowed_cidrs` for both backends and a deprecation notice is printed. |

### Deprecated: `cockpit_allowed_cidr`

Before this change the role had two variables: `cockpit_allowed_cidr` (a
string, UFW on Ubuntu only, defaulting to the whole of `10.0.0.0/8`) and
`cockpit_allowed_cidrs` (a list, firewalld only, defaulting to `[]`, which left
the firewall untouched). Now `cockpit_allowed_cidrs` drives both backends.

`cockpit_allowed_cidr` still works but has no default any more. If you set it,
it is appended to `cockpit_allowed_cidrs`, on firewalld hosts too, and the
role prints a `DEPRECATED` notice. Move the value into the list; the singular
variable will be removed in a future major release.

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
          - 2001:db8:70::/48
```

Where something else already scopes 9090 (another role, a cloud security
group), skip the firewall handling entirely:

```yaml
    - role: danmwallace.linux.cockpit
      vars:
        cockpit_hostname: cockpit.example.com
        cockpit_manage_firewall: false
```

## What the Role Does

1. On Ubuntu and RedHat-family hosts with `cockpit_manage_firewall` true,
   fails before changing anything if `cockpit_allowed_cidrs` (plus the
   deprecated `cockpit_allowed_cidr`) is empty. Prints a deprecation notice if
   `cockpit_allowed_cidr` is set.
2. Ensures the Cockpit certificate directory (`cockpit_cert_path`) exists.
3. Copies `fullchain.pem` to `<cockpit_cert_path>/<cockpit_hostname>.crt` and
   `privkey.pem` to `<cockpit_cert_path>/<cockpit_hostname>.key` from
   `cockpit_letsencrypt_cert_path` (remote-to-remote copy), owned per
   `cockpit_cert_owner` / `cockpit_cert_group` / `cockpit_cert_mode`.
4. Ensures the certbot deploy hook directory
   (`/etc/letsencrypt/renewal-hooks/deploy`) exists.
5. Installs the templated deploy hook at
   `/etc/letsencrypt/renewal-hooks/deploy/10-cockpit.sh` (mode `0755`).
6. Removes the legacy post-renewal hook at
   `/etc/letsencrypt/renewal-hooks/post/001-restart-cockpit.sh`, which the
   deploy hook supersedes.
7. Enables and starts `cockpit_service_name` (`cockpit.socket` by default).
8. On RedHat-family hosts, adds one firewalld rich rule per allowed CIDR
   permitting TCP 9090 (`family=ipv6` for IPv6 CIDRs, `ipv4` otherwise).
9. On RedHat-family hosts with `cockpit_remove_blanket_firewalld_service`
   true, disables the zone-wide `cockpit` firewalld service.
10. On Ubuntu, opens TCP 9090 in UFW from each allowed CIDR (notifies the
    `Restart cockpit` handler).
11. On Ubuntu, deletes the `9090/tcp ALLOW 10.0.0.0/8` UFW rule that the old
    default created, unless `10.0.0.0/8` is in the allowed CIDRs.

Steps 8–11 run only while `cockpit_manage_firewall` is true.

A `Restart cockpit` handler restarts `cockpit_service_name`; it is notified
by the cert/key copy tasks and by the Ubuntu UFW rule task.

## Notes

- **The deploy hook only fires on an actual renewal, and only for this
  host's own lineage.** `10-cockpit.sh` checks `$RENEWED_LINEAGE` against
  `cockpit_letsencrypt_cert_path` and exits 0 immediately if they don't
  match, so certbot renewing an unrelated certificate on the same host never
  touches Cockpit's files or restarts the service.
- **An empty `cockpit_allowed_cidrs` fails the role; it never falls back to
  "open to all".** On Ubuntu the old default opened 9090 to the whole of
  `10.0.0.0/8`. On firewalld an empty list used to skip both tasks, leaving
  Fedora's zone-wide `cockpit` service (all sources) in place. Silently skipping
  the firewall step would keep that second hole open, so the role asserts
  before it changes anything. Upgrading a play that never set either CIDR
  variable therefore **fails on purpose** until you set the list (or set
  `cockpit_manage_firewall: false`).
- **The allowlist is additive: removing a CIDR does not revoke it.** Dropping
  an entry from `cockpit_allowed_cidrs` leaves its existing rich rule or UFW
  rule on the host. Remove it by hand (`firewall-cmd --permanent
  --remove-rich-rule=...` / `ufw delete allow from <cidr> to any port 9090
  proto tcp`). The one exception is the old `10.0.0.0/8` UFW default, which
  the role removes itself unless you list it.
- **Pass `cockpit_manage_firewall` as a real boolean.** `-e
  cockpit_manage_firewall=false` arrives as the string `"false"`, which
  ansible-core rejects in a conditional. Use `-e
  '{"cockpit_manage_firewall": false}'` or set it in vars.
- **`cockpit_firewalld_zone` defaults to firewalld's default zone — set it
  explicitly if the host's active interfaces are bound to a different zone.**
  `ansible.posix.firewalld` acts on `firewall-cmd --get-default-zone` when no
  `zone:` is given. On a host whose interfaces sit in a non-default zone, the
  rich rules land in a zone nothing uses, and the blanket-service removal
  reports `changed` against that same unused zone while the real zone-wide
  `cockpit` allow survives — the CIDR restriction only *looks* enforced. Set
  `cockpit_firewalld_zone` to the zone your interfaces are actually in
  (`firewall-cmd --get-active-zones`) whenever it isn't the default.
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
