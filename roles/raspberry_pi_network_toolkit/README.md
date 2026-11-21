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
| `docker_compose_version` | `v5.8.0` | Reserved compose version variable (currently not used in tasks) |
| `portainer_socket_proxy_version` | `3.4@sha256:027f9fa5…` | docker-socket-proxy tag plus multi-arch index digest; see Notes |
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
- Portainer (since 2.43) needs a one-time setup token to create the first
  administrator on a new instance; read it with `docker logs portainer`.
- Portainer and Uptime Kuma migrate their databases when a newer image starts
  and can't be rolled back afterwards. Back up the `portainer_data` and
  `uptime-kuma` volumes before raising `portainer_version` or
  `uptime_kuma_version` on an existing install.
- docker-socket-proxy publishes no versioned tags after v0.6.0, only the
  weekly-rebuilt `lts`, `latest` and `3.4`. `portainer_socket_proxy_version`
  pins `3.4` to the digest of its multi-arch image index
  (`3.4@sha256:<digest>`), so the image never changes under you and Docker
  still picks the arm64 or arm/v7 build. To update, take the index digest,
  not a per-platform one:
  `skopeo inspect --raw docker://ghcr.io/tecnativa/docker-socket-proxy:3.4 | sha256sum`
  (or `docker buildx imagetools inspect ghcr.io/tecnativa/docker-socket-proxy:3.4`).
