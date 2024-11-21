#!/bin/bash

# Exit on any error
set -e

# Function to check if the script is run as root
function check_root() {
  if [ "$EUID" -ne 0 ]; then
    echo "Please run as root or use sudo."
    exit 1
  fi
}

# Function to downgrade a user to standard
function downgrade_user() {
  echo "You chose to downgrade a user to standard."
  read -p "Enter the username to downgrade from admin to standard: " target_user

  # Remove the user from sudo and netdev groups
  if id "$target_user" &>/dev/null; then
    deluser "$target_user" sudo || true
    deluser "$target_user" netdev || true
    echo "User '$target_user' downgraded to standard user."
  else
    echo "The user '$target_user' does not exist."
  fi
}

# Function to create a new admin account and hide it
function create_admin_user() {
  echo "You chose to create a new admin account."
  read -p "Enter a username for the new admin account: " new_admin

  # Check if the user already exists
  if id "$new_admin" &>/dev/null; then
    echo "The user '$new_admin' already exists."
    read -p "Do you want to update this user to have admin privileges? (y/n): " choice
    if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
      # Add the user to the sudo group
      usermod -aG sudo "$new_admin"
      echo "User '$new_admin' updated to have admin privileges."
    else
      echo "Skipping admin creation for '$new_admin'."
    fi
    return
  fi

  # Add the new admin user
  adduser --disabled-password --gecos "" "$new_admin"
  read -s -p "Enter a password for the new admin account: " new_password
  echo
  echo "$new_admin:$new_password" | chpasswd

  # Add the new admin user to the sudo group
  usermod -aG sudo "$new_admin"

  # Hide the new admin user from the login screen
  mkdir -p /var/lib/AccountsService/users
  echo -e "[User]\nSystemAccount=true" > /var/lib/AccountsService/users/"$new_admin"

  echo "New admin user '$new_admin' created and hidden from the login screen."
}

# Function to restrict network changes for standard users
function restrict_network_changes() {
  echo "You chose to restrict network changes for standard users."

  # Create PolicyKit rule to restrict network changes
  cat <<EOF | sudo tee /etc/polkit-1/localauthority/50-local.d/restrict-network.pkla
[Restrict Network Changes]
Identity=unix-group:users
Action=org.freedesktop.NetworkManager.settings.modify.system
ResultAny=no
ResultInactive=no
ResultActive=no
EOF

  # Restart PolicyKit service
  sudo systemctl restart polkit

  echo "Network changes have been restricted for standard users."
}

# Function to remove Deja Dup (Backups) and clean up
function remove_deja_dup() {
  echo "You chose to remove Deja Dup (Backups) and clean up configuration files."

  # Uninstall the application
  echo "Removing Deja Dup..."
  sudo apt remove --purge -y deja-dup

  # Remove leftover configuration files
  echo "Cleaning up configuration files..."
  rm -rf ~/.cache/deja-dup
  rm -rf ~/.config/deja-dup

  echo "Deja Dup (Backups) has been removed along with its configuration files."
}

# Function to fully update the system
function update_system_fully() {
  echo "You chose to fully update the system to ensure no pending updates."

  # Update package lists and upgrade all packages
  sudo apt update
  sudo apt full-upgrade -y

  # Apply security updates
  sudo unattended-upgrade

  # Install firmware updates if applicable
  if command -v fwupdmgr &>/dev/null; then
    echo "Checking for firmware updates..."
    sudo fwupdmgr refresh --force
    sudo fwupdmgr update || true
  else
    echo "fwupdmgr is not installed. Skipping firmware updates."
  fi

  # Clean up unnecessary packages
  sudo apt autoremove -y
  sudo apt clean

  echo "System fully updated. There should be no pending updates in the GUI."
}

# Function to forget a WiFi network and reboot in 5 seconds
function forget_wifi_and_reboot() {
  echo "You chose to forget a WiFi network and schedule a reboot."

  # List all saved WiFi networks
  echo "Available saved WiFi networks:"
  nmcli connection show | grep wifi
  
  # Prompt user for the SSID to forget
  read -p "Enter the WiFi SSID to forget: " ssid
  
  # Check if the SSID exists
  if nmcli connection show | grep -q "$ssid"; then
    echo "Creating a temporary script to forget WiFi and reboot..."
    
    # Create a temporary script to forget WiFi and reboot
    tmp_script="/tmp/forget_wifi_and_reboot.sh"
    sudo bash -c "cat <<EOF > $tmp_script
#!/bin/bash
nmcli connection delete \"$ssid\"
echo \"WiFi network '$ssid' forgotten. Rebooting now...\"
/sbin/reboot
EOF"

    # Make the temporary script executable
    sudo chmod +x "$tmp_script"

    # Schedule the script to run in 5 seconds
    echo "Scheduling the WiFi forget and reboot in 5 seconds..."
    (sleep 5 && bash $tmp_script) &

    echo "The WiFi forget and reboot have been scheduled. Disconnecting will occur soon."
  else
    echo "WiFi network '$ssid' not found. No action taken."
  fi
}

# Display menu options
function display_menu() {
  echo "Select an operation to perform:"
  echo "1) Downgrade a user to standard"
  echo "2) Create a new admin account and hide it"
  echo "3) Restrict network changes for standard users"
  echo "4) Remove Deja Dup (Backups) and clean up"
  echo "5) Fully update the system (apply all updates)"
  echo "6) Forget a WiFi network and reboot"
  echo "7) Perform both 1 and 2"
  echo "8) Perform both 2 and 3"
  echo "9) Perform all (1, 2, 3, 4, 5, and 6)"
  echo "10) Exit"
}

# Main script execution
function main() {
  check_root

  while true; do
    display_menu
    read -p "Enter your choice: " choice

    case $choice in
      1)
        downgrade_user
        ;;
      2)
        create_admin_user
        ;;
      3)
        restrict_network_changes
        ;;
      4)
        remove_deja_dup
        ;;
      5)
        update_system_fully
        ;;
      6)
        forget_wifi_and_reboot
        ;;
      7)
        downgrade_user
        create_admin_user
        ;;
      8)
        create_admin_user
        restrict_network_changes
        ;;
      9)
        downgrade_user
        create_admin_user
        restrict_network_changes
        remove_deja_dup
        update_system_fully
        forget_wifi_and_reboot
        ;;
      10)
        echo "Exiting the script. Goodbye!"
        exit 0
        ;;
      *)
        echo "Invalid choice. Please select a valid option."
        ;;
    esac

    echo
    echo "Operation completed. Returning to the menu..."
  done
}

main
