# danmwallace.linux.nm_bridge

Declares [NetworkManager](https://networkmanager.dev/) bridge connections and the ethernet or
802.1Q VLAN ports enslaved to them, from a single `nm_bridge_bridges` list. Each profile is
persisted with `nmcli con modify` through `community.general.nmcli`, matched by connection
name so the UUIDs NetworkManager already assigned survive. Profiles that were active and
changed are applied with `nmcli device reapply`, which updates the live device in place.

The role exists because of how bridges fail on a libvirt hypervisor: re-creating a bridge
(`nmcli con up` on an active connection, or NetworkManager re-activating it after a failed
DHCP lease) silently detaches every guest tap on it. The role therefore never runs
`con up` on a connection that was already active. It only brings up profiles that exist but
are inactive, which is the freshly provisioned host with no guests to orphan.

## Requirements

- Ansible >= 2.16
- `community.general` (for the `nmcli` module; declared by the collection's `galaxy.yml`)
- Target host running NetworkManager with the `nmcli` CLI, and `become` privileges

## Role Variables

| Variable | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `nm_bridge_bridges` | list of dict | no | `[]` | Bridge connections to manage. An empty list is a no-op. |

Each entry of `nm_bridge_bridges`:

| Key | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `name` | str | yes | — | Connection id, also used as the bridge interface name. |
| `stp` | bool | no | `true` | Enable Spanning Tree on the bridge. |
| `forward_delay` | int | no | — | STP forward delay in seconds. Left unmanaged when omitted. |
| `priority` | int | no | `32768` | STP bridge priority. Always written, because `community.general.nmcli` otherwise imposes its own default of 128 and reports a change on every bridge NetworkManager created with its default of 32768. |
| `ipv4` | dict | no | — | IPv4 configuration of the bridge itself. Omit for an L2-only bridge with no host address. |
| `ipv4.method` | str | no | `disabled` | NetworkManager IPv4 method: `disabled`, `auto` or `manual`. |
| `ipv4.address` | str | no | — | Address in CIDR notation. Required when `method` is `manual`. |
| `ipv4.gateway` | str | no | — | Default gateway. |
| `ipv4.dns` | list of str | no | — | DNS servers. |
| `ipv6_method` | str | no | `disabled` | NetworkManager IPv6 method: `disabled`, `auto`, `manual`, `link-local` or `ignore`. |
| `ports` | list of dict | no | `[]` | Port connections enslaved to this bridge. |
| `ports[].name` | str | yes | — | Connection id of the port profile. |
| `ports[].type` | str | yes | — | `ethernet` or `vlan`. |
| `ports[].interface` | str | yes | — | Device name the port profile binds to (for `vlan`, the VLAN device such as `eth0.70`). |
| `ports[].parent` | str | no | — | Parent device of a `vlan` port. Required for `vlan`. |
| `ports[].vlan_id` | int | no | — | 802.1Q VLAN id of a `vlan` port. Required for `vlan`. |

## Dependencies

None declared in `meta/main.yml`. The collection's `galaxy.yml` requires
`community.general >= 8.0.0`.

## Example Playbook

A hypervisor whose NIC carries the untagged management network on `virbr0` and a tagged DMZ
on `vlan70`, where the host keeps a static address on the first and no address on the second:

```yaml
- hosts: hypervisors
  become: true
  roles:
    - role: danmwallace.linux.nm_bridge
      vars:
        nm_bridge_bridges:
          - name: virbr0
            stp: true
            forward_delay: 2
            ipv4:
              method: manual
              address: 10.10.99.4/24
              gateway: 10.10.99.1
              dns:
                - 10.10.99.1
            ports:
              - name: virbr0-slave-enp44s0u1
                type: ethernet
                interface: enp44s0u1
          - name: vlan70
            stp: false
            ports:
              - name: enp44s0u1.70
                type: vlan
                interface: enp44s0u1.70
                parent: enp44s0u1
                vlan_id: 70
```

## What the Role Does

1. Validates every bridge and port entry: names must match `[A-Za-z0-9][A-Za-z0-9_.-]*`, a
   `manual` IPv4 method needs an `address`, and a `vlan` port needs both `parent` and
   `vlan_id`.
2. Records which NetworkManager connections are active before anything is modified
   (`nmcli -t -f NAME connection show --active`). This snapshot decides later whether a
   changed profile is reapplied or brought up.
3. Ensures each bridge profile exists with the declared STP, forward delay, priority and
   IPv4/IPv6 settings (`community.general.nmcli`, `state: present`). Existing profiles are
   modified by name; nothing is activated here.
4. Ensures each port profile exists, bound to its device and enslaved to its bridge, with the
   VLAN id and parent for `vlan` ports.
5. Builds two lists: changed profiles that were active before the run (to reapply), and
   declared profiles that were not active (to bring up).
6. Runs `nmcli device reapply` for each changed, previously active profile. If NetworkManager
   refuses to reapply a property, the play fails with the device name and the manual
   recovery steps.
7. Runs `nmcli connection up` for each declared profile that was not active.

Steps 6 and 7 are skipped in check mode; the `nmcli` module itself is check-mode aware and
reports the profile diff.

## Notes

- **Only declared keys are enforced.** `community.general.nmcli` modifies the properties it
  is given and leaves the rest alone, so settings this role does not model (for example
  `connection.autoconnect-ports`) are neither set on a fresh host nor corrected on an
  existing one.
- **A refused reapply leaves the profile modified on disk.** NetworkManager can reapply IP
  settings in place but refuses some bridge-level properties. When that happens the saved
  profile already carries the change and takes effect at the next reboot, or when you run
  `nmcli con up <name>` yourself in a maintenance window. On a hypervisor, do that only after
  stopping the guests on that bridge, or re-attach each one afterwards with
  `ip link set <vnetN> master <bridge>`.
- **No molecule scenario.** The collection's molecule runs in podman containers, where
  NetworkManager bridge management is not meaningful. The acceptance test is a `--check
  --diff` run against the real host that must report zero changes when the data describes
  the current state.
- Keep a static lease on the DHCP server for any bridge that uses `method: manual`, so the
  address is never offered to another device.

## License

MIT
