#!/bin/bash
# ==============================================================================
# Pi-hole + Unbound Docker Stack Status Check (Standalone)
# ==============================================================================
# This script performs a non-destructive check of the running all-in-one
# container to verify its health and true, final configuration.
# NOTE: This functionality is also available in the main `install.sh` script.
# ==============================================================================

# --- Configuration ---
PIHOLE_CONTAINER="pihole"

# --- Style Definitions ---
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m';
TICK="[${GREEN}✓${NC}]"; CROSS="[${RED}✗${NC}]"; INFO="[${YELLOW}➔${NC}]"

# --- Helper Functions ---
log() { echo ""; echo -e "================== ${YELLOW}$1${NC} =================="; }

# --- Pre-flight Checks ---
if [[ $EUID -ne 0 ]]; then echo -e "${RED}This script must be run with sudo privileges.${NC}"; exit 1; fi
if ! command -v docker &> /dev/null; then echo -e "${RED}Error: Docker is not installed.${NC}"; exit 1; fi

# --- Main Logic ---
log "1. CONTAINER STATUS"
if ! sudo docker ps -q -f name="^/${PIHOLE_CONTAINER}$" | grep -q .; then
    echo -e "${CROSS} ERROR: Pi-hole container ('${PIHOLE_CONTAINER}') is not running."
    exit 1
fi
sudo docker ps --filter "name=${PIHOLE_CONTAINER}"
echo -e "\n${TICK} Container is running."

log "2. INTERNAL PROCESS & CONFIG CHECK"
echo -n "${INFO} Checking for Unbound process... "
if sudo docker exec "$PIHOLE_CONTAINER" pgrep -x unbound > /dev/null; then echo -e "${TICK} Running"; else echo -e "${CROSS} NOT RUNNING"; fi

echo -n "${INFO} Checking for FTL process... "
if sudo docker exec "$PIHOLE_CONTAINER" pgrep -x pihole-FTL > /dev/null; then echo -e "${TICK} Running"; else echo -e "${CROSS} NOT RUNNING"; fi

echo -n "${INFO} Verifying upstream DNS is Unbound... "
# We check the environment variable, which is the ultimate source of truth for this setup.
UPSTREAM_ENV=$(sudo docker inspect --format='{{range .Config.Env}}{{println .}}{{end}}' "$PIHOLE_CONTAINER" | grep "FTLCONF_dns_upstreams")
if [[ "$UPSTREAM_ENV" == *"127.0.0.1#5335"* ]]; then echo -e "${TICK} Correct"; else echo -e "${CROSS} INCORRECT"; fi

log "3. LIVE DNS TESTS (The Final Truth)"
echo -n "${INFO} Testing internal Unbound service... "
if sudo docker exec "$PIHOLE_CONTAINER" dig @127.0.0.1 -p 5335 google.com +short > /dev/null; then echo -e "${TICK} SUCCESS"; else echo -e "${CROSS} FAILED"; fi

HOST_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n 1)
if [ -z "$HOST_IP" ]; then
    echo -e "${CROSS} Could not determine Host IP for external test."
else
    echo -n "${INFO} Testing full stack via Host IP (${HOST_IP})... "
    if dig @"$HOST_IP" google.com +short +time=2 +tries=1 > /dev/null; then
      echo -e "${TICK} SUCCESS"
    else
      echo -e "${CROSS} FAILED"
    fi
fi

echo ""
log "🎉 Status Check Complete 🎉"
