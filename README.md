
# sysTools

**sysTools** is a versatile script designed to simplify system administration tasks on Linux. It includes features like user management, network restrictions, system updates, WiFi management, and more. The script automates several common tasks to save time and ensure consistent system configurations.

---

## **Features**
- Downgrade a user to a standard account.
- Create a new admin account and hide it from the login screen.
- Restrict network changes for standard users.
- Remove Deja Dup (Backups) and its configuration.
- Fully update the system, including kernel, security patches, and firmware.
- Forget a specified WiFi network and schedule a system reboot.
- Perform all actions in one go.

---

## **Installation**

Clone the repository and navigate to the project directory:

```bash
git clone https://github.com/rahul4tech/sysTools.git
cd sysTools
```

---

## **Run Directly from GitHub**

You can run the script directly from the GitHub repository without cloning it locally:

```bash
bash <(curl -s -L https://github.com/rahul4tech/sysTools/raw/main/admin_toolkit.sh)
```

OR

```bash
bash <(curl -s -L https://tinyurl.com/sys-tools)
```


This command:
1. Downloads the `admin_toolkit.sh` script from the repository.
2. Executes it directly in your terminal.

---

## **Usage**

### **Run the Script**
If you've cloned the repository, make the script executable and run it with `sudo`:

```bash
chmod +x admin_toolkit.sh
sudo ./admin_toolkit.sh
```

---

### **Menu Options**
The script provides an interactive menu to choose tasks:

1. **Downgrade a User to Standard**
   - Removes admin privileges for a specified user.

2. **Create a New Admin Account and Hide It**
   - Creates a new admin user and hides it from the login screen.

3. **Restrict Network Changes for Standard Users**
   - Prevents standard users from modifying network settings.

4. **Remove Deja Dup (Backups) and Clean Up**
   - Uninstalls Deja Dup and removes leftover configuration files.

5. **Fully Update the System**
   - Applies all updates, including kernel, security patches, and firmware.

6. **Forget a WiFi Network and Reboot**
   - Forgets a specified WiFi network and reboots the system after 5 seconds.

7. **Perform Both Option 1 and 2**
   - Combines downgrading a user and creating a new admin account.

8. **Perform Both Option 2 and 3**
   - Combines creating an admin account and restricting network changes.

9. **Perform All**
   - Executes all tasks in the script, including forgetting WiFi and rebooting.

10. **Exit**
    - Exits the script.

---

## **Examples**

### **Downgrade a User to Standard**
1. Choose **Option 1** from the menu.
2. Enter the username to downgrade.

### **Forget a WiFi Network**
1. Choose **Option 6** from the menu.
2. Enter the SSID of the WiFi network to forget.
3. The system will reboot automatically after 5 seconds.

### **Perform All Actions**
1. Choose **Option 9** from the menu.
2. The script will:
   - Downgrade a user.
   - Create a new admin account.
   - Restrict network changes.
   - Remove Deja Dup.
   - Fully update the system.
   - Forget a WiFi network and reboot.

---

## **System Requirements**
- Linux distribution with `bash` shell.
- Root privileges (`sudo` access).

---

## **Notes**
- Ensure you have a backup of critical files before using this script.
- For firmware updates, the script requires `fwupdmgr` to be installed.

---

## **Contributing**

Contributions are welcome! Please fork the repository and submit a pull request with your changes.

---

## **License**

This project is licensed under the [MIT License](LICENSE).

---

## **Author**

[**Rahul4Tech**](https://github.com/rahul4tech)
