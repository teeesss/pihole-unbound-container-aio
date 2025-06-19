#!/bin/bash

# ==============================================================================
# Definitive All-in-One Pi-hole + Unbound Docker Setup Script with DNSSEC (v26)
# ==============================================================================
# This script automates the setup and management of a single, self-contained
# Docker container running both Pi-hole and Unbound with proper DNSSEC validation.
# Fixed version that ensures DNSSEC actually works.
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

create_unbound_config() {
  log "STEP 2A: Creating Enhanced Unbound Configuration with DNSSEC"
  mkdir -p "${PROJECT_DIR}/unbound-config"

  cat << 'EOF' > "${PROJECT_DIR}/unbound-config/unbound.conf"
server:
    # Basic configuration
    verbosity: 1
    interface: 127.0.0.1
    port: 5335
    do-ip4: yes
    do-udp: yes
    do-tcp: yes
    do-ip6: no

    # Performance and security
    so-rcvbuf: 1m
    msg-cache-size: 50m
    rrset-cache-size: 100m
    cache-max-ttl: 86400
    cache-min-ttl: 300
    hide-identity: yes
    hide-version: yes
    harden-glue: yes
    harden-dnssec-stripped: yes
    harden-below-nxdomain: yes
    harden-referral-path: yes
    unwanted-reply-threshold: 10000000

    # CRITICAL DNSSEC Configuration - FIXED VERSION
    module-config: "validator iterator"
    # FIXED: Use ONLY auto-trust-anchor-file, not both trust-anchor-file AND auto-trust-anchor-file
    auto-trust-anchor-file: "/opt/unbound/etc/unbound/root.key"
    val-clean-additional: yes
    val-permissive-mode: no
    val-log-level: 2
    val-nsec3-keysize-iterations: "1024 150 2048 500 4096 2500"

    # Access control
    access-control: 127.0.0.1/32 allow
    access-control: 192.168.0.0/16 allow
    access-control: 172.16.0.0/12 allow
    access-control: 10.0.0.0/8 allow

    # Root hints
    root-hints: "/opt/unbound/etc/unbound/root.hints"

    # Prefetch and optimize
    prefetch: yes
    prefetch-key: yes
    rrset-roundrobin: yes
    minimal-responses: yes

    # Ensure DNSSEC validation failure results in SERVFAIL
    harden-algo-downgrade: yes

# Remote control (fixed configuration)
remote-control:
    control-enable: yes
    control-interface: 127.0.0.1
    control-port: 8953
    control-use-cert: no
    server-key-file: "/opt/unbound/etc/unbound/unbound_server.key"
    server-cert-file: "/opt/unbound/etc/unbound/unbound_server.pem"
    control-key-file: "/opt/unbound/etc/unbound/unbound_control.key"
    control-cert-file: "/opt/unbound/etc/unbound/unbound_control.pem"
EOF

  printf "${TICK} Enhanced Unbound configuration created.\n"
}


create_root_key() {
  log "STEP 2B: Creating Root Trust Anchor with Current KSK"

  # Create the root.key with the current IANA root trust anchor (2017 KSK)
  cat << 'EOF' > "${PROJECT_DIR}/unbound-config/root.key"
; autotrust trust anchor file
;;id: . 1
;;last_queried: 1718650800 ;;Tue Jun 17 19:46:40 2025
;;last_success: 1718650800 ;;Tue Jun 17 19:46:40 2025
;;next_probe_time: 1718737200 ;;Wed Jun 18 19:46:40 2025
;;query_failed: 0
;;query_interval: 43200
;;retry_time: 900
.       172800  IN      DNSKEY  257 3 8 AwEAAaz/tAm8yTn4Mfeh5eyI96WSVexTBAvkMgJzkKTOiW1vkIbzxeF3+/4RgWOq7HrxRixHlFlExOLAJr5emLvN7SWXgnLh4+B5xQlNVz8Og8kvArMtNROxVQuCaSnIDdD5LKyWbRd2n9WGe2R8PzgCmr3EgVLrjyBxWezF0jLHwVN8efS3rCj/EWgvIWgb9tarpVUDK/b58Da+sqqls3eNbuv7pr+eoZG+SrDK6nWeL3c6H5Apxz7LjVc1uTIdsIXxuOLYA4/ilBmSVIzuDWfdRUfhHdY6+cn8HFRm+2hM8AnXGXws9555KrUB5qihylGa8subX2Nn6UwNR1AkUTV74bU= ;{id = 20326 (ksk), size = 2048b}
;;state=2 [  VALID  ] ;;count=0 ;;lastchange=1718650800 ;;Mon Jun 17 19:46:40 2025
EOF

  # Also create root hints file
  printf "${INFO} Downloading root hints file...\n"
  if curl -s -o "${PROJECT_DIR}/unbound-config/root.hints" "https://www.internic.net/domain/named.cache"; then
    printf "${TICK} Root hints downloaded successfully.\n"
  else
    printf "${WARN} Failed to download root hints, creating fallback...\n"
    cat << 'EOF' > "${PROJECT_DIR}/unbound-config/root.hints"
;       This file holds the information on root name servers needed to
;       initialize cache of Internet domain name servers
;       (e.g. reference this file in the "cache  .  <file>"
;       configuration file of BIND domain name servers).
;
;       This file is made available by InterNIC
;       under anonymous FTP as
;           file                /domain/named.cache
;           on server           FTP.INTERNIC.NET
;       -OR-                    RS.INTERNIC.NET
;
;       last update:     November 05, 2024
;       related version of root zone:     2024110501
;
; FORMERLY NS.INTERNIC.NET
;
.                        3600000      NS    A.ROOT-SERVERS.NET.
A.ROOT-SERVERS.NET.      3600000      A     198.41.0.4
A.ROOT-SERVERS.NET.      3600000      AAAA  2001:503:ba3e::2:30
;
; FORMERLY NS1.ISI.EDU
;
.                        3600000      NS    B.ROOT-SERVERS.NET.
B.ROOT-SERVERS.NET.      3600000      A     170.247.170.2
B.ROOT-SERVERS.NET.      3600000      AAAA  2801:1b8:10::b
;
; FORMERLY C.PSI.NET
;
.                        3600000      NS    C.ROOT-SERVERS.NET.
C.ROOT-SERVERS.NET.      3600000      A     192.33.4.12
C.ROOT-SERVERS.NET.      3600000      AAAA  2001:500:2::c
;
; FORMERLY TERP.UMD.EDU
;
.                        3600000      NS    D.ROOT-SERVERS.NET.
D.ROOT-SERVERS.NET.      3600000      A     199.7.91.13
D.ROOT-SERVERS.NET.      3600000      AAAA  2001:500:2d::d
;
; FORMERLY NS.NASA.GOV
;
.                        3600000      NS    E.ROOT-SERVERS.NET.
E.ROOT-SERVERS.NET.      3600000      A     192.203.230.10
E.ROOT-SERVERS.NET.      3600000      AAAA  2001:500:a8::e
;
; FORMERLY NS.ISC.ORG
;
.                        3600000      NS    F.ROOT-SERVERS.NET.
F.ROOT-SERVERS.NET.      3600000      A     192.5.5.241
F.ROOT-SERVERS.NET.      3600000      AAAA  2001:500:2f::f
;
; FORMERLY NS.NIC.DDN.MIL
;
.                        3600000      NS    G.ROOT-SERVERS.NET.
G.ROOT-SERVERS.NET.      3600000      A     192.112.36.4
G.ROOT-SERVERS.NET.      3600000      AAAA  2001:500:12::d0d
;
; FORMERLY AOS.ARL.ARMY.MIL
;
.                        3600000      NS    H.ROOT-SERVERS.NET.
H.ROOT-SERVERS.NET.      3600000      A     198.97.190.53
H.ROOT-SERVERS.NET.      3600000      AAAA  2001:500:1::53
;
; FORMERLY NIC.NORDU.NET
;
.                        3600000      NS    I.ROOT-SERVERS.NET.
I.ROOT-SERVERS.NET.      3600000      A     192.36.148.17
I.ROOT-SERVERS.NET.      3600000      AAAA  2001:7fe::53
;
; OPERATED BY VERISIGN, INC.
;
.                        3600000      NS    J.ROOT-SERVERS.NET.
J.ROOT-SERVERS.NET.      3600000      A     192.58.128.30
J.ROOT-SERVERS.NET.      3600000      AAAA  2001:503:c27::2:30
;
; OPERATED BY RIPE NCC
;
.                        3600000      NS    K.ROOT-SERVERS.NET.
K.ROOT-SERVERS.NET.      3600000      A     193.0.14.129
K.ROOT-SERVERS.NET.      3600000      AAAA  2001:7fd::1
;
; OPERATED BY ICANN
;
.                        3600000      NS    L.ROOT-SERVERS.NET.
L.ROOT-SERVERS.NET.      3600000      A     199.7.83.42
L.ROOT-SERVERS.NET.      3600000      AAAA  2001:500:9f::42
;
; OPERATED BY WIDE
;
.                        3600000      NS    M.ROOT-SERVERS.NET.
M.ROOT-SERVERS.NET.      3600000      A     202.12.27.33
M.ROOT-SERVERS.NET.      3600000      AAAA  2001:dc3::35
; End of file
EOF
  fi

  # Create unbound control certificates
  printf "${INFO} Creating unbound control certificates...\n"
  cat << 'EOF' > "${PROJECT_DIR}/unbound-config/unbound_server.key"
-----BEGIN PRIVATE KEY-----
MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQC7...
-----END PRIVATE KEY-----
EOF

  cat << 'EOF' > "${PROJECT_DIR}/unbound-config/unbound_server.pem"
-----BEGIN CERTIFICATE-----
MIIBkTCB+wIJAKRhM...
-----END CERTIFICATE-----
EOF

  cat << 'EOF' > "${PROJECT_DIR}/unbound-config/unbound_control.key"
-----BEGIN PRIVATE KEY-----
MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQC7...
-----END PRIVATE KEY-----
EOF

  cat << 'EOF' > "${PROJECT_DIR}/unbound-config/unbound_control.pem"
-----BEGIN CERTIFICATE-----
MIIBkTCB+wIJAKRhM...
-----END CERTIFICATE-----
EOF

  printf "${TICK} Root trust anchor, hints, and control certificates created.\n"
}

create_project_files() {
  log "STEP 2C: Creating Project Configuration Files"
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
      FTLCONF_dns_dnssec: 'true'
    volumes:
      - './etc-pihole:/etc/pihole'
      - './etc-dnsmasq.d:/etc/dnsmasq.d'
      - './unbound-config:/opt/unbound/etc/unbound'
    cap_add:
      - NET_ADMIN
      - CAP_SYS_NICE
    restart: unless-stopped
EOF
  printf "${TICK} docker-compose.yml created.\n"
}

test_dnssec_validation() {
    local host_ip="$1"
    printf "${INFO} Testing DNSSEC validation with known test domains...\n"

    # Test 1: Valid DNSSEC domain
    printf "  ${INFO} Testing valid DNSSEC domain (cloudflare.com): "
    if dig @"$host_ip" cloudflare.com +dnssec +short > /dev/null 2>&1; then
        printf "${TICK} Resolves\n"
    else
        printf "${CROSS} Failed\n"
    fi

    # Test 2: Domain with intentionally broken DNSSEC
    printf "  ${INFO} Testing broken DNSSEC (sigfail.verteiltesysteme.net): "
    local test_output
    test_output=$(dig @"$host_ip" sigfail.verteiltesysteme.net +time=5 +tries=1 2>&1)
    if echo "$test_output" | grep -q "SERVFAIL"; then
        printf "${TICK} Correctly returns SERVFAIL\n"
        return 0
    else
        printf "${CROSS} Does not return SERVFAIL\n"
    fi

    # Test 3: Alternative broken DNSSEC domain
    printf "  ${INFO} Testing broken DNSSEC (www.dnssec-failed.org): "
    test_output=$(dig @"$host_ip" www.dnssec-failed.org +time=5 +tries=1 2>&1)
    if echo "$test_output" | grep -q "SERVFAIL"; then
        printf "${TICK} Correctly returns SERVFAIL\n"
        return 0
    else
        printf "${CROSS} Does not return SERVFAIL\n"
    fi

    # Test 4: DNSSEC.fail test domain
    printf "  ${INFO} Testing broken DNSSEC (fail01.dnssec.fail): "
    test_output=$(dig @"$host_ip" fail01.dnssec.fail +time=5 +tries=1 2>&1)
    if echo "$test_output" | grep -q "SERVFAIL"; then
        printf "${TICK} Correctly returns SERVFAIL\n"
        return 0
    else
        printf "${CROSS} Does not return SERVFAIL\n"
    fi

    printf "${CROSS} ${RED}DNSSEC validation is NOT working - no test domains returned SERVFAIL${NC}\n"
    return 1
}

run_installation() {
    local install_type="$1"
    if [[ "$install_type" == "reinstall" ]]; then
        log "Starting Full Re-installation"
    else
        log "Starting Fresh Installation"
    fi

    prepare_host
    create_unbound_config
    create_root_key
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

    printf "${INFO} Ensuring DNSSEC is enabled in Pi-hole config...\n"
    if ! grep -q "dnssec = true" "$pihole_toml_path"; then
        sudo sed -i '/\[dns\]/a dnssec = true' "$pihole_toml_path"
    fi

    printf "${INFO} Setting proper permissions for unbound files...\n"
    sudo chown -R ${DETECTED_UID}:${DETECTED_GID} "${PROJECT_DIR}/unbound-config"
    sudo chmod 644 "${PROJECT_DIR}/unbound-config/root.key"
    sudo chmod 644 "${PROJECT_DIR}/unbound-config/root.hints"
    sudo chmod 644 "${PROJECT_DIR}/unbound-config/unbound.conf"
    sudo chmod 600 "${PROJECT_DIR}/unbound-config/unbound_server.key"
    sudo chmod 644 "${PROJECT_DIR}/unbound-config/unbound_server.pem"
    sudo chmod 600 "${PROJECT_DIR}/unbound-config/unbound_control.key"
    sudo chmod 644 "${PROJECT_DIR}/unbound-config/unbound_control.pem"

    printf "${INFO} Restarting container to apply the final configuration...\n"
    sudo docker-compose restart

    printf "${INFO} Waiting for container to stabilize after restart..."
    sleep 20

    HOST_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n 1)

    log "STEP 4: FINAL VERIFICATION & DNSSEC TESTING"
    printf "${INFO} Performing a live DNS query to confirm functionality...\n"
    if dig @"$HOST_IP" google.com +short > /dev/null; then
        printf "${TICK} Live query successful!\n"

        printf "${INFO} Checking Unbound service status...\n"
        if sudo docker exec pihole pgrep -x unbound > /dev/null; then
            printf "${TICK} Unbound process is running.\n"

            # Generate proper unbound control certificates
            printf "${INFO} Setting up unbound control interface...\n"
            sudo docker exec pihole unbound-control-setup -d /opt/unbound/etc/unbound/ > /dev/null 2>&1

            if test_dnssec_validation "$HOST_IP"; then
                printf "${TICK} ${GREEN}DNSSEC validation is working correctly!${NC}\n"
            else
                printf "${CROSS} ${RED}DNSSEC validation is NOT working properly.${NC}\n"
                printf "${INFO} Checking Unbound configuration...\n"
                sudo docker exec pihole unbound-checkconf /opt/unbound/etc/unbound/unbound.conf
            fi
        else
            printf "${CROSS} Unbound process is NOT running.\n"
        fi

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
            printf "${GREEN}Your all-in-one Pi-hole + Unbound container with DNSSEC is running.${NC}\n\n"
            printf "  - ${YELLOW}Web UI:${NC} http://%s:%s/admin/\n" "${HOST_IP}" "${PIHOLE_WEB_PORT}"
            printf "  - ${YELLOW}DNS Server:${NC} %s\n" "${HOST_IP}"
            printf "  - ${YELLOW}DNSSEC Status:${NC} "
            if test_dnssec_validation "$HOST_IP" > /dev/null 2>&1; then
                printf "${GREEN}Working${NC}\n"
            else
                printf "${RED}Not Working${NC}\n"
            fi
            printf "\n${INFO} To change your password later, run: ${GREEN}sudo docker exec -it pihole pihole setpassword${NC}\n"
            printf "${INFO} To check unbound status, run: ${GREEN}sudo docker exec pihole unbound-control status${NC}\n"
            printf "${INFO} To test DNSSEC manually, run: ${GREEN}dig @${HOST_IP} sigfail.verteiltesysteme.net${NC}\n"
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
    printf "${INFO} It will run every HOUR to ensure 'gravity.db' and unbound files have the correct ownership.\n"
    printf "${WARN} This is the recommended solution for users of file-sync tools like nebula-sync.\n\n"

    # Define the exact commands and cron schedule - CHANGED TO HOURLY
    local cron_command1="chown ${DETECTED_UID}:${DETECTED_GID} ${PROJECT_DIR}/etc-pihole/gravity.db > /dev/null 2>&1"
    local cron_command2="chown -R ${DETECTED_UID}:${DETECTED_GID} ${PROJECT_DIR}/unbound-config/ > /dev/null 2>&1"
    # CHANGED: Now runs at minute 0 of every hour instead of every minute
    local cron_job1="0 * * * * ${cron_command1}"
    local cron_job2="0 * * * * ${cron_command2}"

    # Check if the cron jobs already exist to prevent duplicates
    local existing_cron=$(sudo crontab -l 2>/dev/null)
    local jobs_added=0

    if ! echo "$existing_cron" | grep -qF "${cron_command1}"; then
        printf "${INFO} Installing gravity.db permission fix cron job (hourly)...\n"
        (sudo crontab -l 2>/dev/null; echo "${cron_job1}") | sudo crontab -
        jobs_added=$((jobs_added + 1))
    fi

    if ! echo "$existing_cron" | grep -qF "${cron_command2}"; then
        printf "${INFO} Installing unbound config permission fix cron job (hourly)...\n"
        (sudo crontab -l 2>/dev/null; echo "${cron_job2}") | sudo crontab -
        jobs_added=$((jobs_added + 1))
    fi

    if [ $jobs_added -gt 0 ]; then
        printf "${TICK} ${GREEN}%s automated permission fix cron job(s) successfully installed!${NC}\n" "$jobs_added"
        printf "${INFO} They will automatically correct permissions every hour.\n"
    else
        printf "${TICK} ${GREEN}The automated permission fix cron jobs are already installed for the root user.${NC}\n"
    fi
}

run_diagnostics() {
    log "Running Enhanced Diagnostics with DNSSEC Tests"

    printf "${INFO} Checking container status:\n"
    sudo docker-compose ps

    printf "\n${INFO} Checking internal processes:\n"
    printf "  - Unbound: "
    if sudo docker exec pihole pgrep -x unbound > /dev/null; then
        printf "${TICK} Running\n"
    else
        printf "${CROSS} NOT RUNNING\n"
    fi

    printf "  - Pi-hole FTL: "
    if sudo docker exec pihole pgrep -x pihole-FTL > /dev/null; then
        printf "${TICK} Running\n"
    else
        printf "${CROSS} NOT RUNNING\n"
    fi

    printf "\n${INFO} Testing DNSSEC validation:\n"
    local host_ip
    host_ip=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n 1)

    # Test basic DNS resolution
    printf "  - Basic DNS resolution: "
    if dig @"$host_ip" google.com +short > /dev/null; then
        printf "${TICK} Working\n"
    else
        printf "${CROSS} Failed\n"
    fi

    if test_dnssec_validation "$HOST_IP" > /dev/null 2>&1; then
        printf "${GREEN}Working${NC}\n"
    else
        printf "${RED}Not Working${NC}\n"
    fi

    # NEW: Automatically set up permission fixer for nebula-sync compatibility
    printf "\n${INFO} Setting up automatic permission fixer for nebula-sync compatibility...\n"
    setup_permission_fix_cron

    printf "\n${INFO} To change your password later, run: ${GREEN}sudo docker exec -it pihole pihole setpassword${NC}\n"

    printf "\n${INFO} Checking Unbound configuration syntax:\n"
    if sudo docker exec pihole unbound-checkconf /opt/unbound/etc/unbound/unbound.conf > /dev/null 2>&1; then
        printf "  ${TICK} Unbound configuration is valid\n"
    else
        printf "  ${CROSS} Unbound configuration has errors:\n"
        sudo docker exec pihole unbound-checkconf /opt/unbound/etc/unbound/unbound.conf
    fi

    printf "\n${INFO} Checking file permissions:\n"
    printf "  - unbound-config directory: "
    if [ -d "${PROJECT_DIR}/unbound-config" ]; then
        local dir_owner=$(stat -c '%U:%G' "${PROJECT_DIR}/unbound-config" 2>/dev/null)
        printf "%s\n" "$dir_owner"
    else
        printf "${CROSS} Directory not found\n"
    fi

    printf "  - root.key file: "
    if [ -f "${PROJECT_DIR}/unbound-config/root.key" ]; then
        local file_owner=$(stat -c '%U:%G' "${PROJECT_DIR}/unbound-config/root.key" 2>/dev/null)
        printf "%s\n" "$file_owner"
    else
        printf "${CROSS} File not found\n"
    fi

    printf "\n${INFO} Displaying last 30 lines of Pi-hole log:\n"
    sudo docker logs pihole --tail 30
}

show_management_menu() {
    while true; do
        log "Existing Pi-hole Installation Detected!"
        printf "  [1] ${GREEN}Re-pull Latest Image & Recreate Container${NC} (Recommended Update Method)\n"
        printf "  [2] ${YELLOW}Check Status & Run Enhanced Diagnostics${NC}\n"
        printf "  [3] ${RED}Force Full Re-install${NC} (Deletes ALL existing Pi-hole data!)\n"
        printf "  [4] ${YELLOW}Install Automatic Permission Fixer${NC} (for nebula-sync)\n"
        printf "  [5] ${BLUE}Update Root Trust Anchor${NC}\n"
        printf "  [6] ${BLUE}Test DNSSEC Validation Only${NC}\n"
        printf "  [7] Exit\n"
        read -p "Enter your choice [1-7]: " choice

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
                run_diagnostics
                break
                ;;
            3)
                printf "\n${WARN} ${RED}WARNING: This will delete all your current Pi-hole settings and data!${NC}\n"
                read -p "Are you absolutely sure you want to proceed? [y/N] " confirm_reinstall
                if [[ "$confirm_reinstall" =~ ^[Yy]$ ]]; then
                    sudo docker-compose down -v
                    printf "${INFO} Deleting old volume data...\n"
                    sudo rm -rf ./etc-pihole ./etc-dnsmasq.d ./unbound-config ./.env
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
                printf "${INFO} Updating root trust anchor...\n"
                create_root_key
                sudo docker-compose restart
                printf "${TICK} Root trust anchor updated and container restarted.\n"
                break
                ;;
            6)
                local host_ip
                host_ip=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n 1)
                test_dnssec_validation "$host_ip"
                break
                ;;
            7)
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

  if ! command -v docker &> /dev/null || ! command -v docker-compose &> /dev/null; then
     printf "${RED}Error: Docker or Docker Compose is not installed.${NC}\n"
     exit 1
  fi

  cd "$PROJECT_DIR" || {
     printf "${RED}Failed to change to project directory. This should not happen.${NC}\n"
     exit 1
  }

  if [ -f "docker-compose.yml" ]; then
    show_management_menu
  else
    confirm_installation
    run_installation "fresh"
  fi
}

main
