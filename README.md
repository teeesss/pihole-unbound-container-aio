# Pi-hole + Unbound All-in-One Docker Setup with DNSSEC (Robust & Automated)

This repository contains the definitive, robust configuration for running a self-contained Pi-hole and Unbound DNS resolver with **full DNSSEC validation** in a single Docker container. This setup is hardened to work on a shared Ubuntu host and is resilient against common permission and sync-related issues.

## Key Features

*   **Full DNSSEC Validation:** Properly configured Unbound with root trust anchor validation that blocks domains with invalid DNSSEC signatures
*   **Automated Installer & Manager:** A single `install.sh` script handles initial setup, diagnostics, updates, and maintenance with built-in DNSSEC testing
*   **Correct Permissions by Default:** The script automatically detects the correct host user ID (`PIHOLE_UID`/`GID`) to prevent all volume permission errors
*   **Resilient Configuration:** The setup enforces the correct upstream DNS settings and DNSSEC configuration on every container start
*   **Sync Tool Compatibility:** Includes automated permission fixer for seamless integration with root-level file sync tools like `nebula-sync`
*   **All-in-One Simplicity:** Uses the `mpgirro/pihole-unbound` image to run the entire stack in one container, eliminating complex networking and port conflicts
*   **Comprehensive Testing:** Built-in DNSSEC validation testing using multiple test domains to ensure security is working

---

## Setup Instructions

The entire process is handled by the `install.sh` script, which includes automatic DNSSEC configuration and validation.

### Step 1: (Optional) Configure Script Variables
Before running, you can open `install.sh` and edit the configuration variables at the top (e.g., `PIHOLE_PASSWORD`, `TIMEZONE`).
The defaults work, but modify as needed.

### Step 2: Run the Installer
The script is interactive and will confirm all settings before making any changes to your system. Execute it with `sudo`.

```bash
sudo ./install.sh
