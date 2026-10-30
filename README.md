# polt — Project Poltergeist CLI

Unified host setup and full libvirt/KVM virtual machine lifecycle management, all from a single command-line interface.

> **polt** automates everything from preparing a Linux host for virtualization to creating, starting, stopping, inspecting, and deleting VMs — plus managing libvirt networks and storage pools.

---

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick Start (5-Step Workflow)](#quick-start)
- [Usage Examples](#usage-examples)
- [Command Reference](#command-reference)
- [Network Subcommands](#network-subcommands)
- [Storage Subcommands](#storage-subcommands)
- [Aliases](#aliases)
- [Safety & Behavior](#safety--behavior)
- [Full Manual](#full-manual)
- [Contributing](#contributing)
- [License](#license)

---

## Features

| Area | What it does |
|------|-------------|
| **Host setup** | `polt setup` checks CPU virtualization, installs KVM/libvirt via your distro's package manager, starts `libvirtd`, loads KVM modules, adds your user to `libvirt`/`kvm` groups, and verifies `/dev/kvm` access. |
| **VM creation** | `polt create-vm` builds a new VM from an ISO with customizable RAM, vCPUs, disk size, UEFI/BIOS, os-variant, pool, and network. Auto-cleans up storage volumes if creation fails. |
| **VM lifecycle** | Start, stop (graceful with timeout, then force), list, inspect, and delete VMs. |
| **Console** | `polt console-vm` attaches to a VM serial console (`Ctrl+]` to detach). |
| **Networking** | `polt network` lists, creates, starts, stops, and sets autostart on libvirt networks. |
| **Storage** | `polt storage` manages pools and qcow2 volumes (create, delete, list, autostart). |
| **Safety** | Confirmation prompts for deletion, graceful shutdown before power-off, no orphaned disks on failure. |

---

## Requirements

- Linux host (tested on Debian/Ubuntu, RHEL/Fedora, Arch, openSUSE)
- `bash` 4+
- Root / `sudo` access for host setup
- `virsh`, `virt-install`, `libvirtd` (installed automatically by `polt setup` if missing)
- Hardware virtualization enabled in BIOS/UEFI (Intel VT-x or AMD-V)

---

## Installation

Clone the repository and make the scripts executable:

```bash
git clone https://github.com/your-username/project-poltergeist.git
cd project-poltergeist
chmod +x polt Setup.sh create-vm.sh delete-vm.sh lib/common.sh *.sh
```

Run from the project directory:

```bash
./polt help
```

Or install to your PATH (optional):

```bash
sudo cp polt /usr/local/bin/polt
sudo cp Setup.sh create-vm.sh delete-vm.sh list-vms.sh start-vm.sh stop-vm.sh info-vm.sh console-vm.sh network.sh storage.sh /usr/local/lib/polt/
sudo cp -r lib /usr/local/lib/polt/
# Then run from anywhere:
polt help
```

---

## Quick Start (5-Step Workflow)

```bash
# 1. Prepare the host for virtualization
./polt setup

# 2. Ensure the default NAT network exists
./polt network default

# 3. Ensure the default storage pool exists
./polt storage default

# 4. Create and start a VM from an ISO
./polt create-vm --name vm1 --iso ./ubuntu.iso \
  --memory 8192 --vcpus 4 --disk 60 --uefi --start

# 5. Attach to the serial console to complete OS installation
./polt console-vm --name vm1
```

> After step 1, log out and back in so your new `libvirt` and `kvm` group membership applies.

---

## Usage Examples

### Create a VM
```bash
./polt create-vm --name webserver --iso ./ubuntu-server.iso \
  --memory 4096 --vcpus 2 --disk 40 --uefi --start

./polt create-vm --name test-vm --iso ./debian.iso \
  --os-variant debian12 --pool default --network default
```

### List VMs
```bash
./polt list-vms
./polt list-vms --state running
./polt list-vms --state shutoff
```

### Start / stop a VM
```bash
./polt start-vm --name vm1
./polt start-vm --name vm1 --console
./polt start-vm --name vm1 --wait

./polt stop-vm --name vm1
./polt stop-vm --name vm1 --force
./polt stop-vm --name vm1 --timeout 120
```

### Inspect a VM
```bash
./polt info-vm --name vm1
./polt info-vm --name vm1 --security-info
```

### Console access
```bash
./polt console-vm --name vm1
./polt console-vm --name vm1 --force
```

### Delete a VM
```bash
./polt delete-vm --name old-vm
./polt delete-vm --name old-vm --remove-storage --yes
./polt delete-vm --name running-vm --force --remove-storage
```

### Manage networks
```bash
./polt network list
./polt network default
./polt network start --name default
./polt network stop --name mynet
./polt network autostart --name default
```

### Manage storage
```bash
./polt storage list
./polt storage default
./polt storage volumes --pool default
./polt storage create-vol --pool default --name mydisk --size 40
./polt storage delete-vol --pool default --name mydisk
./polt storage autostart --pool default
```

---

## Command Reference

| Command | Alias | Purpose |
|---------|-------|---------|
| `setup` | — | Prepare host (KVM, libvirt, groups, /dev/kvm) |
| `create-vm` | `create` | Create a new VM from an ISO |
| `delete-vm` | `delete` | Undefine/delete a VM (optional storage removal) |
| `list-vms` | `list` | List all VMs and states |
| `start-vm` | `start` | Start a shutoff/paused VM |
| `stop-vm` | `stop` | Gracefully stop, with optional force |
| `info-vm` | `info` | Show detailed VM config and state |
| `console-vm` | `console` | Connect to VM serial console |
| `network` | — | Manage libvirt networks |
| `storage` | — | Manage libvirt storage pools/volumes |
| `help` | — | Show help |

Run `./polt <command> --help` for command-specific options.

---

## Network Subcommands

Command: `polt network <subcommand> [options]`

| Subcommand | Purpose |
|------------|---------|
| `list` | List all networks with state, autostart, and bridge |
| `default` | Ensure the `default` NAT network exists and is active |
| `start --name NAME` | Start a defined network |
| `stop --name NAME` | Stop (destroy) an active network |
| `autostart --name NAME` | Enable autostart for a network |

Global option: `--connection URI` (default: `qemu:///system`)

---

## Storage Subcommands

Command: `polt storage <subcommand> [options]`

| Subcommand | Purpose |
|------------|---------|
| `list` | List all storage pools with state, autostart, capacity |
| `volumes --pool NAME` | List volumes inside a storage pool |
| `default` | Ensure the `default` pool exists and is active |
| `create-vol --pool NAME --name VOL --size GiB` | Create a qcow2 volume |
| `delete-vol --pool NAME --name VOL` | Delete a volume |
| `autostart --pool NAME` | Enable autostart for a pool |

Global option: `--connection URI` (default: `qemu:///system`)

---

## Aliases

| Full command | Short alias |
|--------------|-------------|
| `create-vm` | `create` |
| `delete-vm` | `delete` |
| `list-vms` | `list` |
| `start-vm` | `start` |
| `stop-vm` | `stop` |
| `info-vm` | `info` |
| `console-vm` | `console` |

Example: `./polt start --name vm1` == `./polt start-vm --name vm1`

---

## Safety & Behavior

- **Graceful shutdown first:** `stop-vm` and `delete-vm --force` attempt ACPI shutdown before falling back to hard power-off (`virsh destroy`).
- **No orphaned disks:** `create-vm` removes the storage volume automatically if VM definition fails mid-way.
- **Confirmation required:** `delete-vm` requires typing the exact VM name interactively unless `--yes` is supplied.
- **Shared storage warning:** `delete-vm --remove-storage` deletes **all** attached volumes, including images shared with other VMs.
- **Group membership:** After `polt setup`, log out and back in for new `libvirt`/`kvm` group membership to apply.

---

## Full Manual

For the complete command reference with every option, subcommand, purpose, and example, see:

[VM_CLI_MANUAL.md](./VM_CLI_MANUAL.md)

Or run inline help:

```bash
./polt help
./polt create-vm --help
./polt network --help
./polt storage --help
```

---

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/your-feature`)
3. Commit your changes (`git commit -m "Add your feature"`)
4. Push to the branch (`git push origin feature/your-feature`)
5. Open a Pull Request

Please follow the existing shell style (`set -Eeuo pipefail`, double-quoted variables, `die()`/`need_value()` helpers).

---

## License

MIT License. See [LICENSE](./LICENSE) for details.

---

**Project Poltergeist** — Manage your virtual machines with confidence.