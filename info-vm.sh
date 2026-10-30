#!/usr/bin/env bash
# Show detailed information about a libvirt VM.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: polt info-vm --name NAME [options]

Show detailed configuration and state for a libvirt VM.

Required:
  --name NAME        VM name

Options:
  --connection URI   Libvirt URI (default: qemu:///system)
  --security-info    Include security and XML label information
  -h, --help         Show this help

Examples:
  polt info-vm --name ubuntu
  polt info-vm --name ubuntu --security-info
EOF
}

name=''
connection=qemu:///system
security_info=0

while [[ $# -gt 0 ]]; do
  case $1 in
    --name) need_value "$@"; name=$2; shift 2 ;;
    --connection) need_value "$@"; connection=$2; shift 2 ;;
    --security-info) security_info=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

require_virsh
[[ -n $name ]] || die '--name is required.'
valid_vm_name "$name" || die 'invalid VM name.'
vm_exists "$connection" "$name" || die "VM '$name' does not exist on $connection."
ensure_libvirtd "$connection"

echo "=== VM: $name ==="
echo "Connection: $connection"
echo
virsh --connect "$connection" dominfo "$name"
echo
echo "=== Block devices ==="
virsh --connect "$connection" domblklist "$name" --details 2>/dev/null || echo '(none)'
echo
echo "=== Network interfaces ==="
virsh --connect "$connection" domiflist "$name" 2>/dev/null || echo '(none)'
echo
if [[ $security_info -eq 1 ]]; then
  echo "=== Security info ==="
  virsh --connect "$connection" dominfo "$name" | grep -iE 'security|label' || echo '(none)'
fi
