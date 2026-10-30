#!/usr/bin/env bash
# Start a libvirt VM.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: polt start-vm --name NAME [options]

Start a defined (shutoff) libvirt VM.

Required:
  --name NAME        VM name to start

Options:
  --console          Attach to the VM console after starting
  --connection URI   Libvirt URI (default: qemu:///system)
  --wait             Wait for the VM to reach 'running' state before returning
  -h, --help         Show this help

Examples:
  polt start-vm --name ubuntu
  polt start-vm --name ubuntu --console
  polt start-vm --name ubuntu --wait
EOF
}

name=''
connection=qemu:///system
attach_console=0
wait_running=0

while [[ $# -gt 0 ]]; do
  case $1 in
    --name) need_value "$@"; name=$2; shift 2 ;;
    --connection) need_value "$@"; connection=$2; shift 2 ;;
    --console) attach_console=1; shift ;;
    --wait) wait_running=1; shift ;;
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
if [[ $state == running ]]; then
  printf "VM '%s' is already running.\n" "$name"
elif [[ $state == paused ]]; then
  printf "VM '%s' is paused. Resuming...\n" "$name"
  virsh --connect "$connection" resume "$name" >/dev/null
else
  printf "Starting VM '%s'...\n" "$name"
  virsh --connect "$connection" start "$name" >/dev/null
fi

if [[ $wait_running -eq 1 ]]; then
  printf 'Waiting for VM to reach running state...'
  for _ in {1..60}; do
    state=$(vm_state "$connection" "$name")
    if [[ $state == running ]]; then
      printf ' running.\n'
      break
    fi
    printf '.'
    sleep 2
  done
  state=$(vm_state "$connection" "$name")
  [[ $state != running ]] && die "VM '$name' did not reach running state (current: $state)."
fi

if [[ $attach_console -eq 1 ]]; then
  exec virsh --connect "$connection" console "$name"
fi

printf "VM '%s' started on %s.\n" "$name" "$connection"
