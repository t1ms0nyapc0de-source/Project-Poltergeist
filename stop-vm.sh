#!/usr/bin/env bash
# Stop (shutdown or destroy) a libvirt VM.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: polt stop-vm --name NAME [options]

Stop a running libvirt VM.

Required:
  --name NAME        VM name to stop

Options:
  --force            Power off immediately (virsh destroy) instead of graceful shutdown
  --timeout SECS     Seconds to wait for graceful shutdown before forcing (default: 60)
  --connection URI   Libvirt URI (default: qemu:///system)
  -h, --help         Show this help

Examples:
  polt stop-vm --name ubuntu
  polt stop-vm --name ubuntu --force
  polt stop-vm --name ubuntu --timeout 120
EOF
}

name=''
connection=qemu:///system
force=0
timeout=60

while [[ $# -gt 0 ]]; do
  case $1 in
    --name) need_value "$@"; name=$2; shift 2 ;;
    --connection) need_value "$@"; connection=$2; shift 2 ;;
    --force) force=1; shift ;;
    --timeout) need_value "$@"; timeout=$2; shift 2 ;;
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
  printf "VM '%s' is already %s.\n" "$name" "$state"
  exit 0
fi

if [[ $force -eq 1 ]]; then
  printf 'Powering off VM %s ...\n' "$name"
  virsh --connect "$connection" destroy "$name" >/dev/null
else
  printf 'Gracefully shutting down VM %s ...\n' "$name"
  virsh --connect "$connection" shutdown "$name" >/dev/null 2>&1 || true
  for _ in $(seq 1 "$timeout"); do
    state=$(vm_state "$connection" "$name")
    [[ $state == shutoff || $state == crashed ]] && break
    sleep 1
  done
  state=$(vm_state "$connection" "$name")
  if [[ $state != shutoff && $state != crashed ]]; then
    printf 'Graceful shutdown timed out; powering off %s ...\n' "$name"
    virsh --connect "$connection" destroy "$name" >/dev/null
  fi
fi

printf "VM '%s' stopped.\n" "$name"
