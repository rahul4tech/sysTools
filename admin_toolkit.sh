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

  echo "WiFi has been enabled. A reboot is required to fully restore functionality. Rebooting.."
  sleep 3 && sudo reboot
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

# Function to remove connections by number by matching UUID reading by 4 hyphens
function forget_wifi_and_reboot() {
  echo "You chose to forget multiple WiFi networks and schedule a reboot."

  # Declare an array to store connections
  connections=()

  # List all saved WiFi networks with SSIDs and UUIDs
  echo "Available saved WiFi networks:"
  while read -r line; do
    # echo "Debug: Processing line: $line"  # Debug each line
    uuid=$(echo "$line" | grep -oE '[a-f0-9-]{36}' || true)  # Extract valid UUID
    if [ -n "$uuid" ]; then
      ssid=$(echo "$line" | sed "s/$uuid.*//" | sed 's/[[:space:]]*$//' || true)  # Extract SSID
      connections+=("$ssid|$uuid")  # Store SSID and UUID in the array
      printf "%-3d SSID: %-30s UUID: %s\n" "${#connections[@]}" "$ssid" "$uuid"
    fi
  done < <(nmcli connection show)

  # Check if connections are available
  if [ ${#connections[@]} -eq 0 ]; then
    echo "No saved WiFi networks found."
    return
  fi

  # Debug: Show connections array
  # echo "Debug: Final connections array: ${connections[@]}"

  # Prompt user to select indices
  echo "Enter the indices of the WiFi networks to forget, separated by spaces (e.g., '1 2 3'):"
  read -p "Indices: " indices

  # Create the temporary script for delayed deletion and reboot
  tmp_script="/tmp/forget_wifi_and_reboot.sh"
  sudo bash -c "cat <<EOF > $tmp_script
#!/bin/bash
echo ''
EOF"

  # Process each selected index
  for index in $indices; do
    if [[ $index -gt 0 && $index -le ${#connections[@]} ]]; then
      connection="${connections[$((index-1))]}"  # Get the connection by index
      ssid=$(echo "$connection" | cut -d'|' -f1)
      uuid=$(echo "$connection" | cut -d'|' -f2)
      echo "Adding command to forget WiFi network: SSID=\"$ssid\", UUID=\"$uuid\"..."
      sudo bash -c "echo nmcli connection delete uuid \"$uuid\" >> $tmp_script"
    else
      echo "Invalid selection: $index. Skipping."
    fi
  done

  # Add reboot command to the script
  sudo bash -c "echo \"echo 'Rebooting now...'; /sbin/reboot\" >> $tmp_script"

  # Make the temporary script executable
  sudo chmod +x "$tmp_script"

  # Schedule the script to run in 5 seconds
  echo "Scheduling the WiFi forget and reboot in 5 seconds..."
  (sleep 5 && bash $tmp_script) &

  echo "The WiFi forget and reboot have been scheduled. Disconnecting will occur soon."
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

# Function to identify non-admin users and clear Chrome history
function clear_history_for_non_admin_users() {
  echo "Starting process to clear Chrome history for non-admin users..."

  # Get a list of non-admin users (UID >= 1000, not in 'sudo' group)
  non_admin_users=$(awk -F':' '{ if ($3 >= 1000 && $3 < 65534) print $1 }' /etc/passwd | while read -r user; do
    if ! groups "$user" | grep -q sudo; then
      echo "$user"
    fi
  done)

  # Loop through non-admin users and clear their Chrome history
  for user in $non_admin_users; do
    echo "Processing user: $user"

    # Check if Chrome's Default profile exists for the user
    chrome_dir="/home/$user/.config/google-chrome/Default"
    if [ -d "$chrome_dir" ]; then
      echo "Clearing Chrome history for user: $user"
      sudo -u "$user" rm -f "$chrome_dir/History" "$chrome_dir/History-journal" || true
      echo "Chrome history cleared for user: $user"
    else
      echo "Chrome profile not found for user: $user. Skipping."
    fi
  done

  echo "History clearing completed for all non-admin users."

  # Check if Chrome is running and kill it
  if pgrep chrome &>/dev/null; then
    echo "Killing all Chrome processes..."
    pkill chrome
    echo "All Chrome processes have been terminated."
  else
    echo "No Chrome processes found. Skipping kill step."
  fi
}

# Function to remove Snap Firefox, install APT version, and configure locked proxy
function setup_global_firefox_proxy() {
  echo "You chose to set up a globally locked Firefox proxy."

  echo "→ Ensuring Firefox is not running..."
  sudo pkill -f firefox || true

  # Prompt for proxy settings
  read -p "Enter the proxy host (e.g., 127.0.0.1): " proxy_host
  read -p "Enter the proxy port (e.g., 8080): " proxy_port

  # Remove Snap Firefox if it exists
  if snap list | grep -q "^firefox"; then
    echo "→ Removing Snap-based Firefox..."
    sudo snap remove firefox
    sudo rm -f /snap/bin/firefox
  else
    echo "→ Snap Firefox is not installed."
  fi

  # Remove APT redirector package if present
  if dpkg -l | grep -q "firefox\s\+1:snap"; then
    echo "→ Removing APT Snap-redirector package..."
    sudo apt remove -y firefox
  fi

  # Prevent APT from reinstalling Snap version
  echo "→ Blocking Snap Firefox from reinstalling via APT..."
  sudo tee /etc/apt/preferences.d/firefox-no-snap > /dev/null <<EOF
Package: firefox
Pin: release o=Ubuntu*
Pin-Priority: -1
EOF

  # Add Mozilla PPA if missing
  if ! grep -rq "mozillateam/ppa" /etc/apt/sources.list.d/ /etc/apt/sources.list; then
    echo "→ Adding Mozilla PPA..."
    sudo add-apt-repository -y ppa:mozillateam/ppa
  fi

  # Prefer PPA Firefox over Snap-enabler package
  echo "→ Prioritizing PPA version of Firefox..."
  sudo tee /etc/apt/preferences.d/mozilla-firefox.pref > /dev/null <<EOF
Package: firefox
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 1001
EOF

  echo "→ Updating package lists..."
  sudo apt update

  echo "→ Installing Firefox (APT version)..."
  sudo apt install -y firefox

  # Backup existing policy if present
  if [ -f /etc/firefox/policies/policies.json ]; then
    sudo cp /etc/firefox/policies/policies.json /etc/firefox/policies/policies.json.bak
    echo "→ Backed up existing policies.json to policies.json.bak"
  fi

  echo "→ Creating locked proxy policy..."
  sudo mkdir -p /etc/firefox/policies
  sudo tee /etc/firefox/policies/policies.json > /dev/null <<EOF
{
  "policies": {
    "Proxy": {
      "Mode": "manual",
      "Locked": true,
      "HTTPProxy": "$proxy_host:$proxy_port",
      "SSLProxy": "$proxy_host:$proxy_port",
      "NoProxy": "localhost, 127.0.0.1"
    }
  }
}
EOF

  echo "✅ Firefox installed and proxy is locked globally."
}

function manage_chrome_blocklist() {
  local policy_dir="/etc/opt/chrome/policies/managed"
  local policy_file="$policy_dir/block.json"

  # Ensure required tools
  if ! command -v jq &>/dev/null; then
    echo "Installing jq..."
    sudo apt update && sudo apt install -y jq
  fi

  # Default blocklist
  local default_urls=(
    "https://mail.google.com"
    "https://www.google.com/search"
    "workspace.google.com"
    "accounts.google.com"
    "gmail.com"
  )

  # Ensure policy directory exists
  sudo mkdir -p "$policy_dir"

  local changed=false
  local choice=""

  if [ -f "$policy_file" ]; then
    echo "📄 Existing blocklist:"
    sudo jq -r '.URLBlocklist[]?' "$policy_file" || echo "(Empty or invalid format)"
    echo

    echo "Choose an option:"
    echo "1) Add more URLs to the existing blocklist"
    echo "2) Reset the blocklist (remove all)"
    echo "3) Leave the current blocklist unchanged"
    echo "4) View only (do nothing)"
    read -p "Enter your choice [1/2/3/4]: " choice

    case "$choice" in
      2)
        echo "Resetting blocklist to empty..."
        sudo tee "$policy_file" > /dev/null <<EOF
{
  "URLBlocklist": []
}
EOF
        changed=true
        ;;
      4)
        echo "No changes made."
        return
        ;;
    esac
  else
    echo "🆕 Creating default blocklist with preset URLs..."
    local formatted_urls
    formatted_urls=$(printf '"%s",\n' "${default_urls[@]}" | sed '$s/,$//')
    sudo tee "$policy_file" > /dev/null <<EOF
{
  "URLBlocklist": [
    $formatted_urls
  ]
}
EOF
    changed=true
  fi

  # Add more URLs if desired
  if [[ "$choice" == "1" || ! -f "$policy_file" ]]; then
    while true; do
      read -p "Enter a URL to block (or press Enter to finish): " url
      [ -z "$url" ] && break
      echo "Adding: $url"
      tmp_file=$(mktemp)
      sudo jq --arg url "$url" '.URLBlocklist |= unique + [$url]' "$policy_file" > "$tmp_file" && sudo mv "$tmp_file" "$policy_file"
      changed=true
    done
  fi

  if [ "$changed" = true ]; then
    echo "🔒 Chrome blocklist updated at: $policy_file"

    # Ensure permissions are correct
    sudo chown root:root "$policy_file"
    sudo chmod 644 "$policy_file"
    sudo chmod 755 "$policy_dir"

    echo "✅ Changes saved. Visit chrome://policy in Chrome and click 'Reload Policies' to verify."
  else
    echo "✅ No changes were made to the blocklist."
  fi

  echo "Returning to the menu..."
  sleep 2
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
  echo "12) Perform all (1, 2, 3, 4, 6, 10, 11, 7, 8, 13, 14, 15, 16, 17 and 9 last)"
  echo "13) Update Snap packages"
  echo "14) Update GNOME extensions"
  echo "15) Update Flatpak packages"
  echo "16) Disable notifications for standard users"
  echo "17) Clear Chrome history for non-admin users"
  echo "18) Set up a globally locked Firefox proxy (APT version)"
  echo "19) Configure Chrome site blocking policy"
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
        set +e # Allow the script to continue even if forget_wifi_and_reboot fails
        forget_wifi_and_reboot
        set -e # Re-enable exit on error
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
        clear_history_for_non_admin_users
        set +e  # Allow the script to continue even if forget_wifi_and_reboot fails
        forget_wifi_and_reboot
        set -e  # Re-enable exit on error
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
      17)
        clear_history_for_non_admin_users
        ;;
      18)
        setup_global_firefox_proxy
        ;;
      19)
        manage_chrome_blocklist
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
