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


