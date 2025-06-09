#!/bin/bash

# ==============================================================================
# Definitive All-in-One Pi-hole + Unbound Docker Setup Script (v12.1 - Final)
# ==============================================================================
# This script automates the setup of a single, self-contained Docker container
# running both Pi-hole and Unbound. It is the final, robust, and user-friendly
# version, incorporating all lessons learned from our extensive troubleshooting.
#
# v12.1 Changes:
#   - Corrected the final 'printf' statements to be fully portable and
#     reliably print all output, fixing the final formatting bug.
# ==============================================================================

# --- Configuration Variables ---
DEFAULT_PROJECT_DIR="/home/jonesy/full-stack/pihole"
PIHOLE_WEB_PORT="8088"
PIHOLE_PASSWORD="YourNewSecurePassword"
TIMEZONE="America/Chicago"
FALLBACK_DNS="1.1.1.1 9.9.9.9"

# --- Dynamic Variable ---
PROJECT_DIR=""

# --- Color and Symbol Definitions (Universal ANSI) ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color
TICK="[${GREEN}✓${NC}]"
INFO="[${BLUE}➔${NC}]"
WARN="[${YELLOW}⚠️${NC}]"
CROSS="[${RED}✗${NC}]"
ROCKET="🚀"

# --- Helper Functions ---
log() { printf "\n${BLUE}==================================================================${NC}\n"; printf "=> ${YELLOW}%s${NC}\n" "$1"; printf "${BLUE}==================================================================${NC}\n"; }

select_project_directory() {
    while [ -z "$PROJECT_DIR" ]; do
        log "Please Choose an Installation Directory"
        printf "  [1] Use the default path: ${GREEN}%s${NC}\n" "${DEFAULT_PROJECT_DIR}"
        printf "  [2] Use the current directory: ${GREEN}%s${NC}\n" "$(pwd)"
        printf "  [3] Enter a custom absolute path\n"
        printf "  [4] Abort installation\n"
        read -p "Enter your choice [1-4]: " choice

        case $choice in
            1) PROJECT_DIR="$DEFAULT_PROJECT_DIR";; 2) PROJECT_DIR="$(pwd)";;
            3) read -p "Please enter the full custom path: " custom_path; if [[ "$custom_path" == /* ]]; then PROJECT_DIR="$custom_path"; else printf "${RED}ERROR: Please provide an absolute path.${NC}\n"; fi;;
            4) printf "Installation aborted.\n"; exit 0;; *) printf "${RED}Invalid choice.${NC}\n";;
        esac
    done
    printf "${INFO} Installation path set to: ${GREEN}%s${NC}\n" "${PROJECT_DIR}"
}

confirm_settings() {
  log "CONFIRMATION"
  printf "This script will install Pi-hole + Unbound in: ${GREEN}%s${NC}\n" "${PROJECT_DIR}"
  printf "Using the following settings:\n"
  printf "  - Web UI Port:    %s\n" "${PIHOLE_WEB_PORT}"
  printf "  - Web Password:   %s\n" "${PIHOLE_PASSWORD}"
  printf "  - Timezone:       %s\n" "${TIMEZONE}"
  printf "\n${WARN} This will also reconfigure the host's systemd-resolved.\n"
  read -p "Are these settings correct? [y/N] " response
  if [[ ! "$response" =~ ^[Yy]$ ]]; then printf "Installation cancelled.\n"; exit 0; fi
}

prepare_host() {
  log "STEP 1: Preparing Host"
  printf "${INFO} Disabling systemd-resolved stub listener... "
  sudo systemctl stop systemd-resolved.service >/dev/null 2>&1 && sudo systemctl disable systemd-resolved.service >/dev/null 2>&1
  if ! grep -q "DNSStubListener=no" /etc/systemd/resolved.conf; then sudo sed -i 's/#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf; fi
  if ! grep -q "^DNS=" /etc/systemd/resolved.conf; then sudo sed -i "/\[Resolve\]/a DNS=${FALLBACK_DNS}" /etc/systemd/resolved.conf; else sudo sed -i "s/^DNS=.*/DNS=${FALLBACK_DNS}/" /etc/systemd/resolved.conf; fi
  if [ -L /etc/resolv.conf ] && [ "$(readlink -f /etc/resolv.conf)" != "/run/systemd/resolve/resolv.conf" ]; then sudo rm /etc/resolv.conf; fi
  if [ ! -L /etc/resolv.conf ]; then sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf; fi
  sudo systemctl restart systemd-resolved
  printf "${TICK}\n"
}

create_compose_file() {
  log "STEP 2: Creating Project Configuration Files"
  mkdir -p "$PROJECT_DIR"
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
    environment:
      TZ: '${TIMEZONE}'
      WEBPASSWORD: '${PIHOLE_PASSWORD}'
      FTLCONF_dns_upstreams: '127.0.0.1#5335'
      DNSMASQ_LISTENING: 'all'
    volumes:
      - './etc-pihole:/etc/pihole'
      - './etc-dnsmasq.d:/etc/dnsmasq.d'
    cap_add:
      - NET_ADMIN
    healthcheck:
      test: ["CMD-SHELL", "dig @127.0.0.1 -p 5335 google.com || exit 1"]
      interval: 1m
      timeout: 10s
      retries: 3
      start_period: 60s
    restart: unless-stopped
EOF
  printf "${TICK} docker-compose.yml created.\n"
}

# Main execution block
main() {
  if [ "$EUID" -ne 0 ]; then printf "${RED}This script requires sudo privileges.${NC}\n"; exit 1; fi
  if ! command -v docker &> /dev/null || ! command -v docker-compose &> /dev/null; then printf "${RED}Error: Docker or Docker Compose is not installed.${NC}\n"; exit 1; fi

  select_project_directory
  confirm_settings
  prepare_host
  create_compose_file

  log "STEP 3: Launching & Configuring Container"
  cd "$PROJECT_DIR" || { printf "Failed to change to project directory. Aborting.\n"; exit 1; }
  
  printf "${INFO} Pulling the latest image...\n"
  sudo docker-compose pull
  
  printf "${INFO} Starting container for the first time...\n"
  sudo docker-compose down -v > /dev/null 2>&1
  sudo docker-compose up -d

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
  printf "${INFO} Restarting container to apply changes...\n"
  sudo docker-compose restart
  
  printf "${INFO} Waiting for container to become healthy"
  count=0
  while true; do
    status=$(sudo docker inspect --format '{{.State.Health.Status}}' pihole 2>/dev/null)
    if [ "$status" == "healthy" ]; then printf " ${TICK} Healthy!\n"; break; fi
    if [ $count -ge 60 ]; then printf "\n${CROSS} ${RED}ERROR: Timeout waiting for container to become healthy.${NC}\n"; sudo docker logs pihole; exit 1; fi
    printf "."; sleep 2; count=$((count+1));
  done
  
  HOST_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n 1)

  if dig @"$HOST_IP" google.com +short > /dev/null; then
    log "${ROCKET} SETUP COMPLETE! ${ROCKET}"
    printf "${GREEN}Your all-in-one Pi-hole + Unbound container is fully functional.${NC}\n"
    printf "\n"
    printf "  - ${YELLOW}Web UI:${NC} http://%s:%s/admin/\n" "${HOST_IP}" "${PIHOLE_WEB_PORT}"
    printf "  - ${YELLOW}DNS Server:${NC} %s\n" "${HOST_IP}"
    printf "\n"
    # --- THIS IS THE CORRECTED BLOCK ---
    printf "${INFO} To change your password later, run this command:\n"
    printf "  ${GREEN}sudo docker exec -it pihole pihole setpassword${NC}\n"
    # --- END CORRECTION ---
  else
    log "FAILURE: Installation Failed"
    printf "${RED}The final verification check failed. Please review the logs above.${NC}\n"
  fi
}

main
