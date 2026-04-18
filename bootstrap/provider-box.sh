#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${REPO_ROOT}/config/provider-box.env"
RECORDS_FILE="${REPO_ROOT}/config/unbound.records"
TEMPLATE_DIR="${REPO_ROOT}/templates"

usage() {
  cat <<USAGE
Usage:
  sudo bash bootstrap/provider-box.sh --unbound
  sudo bash bootstrap/provider-box.sh --ntp
  sudo bash bootstrap/provider-box.sh --keycloak
  sudo bash bootstrap/provider-box.sh --all
USAGE
}

require_root() {
  [[ "$EUID" -eq 0 ]] || { echo "Run as root"; exit 1; }
}

require_env_file() {
  [[ -f "$ENV_FILE" ]] || { echo "Missing $ENV_FILE"; exit 1; }
}

require_records_file() {
  [[ -f "$RECORDS_FILE" ]] || { echo "Missing $RECORDS_FILE"; exit 1; }
}

load_env() {
  # shellcheck disable=SC1090
  source "$ENV_FILE"
}

apt_update_once() {
  if [[ "${APT_UPDATED:-0}" -eq 0 ]]; then
    apt-get update
    APT_UPDATED=1
  fi
}

install_pkg() {
  DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

common_pkgs() {
  apt_update_once
  install_pkg ca-certificates curl openssl dnsutils ufw gettext-base
}

unbound_pkgs() {
  apt_update_once
  install_pkg unbound
}

ntp_pkgs() {
  apt_update_once
  install_pkg chrony
}

keycloak_pkgs() {
  apt_update_once
  install_pkg docker.io docker-compose
  systemctl enable docker
  systemctl start docker
}

configure_resolv_conf() {
  systemctl disable systemd-resolved || true
  systemctl stop systemd-resolved || true
  rm -f /etc/resolv.conf
  cat > /etc/resolv.conf <<RESOLV
nameserver 127.0.0.1
search ${SEARCH_DOMAIN}
RESOLV
}

build_dns_record_block() {
  local line fqdn ip
  DNS_RECORD_BLOCK=""
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    [[ "$line" = \#* ]] && continue
    fqdn="${line% *}"
    ip="${line##* }"
    DNS_RECORD_BLOCK="${DNS_RECORD_BLOCK}local-data: \"${fqdn} A ${ip}\"
local-data-ptr: \"${ip} ${fqdn}\"
"
  done < "$RECORDS_FILE"
  export DNS_RECORD_BLOCK
}

render_template() {
  envsubst < "$1" > "$2"
}

do_unbound() {
  common_pkgs
  unbound_pkgs
  configure_resolv_conf
  build_dns_record_block
  render_template "${TEMPLATE_DIR}/unbound.conf.tpl" /etc/unbound/unbound.conf.d/provider-box.conf
  unbound-checkconf
  systemctl enable unbound
  systemctl restart unbound
  ufw allow 53/tcp || true
  ufw allow 53/udp || true
}

do_ntp() {
  common_pkgs
  ntp_pkgs
  systemctl disable systemd-timesyncd || true
  systemctl stop systemd-timesyncd || true
  render_template "${TEMPLATE_DIR}/chrony.conf.tpl" /etc/chrony/chrony.conf
  systemctl enable chrony
  systemctl restart chrony
  ufw allow 123/udp || true
}

generate_certs() {
  mkdir -p "${WORKDIR}" "${KEYCLOAK_DIR}/certs" "${KEYCLOAK_DIR}/data"

  cat > "${WORKDIR}/keycloak-openssl.cnf" <<EOF
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

  openssl genrsa -out "${WORKDIR}/provider-box-ca.key" 4096
  openssl req -x509 -new -nodes \
    -key "${WORKDIR}/provider-box-ca.key" \
    -sha256 -days 3650 \
    -out "${WORKDIR}/provider-box-ca.crt" \
    -subj "/C=${CERT_C}/ST=${CERT_ST}/L=${CERT_L}/O=${CERT_O}/OU=${CERT_OU_CA}/CN=${CERT_CA_CN}"

  openssl genrsa -out "${WORKDIR}/${KEYCLOAK_FQDN}.key" 2048
  openssl req -new \
    -key "${WORKDIR}/${KEYCLOAK_FQDN}.key" \
    -out "${WORKDIR}/${KEYCLOAK_FQDN}.csr" \
    -config "${WORKDIR}/keycloak-openssl.cnf"

  openssl x509 -req \
    -in "${WORKDIR}/${KEYCLOAK_FQDN}.csr" \
    -CA "${WORKDIR}/provider-box-ca.crt" \
    -CAkey "${WORKDIR}/provider-box-ca.key" \
    -CAcreateserial \
    -out "${WORKDIR}/${KEYCLOAK_FQDN}.crt" \
    -days 825 \
    -sha256 \
    -extensions req_ext \
    -extfile "${WORKDIR}/keycloak-openssl.cnf"

  install -D -m 0644 "${WORKDIR}/${KEYCLOAK_FQDN}.crt" "${KEYCLOAK_DIR}/certs/${KEYCLOAK_FQDN}.crt"
  install -D -m 0600 "${WORKDIR}/${KEYCLOAK_FQDN}.key" "${KEYCLOAK_DIR}/certs/${KEYCLOAK_FQDN}.key"
  chown -R 1000:1000 "${KEYCLOAK_DIR}"

  cat "${WORKDIR}/${KEYCLOAK_FQDN}.crt" "${WORKDIR}/provider-box-ca.crt" > "${WORKDIR}/keycloak-chain.crt"
}

do_keycloak() {
  require_keycloak_vars
  common_pkgs
  keycloak_pkgs
  generate_certs
  mkdir -p "${WORKDIR}/keycloak"
  render_template "${TEMPLATE_DIR}/docker-compose.keycloak.yml.tpl" "${WORKDIR}/keycloak/docker-compose.yml"
  (
    cd "${WORKDIR}/keycloak"
    docker compose down || true
    docker compose up -d
  )
  ufw allow 8443/tcp || true
}

require_env_vars() {
  local var
  for var in HOST_IP SEARCH_DOMAIN DNS_FQDN KEYCLOAK_FQDN WORKDIR KEYCLOAK_DIR; do
    [[ -n "${!var:-}" ]] || { echo "Missing required variable: $var"; exit 1; }
  done
}

require_keycloak_vars() {
  local var
  for var in KEYCLOAK_ADMIN_USER KEYCLOAK_ADMIN_PASSWORD CERT_C CERT_ST CERT_L CERT_O CERT_OU_CA CERT_OU_IDP CERT_CA_CN; do
    [[ -n "${!var:-}" ]] || { echo "Missing required variable: $var"; exit 1; }
  done
}

require_root
require_env_file
load_env
require_env_vars


[[ $# -eq 1 ]] || { usage; exit 1; }

case "$1" in
  --unbound)
    require_records_file
    do_unbound
    ;;
  --ntp)
    do_ntp
    ;;
  --keycloak)
    do_keycloak
    ;;
  --all)
    require_records_file
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