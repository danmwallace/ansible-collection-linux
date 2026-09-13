# danmwallace.linux.libvirt_usb_reattach

Keeps USB passthrough devices attached to running [libvirt](https://libvirt.org/)
domains after they re-enumerate on the host. libvirt binds a running domain's
USB hostdev to the bus/device numbers resolved at domain start; when the
device is replugged or reset it gets new bus/device numbers and the guest
silently loses it. This role installs, per configured device, a udev rule
(matched by USB serial) that starts a templated oneshot systemd unit
(`libvirt-usb-reattach@<name>.service`), which live detach/attaches the
device to its domain only when the domain's current binding has gone stale.

The domain's persistent XML must already contain a vendor/product USB
hostdev for the device — this role only reacts to re-enumeration events, it
never edits domain definitions.

## Requirements

- Ansible >= 2.16
- A libvirt host (`virsh`, `virtqemud`/`libvirtd`) with the target domain(s)
  already defined, each with a matching vendor/product USB hostdev in its
  persistent XML
- `bash` on the target host (the re-attach script is a bash script installed
  by the role)

## Role Variables

| Variable | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `libvirt_usb_reattach_devices` | list of dict | no | `[]` | USB devices to keep attached to their libvirt domains. An empty list installs the re-attach script and unit template but defines no per-device udev rules, config, or hostdev XML (no-op). Each entry: `name` (str, required — short identifier, lowercase letters/digits/`_`/`-`, used in file and unit names), `domain` (str, required — libvirt domain the device is passed through to; letters, digits, `_`/`.`/`+`/`:`/`-` only), `vendor_id` (str, required — USB vendor ID as 4 lowercase hex digits, no `0x`, e.g. `"10c4"`), `product_id` (str, required — USB product ID as 4 lowercase hex digits, no `0x`, e.g. `"ea60"`), `serial` (str, required — USB serial number, the sysfs `serial` attribute, distinguishes identical adapters; letters, digits, `.`/`_`/`:`/`-` only). |
| `libvirt_usb_reattach_libvirt_uri` | str | no | `qemu:///system` | libvirt connection URI used by `virsh`. |
| `libvirt_usb_reattach_service_after` | list of str | no | `[virtqemud.service, libvirtd.service]` | Units the re-attach service orders itself after. |

## Dependencies

None declared in `meta/main.yml`.

## Example Playbook

```yaml
- hosts: libvirt_hosts
  become: true
  roles:
    - role: danmwallace.linux.libvirt_usb_reattach
      vars:
        libvirt_usb_reattach_devices:
          - name: ha-zigbee-dongle
            domain: home-assist
            vendor_id: "10c4"
            product_id: "ea60"
            serial: "64d185be7b4bef11bfbbb9a079f42d1b"
```

## What the Role Does

1. Asserts each entry in `libvirt_usb_reattach_devices` has a valid `name`
   (`^[a-z0-9][a-z0-9_-]*$`), 4-hex-digit `vendor_id`/`product_id`, a `serial`
   matching `^[A-Za-z0-9._:-]+$`, and a `domain` matching
   `^[A-Za-z0-9_.+:-]+$`.
2. Creates `/etc/libvirt-usb-reattach` and `/etc/libvirt/hostdev` (mode
   `0755`).
3. Installs the re-attach script to `/usr/local/sbin/libvirt-usb-reattach`
   (mode `0755`) — see [What the script does](#what-the-script-does).
4. Installs the templated unit to
   `/etc/systemd/system/libvirt-usb-reattach@.service`.
5. For each device, writes `/etc/libvirt-usb-reattach/<name>.conf` with
   `DOMAIN`, `SERIAL`, `HOSTDEV_XML` and `LIBVIRT_URI`.
6. For each device, writes the hostdev XML fragment (vendor/product only, no
   serial) to `/etc/libvirt/hostdev/<name>.xml` — this is the XML passed to
   `virsh attach-device`/`detach-device`.
7. For each device, writes the udev rule to
   `/etc/udev/rules.d/99-libvirt-usb-reattach-<name>.rules`, matching on
   `idVendor`/`idProduct`/`serial` and starting
   `libvirt-usb-reattach@<name>.service` via `SYSTEMD_WANTS` on a USB `add`
   event.
8. Flushes handlers (`ansible.builtin.meta: flush_handlers`) so the unit is
   loadable before any udev event can fire it.

Two handlers exist: `Reload systemd` (daemon-reload) fires when the unit
template changes; `Reload udev rules` (`udevadm control --reload`) fires
when any device's rule file changes, but is skipped when
`ansible_facts['virtualization_type']` is `container`, `podman` or `docker`
(no udevd runs inside test containers — on real hosts udevd re-reads changed
rules on the next event regardless).

### What the script does

`/usr/local/sbin/libvirt-usb-reattach <name>` (invoked by the unit as `%i`):

1. Sources `/etc/libvirt-usb-reattach/<name>.conf` for `DOMAIN`, `SERIAL`,
   `HOSTDEV_XML`, `LIBVIRT_URI`.
2. Exits (no-op) if the domain isn't running — libvirt binds USB at domain
   start anyway.
3. Exits (no-op) if no device with the configured `SERIAL` is present under
   `/sys/bus/usb/devices`.
4. Reads the device's current `busnum`/`devnum` and checks the domain's live
   XML (`virsh dumpxml`) for a matching `<address bus='...' device='...'/>`.
   Exits (no-op) if it already matches.
5. Otherwise, detaches the stale hostdev (`virsh detach-device --live`,
   ignoring failure — the entry may already be gone) and re-attaches it
   (`virsh attach-device --live`) using `HOSTDEV_XML`.

## Gotchas

- The domain's persistent XML must already have a vendor/product hostdev;
  the role does not edit domains.
- Devices are attached by USB vendor:product — the libvirt hostdev XML has
  no serial match, only vendor/product. The serial only decides *when* the
  udev rule fires. libvirt does not "pick the wrong one" when devices
  collide: if more than one device matching a given vendor:product is
  present on the host at once (whether configured in this role or not),
  `virsh attach-device` refuses with a "multiple USB devices" error — and
  the domain's own persistent vendor/product hostdev has the same
  limitation at domain start. The role therefore expects one device per
  vendor:product per host.
- The re-attach unit has `TimeoutStartSec=2min`; a hung `virsh` call fails
  the unit instead of wedging indefinitely.
- Removing a device from `libvirt_usb_reattach_devices` leaves its files
  behind (config, hostdev XML, udev rule) — there is no `state: absent`
  cleanup.
- Test on real hardware by cycling the hub port
  (`echo 1 > /sys/bus/usb/devices/<hub>:1.0/usbN-portM/disable`, then `echo
  0 > ...`), never by unbinding the USB driver — that kills QEMU's handle on
  the device without re-enumerating it, so the udev rule never fires.
- The unit/log name pattern is `libvirt-usb-reattach@<name>.service`. Logs:
  `journalctl -u 'libvirt-usb-reattach@*'`.
- Before reflashing a passed-through device, rename its rule
  (`/etc/udev/rules.d/99-libvirt-usb-reattach-<name>.rules`) to add a
  `.disabled` suffix and run `udevadm control --reload`, or the unit may
  grab the device back mid-flash when it re-enumerates.

## License

MIT
