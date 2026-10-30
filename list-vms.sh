#!/usr/bin/env bash
# List libvirt VMs with their states.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: polt list-vms [options]

List all libvirt domains (VMs) and their states.

Options:
  --connection URI   Libvirt URI (default: qemu:///system)
  --all              Include shutoff and crashed VMs (default: show all anyway)
  --state STATE      Filter by state: running, shutoff, paused, crashed
  -h, --help         Show this help

Examples:
  polt list-vms
  polt list-vms --state running
EOF
}

connection=qemu:///system
state_filter=''

while [[ $# -gt 0 ]]; do
  case $1 in
    --connection) need_value "$@"; connection=$2; shift 2 ;;
    --state) need_value "$@"; state_filter=$2; shift 2 ;;
    --all) shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

require_virsh
ensure_libvirtd "$connection"

printf '%-30s %-12s %s\n' 'NAME' 'STATE' 'AUTOSTART'
printf '%-30s %-12s %s\n' '----' '-----' '---------'

mapfile -t vms < <(virsh --connect "$connection" list --all --name 2>/dev/null | grep -v '^$' || true)

if [[ ${#vms[@]} -eq 0 ]]; then
  printf 'No VMs found.\n'
  exit 0
fi

for name in "${vms[@]}"; do
  [[ -z $name ]] && continue
  state=$(vm_state "$connection" "$name")
  autostart=$(virsh --connect "$connection" dominfo "$name" 2>/dev/null | awk '/^Autostart:/ {print $2}' || printf 'no')
  [[ -n $state_filter && $state != "$state_filter" ]] && continue
  printf '%-30s %-12s %s\n' "$name" "$state" "${autostart:-no}"
done
