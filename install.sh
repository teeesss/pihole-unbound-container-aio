#!/bin/bash

# ==============================================================================
# Definitive All-in-One Pi-hole + Unbound Docker Setup Script (v24 - Final)
# ==============================================================================
# This script automates the setup and management of a single, self-contained
# Docker container running both Pi-hole and Unbound. It includes robust
# installation, diagnostics, and an automated permission fixer for users
# of file-sync tools like nebula-sync.
# ==============================================================================

# --- Configuration Variables ---
PIHOLE_WEB_PORT="8088"
PIHOLE_PASSWORD="YourNewSecurePassword"
TIMEZONE="America/Chicago"
FALLBACK_DNS="1.1.1.1 9.9.9.9"

# --- Dynamic Variables (Do Not Edit) ---
PROJECT_DIR=$(pwd)
# This is the critical fix: use SUDO_UID/SUDO_GID if they exist, otherwise fall back to id.
DETECTED_UID=${SUDO_UID:-$(id -u)}
DETECTED_GID=${SUDO_GID:-$(id -g)}

# --- Color and Symbol Definitions ---
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; RED='\033[0;31m'; NC='\033[0m';
TICK="[${GREEN}✓${NC}]"; INFO="[${BLUE}➔${NC}]"; WARN="[${YELLOW}⚠️${NC}]"; CROSS="[${RED}✗${NC}]"; ROCKET="🚀";

# --- Helper Functions ---
log() { printf "\n${BLUE}==================================================================${NC}\n"; printf "=> ${YELLOW}%s${NC}\n" "$1"; printf "${BLUE}==================================================================${NC}\n"; }

confirm_installation() {
  log "CONFIRMATION"
  printf "This script will create a new Pi-hole installation in the current directory:\n"
  printf "  ${GREEN}%s${NC}\n\n" "${PROJECT_DIR}"
  printf "Using the following settings:\n"
  printf "  - Web UI Port:    %s\n" "${PIHOLE_WEB_PORT}"
  printf "  - Web Password:   %s\n" "${PIHOLE_PASSWORD}"
  printf "  - Timezone:       %s\n" "${TIMEZONE}"
  printf "  - User/Group ID:  ${GREEN}%s:%s${NC} (for secure volume permissions)\n" "${DETECTED_UID}" "${DETECTED_GID}"
  printf "\n${WARN} This will also reconfigure the host's systemd-resolved to free up port 53.\n"
  read -p "Are these settings correct? [y/N] " response
  if [[ ! "$response" =~ ^[Yy]$ ]]; then printf "Installation cancelled.\n"; exit 0; fi
}

prepare_host() {
  log "STEP 1: Preparing Host"; printf "${INFO} Disabling systemd-resolved stub listener... "
  sudo systemctl stop systemd-resolved.service >/dev/null 2>&1 && sudo systemctl disable systemd-resolved.service >/dev/null 2>&1
  if ! grep -q "DNSStubListener=no" /etc/systemd/resolved.conf; then sudo sed -i 's/#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf; fi
  if ! grep -q "^DNS=" /etc/systemd/resolved.conf; then sudo sed -i "/\[Resolve\]/a DNS=${FALLBACK_DNS}" /etc/systemd/resolved.conf; else sudo sed -i "s/^DNS=.*/DNS=${FALLBACK_DNS}/" /etc/systemd/resolved.conf; fi
  if [ -L /etc/resolv.conf ] && [ "$(readlink -f /etc/resolv.conf)" != "/run/systemd/resolve/resolv.conf" ]; then sudo rm /etc/resolv.conf; fi
  if [ ! -L /etc/resolv.conf ]; then sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf; fi
  sudo systemctl restart systemd-resolved; printf "${TICK}\n"
}

create_project_files() {
  log "STEP 2: Creating Project Configuration Files"
  mkdir -p "${PROJECT_DIR}/etc-pihole"
  mkdir -p "${PROJECT_DIR}/etc-dnsmasq.d"

  cat << EOF > "${PROJECT_DIR}/.env"
# Docker-compose environment file
TZ=${TIMEZONE}
WEBPASSWORD=${PIHOLE_PASSWORD}
PIHOLE_UID=${DETECTED_UID}
PIHOLE_GID=${DETECTED_GID}
EOF
  printf "${TICK} .env file created.\n"

  cat << EOF > "${PROJECT_DIR}/docker-compose.yml"
version: "3.7"

services:
  pihole:
    image: mpgirro/pihole-unbound:latest
    container_name: pihole
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "${PIHOLE_WEB_PORT}:80/tcp"
    env_file: .env
    environment:
      FTLCONF_dns_upstreams: '127.0.0.1#5335'
    volumes:
      - './etc-pihole:/etc/pihole'
      - './etc-dnsmasq.d:/etc/dnsmasq.d'
    cap_add:
      - NET_ADMIN
      - CAP_SYS_NICE
    restart: unless-stopped
EOF
  printf "${TICK} docker-compose.yml created.\n"
}

run_installation() {
    local install_type="$1"
    if [[ "$install_type" == "reinstall" ]]; then
        log "Starting Full Re-installation"
    else
        log "Starting Fresh Installation"
    fi

    prepare_host
    create_project_files

    log "STEP 3: Launching & Automatically Configuring Container"
    cd "$PROJECT_DIR" || { printf "${RED}Failed to change to project directory. Aborting.${NC}\n"; exit 1; }

    printf "${INFO} Pulling the latest image...\n"
    sudo docker-compose pull

    printf "${INFO} Starting container for the first time to generate config...\n"
    sudo docker-compose up -d --remove-orphans

    local pihole_toml_path="${PROJECT_DIR}/etc-pihole/pihole.toml"
    printf "${INFO} Waiting for Pi-hole to create config file"
    count=0
    while [ ! -f "$pihole_toml_path" ]; do
        if [ $count -ge 30 ]; then printf "\n${CROSS} ${RED}ERROR: Timeout waiting for pihole.toml.${NC}\n"; sudo docker logs pihole; exit 1; fi
        printf "."; sleep 2; count=$((count+1));
    done

    printf " ${TICK}\n"
    printf "${INFO} Automatically correcting 'listeningMode'...\n"
    sudo sed -i 's/listeningMode = "LOCAL"/listeningMode = "ALL"/' "$pihole_toml_path"
    printf "${INFO} Restarting container to apply the final configuration...\n"
    sudo docker-compose restart

    printf "${INFO} Waiting for container to stabilize after restart..."
    sleep 15

    HOST_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n 1)

    log "STEP 4: FINAL VERIFICATION"
    printf "${INFO} Performing a live DNS query to confirm functionality...\n"
    if dig @"$HOST_IP" google.com +short > /dev/null; then
        printf "${TICK} Live query successful!\n"

        printf "${INFO} Running gravity update to confirm database health (will retry up to 3 times)...\n"
        local gravity_success=false
        local gravity_output=""
        for attempt in {1..3}; do
            printf "${INFO} Attempt #%s to update gravity...\n" "$attempt"
            gravity_output=$(sudo docker exec pihole pihole -g 2>&1)

            if echo "$gravity_output" | grep -q "\[✗"; then
                printf "${WARN} Gravity update failed on attempt #%s. Retrying in 15 seconds...\n" "$attempt"
                sleep 15
            else
                gravity_success=true
                printf "${TICK} Gravity update successful! Database is healthy.\n"
                break
            fi
        done

        if [ "$gravity_success" = true ]; then
            log "${ROCKET} SETUP COMPLETE! ${ROCKET}"
            printf "${GREEN}Your all-in-one Pi-hole + Unbound container is fully functional.${NC}\n\n"
            printf "  - ${YELLOW}Web UI:${NC} http://%s:%s/admin/\n" "${HOST_IP}" "${PIHOLE_WEB_PORT}"
            printf "  - ${YELLOW}DNS Server:${NC} %s\n\n" "${HOST_IP}"
            printf "${INFO} To change your password later, run: ${GREEN}sudo docker exec -it pihole pihole setpassword${NC}\n"
        else
            log "🔥 INSTALLATION FAILED 🔥"
            printf "${RED}The final gravity update check failed after all attempts.${NC}\n"
            printf "${INFO} Full gravity output from the last attempt:\n%s\n" "$gravity_output"
            printf "\n${INFO} Please review the container logs for more details:\n"
            printf "  ${GREEN}sudo docker logs pihole${NC}\n"
        fi
    else
        log "🔥 INSTALLATION FAILED 🔥"
        printf "${RED}The final DNS query check failed. Port 53 may not be correctly exposed or FTL may have crashed.${NC}\n"
        printf "${INFO} Please review the container logs:${NC}\n"
        printf "  ${GREEN}sudo docker logs pihole${NC}\n"
    fi
}

setup_permission_fix_cron() {
    log "Setting up Automated Permission Fixer"
    printf "${INFO} This will install a cron job on the HOST system for the 'root' user.\n"
    printf "${INFO} It will run every minute to ensure 'gravity.db' has the correct ownership.\n"
    printf "${WARN} This is the recommended solution for users of file-sync tools like nebula-sync.\n\n"

    # Define the exact command and cron schedule. No 'sudo' is needed as it runs from root's crontab.
    local cron_command="chown ${DETECTED_UID}:${DETECTED_GID} ${PROJECT_DIR}/etc-pihole/gravity.db > /dev/null 2>&1"
    local cron_job="* * * * * ${cron_command}"

    # Check if the cron job already exists to prevent duplicates
    if sudo crontab -l 2>/dev/null | grep -qF "${cron_command}"; then
        printf "${TICK} ${GREEN}The automated permission fix cron job is already installed for the root user.${NC}\n"
    else
        printf "${INFO} Installing cron job into root's crontab...\n"
        # Safely add the new cron job to root's crontab
        (sudo crontab -l 2>/dev/null; echo "${cron_job}") | sudo crontab -
        if [ $? -eq 0 ]; then
            printf "${TICK} ${GREEN}Cron job successfully installed!${NC}\n"
            printf "${INFO} It will automatically correct permissions every minute.\n"
        else
            printf "${CROSS} ${RED}Failed to install cron job.${NC}\n"
        fi
    fi
    printf "\n${INFO} You can view the root user's cron jobs with: '${YELLOW}sudo crontab -l${NC}'\n"
    printf "${INFO} To remove this job later, run '${YELLOW}sudo crontab -e${NC}' and delete the corresponding line.\n"
}

show_management_menu() {
    while true; do
        log "Existing Pi-hole Installation Detected!"
        printf "  [1] ${GREEN}Re-pull Latest Image & Recreate Container${NC} (Recommended Update Method)\n"
        printf "  [2] ${YELLOW}Check Status & Run Diagnostics${NC}\n"
        printf "  [3] ${RED}Force Full Re-install${NC} (Deletes ALL existing Pi-hole data!)\n"
        printf "  [4] ${YELLOW}Install Automatic Permission Fixer${NC} (for nebula-sync)\n"
        printf "  [5] Exit\n"
        read -p "Enter your choice [1-5]: " choice

        case $choice in
            1)
                printf "${INFO} Pulling latest image...\n"
                sudo docker-compose pull
                printf "${INFO} Recreating container with new image...\n"
                sudo docker-compose up -d --force-recreate --remove-orphans
                printf "${TICK} Update complete.\n"
                break
                ;;
            2)
                log "Running Diagnostics"
                printf "${INFO} Checking container status:\n"
                sudo docker-compose ps
                printf "\n${INFO} Performing live DNS check:\n"
                local host_ip
                host_ip=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n 1)
                if dig @"$host_ip" google.com +short > /dev/null; then
                    printf "${TICK} DNS resolution on %s is WORKING.\n" "$host_ip"
                else
                    printf "${CROSS} DNS resolution on %s is FAILED.\n" "$host_ip"
                fi
                printf "\n${INFO} Displaying last 30 lines of Pi-hole log:\n"
                sudo docker logs pihole --tail 30
                break
                ;;
            3)
                printf "\n${WARN} ${RED}WARNING: This will delete all your current Pi-hole settings and data!${NC}\n"
                read -p "Are you absolutely sure you want to proceed? [y/N] " confirm_reinstall
                if [[ "$confirm_reinstall" =~ ^[Yy]$ ]]; then
                    sudo docker-compose down -v
                    printf "${INFO} Deleting old volume data...\n"
                    sudo rm -rf ./etc-pihole ./etc-dnsmasq.d ./.env
                    run_installation "reinstall"
                else
                    printf "Re-install cancelled.\n"
                fi
                break
                ;;
            4)
                setup_permission_fix_cron
                break
                ;;
            5)
                printf "Exiting.\n"
                break
                ;;
            *)
                printf "${RED}Invalid choice.${NC}\n"
                ;;
        esac
    done
}

# Main execution block
main() {
  if [[ $EUID -ne 0 ]]; then
     printf "${RED}This script must be run with sudo privileges.${NC}\n"
     exit 1
  fi
  if ! command -v docker &> /dev/null || ! command -v docker-compose &> /dev/null; then printf "${RED}Error: Docker or Docker Compose is not installed.${NC}\n"; exit 1; fi

  cd "$PROJECT_DIR" || { printf "${RED}Failed to change to project directory. This should not happen.${NC}\n"; exit 1; }

  if [ -f "docker-compose.yml" ]; then
    show_management_menu
  else
    confirm_installation
    run_installation "fresh"
  fi
}

main
