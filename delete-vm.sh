#!/usr/bin/env bash
# Safely undefine a libvirt VM. Disk removal requires explicit opt-in.
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: delete-vm.sh --name NAME [options]

Required:
  --name NAME             Existing libvirt VM name

Options:
  --remove-storage        Also remove all storage volumes attached to this VM (destructive)
  --force                 Power off a running VM after confirmation
  --yes                   Skip the typed-name confirmation
  --connection URI        Libvirt URI (default: qemu:///system)
  -h, --help              Show this help

By default this only removes the VM definition; its virtual disks remain in
their storage pool. --remove-storage permanently deletes all storage volumes
attached to the VM (including shared images).
EOF
}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
need_value() { [[ $# -ge 2 ]] || die "$1 needs a value"; }

name=''
connection=qemu:///system
remove_storage=0
force=0
assume_yes=0

while [[ $# -gt 0 ]]; do
  case $1 in
    --name) need_value "$@"; name=$2; shift 2 ;;
    --connection) need_value "$@"; connection=$2; shift 2 ;;
    --remove-storage) remove_storage=1; shift ;;
    --force) force=1; shift ;;
    --yes) assume_yes=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

command -v virsh >/dev/null || die 'virsh is required.'
[[ -n $name ]] || die '--name is required.'
[[ $name =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$ ]] || die 'invalid VM name.'
virsh --connect "$connection" dominfo "$name" >/dev/null 2>&1 \
  || die "VM '$name' does not exist on $connection."

state=$(virsh --connect "$connection" domstate "$name" | tr -d '[:space:]')
printf 'VM: %s\nState: %s\nConnection: %s\n' "$name" "$state" "$connection"
if [[ $remove_storage -eq 1 ]]; then
  printf '\nManaged disks that libvirt may remove:\n'
  virsh --connect "$connection" domblklist "$name" --details || true
  printf '\nWARNING: --remove-storage permanently deletes managed virtual disks.\n'
else
  printf '\nVirtual disks will be preserved. Use --remove-storage to delete managed disks too.\n'
fi

if [[ $assume_yes -eq 0 ]]; then
  [[ -r /dev/tty ]] || die 'interactive confirmation requires a terminal; use --yes only when intentional.'
  printf 'Type the exact VM name (%s) to continue: ' "$name" > /dev/tty
  read -r confirmation < /dev/tty || die 'could not read confirmation.'
  [[ $confirmation == "$name" ]] || die 'confirmation did not match; nothing was changed.'
fi

if [[ $state != shutoff && $state != crashed ]]; then
  [[ $force -eq 1 ]] || die "VM is $state. Re-run with --force to power it off before deletion."
  printf 'Attempting graceful shutdown of %s ...\n' "$name"
  virsh --connect "$connection" shutdown "$name" >/dev/null 2>&1 || true
  for _ in {1..30}; do
    state=$(virsh --connect "$connection" domstate "$name" | tr -d '[:space:]')
    [[ $state == shutoff || $state == crashed ]] && break
    sleep 1
  done
  state=$(virsh --connect "$connection" domstate "$name" | tr -d '[:space:]')
  if [[ $state != shutoff && $state != crashed ]]; then
    printf 'Graceful shutdown timed out; powering off %s ...\n' "$name"
    virsh --connect "$connection" destroy "$name"
  fi
fi

if [[ $remove_storage -eq 1 ]]; then
  virsh --connect "$connection" undefine "$name" \
    --managed-save --snapshots-metadata --nvram --remove-all-storage
  printf 'VM definition and managed storage for %s were removed.\n' "$name"
else
  virsh --connect "$connection" undefine "$name" \
    --managed-save --snapshots-metadata --nvram
  printf 'VM definition for %s was removed; its disks were preserved.\n' "$name"
fi
