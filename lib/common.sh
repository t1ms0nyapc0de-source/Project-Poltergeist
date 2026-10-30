#!/usr/bin/env bash
# lib/common.sh - Shared helpers for polt subcommands.
# Source this file in each command script.

set -Eeuo pipefail

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
need_value() { [[ $# -ge 2 ]] || die "$1 needs a value"; }
require_virsh() { command -v virsh >/dev/null 2>&1 || die 'virsh is required. Install libvirt-client.'; }
require_connection() {
  [[ -n ${1:-} ]] || die 'libvirt connection URI is required.'
}
vm_exists() {
  local connection="$1" name="$2"
  virsh --connect "$connection" dominfo "$name" >/dev/null 2>&1
}
vm_state() {
  local connection="$1" name="$2"
  virsh --connect "$connection" domstate "$name" 2>/dev/null | tr -d '[:space:]' || printf 'unknown'
}
ensure_libvirtd() {
  local connection="$1"
  require_virsh
  if ! systemctl is-active --quiet libvirtd 2>/dev/null && ! systemctl is-active --quiet libvirtd.socket 2>/dev/null; then
    printf 'libvirt is not running. Attempting to start libvirtd...\n'
    sudo systemctl start libvirtd 2>/dev/null || sudo systemctl start libvirtd.socket 2>/dev/null \
      || die 'could not start libvirt. Run: sudo systemctl start libvirtd'
    sleep 1
  fi
  # Verify we can talk to the hypervisor
  virsh --connect "$connection" list --all >/dev/null 2>&1 \
    || die "cannot connect to libvirt at $connection. Is libvirtd running and are you in the libvirt group?"
}
ensure_default_pool() {
  local connection="$1"
  if ! virsh --connect "$connection" pool-info default >/dev/null 2>&1; then
    printf 'default storage pool not found. Creating it...\n'
    virsh --connect "$connection" pool-define-as default dir --target /var/lib/libvirt/images >/dev/null \
      || die 'failed to define default storage pool'
    virsh --connect "$connection" pool-start default >/dev/null 2>&1 || true
    virsh --connect "$connection" pool-autostart default >/dev/null 2>&1 || true
    printf 'default storage pool created.\n'
  fi
}
ensure_default_network() {
  local connection="$1"
  if ! virsh --connect "$connection" net-info default >/dev/null 2>&1; then
    printf 'default network not found. Creating it...\n'
    virsh --connect "$connection" net-define /dev/stdin <<'EOF' >/dev/null 2>&1 || die 'failed to define default network'
<network>
  <name>default</name>
  <bridge name="virbr0" stp="on" delay="0"/>
  <forward mode="nat"/>
  <ip address="192.168.122.1" netmask="255.255.255.0">
    <dhcp>
      <range start="192.168.122.2" end="192.168.122.254"/>
    </dhcp>
  </ip>
</network>
EOF
    virsh --connect "$connection" net-start default >/dev/null 2>&1 || true
    virsh --connect "$connection" net-autostart default >/dev/null 2>&1 || true
    printf 'default network created.\n'
  fi
}
is_positive_int() { [[ $1 =~ ^[1-9][0-9]*$ ]]; }
valid_vm_name() { [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$ ]]; }
