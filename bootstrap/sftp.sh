#!/usr/bin/env bash

require_sftp_vars() {
  local var
  for var in SFTP_FQDN SFTP_PORT SFTP_ADMIN_PORT SFTP_DATA_DIR SFTP_HOME_DIR; do
    [[ -n "${!var:-}" ]] || fail "Missing required variable: $var"
  done

  validate_var_fqdn "${SFTP_FQDN}"
  validate_var_port "${SFTP_PORT}"
  validate_var_port "${SFTP_ADMIN_PORT}"
  validate_var_path "${SFTP_DATA_DIR}"
  validate_var_path "${SFTP_HOME_DIR}"
}

do_sftp() {
  require_sftp_vars
  common_pkgs
  docker_pkgs
  mkdir -p "${WORKDIR}/sftpgo" "${SFTP_DATA_DIR}" "${SFTP_HOME_DIR}"
  if [[ "$(stat -c %u "${SFTP_DATA_DIR}")" != "1000" ]]; then
    chown 1000:1000 "${SFTP_DATA_DIR}"
  fi
  if [[ "$(stat -c %u "${SFTP_HOME_DIR}")" != "1000" ]]; then
    chown 1000:1000 "${SFTP_HOME_DIR}"
  fi
  render_template "${TEMPLATE_DIR}/docker-compose.sftpgo.yml.tpl" "${WORKDIR}/sftpgo/docker-compose.yml"
  (
    cd "${WORKDIR}/sftpgo"
    docker compose down || true
    docker compose up -d
  )
  ufw allow "${SFTP_PORT}/tcp" || true
  ufw allow "${SFTP_ADMIN_PORT}/tcp" || true
}
