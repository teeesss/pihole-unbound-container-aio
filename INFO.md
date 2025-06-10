# Pi-hole All-in-One Container: Useful Commands & Info

This document contains common commands for managing and troubleshooting the all-in-one Pi-hole + Unbound Docker container. All management, installation, and diagnostic tasks are handled by the main `install.sh` script.

**Important:** All commands should be run from your project directory (e.g., `~/full-stack/pihole`).

---

### Primary Management Tool

The `install.sh` script is your main tool for managing the stack. Running it after the initial installation will bring up a management menu.

    sudo ./install.sh

*   **Option [1]** Re-pull Latest Image & Recreate Container
*   **Option [2]** runs a full diagnostic check
*   **Option [3]** Force Full Re-install (Deletes ALL existing Pi-hole data!). # Run this for a new install
*   **Option [4]** installs the automated permission fixer for `nebula-sync`
*   **Option [5]** Exit

---

### Basic Container Management (Manual)

*   **Check Status:**
    See if the `pihole` container is running and healthy.
    ```bash
    sudo docker-compose ps
    ```

*   **Stop the Container:**
    ```bash
    sudo docker-compose stop
    ```

*   **Start the Container:**
    ```bash
    sudo docker-compose start
    ```

*   **Restart the Container:**
    ```bash
    sudo docker-compose restart
    ```

*   **Stop and Remove the Container:**
    This stops and removes the container. Your configuration in the volumes is safe.
    ```bash
    sudo docker-compose down
    ```

---

### Viewing Logs

*   **View Live Container Logs:**
    Shows a continuous stream of the container log, including startup messages from Pi-hole and Unbound. Press `Ctrl+C` to exit.
    ```bash
    sudo docker logs -f pihole
    ```

*   **View Pi-hole's Live DNS Query Log:**
    This shows the live DNS queries being processed by Pi-hole's FTL engine.
    ```bash
    sudo docker exec pihole pihole -t
    ```

---

### Pi-hole & Unbound Specific Commands

*   **Change the Web Interface Password:**
    ```bash
    sudo docker exec pihole pihole setpassword
    ```

*   **Manually Update Gravity (Blocklists):**
    ```bash
    sudo docker exec pihole pihole -g
    ```

*   **Check Unbound Status:**
    This command asks the running Unbound process for its status.
    ```bash
    sudo docker exec pihole unbound-control status
    ```

*   **Test Unbound Resolution Directly:**
    This bypasses Pi-hole and queries the internal Unbound service. This is the best way to test Unbound's health.
    ```bash
    sudo docker exec pihole dig @127.0.0.1 -p 5335 google.com
    ```

*   **Open a Shell Inside the Container:**
    For advanced debugging, this gives you a command prompt inside the container.
    ```bash
    sudo docker exec -it pihole /bin/bash
    ```

---

### Troubleshooting `nebula-sync`

*   **Problem:** After `nebula-sync` runs, updating gravity fails with `Permission denied` or `FOREIGN KEY` errors.
*   **Cause:** `nebula-sync` (running as root) changes the ownership of `gravity.db` on the host volume.
*   **Solution:** Use the installer to set up the automated permission fixer. This is a one-time setup.
    1.  Run `sudo ./install.sh`.
    2.  Choose option `[4] Install Automatic Permission Fixer`.
    3.  This installs a host-level cron job that runs every minute to correct the file ownership, making the system seamlessly compatible with `nebula-sync`.
