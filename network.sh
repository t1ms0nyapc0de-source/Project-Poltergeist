#!/usr/bin/env bash
# Manage libvirt virtual networks.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: polt network <subcommand> [options]

Manage libvirt virtual networks.

Subcommands:
  list               List all networks and their states
  default            Ensure the 'default' network exists and is active
  start --name NAME  Start a network
  stop --name NAME   Stop a network
  autostart --name NAME  Enable autostart for a network

Options:
  --connection URI   Libvirt URI (default: qemu:///system)
  -h, --help         Show this help

Examples:
  polt network list
  polt network default
  polt network start --name default
EOF
}

if [[ $# -eq 0 ]]; then
  usage
  exit 0
fi

subcmd="$1"
shift

# --help must work even without virsh installed
case "$subcmd" in
  -h|--help|help) usage; exit 0 ;;
esac

connection=qemu:///system
name=''

while [[ $# -gt 0 ]]; do
  case $1 in
    --connection) need_value "$@"; connection=$2; shift 2 ;;
    --name) need_value "$@"; name=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

require_virsh
ensure_libvirtd "$connection"

case "$subcmd" in
  list)
    printf '%-30s %-12s %-10s %s\n' 'NAME' 'STATE' 'AUTOSTART' 'BRIDGE'
    printf '%-30s %-12s %-10s %s\n' '----' '-----' '---------' '------'
    mapfile -t nets < <(virsh --connect "$connection" net-list --all --name 2>/dev/null | grep -v '^$' || true)
    if [[ ${#nets[@]} -eq 0 ]]; then
      printf 'No networks found.\n'
      exit 0
    fi
    for n in "${nets[@]}"; do
      [[ -z $n ]] && continue
      state=$(virsh --connect "$connection" net-info "$n" 2>/dev/null | awk '/^State:/ {print $2}' || printf 'unknown')
      autostart=$(virsh --connect "$connection" net-info "$n" 2>/dev/null | awk '/^Autostart:/ {print $2}' || printf 'no')
      bridge=$(virsh --connect "$connection" net-info "$n" 2>/dev/null | awk '/^Bridge:/ {print $2}' || printf '-')
      printf '%-30s %-12s %-10s %s\n' "$n" "$state" "$autostart" "$bridge"
    done
    ;;
  default)
    ensure_default_network "$connection"
    ;;
  start)
    [[ -n $name ]] || die '--name is required.'
    virsh --connect "$connection" net-start "$name" >/dev/null
    printf "Network '%s' started.\n" "$name"
    ;;
  stop)
    [[ -n $name ]] || die '--name is required.'
    virsh --connect "$connection" net-destroy "$name" >/dev/null
    printf "Network '%s' stopped.\n" "$name"
    ;;
  autostart)
    [[ -n $name ]] || die '--name is required.'
    virsh --connect "$connection" net-autostart "$name" >/dev/null
    printf "Network '%s' set to autostart.\n" "$name"
    ;;
  *)
    die "unknown network subcommand: $subcmd"
    ;;
esac
