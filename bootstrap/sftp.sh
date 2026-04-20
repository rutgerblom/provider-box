#!/usr/bin/env bash

require_sftp_ca_vars() {
  local var
  for var in CA_FQDN CA_PORT CA_DATA_DIR CA_PROVISIONER_NAME; do
    [[ -n "${!var:-}" ]] || fail "Missing required variable: $var"
  done

  validate_var_fqdn "${CA_FQDN}"
  validate_var_port "${CA_PORT}"
  validate_var_path "${CA_DATA_DIR}"
  resolve_ca_password_file
  validate_var_path "${CA_PASSWORD_FILE}"
  [[ "${CA_PASSWORD_FILE}" == "${CA_DATA_DIR}"/* ]] || \
    fail "CA_PASSWORD_FILE must be located under CA_DATA_DIR so the step-ca container can read it"
}

require_sftp_vars() {
  local var
  for var in WORKDIR SFTP_FQDN SFTP_PORT SFTP_ADMIN_PORT SFTP_ADMIN_USER SFTP_ADMIN_PASSWORD SFTP_DATA_DIR SFTP_HOME_DIR SFTP_CERT_DIR; do
    [[ -n "${!var:-}" ]] || fail "Missing required variable: $var"
  done

  validate_var_path "${WORKDIR}"
  validate_var_fqdn "${SFTP_FQDN}"
  validate_var_port "${SFTP_PORT}"
  validate_var_port "${SFTP_ADMIN_PORT}"
  validate_var_not_placeholder "${SFTP_ADMIN_PASSWORD}"
  validate_var_path "${SFTP_DATA_DIR}"
  validate_var_path "${SFTP_HOME_DIR}"
  validate_var_path "${SFTP_CERT_DIR}"
}

require_sftp_remove_vars() {
  local var
  for var in WORKDIR SFTP_DATA_DIR SFTP_HOME_DIR SFTP_CERT_DIR; do
    [[ -n "${!var:-}" ]] || fail "Missing required variable: $var"
  done

  validate_var_path "${WORKDIR}"
  validate_var_path "${SFTP_DATA_DIR}"
  validate_var_path "${SFTP_HOME_DIR}"
  validate_var_path "${SFTP_CERT_DIR}"
}

require_ca_ready_for_sftp() {
  [[ -f "${CA_DATA_DIR}/config/ca.json" ]] || \
    fail "step-ca is not initialized. Run --ca first."
  [[ -f "${CA_DATA_DIR}/certs/root_ca.crt" ]] || \
    fail "Missing step-ca root certificate in ${CA_DATA_DIR}/certs/root_ca.crt. Run --ca first."
  [[ -f "${CA_DATA_DIR}/certs/intermediate_ca.crt" ]] || \
    fail "Missing step-ca intermediate certificate in ${CA_DATA_DIR}/certs/intermediate_ca.crt. Run --ca first."
  [[ -f "${CA_PASSWORD_FILE}" ]] || \
    fail "Missing CA password file: ${CA_PASSWORD_FILE}. Run --ca first."

  curl --silent --show-error --fail \
    --cacert "${CA_DATA_DIR}/certs/root_ca.crt" \
    --resolve "${CA_FQDN}:${CA_PORT}:127.0.0.1" \
    "https://${CA_FQDN}:${CA_PORT}/roots.pem" >/dev/null || \
    fail "step-ca is not reachable on https://${CA_FQDN}:${CA_PORT}. Run --ca first and ensure the CA is healthy."
}

issue_sftp_certificates() {
  local cert_dir="${SFTP_CERT_DIR}"
  local cert_dir_in_container="/etc/provider-box/sftpgo-certs"
  local password_file_in_container="/home/step/${CA_PASSWORD_FILE#${CA_DATA_DIR}/}"

  install -d -m 0755 "${cert_dir}"
  if [[ "$(stat -c %u "${cert_dir}")" != "1000" ]]; then
    chown 1000:1000 "${cert_dir}"
  fi

  rm -f \
    "${cert_dir}/sftpgo.crt" \
    "${cert_dir}/sftpgo.key" \
    "${cert_dir}/sftpgo-ca-chain.pem" \
    "${cert_dir}/sftpgo-ca-roots.pem" \
    "${cert_dir}/sftpgo-leaf.crt"

  docker run --rm --network host \
    -v "${CA_DATA_DIR}:/home/step" \
    -v "${cert_dir}:${cert_dir_in_container}" \
    smallstep/step-ca:0.29.0 \
    step ca certificate "${SFTP_FQDN}" "${cert_dir_in_container}/sftpgo-leaf.crt" "${cert_dir_in_container}/sftpgo.key" \
      --san "${SFTP_FQDN}" \
      --issuer "${CA_PROVISIONER_NAME}" \
      --provisioner-password-file "${password_file_in_container}" \
      --ca-url "https://${CA_FQDN}:${CA_PORT}" \
      --root /home/step/certs/root_ca.crt || \
      fail "Failed to issue an SFTPGo certificate from step-ca."

  mv "${cert_dir}/sftpgo-leaf.crt" "${cert_dir}/sftpgo.crt" || \
    fail "Failed to store the SFTPGo certificate chain."

  cat "${CA_DATA_DIR}/certs/intermediate_ca.crt" "${CA_DATA_DIR}/certs/root_ca.crt" > "${cert_dir}/sftpgo-ca-chain.pem" || \
    fail "Failed to build the SFTPGo CA chain bundle."

  docker run --rm --network host \
    -v "${CA_DATA_DIR}:/home/step" \
    -v "${cert_dir}:${cert_dir_in_container}" \
    smallstep/step-ca:0.29.0 \
    step ca roots "${cert_dir_in_container}/sftpgo-ca-roots.pem" \
      --ca-url "https://${CA_FQDN}:${CA_PORT}" \
      --root /home/step/certs/root_ca.crt || \
      fail "Failed to fetch the step-ca root bundle for SFTPGo."

  chmod 0644 "${cert_dir}/sftpgo.crt" "${cert_dir}/sftpgo-ca-chain.pem" "${cert_dir}/sftpgo-ca-roots.pem"
  chmod 0600 "${cert_dir}/sftpgo.key"
  chown 1000:1000 \
    "${cert_dir}" \
    "${cert_dir}/sftpgo.crt" \
    "${cert_dir}/sftpgo.key" \
    "${cert_dir}/sftpgo-ca-chain.pem" \
    "${cert_dir}/sftpgo-ca-roots.pem"
}

wait_for_sftp_admin_https() {
  local attempt http_code
  local sftp_admin_url="https://${SFTP_FQDN}:${SFTP_ADMIN_PORT}/web/admin"

  echo "Waiting for SFTPGo admin UI to become ready at ${sftp_admin_url}."

  for attempt in $(seq 1 60); do
    http_code="$(curl --silent --show-error \
      --output /dev/null \
      --write-out '%{http_code}' \
      --cacert "${CA_DATA_DIR}/certs/root_ca.crt" \
      --resolve "${SFTP_FQDN}:${SFTP_ADMIN_PORT}:127.0.0.1" \
      "${sftp_admin_url}" || true)"

    case "${http_code}" in
      200|301|302)
        return 0
        ;;
    esac

    sleep 2
  done

  fail "SFTPGo admin UI did not become ready at ${sftp_admin_url}. Check 'docker compose ps' and 'docker compose logs'."
}

do_sftp() {
  require_sftp_vars
  require_sftp_ca_vars
  common_pkgs
  docker_pkgs
  require_ca_ready_for_sftp
  issue_sftp_certificates
  mkdir -p "${WORKDIR}/sftpgo" "${SFTP_DATA_DIR}" "${SFTP_HOME_DIR}" "${SFTP_CERT_DIR}"
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
  wait_for_sftp_admin_https
}

remove_sftp() {
  local runtime_dir="${WORKDIR}/sftpgo"
  local compose_file="${runtime_dir}/docker-compose.yml"

  require_sftp_remove_vars

  if [[ -f "${compose_file}" ]]; then
    require_command docker
    (
      cd "${runtime_dir}"
      docker compose down || true
    )
  fi

  rm -rf "${runtime_dir}"
  echo "Removed SFTPGo containers and runtime files. Persistent data in ${SFTP_DATA_DIR}, ${SFTP_HOME_DIR}, and ${SFTP_CERT_DIR} was preserved."
}
