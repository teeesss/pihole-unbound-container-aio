# Pi-hole All-in-One Container: Useful Commands & Info

This document contains common commands for managing and troubleshooting the all-in-one Pi-hole + Unbound Docker container.

**Important:** All `docker-compose` commands should be run from your project directory (e.g., `~/full-stack/pihole`).

---

### Basic Container Management

*   **Check Status:**
    See if the `pihole` container is running and healthy.

        sudo docker-compose ps

*   **Stop the Container:**
    Stops the container but does not remove it.

        sudo docker-compose stop

*   **Start the Container:**
    Starts the previously stopped container.

        sudo docker-compose start

*   **Restart the Container:**
    A quick way to stop and then start the container.

        sudo docker-compose restart

*   **Stop and Remove the Container:**
    This stops the container and removes it. Your configuration in the volumes is safe.

        sudo docker-compose down

*   **Apply `docker-compose.yml` Changes:**
    If you change the `docker-compose.yml` file (e.g., the password or environment variables), run this command to recreate the container with the new settings.

        sudo docker-compose up -d --force-recreate

---

### Viewing Logs

*   **View Live Container Logs:**
    Shows a continuous stream of the container log, including startup messages from both Pi-hole and Unbound. Press `Ctrl+C` to exit.

        sudo docker logs -f pihole

*   **View Pi-hole's Live DNS Query Log:**
    This shows the live DNS queries being processed by Pi-hole's FTL engine.

        sudo docker exec -it pihole pihole -t

---

### Pi-hole & Unbound Specific Commands

These commands let you interact directly with the applications inside the container.

*   **Change the Web Interface Password:**

        sudo docker exec -it pihole pihole setpassword

*   **Update Gravity (Blocklists):**

        sudo docker exec -it pihole pihole -g

*   **Check Unbound Status:**
    This command asks the running Unbound process for its status. Note: This requires enabling `remote-control` in the image, which is not done by default.

        sudo docker exec pihole unbound-control status

*   **Test Unbound Resolution Directly:**
    This bypasses Pi-hole and queries the internal Unbound service directly. This is the best way to test Unbound's health.

        sudo docker exec pihole dig @127.0.0.1 -p 5335 google.com

*   **Open a Bash Shell Inside the Container:**
    For advanced debugging, this gives you a command prompt inside the all-in-one container.

        sudo docker exec -it pihole /bin/bash

---

### Troubleshooting

*   **Run the Diagnostic Script:** Your first step should always be to run the status checker created by the installer.

        sudo ./check_status.sh

*   **Problem:** The container is in a "Restarting" loop or is "Unhealthy".
    1.  **Check the logs immediately:** `sudo docker logs pihole`. The error message will almost always be at the end of the log.

*   **Problem:** `dig @<host_ip>` fails, but the container seems healthy.
    1.  Run `sudo ./check_status.sh`. It will likely report that the `listeningMode` is not `ALL`.
    2.  This means the automated `sed` command in the installer may have failed. Manually edit `./etc-pihole/pihole.toml`, change `listeningMode = "LOCAL"` to `listeningMode = "ALL"`, and restart the container with `sudo docker-compose restart`.
