#!/usr/bin/env bash
set -Eeuo pipefail

# Homelab shared-services bootstrap for NUC (modular version)
#
# Supports:
#   --unbound
#   --ntp
#   --keycloak
#   --all
#
# Examples:
#   sudo bash bootstrap_shared_services_modular.sh --unbound
#   sudo bash bootstrap_shared_services_modular.sh --ntp
#   sudo bash bootstrap_shared_services_modular.sh --keycloak
#   sudo bash bootstrap_shared_services_modular.sh --all
#
# Notes:
# - Debian/Ubuntu-style apt + systemd assumed
# - Keycloak is deployed directly on the host, not behind Traefik
# - Unbound includes A + PTR records for VCF 9
# - Keycloak uses embedded DB, matching the manual setup

#######################################
# User variables - adjust as needed
#######################################

HOST_IP="192.168.12.121"
DNS_FQDN="dns.sddc.lab"
KEYCLOAK_FQDN="auth.sddc.lab"
SEARCH_DOMAIN="sddc.lab"

ALLOW_NET_1="10.0.0.0/8"
ALLOW_NET_2="192.168.12.0/24"

UNBOUND_FORWARDER="8.8.8.8"

CHRONY_SERVER_1="0.se.pool.ntp.org"
CHRONY_SERVER_2="1.se.pool.ntp.org"
CHRONY_SERVER_3="2.se.pool.ntp.org"

KEYCLOAK_ADMIN_USER="admin"
KEYCLOAK_ADMIN_PASSWORD="CHANGE_ME"

CERT_C="SE"
CERT_ST="Skane"
CERT_L="Home"
CERT_O="Homelab"
CERT_OU_CA="Infra"
CERT_OU_IDP="Identity"
CERT_CA_CN="Homelab Root CA"

WORKDIR="/root/homelab-bootstrap"
KEYCLOAK_DIR="/opt/keycloak"

#######################################
# DNS records
# Format: "fqdn ip"
#######################################
DNS_RECORDS=(
  "host32.sddc.lab 10.203.5.32"
  "pod-240-vc01.sddc.lab 10.203.240.10"
  "pod-240-nsx01.sddc.lab 10.203.240.11"
  "pod-240-nsx02.sddc.lab 10.203.240.12"
  "pod-240-ops01.sddc.lab 10.203.240.13"
  "pod-240-collector.sddc.lab 10.203.240.14"
  "pod-240-vsp01.sddc.lab 10.203.240.15"
  "pod-240-sddcm.sddc.lab 10.203.240.16"
  "pod-240-fleet01.sddc.lab 10.203.240.17"
  "pod-240-int01.sddc.lab 10.203.240.18"
  "pod-240-vidb.sddc.lab 10.203.240.19"
  "pod-240-auto.sddc.lab 10.203.240.20"
  "pod-240-license.sddc.lab 10.203.240.21"
  "pod-240-autosvc.sddc.lab 10.203.240.56"
  "pod-240-en1.sddc.lab 10.203.240.57"
  "pod-240-en2.sddc.lab 10.203.240.58"
)

#######################################
# Helpers
#######################################

log() {
  printf '\n[%s] %s\n' "$(date +'%F %T')" "$*"
}

usage() {
  cat <<EOF
Usage:
  sudo bash $0 --unbound
  sudo bash $0 --ntp
  sudo bash $0 --keycloak
  sudo bash $0 --all

Actions:
  --unbound    Install and configure Unbound DNS
  --ntp        Install and configure Chrony NTP
  --keycloak   Install Docker/Compose if needed, generate CA/certs, and deploy Keycloak
  --all        Run all of the above

Notes:
  - Edit KEYCLOAK_ADMIN_PASSWORD before using --keycloak or --all
  - Root CA and cert chain are written under ${WORKDIR}
EOF
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run this script as root, for example: sudo bash $0 --all" >&2
    exit 1
  fi
}

install_pkg() {
  DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

apt_update_once() {
  if [[ "${APT_UPDATED:-0}" -eq 0 ]]; then
    apt-get update
    APT_UPDATED=1
  fi
}

ensure_common_tools() {
  log "Installing common prerequisites"
  apt_update_once
  install_pkg ca-certificates curl openssl gnupg lsb-release apt-transport-https ufw dnsutils
}

ensure_unbound_pkgs() {
  log "Installing Unbound packages"
  apt_update_once
  install_pkg unbound
}

ensure_ntp_pkgs() {
  log "Installing Chrony packages"
  apt_update_once
  install_pkg chrony
}

ensure_keycloak_pkgs() {
  log "Installing Docker and Compose packages"
  apt_update_once
  install_pkg docker.io docker-compose
  systemctl enable docker
  systemctl start docker
}

configure_resolver() {
  log "Disabling systemd-resolved and configuring local resolver"
  systemctl disable systemd-resolved || true
  systemctl stop systemd-resolved || true

  rm -f /etc/resolv.conf
  cat > /etc/resolv.conf <<EOF
nameserver 127.0.0.1
search ${SEARCH_DOMAIN}
EOF
  chmod 644 /etc/resolv.conf
}

configure_unbound() {
  log "Configuring Unbound"
  mkdir -p /etc/unbound/unbound.conf.d

  {
    cat <<EOF
server:
    interface: 0.0.0.0
    port: 53
    do-ip4: yes
    do-udp: yes
    do-tcp: yes
    access-control: ${ALLOW_NET_1} allow
    access-control: ${ALLOW_NET_2} allow
    verbosity: 1
    hide-identity: yes
    hide-version: yes

local-zone: "${SEARCH_DOMAIN}." static

local-data: "${DNS_FQDN} A ${HOST_IP}"
local-data-ptr: "${HOST_IP} ${DNS_FQDN}"

local-data: "${KEYCLOAK_FQDN} A ${HOST_IP}"
local-data-ptr: "${HOST_IP} ${KEYCLOAK_FQDN}"
EOF

    for record in "${DNS_RECORDS[@]}"; do
      fqdn="${record% *}"
      ip="${record##* }"
      printf 'local-data: "%s A %s"\n' "$fqdn" "$ip"
      printf 'local-data-ptr: "%s %s"\n' "$ip" "$fqdn"
    done

    cat <<EOF

forward-zone:
    name: "."
    forward-addr: ${UNBOUND_FORWARDER}
EOF
  } > /etc/unbound/unbound.conf.d/sddc.conf

  unbound-checkconf
  systemctl enable unbound
  systemctl restart unbound

  ufw allow 53/tcp || true
  ufw allow 53/udp || true
}

configure_chrony() {
  log "Configuring Chrony"
  systemctl disable systemd-timesyncd || true
  systemctl stop systemd-timesyncd || true

  cat > /etc/chrony/chrony.conf <<EOF
server ${CHRONY_SERVER_1} iburst
server ${CHRONY_SERVER_2} iburst
server ${CHRONY_SERVER_3} iburst

allow ${ALLOW_NET_1}
allow ${ALLOW_NET_2}

bindaddress 0.0.0.0
local stratum 10

driftfile /var/lib/chrony/drift
logdir /var/log/chrony
EOF

  systemctl enable chrony
  systemctl restart chrony

  ufw allow 123/udp || true
}

generate_keycloak_certs() {
  log "Generating internal CA and Keycloak certificate"
  mkdir -p "${WORKDIR}" "${KEYCLOAK_DIR}/certs" "${KEYCLOAK_DIR}/data"

  cat > "${WORKDIR}/auth-openssl.cnf" <<EOF
[ req ]
default_bits       = 2048
distinguished_name = req_distinguished_name
req_extensions     = req_ext
prompt             = no

[ req_distinguished_name ]
C  = ${CERT_C}
ST = ${CERT_ST}
L  = ${CERT_L}
O  = ${CERT_O}
OU = ${CERT_OU_IDP}
CN = ${KEYCLOAK_FQDN}

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = ${KEYCLOAK_FQDN}
IP.1  = ${HOST_IP}
EOF

  openssl genrsa -out "${WORKDIR}/homelab-ca.key" 4096
  openssl req -x509 -new -nodes \
    -key "${WORKDIR}/homelab-ca.key" \
    -sha256 -days 3650 \
    -out "${WORKDIR}/homelab-ca.crt" \
    -subj "/C=${CERT_C}/ST=${CERT_ST}/L=${CERT_L}/O=${CERT_O}/OU=${CERT_OU_CA}/CN=${CERT_CA_CN}"

  openssl genrsa -out "${WORKDIR}/${KEYCLOAK_FQDN}.key" 2048
  openssl req -new \
    -key "${WORKDIR}/${KEYCLOAK_FQDN}.key" \
    -out "${WORKDIR}/${KEYCLOAK_FQDN}.csr" \
    -config "${WORKDIR}/auth-openssl.cnf"

  openssl x509 -req \
    -in "${WORKDIR}/${KEYCLOAK_FQDN}.csr" \
    -CA "${WORKDIR}/homelab-ca.crt" \
    -CAkey "${WORKDIR}/homelab-ca.key" \
    -CAcreateserial \
    -out "${WORKDIR}/${KEYCLOAK_FQDN}.crt" \
    -days 825 \
    -sha256 \
    -extensions req_ext \
    -extfile "${WORKDIR}/auth-openssl.cnf"

  install -m 0644 "${WORKDIR}/${KEYCLOAK_FQDN}.crt" "${KEYCLOAK_DIR}/certs/${KEYCLOAK_FQDN}.crt"
  install -m 0600 "${WORKDIR}/${KEYCLOAK_FQDN}.key" "${KEYCLOAK_DIR}/certs/${KEYCLOAK_FQDN}.key"
  chown -R 1000:1000 "${KEYCLOAK_DIR}"

  cat "${WORKDIR}/${KEYCLOAK_FQDN}.crt" "${WORKDIR}/homelab-ca.crt" > "${WORKDIR}/keycloak-chain.crt"

  log "CA certificate: ${WORKDIR}/homelab-ca.crt"
  log "Leaf certificate: ${WORKDIR}/${KEYCLOAK_FQDN}.crt"
  log "Combined chain: ${WORKDIR}/keycloak-chain.crt"
}

configure_keycloak_compose() {
  log "Writing Docker Compose file for Keycloak"
  mkdir -p "${WORKDIR}/keycloak"

  cat > "${WORKDIR}/keycloak/docker-compose.yml" <<EOF
services:
  keycloak:
    image: quay.io/keycloak/keycloak:latest
    container_name: keycloak
    restart: unless-stopped
    ports:
      - "8443:8443"
    environment:
      KEYCLOAK_ADMIN: ${KEYCLOAK_ADMIN_USER}
      KEYCLOAK_ADMIN_PASSWORD: ${KEYCLOAK_ADMIN_PASSWORD}
      KC_HOSTNAME: ${KEYCLOAK_FQDN}
      KC_HTTPS_CERTIFICATE_FILE: /opt/keycloak/certs/${KEYCLOAK_FQDN}.crt
      KC_HTTPS_CERTIFICATE_KEY_FILE: /opt/keycloak/certs/${KEYCLOAK_FQDN}.key
    volumes:
      - ${KEYCLOAK_DIR}/data:/opt/keycloak/data
      - ${KEYCLOAK_DIR}/certs:/opt/keycloak/certs:ro
    command: start --https-port=8443
EOF
}

deploy_keycloak() {
  log "Deploying Keycloak with Docker Compose"
  cd "${WORKDIR}/keycloak"
  docker compose down || true
  docker compose up -d
  ufw allow 8443/tcp || true
}

validate_unbound() {
  log "Validating Unbound"
  systemctl is-active --quiet unbound && echo "Unbound: active" || echo "Unbound: inactive"
  dig @"127.0.0.1" "${KEYCLOAK_FQDN}" +short || true
  dig -x 10.203.240.10 @"127.0.0.1" +short || true
}

validate_ntp() {
  log "Validating Chrony"
  systemctl is-active --quiet chrony && echo "Chrony: active" || echo "Chrony: inactive"
  chronyc tracking || true
}

validate_keycloak() {
  log "Validating Keycloak"
  docker compose -f "${WORKDIR}/keycloak/docker-compose.yml" ps || true
  curl -skI "https://${KEYCLOAK_FQDN}:8443" || true
}

do_unbound() {
  ensure_common_tools
  ensure_unbound_pkgs
  configure_resolver
  configure_unbound
  validate_unbound
}

do_ntp() {
  ensure_common_tools
  ensure_ntp_pkgs
  configure_chrony
  validate_ntp
}

do_keycloak() {
  ensure_common_tools
  ensure_keycloak_pkgs
  generate_keycloak_certs
  configure_keycloak_compose
  deploy_keycloak
  validate_keycloak
}

print_next_steps() {
  cat <<EOF

Completed.

Files of interest:
- Unbound config: /etc/unbound/unbound.conf.d/sddc.conf
- Chrony config: /etc/chrony/chrony.conf
- Keycloak compose: ${WORKDIR}/keycloak/docker-compose.yml
- Root CA cert: ${WORKDIR}/homelab-ca.crt
- Keycloak cert chain: ${WORKDIR}/keycloak-chain.crt

Important next steps:
1. Import ${WORKDIR}/homelab-ca.crt into the trust store of clients that must trust Keycloak.
2. For VCF 9 SSO, use the CA certificate or the full chain file if the UI expects a chain.
3. Replace KEYCLOAK_ADMIN_PASSWORD in this script before using --keycloak or --all.
4. Consider moving Keycloak to PostgreSQL later; the default embedded DB is fine for initial lab bring-up but not ideal long-term.

EOF
}

main() {
  require_root

  if [[ $# -ne 1 ]]; then
    usage
    exit 1
  fi

  case "$1" in
    --unbound)
      do_unbound
      ;;
    --ntp)
      do_ntp
      ;;
    --keycloak)
      do_keycloak
      ;;
    --all)
      do_unbound
      do_ntp
      do_keycloak
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 1
      ;;
  esac

  print_next_steps
}

main "$@"
