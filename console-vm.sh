#!/usr/bin/env bash
# Connect to a libvirt VM serial console.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: polt console-vm --name NAME [options]

Connect to the serial console of a running libvirt VM.

Required:
  --name NAME        VM name

Options:
  --connection URI   Libvirt URI (default: qemu:///system)
  --force            Start the VM if it is shutoff before opening console
  -h, --help         Show this help

Notes:
  Press Ctrl+] to detach from the console.

Examples:
  polt console-vm --name ubuntu
  polt console-vm --name ubuntu --force
EOF
}

name=''
connection=qemu:///system
force_start=0

while [[ $# -gt 0 ]]; do
  case $1 in
    --name) need_value "$@"; name=$2; shift 2 ;;
    --connection) need_value "$@"; connection=$2; shift 2 ;;
    --force) force_start=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

require_virsh
[[ -n $name ]] || die '--name is required.'
valid_vm_name "$name" || die 'invalid VM name.'
vm_exists "$connection" "$name" || die "VM '$name' does not exist on $connection."
ensure_libvirtd "$connection"

state=$(vm_state "$connection" "$name")
if [[ $state == shutoff || $state == crashed ]]; then
  if [[ $force_start -eq 1 ]]; then
    printf "VM '%s' is %s. Starting it...\n" "$name" "$state"
    virsh --connect "$connection" start "$name" >/dev/null
    for _ in {1..30}; do
      state=$(vm_state "$connection" "$name")
      [[ $state == running ]] && break
      sleep 2
    done
    state=$(vm_state "$connection" "$name")
    [[ $state != running ]] && die "VM '$name' did not start (current: $state)."
  else
    die "VM '$name' is $state. Start it first, or use --force."
  fi
elif [[ $state == paused ]]; then
  die "VM '$name' is paused. Resume it first."
fi

printf 'Connecting to console of %s (Ctrl+] to detach)...\n' "$name"
exec virsh --connect "$connection" console "$name"
