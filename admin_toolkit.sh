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

# Function to disable LTS upgrade prompts
function disable_lts_upgrade_prompts() {
  echo "Disabling LTS upgrade prompts in GUI..."

  # Edit /etc/update-manager/release-upgrades to disable LTS prompts
  sudo sed -i 's/^Prompt=.*/Prompt=never/' /etc/update-manager/release-upgrades
  echo "LTS upgrade prompts disabled."
}

# Function to clear GUI metadata
function clear_gui_metadata() {
  echo "Clearing GUI update metadata to avoid stale prompts..."
  sudo apt clean
  sudo apt update
  echo "GUI update metadata cleared."
}

# Function to disable WiFi by blacklisting the driver
function disable_wifi_blacklist() {
  echo "Disabling WiFi by blacklisting the iwlwifi driver and its dependencies."

  # Create a custom blacklist file for WiFi drivers
  sudo tee /etc/modprobe.d/blacklist-wifi.conf <<EOF
# Custom blacklist to disable WiFi
blacklist iwlwifi
blacklist iwldvm
blacklist iwlmvm
blacklist mac80211
blacklist cfg80211
EOF

  echo "WiFi has been disabled by blacklisting the driver. A reboot is required to apply the changes."
}

# Function to enable WiFi by removing the blacklist
function enable_wifi_blacklist() {
  echo "Enabling WiFi by removing the custom blacklist for iwlwifi and its dependencies."

  # Remove the custom blacklist file
  sudo rm -f /etc/modprobe.d/blacklist-wifi.conf

  echo "WiFi has been enabled. A reboot is required to fully restore functionality."
}

# Function to fully update the system
function update_system_fully() {
  echo "You chose to fully update the system to ensure no pending updates."

  # Remove old versions of Google Chrome (to avoid update conflicts)
  echo "Removing old versions of Google Chrome..."
  sudo apt remove --purge -y google-chrome-stable google-chrome-beta google-chrome-unstable || true

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


# Function to update Google Chrome
function update_google_chrome() {
  echo "You chose to update Google Chrome to the latest version."

  # Add the official Google Chrome repository
  wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo apt-key add -
  echo 'deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main' | sudo tee /etc/apt/sources.list.d/google-chrome.list

  # Update package lists and install the latest version of Google Chrome
  sudo apt update
  sudo apt install -y google-chrome-stable

  echo "Google Chrome has been updated to the latest version."
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

# Function to update Snap packages
function update_snap_packages() {
  echo "Updating Snap packages..."
  
  # Update all Snap packages
  sudo snap refresh
  
  echo "All Snap packages are up to date."
}

# Function to update GNOME extensions
function update_gnome_extensions() {
  echo "Updating GNOME extensions..."

  # Ensure the gnome-shell-extensions package is installed
  if ! command -v gnome-extensions &>/dev/null; then
    echo "gnome-extensions command not found. Installing..."
    sudo apt install -y gnome-shell-extensions
  fi

  # Update all enabled extensions
  gnome-extensions list --enabled | while read -r ext; do
    echo "Updating extension: $ext"
    gnome-extensions update "$ext" || echo "Failed to update $ext"
  done

  echo "All GNOME extensions are updated."
}

# Function to update Flatpak packages
function update_flatpak_packages() {
  echo "Updating Flatpak packages..."

  # Ensure Flatpak is installed
  if ! command -v flatpak &>/dev/null; then
    echo "Flatpak command not found. Installing..."
    sudo apt install -y flatpak
  fi

  # Update all Flatpak packages
  flatpak update -y

  echo "All Flatpak packages are up to date."
}


# Function to disable notifications for all non-admin users
function disable_notifications_for_users() {
  echo "Disabling notifications for all non-admin users..."

  # Ensure dbus-x11 is installed
  if ! dpkg -l | grep -q dbus-x11; then
    echo "dbus-x11 is not installed. Installing it now..."
    apt update && apt install -y dbus-x11
    if [ $? -ne 0 ]; then
      echo "Failed to install dbus-x11. Exiting."
      exit 1
    fi
  else
    echo "dbus-x11 is already installed."
  fi

  # Get the list of non-admin users (UID >= 1000, not in 'sudo' group)
  non_admin_users=$(awk -F':' '{ if ($3 >= 1000 && $3 < 65534) print $1 }' /etc/passwd | while read -r user; do
    if ! groups "$user" | grep -q sudo; then
      echo "$user"
    fi
  done | tr '\n' ' ') # Ensure output is a single line

  # Loop through each user
  for user in $non_admin_users; do
    echo "Disabling notifications for user: $user"

    # Check if the user's home directory exists
    if [ -d "/home/$user" ]; then
      # Ensure the user's DConf directory exists
      sudo -u "$user" mkdir -p /home/"$user"/.config/dconf

      # Use dbus-launch to apply the setting via gsettings
      sudo -u "$user" dbus-launch gsettings set org.gnome.desktop.notifications show-banners false

      echo "Notifications disabled for user: $user"
    else
      echo "Home directory for user $user does not exist. Skipping."
    fi
  done

  echo "Notification settings have been updated for all non-admin users."
}



# Display menu options
function display_menu() {
  echo "Select an operation to perform:"
  echo "1) Downgrade a user to standard"
  echo "2) Create a new admin account and hide it"
  echo "3) Restrict network changes for standard users"
  echo "4) Disable WiFi by blacklisting driver"
  echo "5) Enable WiFi by removing driver blacklist"
  echo "6) Remove Deja Dup (Backups) and clean up"
  echo "7) Fully update the system"
  echo "8) Update Google Chrome to the latest version"
  echo "9) Forget a WiFi network and reboot"
  echo "10) Disable LTS upgrade prompts"
  echo "11) Clear GUI update metadata"
  echo "12) Perform all (1, 2, 3, 4, 6, 10, 11, 7, 8, 13, 14, 15, 16 and 9 last)"
  echo "13) Update Snap packages"
  echo "14) Update GNOME extensions"
  echo "15) Update Flatpak packages"
  echo "16) Disable notifications for standard users"
  echo "0) Exit"
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
        disable_wifi_blacklist
        ;;
      5)
        enable_wifi_blacklist
        ;;
      6)
        remove_deja_dup
        ;;
      7)
        update_system_fully
        ;;
      8)
        update_google_chrome
        ;;
      9)
        forget_wifi_and_reboot
        ;;
      10)
        disable_lts_upgrade_prompts
        ;;
      11)
        clear_gui_metadata
        ;;
      12)
        downgrade_user
        create_admin_user
        restrict_network_changes
        disable_wifi_blacklist
        remove_deja_dup
        disable_lts_upgrade_prompts
        clear_gui_metadata
        update_system_fully
        update_google_chrome
        update_snap_packages
        update_gnome_extensions
        update_flatpak_packages
        disable_notifications_for_users
        forget_wifi_and_reboot
        ;;
      13)
        update_snap_packages
        ;;
      14)
        update_gnome_extensions
        ;;
       15)
        update_flatpak_packages
        ;;
      16)
        disable_notifications_for_users
        ;;
      0)
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
