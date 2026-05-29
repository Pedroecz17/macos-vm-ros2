#!/bin/bash
# setup.sh
set -euo pipefail

# User Config

WIFI_INTERFACE="en1"   # to know which one it is run: networksetup -listallhardwareports
VM_CPUS=4
VM_MEMORY="12GiB"
VM_DISK="35GiB"
VNC_PASSWORD="123456"
ROS_DISTRO="humble"

# Script

SCRIPT_DIR="$(cd "$(dirname "$BASH_SOURCE[0]}" && pwd)"

echo "Checking Dependencies"
if ! command -v limactl &>/dev/null; then
  echo "Lima not found, Installing with brew..."
  brew install lima
fi

if ! command -v git &>/dev/null; then
  echo "Git not found, Please install Xcode Command Line Tools: xcode-select --install"
  exit 1
fi

echo "Building the VM bridge Net (socket_vmnet)"

SOCKET_VMNET_PREFIX="/opt/socket_vmnet"

if [ ! -f "${SOCKET_VMNET_PREFIX}/bin/socket_vmnet" ]; then
  echo "Cloning socket_vmnet..."
  TMP_DIR=$(mktemp -d)
  git clone https://github.com/lima-vm/socket_vmnet.git "$TMP_DIR/socket_vmnet"
  cd "$TMP_DIR/socket_vmnet"
  LATEST_TAG=$(git tag -l "v*" | sort -V | tail -1)
  echo "Checking out $LATEST_TAG..."
  git checkout "$LATEST_TAG"
  SDKROOT=$(xcrun --show-sdk-path) make
  sudo make PREFIX="${SOCKET_VMNET_PREFIX}" install.bin
  cd -
  rm -rf "$TMP_DIR"
else
  echo "socket_vmnet already installed at ${SOCKET_VMNET_PREFIX}, skipping."
fi

echo "Setting up sudoers for lima to control socket_vmnet"
limactl sudoers > /tmp/etc_sudoers.d_lima
sudo install -o root /tmp/etc_sudoers.d_lima /etc/sudoers.d/lima
rm /tmp/etc_sudoers.d_lima

echo "Creating launchd for socket_vmnet."
PLIST_LABEL="io.github.lima-vm.socket_vmnet.bridged.${WIFI_INTERFACE}"
PLIST_PATH="/Library/LaunchDaemons/${PLIST_LABEL}.plist"
LOG_DIR="/var/log/socket_vmnet"
SOCKET_PATH="/var/run/socket_vmnet.bridged.${WIFI_INTERFACE}"

sudo mkdir -p "$LOG_DIR"

sudo tee "$PLIST_PATH" > /dev/null << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_LABEL}</string>
    <key>Program</key>
    <string>${SOCKET_VMNET_PREFIX}/bin/socket_vmnet</string>
    <key>ProgramArguments</key>
    <array>
        <string>${SOCKET_VMNET_PREFIX}/bin/socket_vmnet</string>
        <string>--vmnet-mode=bridged</string>
        <string>--vmnet-interface=${WIFI_INTERFACE}</string>
        <string>${SOCKET_PATH}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/bridged.${WIFI_INTERFACE}.stderr</string>
    <key>StandardOutPath</key>
    <string>${LOG_DIR}/bridged.${WIFI_INTERFACE}.stdout</string>
</dict>
</plist>
PLIST

sudo launchctl bootstrap system "$PLIST_PATH" 2>/dev/null || true
sudo launchctl kickstart -kp "system/${PLIST_LABEL}"
sleep 2

echo "Verifying socket_vmnet"
ls -la "$SOCKET_PATH" || { echo "ERROR: socket not created. Check logs at ${LOG_DIR}"; exit 1; }

echo "Creating Lima VM config..."
# Substitute config variables into the YAML template
sed \
  -e "s|__WIFI_INTERFACE__|${WIFI_INTERFACE}|g" \
  -e "s|__VM_CPUS__|${VM_CPUS}|g" \
  -e "s|__VM_MEMORY__|${VM_MEMORY}|g" \
  -e "s|__VM_DISK__|${VM_DISK}|g" \
  -e "s|__VNC_PASSWORD__|${VNC_PASSWORD}|g" \
  -e "s|__LINUX_PASSWORD__|${LINUX_PASSWORD}|g" \
  "${SCRIPT_DIR}/ros2.yaml" > ~/.lima/ros2.yaml

echo "Creating and starting Lima VM"
limactl create --name="${VM_NAME}" ~/.lima/ros2.yaml
limactl start "${VM_NAME}"

echo ""
echo "Setup complete!"
echo ""
echo "Next steps:"
echo "  - Shell into VM:       limactl shell ${VM_NAME}"
echo "  - Connect VNC:         open vnc://localhost:5901  (password: ${VNC_PASSWORD})"
echo "  - VNC unlock password: ${LINUX_PASSWORD}"
echo "  - SSH config:          limactl show-ssh --format config ${VM_NAME}"
