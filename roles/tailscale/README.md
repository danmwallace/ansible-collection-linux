# danmwallace.linux.tailscale

Installs Tailscale from the official stable apt repository and configures the host
as a [Tailscale](https://tailscale.com/) subnet router, advertising one or more CIDR
routes to the tailnet. Intended for dedicated always-on hosts (Raspberry Pi,
edge devices) that bridge a LAN into Tailscale.

On the first run the role authenticates with a pre-auth key and sets advertised
routes via `tailscale up`. On subsequent runs it uses `tailscale set` to update
routes without re-authenticating, keeping the role idempotent.

**Note:** Advertised routes must be approved in the Tailscale admin console
(Machines → the node → Edit route settings) before tailnet clients can use them.

## Requirements

- Ansible >= 2.16
- `ansible.posix` >= 1.5.0 (for `sysctl` module)
- Target host: Debian or Raspberry Pi OS (Bullseye/Bookworm) or Ubuntu (Jammy/Noble)
- A Tailscale account and a pre-auth key (Settings → Keys in the admin console)

## Role Variables

| Variable | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `tailscale_auth_key` | str | no | `""` | Pre-auth key for initial login. Not used if already authenticated. **Supply from vault.** |
| `tailscale_advertise_routes` | str | no | `""` | Comma-separated CIDRs to advertise, e.g. `10.10.99.0/24,192.168.70.0/24`. |
| `tailscale_hostname` | str | no | `""` | Device name in the Tailscale admin console. Defaults to system hostname. |
| `tailscale_accept_routes` | bool | no | `false` | Accept routes advertised by other subnet routers on the tailnet. |
| `tailscale_exit_node` | bool | no | `false` | Advertise this node as a Tailscale exit node. |

## Dependencies

None declared in `meta/main.yml`. Requires `ansible.posix` at the controller
(declared in the collection's `galaxy.yml` dependencies).

## Example Playbook

```yaml
- hosts: raspberry_pi
  become: true
  roles:
    - role: danmwallace.linux.tailscale
      vars:
        tailscale_auth_key: "{{ vault_tailscale_auth_key }}"
        tailscale_advertise_routes: "10.10.99.0/24,192.168.70.0/24"
        tailscale_hostname: rpi-toolkit
```

## What the Role Does

1. Enables `net.ipv4.ip_forward` and `net.ipv6.conf.all.forwarding` via `sysctl`,
   persisted to `/etc/sysctl.d/99-tailscale.conf`.
2. Downloads the Tailscale GPG key to `/usr/share/keyrings/tailscale-archive-keyring.gpg`.
3. Adds the official Tailscale stable apt repository for the host's OS release.
4. Installs the `tailscale` package via apt.
5. Enables and starts the `tailscaled` systemd service.
6. Checks whether the node is already authenticated (`tailscale status`).
7. If not authenticated: runs `tailscale up --authkey=... --advertise-routes=...`.
8. If already authenticated: runs `tailscale set --advertise-routes=...` to
   update routes without re-authenticating.

## Notes

- The `tailscale_auth_key` variable is `no_log: true` in tasks — auth key values
  are never written to Ansible output.
- After the first run, approve the advertised routes in the Tailscale admin console
  (Machines → node → Edit route settings → enable each route).
- For a multi-homed subnet router reaching a remote subnet via a gateway (e.g.
  `192.168.70.0/24` via `10.10.99.1`), ensure the host's default gateway routes
  traffic to that subnet. The role does not configure static routes — those are
  handled at the network or OS level.

## License

MIT
