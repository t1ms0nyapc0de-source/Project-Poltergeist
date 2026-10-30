#!/usr/bin/env bash
# Manage libvirt storage pools and volumes.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: polt storage <subcommand> [options]

Manage libvirt storage pools and volumes.

Subcommands:
  list                          List all storage pools
  volumes --pool NAME           List volumes in a pool
  default                       Ensure the 'default' pool exists and is active
  create-vol --pool NAME --name VOL --size GiB  Create a qcow2 volume
  delete-vol --pool NAME --name VOL             Delete a volume
  autostart --pool NAME         Enable autostart for a pool

Options:
  --connection URI              Libvirt URI (default: qemu:///system)
  --size GiB                    Volume size in GiB
  --format FMT                  Volume format (default: qcow2)
  -h, --help                    Show this help

Examples:
  polt storage list
  polt storage volumes --pool default
  polt storage default
  polt storage create-vol --pool default --name mydisk --size 40
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
pool=''
vol=''
size=''
format='qcow2'

while [[ $# -gt 0 ]]; do
  case $1 in
    --connection) need_value "$@"; connection=$2; shift 2 ;;
    --pool) need_value "$@"; pool=$2; shift 2 ;;
    --name) need_value "$@"; vol=$2; shift 2 ;;
    --size) need_value "$@"; size=$2; shift 2 ;;
    --format) need_value "$@"; format=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

require_virsh
ensure_libvirtd "$connection"

case "$subcmd" in
  list)
    printf '%-30s %-12s %-10s %s\n' 'NAME' 'STATE' 'AUTOSTART' 'CAPACITY'
    printf '%-30s %-12s %-10s %s\n' '----' '-----' '---------' '--------'
    mapfile -t pools < <(virsh --connect "$connection" pool-list --all --name 2>/dev/null | grep -v '^$' || true)
    if [[ ${#pools[@]} -eq 0 ]]; then
      printf 'No storage pools found.\n'
      exit 0
    fi
    for p in "${pools[@]}"; do
      [[ -z $p ]] && continue
      state=$(virsh --connect "$connection" pool-info "$p" 2>/dev/null | awk '/^State:/ {print $2}' || printf 'unknown')
      autostart=$(virsh --connect "$connection" pool-info "$p" 2>/dev/null | awk '/^Autostart:/ {print $2}' || printf 'no')
      capacity=$(virsh --connect "$connection" pool-info "$p" 2>/dev/null | awk '/^Capacity:/ {print $2, $3}' || printf '-')
      printf '%-30s %-12s %-10s %s\n' "$p" "$state" "$autostart" "$capacity"
    done
    ;;
  default)
    if ! virsh --connect "$connection" pool-info default >/dev/null 2>&1; then
      printf 'default storage pool not found. Creating it...\n'
      virsh --connect "$connection" pool-define-as default dir --target /var/lib/libvirt/images >/dev/null \
        || die 'failed to define default storage pool'
    fi
    virsh --connect "$connection" pool-start default >/dev/null 2>&1 || true
    virsh --connect "$connection" pool-autostart default >/dev/null 2>&1 || true
    printf 'default storage pool is ready.\n'
    ;;
  volumes)
    [[ -n $pool ]] || die '--pool is required.'
    virsh --connect "$connection" pool-info "$pool" >/dev/null 2>&1 \
      || die "storage pool '$pool' does not exist."
    printf '%-30s %-12s %s\n' 'NAME' 'CAPACITY' 'ALLOCATION'
    printf '%-30s %-12s %s\n' '----' '--------' '----------'
    mapfile -t vols < <(virsh --connect "$connection" vol-list --pool "$pool" --name 2>/dev/null | grep -v '^$' || true)
    if [[ ${#vols[@]} -eq 0 ]]; then
      printf 'No volumes in pool %s.\n' "$pool"
      exit 0
    fi
    for v in "${vols[@]}"; do
      [[ -z $v ]] && continue
      info=$(virsh --connect "$connection" vol-info --pool "$pool" "$v" 2>/dev/null || true)
      cap=$(printf '%s\n' "$info" | awk '/^Capacity:/ {print $2, $3}')
      alloc=$(printf '%s\n' "$info" | awk '/^Allocation:/ {print $2, $3}')
      printf '%-30s %-12s %s\n' "$v" "${cap:- -}" "${alloc:- -}"
    done
    ;;
  create-vol)
    [[ -n $pool && -n $vol && -n $size ]] || die '--pool, --name, and --size are required.'
    is_positive_int "$size" || die '--size must be a positive integer (GiB).'
    virsh --connect "$connection" pool-info "$pool" >/dev/null 2>&1 \
      || die "storage pool '$pool' does not exist."
    virsh --connect "$connection" vol-info --pool "$pool" "$vol" >/dev/null 2>&1 \
      && die "volume '$vol' already exists in pool '$pool'."
    virsh --connect "$connection" vol-create-as "$pool" "$vol" "${size}G" --format "$format" >/dev/null
    printf "Volume '%s' created in pool '%s' (%s GiB, %s).\n" "$vol" "$pool" "$size" "$format"
    ;;
  delete-vol)
    [[ -n $pool && -n $vol ]] || die '--pool and --name are required.'
    virsh --connect "$connection" vol-info --pool "$pool" "$vol" >/dev/null 2>&1 \
      || die "volume '$vol' does not exist in pool '$pool'."
    virsh --connect "$connection" vol-delete --pool "$pool" "$vol" >/dev/null
    printf "Volume '%s' deleted from pool '%s'.\n" "$vol" "$pool"
    ;;
  autostart)
    [[ -n $pool ]] || die '--pool is required.'
    virsh --connect "$connection" pool-autostart "$pool" >/dev/null
    printf "Pool '%s' set to autostart.\n" "$pool"
    ;;
  *)
    die "unknown storage subcommand: $subcmd"
    ;;
esac
