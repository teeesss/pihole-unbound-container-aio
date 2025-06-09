# Pi-hole + Unbound All-in-One Docker Setup

This repository contains the definitive, robust configuration for running a self-contained Pi-hole and Unbound DNS resolver in a single Docker container. This setup is specifically hardened to work on a complex, shared Ubuntu host.

## Core Architecture: The All-in-One Image

After extensive troubleshooting, it was determined that the most stable and secure solution is to use the **`mpgirro/pihole-unbound`** community image.

This approach provides the best of all worlds:
*   **Simplicity:** The entire stack runs as a single Docker service (`pihole`), eliminating all complex multi-container networking issues.
*   **Conflict Avoidance:** By running Unbound inside the Pi-hole container, we avoid all potential port conflicts with other services on the host (like a Unifi controller).
*   **Resilience:** The setup is made immune to configuration drift from sync tools (like `nebula-sync`) by using environment variables in the `docker-compose.yml` that enforce the correct settings on every container start.

---

## Setup Instructions

The entire setup process is automated by the `install.sh` script.

### Step 1: Configure the Installer Script

Before running, open the `install.sh` script and customize the variables in the configuration block at the top to match your environment (e.g., `PROJECT_DIR`, `PIHOLE_PASSWORD`, etc.).

### Step 2: Run the Installer

The script is interactive and safe. It will ask you to confirm the installation path and all settings before making any changes. Execute it with `sudo`.

    sudo ./install.sh

The script will:
1.  **Prepare the Host:** Reconfigure `systemd-resolved` to free up port 53 for Pi-hole.
2.  **Create `docker-compose.yml`:** Generate the final Docker Compose file that orchestrates the service.
3.  **Automate Configuration:** Launch the container, wait for it to create its initial config, and then automatically use `sed` to correct the `listeningMode` to `ALL`.
4.  **Launch & Verify:** Restart the container with the correct settings and perform a final verification to confirm the setup was successful.

---

### Post-Installation

After the script completes, your Pi-hole is live.

1.  **Check Status:** You can verify the system's health at any time using the `check_status.sh` script that the installer creates for you.

        sudo ./check_status.sh

2.  **Access the Web Interface:**
    Open your browser and navigate to your host's IP on the port you configured (e.g., `8088`):

        http://<your_host_ip>:8088/admin/

Login with the password you set. Go to **Settings -> DNS**. You will see that the only upstream DNS server configured and checked is `Custom 1 (IPv4): 127.0.0.1#5335`. This confirms Pi-hole is correctly using the Unbound service running inside the same container.

For a list of common management commands, see the `INFO.md` file.
