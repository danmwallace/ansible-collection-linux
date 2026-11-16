# danmwallace.linux.mcp_gate

This role installs an SSH forced-command gate on a [libvirt](https://libvirt.org/) host, so desktop [MCP](https://modelcontextprotocol.io/) servers can read the host, and optionally start and shut down a fixed list of VMs, without holding a shell.

- **The gate:** `gate/mcp-gate` from the `homelab-mcp` repo, pinned to a tag or commit, installed as `/usr/local/libexec/mcp-gate`.
- **The read-only account:** `mcp-ro`. Its only authorized keys carry `command="/usr/local/libexec/mcp-gate ro",restrict`, so every SSH request runs the gate in read-only mode, with no pty and no forwarding.
- **The ops account (optional):** `mcp-ops`, created only when `mcp_gate_ops_keys` holds a key. Its keys carry `command="/usr/local/libexec/mcp-gate ops",restrict`. In `ops` mode the gate accepts only `vm-start <name>` and `vm-shutdown <name>` (ACPI), for VMs in `mcp_gate_ops_vms`, and nothing else.
- **What the gate accepts:** five read verbs, `vms`, `vm-info <name>`, `failed-units`, `journal <unit> [lines]` and `host`. It refuses anything else with exit 2, and runs each command as an argv list, never through a shell.
- **Two walls on libvirt:** libvirt reads use the read-only socket (`virsh -r -c qemu:///system`), and the account is never in `libvirt`. So libvirt itself refuses writes, even without the gate.
- **The config:** `/etc/mcp-gate.json` holds the journal units the gate may read, the storage paths it reports, and `ops_vms`.

## Requirements

- Ansible >= 2.16
- **On the controller:** `git`, and read access to `mcp_gate_source` (a private GitHub repo by default). Alternatively, set `mcp_gate_src_dir` to an existing checkout.
- **On the target:** a Fedora libvirt host running the modular daemons or `libvirtd`, with `python3` and an existing `systemd-journal` group. Its read-only libvirt socket must be readable by any user, which is the default `srw-rw-rw-` mode.

## Role Variables

| Variable | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `mcp_gate_version` | str | yes | — | The homelab-mcp git ref (tag or commit) whose `gate/mcp-gate` is installed. |
| `mcp_gate_ro_keys` | list of str | yes | — | ed25519 public keys allowed to call the gate, each a single `ssh-ed25519 <key> [comment]` line. Each gets `command=...,restrict`. |
| `mcp_gate_source` | str | no | `ssh://git@github.com/danmwallace/homelab-mcp` | The homelab-mcp git URL, cloned on the controller. |
| `mcp_gate_src_dir` | str | no | `""` | A controller path to a homelab-mcp checkout. When set, nothing is cloned. |
| `mcp_gate_cache_dir` | str | no | `~/.cache/mcp-gate` (controller user) | Where the controller keeps homelab-mcp clones, one folder per version. |
| `mcp_gate_ro_user` | str | no | `mcp-ro` | The read-only account. |
| `mcp_gate_ops_user` | str | no | `mcp-ops` | The ops account, in `libvirt`. Created only when `mcp_gate_ops_keys` holds a key. Must start with `mcp-`. |
| `mcp_gate_ops_keys` | list of str | no | `[]` | ed25519 public keys allowed to call the gate in `ops` mode, each a single `ssh-ed25519 <key> [comment]` line. Each gets `command="…mcp-gate ops",restrict`. Emptying it removes the ops account and its home (revocation). |
| `mcp_gate_ops_vms` | list of str | no | `[]` | VMs the `ops` mode may start and shut down. Empty refuses every ops request; required when `mcp_gate_ops_keys` is set. |
| `mcp_gate_journal_units` | list of str | no | `[virtqemud, virtnetworkd, virtstoraged, virtlogd, ha-dongle-reattach, cockpit, sshd, NetworkManager, chronyd]` | Units the gate's `journal` verb may read. |
| `mcp_gate_storage_paths` | list of str | no | `[/var/lib/libvirt/images]` | Paths the gate's `host` verb reports `df` for. |

## Dependencies

None declared in `meta/main.yml`. Only `ansible.builtin` modules are used.

## Example Playbook

```yaml
- hosts: hypervisors
  become: true
  roles:
    - role: danmwallace.linux.mcp_gate
      vars:
        mcp_gate_version: v0.1.0
        mcp_gate_ro_keys:
          - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... srv01-mcp@frmwrk
```

## What the Role Does

1. Checks that `mcp_gate_ro_keys` has at least one key, that every ro and ops key is a single `ssh-ed25519` line, that ops keys come with a non-empty `mcp_gate_ops_vms`, that no key is in both lists, and that `mcp_gate_ops_user` starts with `mcp-` (revoking removes that account and its home, so it can never be a real login).
2. Clones `mcp_gate_source` at `mcp_gate_version` on the controller, into `<mcp_gate_cache_dir>/<version>`. It runs once, as the controller user, without become, and in check mode too: it changes nothing on the target, and the next step needs the file. It's skipped when `mcp_gate_src_dir` is set.
3. Installs `gate/mcp-gate` as `/usr/local/libexec/mcp-gate` (root, 0755).
4. Writes `/etc/mcp-gate.json` from `mcp_gate_journal_units`, `mcp_gate_storage_paths` and `mcp_gate_ops_vms`.
5. For `mcp-ro`, and then for `mcp-ops` when it has keys (`tasks/account.yml`), creates the account with a locked password (`!`), `/bin/bash` as its shell, and fixed extra groups (`append: false`, so other groups are removed): `systemd-journal` for `mcp-ro`, `libvirt` and `systemd-journal` for `mcp-ops`. There's no `/etc/skel` copy.
6. Makes each account's home folder root-owned (0755) and removes everything in it except `.ssh`, such as the `/etc/skel` files 1.10.0 copied in. Then makes `~/.ssh` root-owned (0755) and writes `authorized_keys` (root, 0644) with one forced-command line per key, in that account's mode.
7. With no `mcp_gate_ops_keys`, removes the ops account and its home, so emptying the list revokes every ops key.
8. Fails if `mcp-ro` is in `libvirt`. In check mode on a new host, the account doesn't exist yet, so this check is skipped.

## Notes

- **The shell must be a real shell.** sshd runs a forced command through the account's login shell, so `/sbin/nologin` would refuse every request. The `command=…,restrict` options are what keep the key from being a login: no pty, no forwarding, nothing but the gate.
- **`systemd-journal` lets the account read every journal.** The gate only ever runs `journalctl -u <unit>` for units in `mcp_gate_journal_units`, and the key can run nothing but the gate.
- **The account owns nothing it could use to get around the gate.** Its home, `.ssh` and `authorized_keys` are root-owned, which sshd's `StrictModes` accepts, and the home holds nothing else.
  - If the account owned its home, it could rename `.ssh` and swap in a key file without `command=…,restrict`.
  - If it owned a `.bashrc` or `~/.config`, code planted there would run through its login shell or user manager before or beside the gate.
- **`libvirt` grants full management.** Membership gives full libvirt control through libvirt's default polkit rule, so the role stops rather than run with it. Reads don't need it: the read-only socket is open to every user.
- **`mcp-ops` is in `libvirt` on purpose.** Start and shutdown need management access through libvirt's polkit rule, so the key's forced command (`mcp-gate ops`, `restrict`) and the gate's `ops_vms` list are what limit it: no other verb, no other VM, no destroy, undefine or reboot. A VM that's already in the requested state is left alone.
- **In `ro` mode, the gate only reads.** It never touches NetworkManager, bridges, firewalld or VM definitions. It logs each request to journald under the identifier `mcp-gate`, with the client address (`journalctl -t mcp-gate`).
- **Replies are JSON.** The gate answers with one JSON object, exiting 0 (ok), 1 (a command failed), 2 (refused) or 124 (timed out). The protocol lives in homelab-mcp's `gate/mcp-gate`.
- **Molecule:** the scenario builds a Fedora 44 container and stubs `virsh`. On the controller it builds a local git repo with a `test` tag from `MCP_GATE_SRC_DIR` (default `~/Code/homelab-mcp`), so the role's real clone path runs, first in a `check` stage on a fresh cache and then in converge. It checks the allowed verbs, the refusals (unknown verb, shell characters, unknown or flag-like VM names, unlisted units, no command, unknown mode), the account's groups and password, and file ownership.

## License

MIT
