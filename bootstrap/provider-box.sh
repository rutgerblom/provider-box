#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${REPO_ROOT}/config/provider-box.env"
RECORDS_FILE="${REPO_ROOT}/config/unbound.records"
TEMPLATE_DIR="${REPO_ROOT}/templates"
BOOTSTRAP_DIR="${REPO_ROOT}/bootstrap"
APT_UPDATED=0

trap 'echo "Error: command failed on line ${LINENO}. See output above for details." >&2' ERR

usage() {
  cat <<USAGE
Usage:
  sudo bash bootstrap/provider-box.sh --unbound
  sudo bash bootstrap/provider-box.sh --ntp
  sudo bash bootstrap/provider-box.sh --rsyslog
  sudo bash bootstrap/provider-box.sh --ca
  sudo bash bootstrap/provider-box.sh --keycloak
  sudo bash bootstrap/provider-box.sh --netbox
  sudo bash bootstrap/provider-box.sh --s3
  sudo bash bootstrap/provider-box.sh --sftp
  sudo bash bootstrap/provider-box.sh --all
USAGE
}

require_root() {
  [[ "$EUID" -eq 0 ]] || { echo "Run as root"; exit 1; }
}

fail() {
  echo "Error: $*" >&2
  exit 1
}

require_env_file() {
  [[ -f "$ENV_FILE" ]] || fail "Missing ${ENV_FILE}"
}

require_records_file() {
  [[ -f "$RECORDS_FILE" ]] || fail "Missing ${RECORDS_FILE}"
}

require_template_file() {
  [[ -f "$1" ]] || fail "Missing template: $1"
}

require_module_file() {
  [[ -f "$1" ]] || fail "Missing bootstrap module: $1"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

require_package_installed() {
  local pkg
  for pkg in "$@"; do
    dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed" || \
      fail "Package '${pkg}' is not installed. Check apt output for details."
  done
}

load_env() {
  # shellcheck disable=SC1090
  set -a
  source "$ENV_FILE"
  set +a
}

apt_update_once() {
  require_command apt-get
  if [[ "$APT_UPDATED" -eq 0 ]]; then
    apt-get update || fail "apt-get update failed"
    APT_UPDATED=1
  fi
}

install_pkg() {
  local packages=("$@")
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}" || \
    fail "Failed to install packages: ${packages[*]}"
  require_package_installed "${packages[@]}"
}

common_pkgs() {
  apt_update_once
  install_pkg ca-certificates curl openssl bind9-dnsutils ufw gettext-base
  require_command dig
}

unbound_pkgs() {
  apt_update_once
  install_pkg unbound
}

ntp_pkgs() {
  apt_update_once
  install_pkg chrony
}

rsyslog_pkgs() {
  apt_update_once
  install_pkg rsyslog
}

docker_pkgs() {
  apt_update_once
  install_pkg docker.io docker-compose
  require_command docker
  systemctl enable docker
  systemctl start docker
  docker compose version >/dev/null 2>&1 || \
    fail "Docker Compose v2 is required but not available via 'docker compose'"
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

build_provider_box_dns_block() {
  PROVIDER_BOX_DNS_BLOCK="local-data: \"${DNS_FQDN} A ${HOST_IP}\"
local-data: \"${CA_FQDN} A ${HOST_IP}\"
local-data: \"${KEYCLOAK_FQDN} A ${HOST_IP}\"
local-data: \"${NETBOX_FQDN} A ${HOST_IP}\"
local-data: \"${S3_FQDN} A ${HOST_IP}\"
local-data: \"${SFTP_FQDN} A ${HOST_IP}\"
local-data: \"${SYSLOG_FQDN} A ${HOST_IP}\"
local-data-ptr: \"${HOST_IP} ${DNS_FQDN}\"
"
  export PROVIDER_BOX_DNS_BLOCK
}

render_template() {
  require_command envsubst
  require_template_file "$1"
  envsubst < "$1" > "$2"
}

validate_ipv4() {
  local ip="$1"
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1

  local octet
  IFS='.' read -r -a octets <<< "$ip"
  for octet in "${octets[@]}"; do
    (( octet >= 0 && octet <= 255 )) || return 1
  done
}

validate_cidr() {
  local cidr="$1"
  local ip="${cidr%/*}"
  local prefix="${cidr##*/}"
  [[ "$cidr" == */* ]] || return 1
  validate_ipv4 "$ip" || return 1
  [[ "$prefix" =~ ^[0-9]{1,2}$|^3[0-2]$ ]] || return 1
}

validate_fqdn() {
  local fqdn="$1"
  [[ "$fqdn" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$ ]]
}

validate_path() {
  local path="$1"
  [[ "$path" = /* ]]
}

validate_var_ipv4() {
  validate_ipv4 "$1" || fail "Invalid IPv4 address: $1"
}

validate_var_cidr() {
  validate_cidr "$1" || fail "Invalid CIDR value: $1"
}

validate_var_fqdn() {
  validate_fqdn "$1" || fail "Invalid FQDN value: $1"
}

validate_var_path() {
  validate_path "$1" || fail "Path must be absolute: $1"
}

validate_var_not_placeholder() {
  [[ "$1" != "CHANGE_ME" ]] || fail "Replace placeholder value before continuing"
}

validate_port() {
  local port="$1"
  [[ "$port" =~ ^[0-9]+$ ]] || return 1
  (( port >= 1 && port <= 65535 ))
}

validate_var_port() {
  validate_port "$1" || fail "Invalid TCP port: $1"
}

validate_records_file() {
  local line line_no=0 fqdn ip
  while IFS= read -r line; do
    line_no=$((line_no + 1))
    [[ -z "$line" || "$line" = \#* ]] && continue

    [[ "$line" =~ ^[^[:space:]]+[[:space:]]+[^[:space:]]+$ ]] || \
      fail "Invalid record format in ${RECORDS_FILE}:${line_no}. Expected: <fqdn> <ip>"

    fqdn="${line% *}"
    ip="${line##* }"
    validate_fqdn "$fqdn" || fail "Invalid FQDN in ${RECORDS_FILE}:${line_no}: ${fqdn}"
    validate_ipv4 "$ip" || fail "Invalid IP in ${RECORDS_FILE}:${line_no}: ${ip}"
  done < "$RECORDS_FILE"
}

require_env_vars() {
  local var
  for var in HOST_IP SEARCH_DOMAIN DNS_FQDN ALLOW_NET_1 ALLOW_NET_2 ALLOW_NET_3 UNBOUND_FORWARDER CHRONY_SERVER_1 CHRONY_SERVER_2 CHRONY_SERVER_3 WORKDIR KEYCLOAK_DIR; do
    [[ -n "${!var:-}" ]] || fail "Missing required variable: $var"
  done

  validate_var_ipv4 "${HOST_IP}"
  validate_var_fqdn "${SEARCH_DOMAIN}"
  validate_var_fqdn "${DNS_FQDN}"
  validate_var_cidr "${ALLOW_NET_1}"
  validate_var_cidr "${ALLOW_NET_2}"
  validate_var_cidr "${ALLOW_NET_3}"
  validate_var_ipv4 "${UNBOUND_FORWARDER}"
  validate_var_fqdn "${CHRONY_SERVER_1}"
  validate_var_fqdn "${CHRONY_SERVER_2}"
  validate_var_fqdn "${CHRONY_SERVER_3}"
  validate_var_path "${WORKDIR}"
  validate_var_path "${KEYCLOAK_DIR}"
}

require_keycloak_vars() {
  local var
  for var in KEYCLOAK_FQDN KEYCLOAK_ADMIN_USER KEYCLOAK_ADMIN_PASSWORD; do
    [[ -n "${!var:-}" ]] || fail "Missing required variable: $var"
  done

  validate_var_fqdn "${KEYCLOAK_FQDN}"
  validate_var_not_placeholder "${KEYCLOAK_ADMIN_PASSWORD}"
}

require_module_file "${BOOTSTRAP_DIR}/dns.sh"
# shellcheck disable=SC1090
source "${BOOTSTRAP_DIR}/dns.sh"

require_module_file "${BOOTSTRAP_DIR}/ntp.sh"
# shellcheck disable=SC1090
source "${BOOTSTRAP_DIR}/ntp.sh"

require_module_file "${BOOTSTRAP_DIR}/keycloak.sh"
# shellcheck disable=SC1090
source "${BOOTSTRAP_DIR}/keycloak.sh"

require_module_file "${BOOTSTRAP_DIR}/netbox.sh"
# shellcheck disable=SC1090
source "${BOOTSTRAP_DIR}/netbox.sh"

require_module_file "${BOOTSTRAP_DIR}/s3.sh"
# shellcheck disable=SC1090
source "${BOOTSTRAP_DIR}/s3.sh"

require_module_file "${BOOTSTRAP_DIR}/sftp.sh"
# shellcheck disable=SC1090
source "${BOOTSTRAP_DIR}/sftp.sh"

require_module_file "${BOOTSTRAP_DIR}/rsyslog.sh"
# shellcheck disable=SC1090
source "${BOOTSTRAP_DIR}/rsyslog.sh"

require_module_file "${BOOTSTRAP_DIR}/ca.sh"
# shellcheck disable=SC1090
source "${BOOTSTRAP_DIR}/ca.sh"

require_root

[[ $# -eq 1 ]] || { usage; exit 1; }

case "$1" in
  --unbound)
    require_env_file
    load_env
    require_env_vars
    require_records_file
    do_unbound
    ;;
  --ntp)
    require_env_file
    load_env
    require_env_vars
    do_ntp
    ;;
  --rsyslog)
    require_env_file
    load_env
    require_env_vars
    do_rsyslog
    ;;
  --ca)
    require_env_file
    load_env
    require_env_vars
    do_ca
    ;;
  --keycloak)
    require_env_file
    load_env
    require_env_vars
    do_keycloak
    ;;
  --netbox)
    require_env_file
    load_env
    require_env_vars
    do_netbox
    ;;
  --s3)
    require_env_file
    load_env
    require_env_vars
    do_s3
    ;;
  --sftp)
    require_env_file
    load_env
    require_env_vars
    do_sftp
    ;;
  --all)
    require_env_file
    load_env
    require_env_vars
    require_records_file
    do_unbound
    do_ntp
    do_rsyslog
    do_ca
    do_keycloak
    do_netbox
    do_s3
    do_sftp
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
