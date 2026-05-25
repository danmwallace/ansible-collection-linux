# raspberry_pi_network_toolkit

Configure a Raspberry Pi (or Debian/Ubuntu host) as a portable network diagnostics and reconnaissance toolkit.

## What this role does

- Installs base packages and system prerequisites
- Installs network diagnostics utilities (for example `nmap`, `tcpdump`, `masscan`, `iperf3`)
- Installs security assessment tools (for example `nikto`, `lynis`, `hydra`, `hashcat`)
- Installs monitoring tools (for example `htop`, `btop`, `glances`)
- Optionally installs Docker and Docker Compose plugin
- Optionally deploys monitoring containers with Docker Compose
- Deploys helper scripts to a configurable toolkit directory
- Applies user/system configuration (tmux config and logrotate policy)

## Requirements

- Ansible `>= 2.9`
- Target OS:
  - Debian: buster, bullseye, bookworm
  - Ubuntu: focal, jammy
- Internet access from the managed host for apt repositories and git clone operations
- Community collection for Docker tasks:
  - `community.docker`

## Role Variables

Defaults are defined in `defaults/main.yml`.

| Variable | Default | Description |
|---|---|---|
| `toolkit_user` | `pi` | Local user that owns toolkit assets and gets Docker group membership |
| `install_docker` | `true` | Install and configure Docker engine + compose plugin |
| `install_gui_tools` | `false` | Reserved toggle for GUI tools (currently not used in tasks) |
| `docker_compose_version` | `v2.23.0` | Reserved compose version variable (currently not used in tasks) |
| `enable_monitoring` | `true` | Deploy monitoring stack with Docker Compose |
| `monitoring_ports.portainer` | `9000` | Portainer host port |
| `monitoring_ports.netdata` | `19999` | Netdata host port |
| `monitoring_ports.uptime_kuma` | `3001` | Uptime Kuma host port |
| `monitoring_ports.wireshark_web` | `3000` | Wireshark web host port |
| `toolkit_scripts_dir` | `/opt/network-toolkit` | Directory where helper scripts are deployed |
| `portainer_hostname` | `portainer.example.com` | Hostname for Portainer (Traefik labels/template use) |
| `netdata_hostname` | `netdata.example.com` | Hostname for Netdata (Traefik labels/template use) |
| `uptime_kuma_hostname` | `uptime.example.com` | Hostname for Uptime Kuma (Traefik labels/template use) |

## Dependencies

No Ansible role dependencies are declared in `meta/main.yml`.

## Example Playbook

```yaml
- hosts: raspberry_pi
  become: true
  roles:
    - role: raspberry_pi_network_toolkit
      vars:
        toolkit_user: pi
        install_docker: true
        enable_monitoring: true
        toolkit_scripts_dir: /opt/network-toolkit
        monitoring_ports:
          portainer: 9000
          netdata: 19999
          uptime_kuma: 3001
          wireshark_web: 3000
```

## Notes

- Docker monitoring services are only deployed when both `install_docker` and `enable_monitoring` are `true`.
- The role creates an external Docker network named `proxy_network`.
- `testssl.sh` is installed to `/opt/testssl.sh` and linked at `/usr/local/bin/testssl`.

