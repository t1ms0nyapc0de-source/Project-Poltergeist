#!/usr/bin/env bash
# Create a Linux VM through libvirt and virt-install.
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: create-vm.sh --name NAME --iso ISO [options]

Required:
  --name NAME             New libvirt VM name
  --iso PATH              Bootable installation ISO

Options:
  --memory MiB            Memory in MiB (default: 4096)
  --vcpus COUNT           Virtual CPUs (default: 2)
  --disk GiB              New disk size in GiB (default: 40)
  --disk-name NAME.qcow2  Storage-volume name (default: NAME.qcow2)
  --pool NAME             Libvirt storage pool (default: default)
  --network NAME          Libvirt network (default: default)
  --os-variant NAME       osinfo variant, e.g. ubuntu24.04 (default: generic)
  --uefi                  Boot with UEFI firmware
  --connection URI        Libvirt URI (default: qemu:///system)
  --start                 Start the VM installer immediately
  -h, --help              Show this help

The VM is created shut down unless --start is given.  Use virt-manager or
virsh console afterwards to complete operating-system installation.
EOF
}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
need_value() { [[ $# -ge 2 ]] || die "$1 needs a value"; }

name=''
iso=''
memory=4096
vcpus=2
disk=40
disk_name=''
pool=default
network=default
os_variant=generic
connection=qemu:///system
uefi=0
start=0

while [[ $# -gt 0 ]]; do
  case $1 in
    --name) need_value "$@"; name=$2; shift 2 ;;
    --iso) need_value "$@"; iso=$2; shift 2 ;;
    --memory) need_value "$@"; memory=$2; shift 2 ;;
    --vcpus) need_value "$@"; vcpus=$2; shift 2 ;;
    --disk) need_value "$@"; disk=$2; shift 2 ;;
    --disk-name) need_value "$@"; disk_name=$2; shift 2 ;;
    --pool) need_value "$@"; pool=$2; shift 2 ;;
    --network) need_value "$@"; network=$2; shift 2 ;;
    --os-variant) need_value "$@"; os_variant=$2; shift 2 ;;
    --connection) need_value "$@"; connection=$2; shift 2 ;;
    --uefi) uefi=1; shift ;;
    --start) start=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

for command in virsh virt-install realpath; do
  command -v "$command" >/dev/null || die "required command not found: $command"
done
[[ -n $name ]] || die '--name is required.'
[[ $name =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$ ]] || die 'VM name may contain letters, numbers, dot, underscore, and hyphen only.'
[[ -n $iso && -f $iso && -r $iso ]] || die '--iso must name a readable ISO file.'
[[ $memory =~ ^[1-9][0-9]*$ ]] || die '--memory must be a positive integer.'
[[ $vcpus =~ ^[1-9][0-9]*$ ]] || die '--vcpus must be a positive integer.'
[[ $disk =~ ^[1-9][0-9]*$ ]] || die '--disk must be a positive integer.'
iso=$(realpath "$iso")
[[ -n $disk_name ]] || disk_name="${name}.qcow2"
[[ $disk_name != */* && $disk_name == *.qcow2 ]] || die '--disk-name must be a qcow2 file name, not a path.'

virsh --connect "$connection" dominfo "$name" >/dev/null 2>&1 \
  && die "a VM named '$name' already exists."
virsh --connect "$connection" pool-info "$pool" >/dev/null \
  || die "storage pool '$pool' is unavailable. Run: virsh -c $connection pool-list --all"
virsh --connect "$connection" net-info "$network" >/dev/null \
  || die "network '$network' is unavailable. Run: virsh -c $connection net-list --all"
if virsh --connect "$connection" vol-info --pool "$pool" "$disk_name" >/dev/null 2>&1; then
  die "storage volume '$disk_name' already exists in pool '$pool'. Choose --disk-name."
fi

cleanup() {
  if [[ -n ${disk_name:-} && -n ${pool:-} && -n ${connection:-} ]]; then
    virsh --connect "$connection" vol-delete --pool "$pool" "$disk_name" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

printf 'Creating storage volume %q in pool %q ...\n' "$disk_name" "$pool"
virsh --connect "$connection" vol-create-as "$pool" "$disk_name" "${disk}G" --format qcow2
disk_path=$(virsh --connect "$connection" vol-path --pool "$pool" "$disk_name")

command=(
  virt-install
  --connect "$connection"
  --name "$name"
  --memory "$memory"
  --vcpus "$vcpus"
  --disk "path=${disk_path},format=qcow2,bus=virtio"
  --cdrom "$iso"
  --os-variant "$os_variant"
  --network "network=${network},model=virtio"
  --graphics spice
  --video virtio
  --channel unix,target.type=virtio,target.name=org.qemu.guest_agent.0
  --noautoconsole
)

[[ $uefi -eq 1 ]] && command+=(--boot uefi)
[[ $start -eq 0 ]] && command+=(--print-xml)

printf 'Creating VM %q: %s MiB RAM, %s vCPU, %s GiB disk in pool %q.\n' \
  "$name" "$memory" "$vcpus" "$disk" "$pool"

if [[ $start -eq 1 ]]; then
  "${command[@]}"
  trap - EXIT
  printf 'Installer started. Open it with: virt-manager --connect %q\n' "$connection"
else
  # The volume already exists, so the generated XML can be safely defined
  # without starting the installer.
  xml=$("${command[@]}")
  printf '%s\n' "$xml" | virsh --connect "$connection" define /dev/stdin
  trap - EXIT
  printf 'VM defined but not started. Start it with: virsh -c %q start %q\n' "$connection" "$name"
fi
