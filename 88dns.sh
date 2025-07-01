#!/bin/bash

# Exit on error inside any command
set -e

# check if os is ubuntu on any platform if its macOS or Linux
if [[ "$(uname)" == "Darwin" ]]; then
  echo "This script is intended for Ubuntu systems only."
  exit 1
elif [[ "$(uname)" != "Linux" ]]; then
  echo "This script is intended for Ubuntu systems only."
  exit 1
fi 

# Check if nmcli is installed
if ! command -v nmcli &> /dev/null; then
  echo "nmcli is not installed. Please install NetworkManager to use this script."
  echo "For safety, the script will NOT auto-install NetworkManager."
  echo "Please install it manually (e.g., 'sudo apt install network-manager') and try again."
  exit 1
fi

# Store original DNS
original_dns=$(nmcli dev show | grep 'IP4.DNS' | awk '{print $2}' | paste -sd ' ')
active_conn=$(nmcli -t -f NAME connection show --active | head -n1)

# Set DNS to 8.8.8.8 temporarily
echo "🔧 Switching DNS to 8.8.8.8..."
nmcli connection modify "$active_conn" ipv4.dns "8.8.8.8"
nmcli connection modify "$active_conn" ipv4.ignore-auto-dns yes
nmcli connection down "$active_conn" && nmcli connection up "$active_conn"

# Ensure DNS is restored no matter what happens
cleanup() {
  echo "🔄 Restoring original DNS: $original_dns"
  nmcli connection modify "$active_conn" ipv4.dns "$original_dns"
  nmcli connection modify "$active_conn" ipv4.ignore-auto-dns no
  nmcli connection down "$active_conn" && nmcli connection up "$active_conn"
  echo "✅ DNS restored"
}
trap cleanup EXIT

# Run the passed script or command
"$@"