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

require_files() {
  [[ -f "$ENV_FILE" ]] || { echo "Missing $ENV_FILE"; exit 1; }
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
    DNS_RECORD_BLOCK="${DNS_RECORD_BLOCK}local-data: \"${fqdn} A ${ip}\"\n"
    DNS_RECORD_BLOCK="${DNS_RECORD_BLOCK}local-data-ptr: \"${ip} ${fqdn}\"\n"
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

  openssl genrsa -out "${WORKDIR}/ca.key" 4096
  openssl req -x509 -new -nodes \
    -key "${WORKDIR}/ca.key" \
    -sha256 -days 3650 \
    -out "${WORKDIR}/ca.crt" \
    -subj "/CN=ProviderBoxCA"

  openssl req -newkey rsa:2048 -nodes \
    -keyout "${WORKDIR}/keycloak.key" \
    -out "${WORKDIR}/keycloak.csr" \
    -subj "/CN=${KEYCLOAK_FQDN}"

  openssl x509 -req \
    -in "${WORKDIR}/keycloak.csr" \
    -CA "${WORKDIR}/ca.crt" \
    -CAkey "${WORKDIR}/ca.key" \
    -CAcreateserial \
    -out "${WORKDIR}/keycloak.crt" \
    -days 825 -sha256

  install -m 0644 "${WORKDIR}/keycloak.crt" "${KEYCLOAK_DIR}/certs/${KEYCLOAK_FQDN}.crt"
  install -m 0600 "${WORKDIR}/keycloak.key" "${KEYCLOAK_DIR}/certs/${KEYCLOAK_FQDN}.key"
  chown -R 1000:1000 "${KEYCLOAK_DIR}"
}

do_keycloak() {
  common_pkgs
  keycloak_pkgs
  generate_certs
  mkdir -p "${WORKDIR}/keycloak"
  render_template "${TEMPLATE_DIR}/docker-compose.keycloak.yml.tpl" "${WORKDIR}/keycloak/docker-compose.yml"
  (cd "${WORKDIR}/keycloak" && docker compose up -d)
  ufw allow 8443/tcp || true
}

require_root
require_files
load_env

[[ $# -eq 1 ]] || { usage; exit 1; }

case "$1" in
  --unbound) do_unbound ;;
  --ntp) do_ntp ;;
  --keycloak) do_keycloak ;;
  --all) do_unbound; do_ntp; do_keycloak ;;
  *) usage; exit 1 ;;
esac