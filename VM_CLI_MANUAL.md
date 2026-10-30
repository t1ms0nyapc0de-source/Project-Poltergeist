# Project Poltergeist — VM CLI Manual

**Tool:** `polt`  
**Purpose:** Unified host setup and full libvirt/KVM virtual machine lifecycle management.  
**Target platform:** Linux hosts with `virsh`, `virt-install`, and `libvirtd` available.

---

## Table of Contents

1. [Global Usage](#global-usage)
2. [Getting Started (5-Step Workflow)](#getting-started)
3. [Command Reference](#command-reference)
   - [setup](#setup)
   - [create-vm](#create-vm)
   - [delete-vm](#delete-vm)
   - [list-vms](#list-vms)
   - [start-vm](#start-vm)
   - [stop-vm](#stop-vm)
   - [info-vm](#info-vm)
   - [console-vm](#console-vm)
   - [network](#network)
   - [storage](#storage)
4. [Network Subcommands](#network-subcommands)
5. [Storage Subcommands](#storage-subcommands)
6. [Aliases](#aliases)
7. [Exit Codes](#exit-codes)
8. [Safety & Behavior Notes](#safety--behavior-notes)

---

## Global Usage

```bash
polt <command> [options]
polt <command> --help
```

If no command is given, `polt` prints the full help screen and exits.

---

## Getting Started (5-Step Workflow)

```bash
# 1. Prepare the host (KVM, libvirt, groups, /dev/kvm)
polt setup

# 2. Ensure virtual networking exists (default NAT network)
polt network default

# 3. Ensure default storage pool exists
polt storage default

# 4. Create and start a VM from an ISO
polt create-vm --name vm1 --iso ./ubuntu.iso --memory 8192 --vcpus 4 --disk 60 --uefi --start

# 5. Attach to the serial console to complete OS installation
polt console-vm --name vm1
```

---

## Command Reference

### setup

**Purpose:** One-time host preparation. Checks CPU virtualization support, installs KVM/libvirt packages via the distro package manager, starts `libvirtd`, loads KVM kernel modules, adds your user to the `libvirt` and `kvm` groups, and verifies `/dev/kvm` permissions.

**Usage:**
```bash
polt setup
```

**Options:** None.

**Notes:**
- Must be run as a user with `sudo` privileges (or as root).
- After group changes, you must log out and back in for new group membership to take effect.
- If virtualization is disabled in BIOS/UEFI, the script offers to reboot into firmware setup (on EFI systems) or instructs you to reboot manually (legacy BIOS).

---

### create-vm (alias: create)

**Purpose:** Create a new libvirt virtual machine from a bootable ISO image. Creates a qcow2 storage volume, defines the VM XML, and optionally starts the installer immediately.

**Usage:**
```bash
polt create-vm --name NAME --iso PATH [options]
```

**Required options:**
| Option | Purpose |
|--------|---------|
| `--name NAME` | New libvirt VM name (letters, numbers, dot, underscore, hyphen; max 63 chars, must start with alphanumeric) |
| `--iso PATH` | Path to a readable bootable installation ISO |

**Optional options:**
| Option | Default | Purpose |
|--------|---------|---------|
| `--memory MiB` | `4096` | RAM in MiB (positive integer) |
| `--vcpus COUNT` | `2` | Virtual CPUs (positive integer) |
| `--disk GiB` | `40` | Disk size in GiB (positive integer) |
| `--disk-name NAME.qcow2` | `NAME.qcow2` | Storage volume filename (must end in `.qcow2`, no path separators) |
| `--pool NAME` | `default` | Libvirt storage pool to place the disk in |
| `--network NAME` | `default` | Libvirt network to attach |
| `--os-variant NAME` | `generic` | osinfo variant (e.g. `ubuntu24.04`, `debian12`) |
| `--uefi` | off | Boot with UEFI firmware instead of BIOS |
| `--start` | off | Start the VM installer immediately after defining |
| `--connection URI` | `qemu:///system` | Libvirt connection URI |

**Examples:**
```bash
polt create-vm --name webserver --iso ./ubuntu-server.iso --memory 4096 --vcpus 2 --disk 40 --uefi --start
polt create-vm --name test-vm --iso ./debian.iso --pool default --network default --os-variant debian12
```

**Notes:**
- The VM is created shut down unless `--start` is given.
- If creation fails after the storage volume is made, the volume is automatically cleaned up (no orphaned disks).

---

### delete-vm (alias: delete)

**Purpose:** Undefine (delete) a libvirt VM definition. Optionally removes all attached storage volumes.

**Usage:**
```bash
polt delete-vm --name NAME [options]
```

**Required options:**
| Option | Purpose |
|--------|---------|
| `--name NAME` | Existing libvirt VM name to delete |

**Optional options:**
| Option | Purpose |
|--------|---------|
| `--remove-storage` | Also permanently delete all storage volumes attached to the VM |
| `--force` | Power off a running VM before deletion (attempts graceful shutdown first) |
| `--yes` | Skip the typed-name confirmation prompt |
| `--connection URI` | Libvirt connection URI (default: `qemu:///system`) |

**Examples:**
```bash
polt delete-vm --name old-vm
polt delete-vm --name old-vm --remove-storage --yes
polt delete-vm --name running-vm --force --remove-storage
```

**Safety:**
- By default, only the VM definition is removed; virtual disks are preserved.
- `--remove-storage` deletes **all** attached storage volumes, including images shared with other VMs.
- Interactive confirmation requires typing the exact VM name unless `--yes` is used.
- A running VM is shut down gracefully before being force-powered-off.

---

### list-vms (alias: list)

**Purpose:** List all defined libvirt domains (VMs) and their current states.

**Usage:**
```bash
polt list-vms [options]
```

**Optional options:**
| Option | Purpose |
|--------|---------|
| `--connection URI` | Libvirt connection URI (default: `qemu:///system`) |
| `--state STATE` | Filter by state: `running`, `shutoff`, `paused`, `crashed` |
| `--all` | Accepted for compatibility (all states are listed by default) |

**Output columns:** `NAME`, `STATE`, `AUTOSTART`

**Examples:**
```bash
polt list-vms
polt list-vms --state running
polt list-vms --state shutoff
```

---

### start-vm (alias: start)

**Purpose:** Start a shutoff or paused libvirt VM.

**Usage:**
```bash
polt start-vm --name NAME [options]
```

**Required options:**
| Option | Purpose |
|--------|---------|
| `--name NAME` | VM name to start |

**Optional options:**
| Option | Purpose |
|--------|---------|
| `--console` | Attach to the VM serial console after starting |
| `--wait` | Wait for the VM to reach `running` state before returning |
| `--connection URI` | Libvirt connection URI (default: `qemu:///system`) |

**Examples:**
```bash
polt start-vm --name vm1
polt start-vm --name vm1 --console
polt start-vm --name vm1 --wait
```

**Notes:**
- If the VM is already running, the command reports success and exits.
- If paused, it resumes instead of starting.

---

### stop-vm (alias: stop)

**Purpose:** Gracefully stop a running VM, with optional forced power-off.

**Usage:**
```bash
polt stop-vm --name NAME [options]
```

**Required options:**
| Option | Purpose |
|--------|---------|
| `--name NAME` | VM name to stop |

**Optional options:**
| Option | Default | Purpose |
|--------|---------|---------|
| `--force` | off | Power off immediately (`virsh destroy`) instead of graceful shutdown |
| `--timeout SECS` | `60` | Seconds to wait for graceful shutdown before falling back to force |
| `--connection URI` | `qemu:///system` | Libvirt connection URI |

**Examples:**
```bash
polt stop-vm --name vm1
polt stop-vm --name vm1 --force
polt stop-vm --name vm1 --timeout 120
```

**Notes:**
- If the VM is already shutoff or crashed, the command reports this and exits.
- By default it sends `virsh shutdown` (ACPI signal) and waits up to `--timeout` seconds. If the VM does not stop, it falls back to `virsh destroy` (hard power-off).

---

### info-vm (alias: info)

**Purpose:** Show detailed configuration and runtime state for a libvirt VM.

**Usage:**
```bash
polt info-vm --name NAME [options]
```

**Required options:**
| Option | Purpose |
|--------|---------|
| `--name NAME` | VM name to inspect |

**Optional options:**
| Option | Purpose |
|--------|---------|
| `--connection URI` | Libvirt connection URI (default: `qemu:///system`) |
| `--security-info` | Include security and XML label information |

**Output:**
- General domain info (state, memory, vCPUs, autostart)
- Block devices (disk paths, capacities)
- Network interfaces (bridge/network, MAC, model)

**Examples:**
```bash
polt info-vm --name vm1
polt info-vm --name vm1 --security-info
```

---

### console-vm (alias: console)

**Purpose:** Connect to the serial console of a running libvirt VM.

**Usage:**
```bash
polt console-vm --name NAME [options]
```

**Required options:**
| Option | Purpose |
|--------|---------|
| `--name NAME` | VM name to console into |

**Optional options:**
| Option | Purpose |
|--------|---------|
| `--connection URI` | Libvirt connection URI (default: `qemu:///system`) |
| `--force` | Start the VM automatically if it is shutoff before opening console |

**Examples:**
```bash
polt console-vm --name vm1
polt console-vm --name vm1 --force
```

**Notes:**
- Press `Ctrl+]` to detach from the console.
- Requires the VM to be running (or use `--force` to start it first).
- The guest OS must have a serial console enabled (getty on `ttyS0` or similar).

---

## Network Subcommands

Command: `polt network <subcommand> [options]`

**Purpose:** Manage libvirt virtual networks (NAT, bridged, isolated, etc.).

| Subcommand | Purpose |
|------------|---------|
| `list` | List all networks with state, autostart, and bridge |
| `default` | Ensure the `default` NAT network exists and is active (auto-creates `virbr0` with DHCP `192.168.122.x` if missing) |
| `start --name NAME` | Start a defined network |
| `stop --name NAME` | Stop (destroy) an active network |
| `autostart --name NAME` | Enable autostart for a network |

**Options (all subcommands):**
| Option | Purpose |
|--------|---------|
| `--connection URI` | Libvirt connection URI (default: `qemu:///system`) |

**Examples:**
```bash
polt network list
polt network default
polt network start --name default
polt network stop --name mynet
polt network autostart --name default
```

---

## Storage Subcommands

Command: `polt storage <subcommand> [options]`

**Purpose:** Manage libvirt storage pools and volumes (virtual disks).

| Subcommand | Purpose |
|------------|---------|
| `list` | List all storage pools with state, autostart, and capacity |
| `volumes --pool NAME` | List all volumes inside a storage pool |
| `default` | Ensure the `default` pool exists and is active (auto-creates dir pool at `/var/lib/libvirt/images` if missing) |
| `create-vol --pool NAME --name VOL --size GiB` | Create a new qcow2 volume in a pool |
| `delete-vol --pool NAME --name VOL` | Delete a volume from a pool |
| `autostart --pool NAME` | Enable autostart for a pool |

**Options (varies by subcommand):**
| Option | Purpose |
|--------|---------|
| `--connection URI` | Libvirt connection URI (default: `qemu:///system`) |
| `--pool NAME` | Storage pool name |
| `--name VOL` | Volume name |
| `--size GiB` | Volume size in gibibytes (positive integer) |
| `--format FMT` | Volume format (default: `qcow2`) |

**Examples:**
```bash
polt storage list
polt storage default
polt storage volumes --pool default
polt storage create-vol --pool default --name mydisk --size 40
polt storage delete-vol --pool default --name mydisk
polt storage autostart --pool default
```

---

## Aliases

| Full command | Alias |
|--------------|-------|
| `create-vm` | `create` |
| `delete-vm` | `delete` |
| `list-vms` | `list` |
| `start-vm` | `start` |
| `stop-vm` | `stop` |
| `info-vm` | `info` |
| `console-vm` | `console` |

Examples: `polt start --name vm1` is equivalent to `polt start-vm --name vm1`.

---

## Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | General error (missing argument, invalid VM name, VM not found, command failure, etc.) |

All commands validate input before making changes and exit non-zero on any failure.

---

## Safety & Behavior Notes

1. **Graceful shutdown first:** `stop-vm` and `delete-vm --force` attempt ACPI shutdown before falling back to hard power-off (`virsh destroy`).
2. **No orphaned disks:** `create-vm` removes the storage volume automatically if VM definition fails mid-way.
3. **Confirmation required:** `delete-vm` requires typing the exact VM name interactively unless `--yes` is supplied.
4. **Shared storage warning:** `delete-vm --remove-storage` deletes **all** attached volumes, including images shared with other VMs.
5. **Group membership:** After `polt setup` adds you to `libvirt`/`kvm`, log out and back in for changes to apply before managing VMs without `sudo`.
6. **Connection URI:** All commands default to `qemu:///system`. Use `--connection` only for non-standard libvirt setups (e.g., remote tunnels, session URI).

---

*End of manual.*  
Run `polt help` or `polt <command> --help` for inline help at any time.
