#!/bin/bash
set -uo pipefail

# Use sudo only when not already root
if [ "$EUID" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
fi

# User to add to groups (the real user, even when run with sudo)
TARGET_USER="${SUDO_USER:-$USER}"

# ---------- 1. CPU virtualisation check ----------
if ! grep -E -q '(vmx|svm)' /proc/cpuinfo; then
    echo "Virtualisation not supported, or disabled in BIOS/UEFI"

    if [ -d /sys/firmware/efi ]; then
        read -r -p "Reboot into UEFI setup now to enable it? [y/N] " answer
        case "$answer" in
            [yY]|[yY][eE][sS])
                echo "Rebooting into UEFI setup..."
                if ! $SUDO systemctl reboot --firmware-setup; then
                    echo "Failed to reboot into UEFI setup. Reboot manually and enable virtualisation."
                    exit 1
                fi
                exit 0
                ;;
            *)
                echo "Not rebooting. Enable virtualisation in BIOS/UEFI manually, then run this script again."
                ;;
        esac
    else
        echo "Legacy BIOS detected. Reboot manually and press the BIOS key (F2/Del/F10/Esc) to enable it."
    fi
    exit 1
fi

# ---------- 2. Install KVM and tools ----------
install_kvm() {
    if command -v apt-get >/dev/null 2>&1; then
        $SUDO apt-get update
        $SUDO apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virt-manager
    elif command -v dnf >/dev/null 2>&1; then
        $SUDO dnf install -y @virtualization
    elif command -v pacman >/dev/null 2>&1; then
        $SUDO pacman -S --needed --noconfirm qemu-full libvirt virt-manager dnsmasq
    elif command -v zypper >/dev/null 2>&1; then
        $SUDO zypper install -y -t pattern kvm_server kvm_tools
    else
        echo "Unsupported package manager. Install QEMU, libvirt and virt-manager manually."
        return 1
    fi
}

if command -v virsh >/dev/null 2>&1 && command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "KVM tools already installed"
else
    read -r -p "KVM tools not found. Install them now? [y/N] " answer
    case "$answer" in
        [yY]|[yY][eE][sS])
            install_kvm || exit 1
            ;;
        *)
            echo "Skipping install."
            ;;
    esac
fi

# ---------- 3. Start libvirt service ----------
if command -v virsh >/dev/null 2>&1; then
    if ! $SUDO systemctl enable --now libvirtd 2>/dev/null; then
        # Some newer distros use socket activation instead
        $SUDO systemctl enable --now libvirtd.socket 2>/dev/null \
            || echo "Could not start libvirt. Check: systemctl status libvirtd"
    fi
fi

# ---------- 4. Load KVM module / check /dev/kvm ----------
if [ -e /dev/kvm ]; then
    echo "/dev/kvm exists: KVM is ready to use"
else
    echo "/dev/kvm missing, trying to load the KVM module..."

    if grep -q "GenuineIntel" /proc/cpuinfo; then
        $SUDO modprobe kvm_intel
    elif grep -q "AuthenticAMD" /proc/cpuinfo; then
        $SUDO modprobe kvm_amd
    else
        echo "Unknown CPU vendor"
        exit 1
    fi

    if [ -e /dev/kvm ]; then
        echo "KVM module loaded, /dev/kvm is now available"
    else
        echo "Still no /dev/kvm. Check: sudo dmesg | grep -i kvm"
        exit 1
    fi
fi

# ---------- 5. Add user to groups ----------
for grp in libvirt kvm; do
    if getent group "$grp" >/dev/null; then
        if ! id -nG "$TARGET_USER" | grep -qw "$grp"; then
            $SUDO usermod -aG "$grp" "$TARGET_USER"
            echo "Added $TARGET_USER to group '$grp' (log out and back in to apply)"
        fi
    fi
done

# ---------- 6. Permission check ----------
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    echo "You have permission to use KVM"
else
    echo "No permission for /dev/kvm yet. Log out and back in so the new groups apply."
fi

# ---------- 7. Final verification ----------
if command -v virsh >/dev/null 2>&1; then
    echo "Libvirt status:"
    $SUDO virsh list --all
fi