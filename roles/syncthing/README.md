# danmwallace.linux.syncthing

A user's Syncthing on one machine, with its folders paired with an always-on
hub (a NAS) in a hub-and-spoke layout. Both sides are configured through
Syncthing's REST API: this machine's own instance and the hub's.

## What it does

- Installs the `syncthing` package on a regular Fedora host. On a bootc host
  the package comes with the image, and the role stops if it's missing.
- Creates the user's identity if absent (`syncthing generate`, as the user).
- Enables the user service (the `default.target.wants` link, as
  `systemctl --user enable` would) and starts it. That needs the user's
  systemd manager running: the user logged in, or lingering. Otherwise it
  stops with a message saying so.
- **This machine:**
  - adds the hub as a device at its fixed address;
  - turns global discovery and relays off (no public Syncthing
    infrastructure; reach the hub on the LAN or over a VPN such as
    Tailscale);
  - creates each folder, shares it with the hub, and writes the folder's
    `.stignore`.
- **The hub:** adds this machine as a device (named after the inventory host)
  and shares each folder with it, creating the folder at
  `folder_paths[<id>]` if the hub doesn't have it.

**The hub's API is reached safely.**
- It must be `https://`. A CA-signed certificate reached by a name it covers
  is validated the usual way: leave `api_fingerprint` empty.
- For Syncthing's own self-signed GUI certificate, which names no IP address,
  pin its SHA-256 in `api_fingerprint`. The role checks it (`openssl
  s_client`) before sending the key, then talks HTTPS without CA validation.
  A pin breaks when the certificate is renewed, so prefer a CA-signed one.
- Plain `http://` is accepted only to this machine.
- Hub calls run on `delegate_to` (e.g. `localhost`, the Ansible controller), so
  the key never has to reach the laptops, and they never run as root.
- Run the role **one host at a time** (`serial: 1`). Each host appends itself
  to the hub's folder, and two hosts doing that at once can drop each other.

**The hub only gains.** Existing devices and folders are never removed, a new
folder whose path overlaps an existing folder is refused, and an existing
folder at a different path stops the play.

Everything reads first and writes only what differs. New devices and folders
start from Syncthing's own defaults (`/rest/config/defaults/...`), since a
bare object would switch off rescans and the file watcher. An existing folder
whose path differs is never moved: the play stops and says so. In check mode
the role only reads, then reports each change a real run would make.

## Variables

| Variable | Default | Meaning |
|---|---|---|
| `syncthing_user` | `ansible_user_id` | whose Syncthing this is |
| `syncthing_folders` | `[]` | list of `{id, label, path, type, ignore}`; `path` may start with `~`; `ignore` lines go to `<path>/.stignore` |
| `syncthing_hub` | `{}` | `{name, device_id, address, api_url, api_key, api_fingerprint, delegate_to, folder_paths}` |
| `syncthing_global_discovery` | `false` | this machine's global discovery |
| `syncthing_relays` | `false` | this machine's relays |
| `syncthing_device_name` | `inventory_hostname` | this machine's name on the hub |

## Example

```yaml
- role: danmwallace.linux.syncthing
  vars:
    syncthing_user: dwallace
    syncthing_folders:
      - { id: syncthing, label: Syncthing, path: ~/Syncthing, type: sendreceive,
          ignore: ["(?d).git", "(?d)**/.obsidian/workspace*.json"] }
    syncthing_hub:
      name: syncthing-nas
      device_id: AAAAAAA-BBBBBBB-...
      address: tcp://10.10.99.3:22000
      api_url: https://nas.danwallace.cloud:20910   # CA-signed (*.danwallace.cloud): validated normally
      api_key: "{{ vault_syncthing_nas_api_key }}"
      delegate_to: localhost
      folder_paths: { syncthing: /var/syncthing/data }
```

## Gotchas

- The hub's API key travels in a header and is never logged: every API call
  is `no_log`, and so is every fact or check that holds it.
- `folder_paths` is the path *as the hub sees it*. For a NAS app in a
  container, that's the path inside the container, not the dataset's mount
  point on the host.
- Ignore patterns are per device, so the role writes `.stignore` on each
  machine, as a managed block; lines of your own in `.stignore` stay. `(?d)` lets Syncthing delete an ignored file when it would
  otherwise block removing a directory.
- Global discovery and relays off means the hub must be reachable at
  `address` from wherever the machine is.

## Tests

```bash
cd roles/syncthing && molecule test              # podman: a laptop user and a stand-in hub in one container
bash roles/syncthing/tests/check-verbose-log.sh  # the same at -vvvv, failing if the hub's API key is printed
# molecule also runs the guards: a wrong or malformed fingerprint, plain http to another
# machine, and a folder overlapping an existing one must each stop the role.
```
