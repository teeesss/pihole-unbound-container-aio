# Pi-hole + Unbound All-in-One Docker Setup (Robust & Automated)

This repository contains the definitive, robust configuration for running a self-contained Pi-hole and Unbound DNS resolver in a single Docker container. This setup is hardened to work on a shared Ubuntu host and is resilient against common permission and sync-related issues.

## Key Features

*   **Automated Installer & Manager:** A single `install.sh` script handles initial setup, diagnostics, updates, and maintenance.
*   **Correct Permissions by Default:** The script automatically detects the correct host user ID (`PIHOLE_UID`/`GID`) to prevent all volume permission errors.
*   **Resilient Configuration:** The setup enforces the correct upstream DNS settings on every container start, making it immune to configuration drift.
*   **Sync Tool Compatibility:** Includes a one-time, automated permission fixer for seamless integration with root-level file sync tools like `nebula-sync`.
*   **All-in-One Simplicity:** Uses the `mpgirro/pihole-unbound` image to run the entire stack in one container, eliminating complex networking and port conflicts.

---

## Setup Instructions

The entire process is handled by the `install.sh` script.

### Step 1: (Optional) Configure Script Variables
Before running, you can open `install.sh` and edit the configuration variables at the top (e.g., `PIHOLE_PASSWORD`, `TIMEZONE`). The defaults are also fine.

### Step 2: Run the Installer
The script is interactive and will confirm all settings before making any changes to your system. Execute it with `sudo`.

```
sudo ./install.sh
```

The script will:
1.  **Prepare the Host:** Reconfigure `systemd-resolved` to free up port 53.
2.  **Create Project Files:** Generate the final `docker-compose.yml` and `.env` files.
3.  **Automate Configuration:** Launch the container and automatically correct the Pi-hole `listeningMode`.
4.  **Launch & Verify:** Restart the container and perform a robust, multi-attempt verification to ensure the setup is fully functional.

### Management & Troubleshooting

After installation, simply re-run `sudo ./install.sh` at any time to access the **Management Menu**.

From there, you can:
*   Update the container image.
*   Run diagnostics to check the system's health.
*   Perform a full re-install.
*   **Install the automated permission fixer for `nebula-sync`.**

### Post-Installation Verification

Your Pi-hole is live once the script completes.

1.  **Access the Web Interface:**
    Navigate to `http://<your_host_ip>:8088/admin/`.
2.  **Login** with the password you set.
3.  Go to **Settings -> DNS**. You will see that the only upstream DNS server is `Custom 1 (IPv4): 127.0.0.1#5335`. This confirms Pi-hole is correctly using its internal Unbound service.

For a list of common manual commands, see the `INFO.md` file.
