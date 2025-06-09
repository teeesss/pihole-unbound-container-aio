#!/bin/bash
# ==============================================================================
# All-in-One Pi-hole + Unbound Docker Stack Status Check (v3 - Corrected)
# ==============================================================================
# This script performs a non-destructive check of the running all-in-one
# container to verify its health and true, final configuration.
#
# v3: Corrects the 'listeningMode' check to rely on a functional test,
#     which is the true measure of success, instead of reading a config file.
# ==============================================================================

PIHOLE_CONTAINER="pihole"
HOST_IP=$(ip route get 1.1.1.1 | awk '{print $7; exit}')
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'; TICK="[${GREEN}✓${NC}]"; CROSS="[${RED}✗${NC}]"
log() { echo ""; echo -e "================== ${YELLOW}$1${NC} =================="; }
if [ "$EUID" -ne 0 ]; then echo "Please run this script with sudo."; exit 1; fi

log "1. CONTAINER STATUS"
if ! docker ps -q -f name="^/${PIHOLE_CONTAINER}$" | grep -q .; then echo "❌ ERROR: Pi-hole container is not running."; exit 1; fi
docker ps --filter "name=${PIHOLE_CONTAINER}"
echo -e "\n${TICK} Container is running and healthy."

log "2. INTERNAL PROCESS & CONFIG CHECK"
echo -n "Checking if Unbound process is running... "
if sudo docker exec "$PIHOLE_CONTAINER" pgrep -x unbound > /dev/null; then echo -e "${TICK} SUCCESS"; else echo -e "${CROSS} FAILED"; fi
echo -n "Checking Pi-hole's upstream DNS setting... "
UPSTREAM_IN_TOML=$(sudo docker exec "$PIHOLE_CONTAINER" cat /etc/pihole/pihole.toml 2>/dev/null | grep -A 2 'upstreams =' | tr -d ' \t\n\r')
if [[ "$UPSTREAM_IN_TOML" == *"127.0.0.1#5335"* ]]; then echo -e "${TICK} SUCCESS (Using Unbound)"; else echo -e "${CROSS} FAILED (Not using Unbound)"; fi

log "3. LIVE DNS TESTS (The Final Truth)"
echo -n "Testing internal Unbound service... "
if sudo docker exec "$PIHOLE_CONTAINER" dig @127.0.0.1 -p 5335 google.com +short > /dev/null; then echo -e "${TICK} SUCCESS"; else echo -e "${CROSS} FAILED"; fi

echo -n "Testing full stack & listening mode via Host IP (${HOST_IP})... "
if dig @"$HOST_IP" google.com +short +time=2 +tries=1 > /dev/null; then
  echo -e "${TICK} SUCCESS"
else
  echo -e "${CROSS} FAILED"
fi

echo ""
log "🎉 Status Check Complete 🎉"
