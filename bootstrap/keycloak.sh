#!/usr/bin/env bash

require_keycloak_ca_vars() {
  local var
  for var in CA_FQDN CA_PORT CA_DATA_DIR CA_PROVISIONER_NAME CA_PASSWORD_FILE; do
    [[ -n "${!var:-}" ]] || fail "Missing required variable: $var"
  done

  validate_var_fqdn "${CA_FQDN}"
  validate_var_port "${CA_PORT}"
  validate_var_path "${CA_DATA_DIR}"
  validate_var_path "${CA_PASSWORD_FILE}"
  [[ "${CA_PASSWORD_FILE}" == "${CA_DATA_DIR}"/* ]] || \
    fail "CA_PASSWORD_FILE must be located under CA_DATA_DIR so the step-ca container can read it"
}

require_ca_ready_for_keycloak() {
  [[ -f "${CA_DATA_DIR}/config/ca.json" ]] || \
    fail "step-ca is not initialized. Run --ca first."
  [[ -f "${CA_DATA_DIR}/certs/root_ca.crt" ]] || \
    fail "Missing step-ca root certificate in ${CA_DATA_DIR}/certs/root_ca.crt. Run --ca first."
  [[ -f "${CA_DATA_DIR}/certs/intermediate_ca.crt" ]] || \
    fail "Missing step-ca intermediate certificate in ${CA_DATA_DIR}/certs/intermediate_ca.crt. Run --ca first."
  [[ -f "${CA_PASSWORD_FILE}" ]] || \
    fail "Missing CA password file: ${CA_PASSWORD_FILE}. Run --ca first after creating it."

  curl --silent --show-error --fail \
    --cacert "${CA_DATA_DIR}/certs/root_ca.crt" \
    --resolve "${CA_FQDN}:${CA_PORT}:127.0.0.1" \
    "https://${CA_FQDN}:${CA_PORT}/roots.pem" >/dev/null || \
    fail "step-ca is not reachable on https://${CA_FQDN}:${CA_PORT}. Run --ca first and ensure the CA is healthy."
}

issue_keycloak_certificates() {
  local cert_dir="${KEYCLOAK_DIR}/certs"
  local password_file_in_container="/home/step/${CA_PASSWORD_FILE#${CA_DATA_DIR}/}"

  install -d -m 0755 "${WORKDIR}/keycloak" "${cert_dir}" "${KEYCLOAK_DIR}/data"

  rm -f \
    "${cert_dir}/keycloak.crt" \
    "${cert_dir}/keycloak.key" \
    "${cert_dir}/keycloak-ca-chain.pem" \
    "${cert_dir}/keycloak-ca-roots.pem" \
    "${cert_dir}/keycloak-leaf.crt"

  docker run --rm --network host \
    -v "${CA_DATA_DIR}:/home/step" \
    -v "${cert_dir}:/out" \
    smallstep/step-ca:latest \
    step ca certificate "${KEYCLOAK_FQDN}" /out/keycloak-leaf.crt /out/keycloak.key \
      --san "${KEYCLOAK_FQDN}" \
      --issuer "${CA_PROVISIONER_NAME}" \
      --provisioner-password-file "${password_file_in_container}" \
      --ca-url "https://${CA_FQDN}:${CA_PORT}" \
      --root /home/step/certs/root_ca.crt || \
      fail "Failed to issue a Keycloak certificate from step-ca."

  cat "${cert_dir}/keycloak-leaf.crt" "${CA_DATA_DIR}/certs/intermediate_ca.crt" > "${cert_dir}/keycloak.crt" || \
    fail "Failed to build the Keycloak certificate chain."

  cat "${CA_DATA_DIR}/certs/intermediate_ca.crt" "${CA_DATA_DIR}/certs/root_ca.crt" > "${cert_dir}/keycloak-ca-chain.pem" || \
    fail "Failed to build the Keycloak CA chain bundle."

  docker run --rm --network host \
    -v "${CA_DATA_DIR}:/home/step" \
    -v "${cert_dir}:/out" \
    smallstep/step-ca:latest \
    step ca roots /out/keycloak-ca-roots.pem \
      --ca-url "https://${CA_FQDN}:${CA_PORT}" \
      --root /home/step/certs/root_ca.crt || \
      fail "Failed to fetch the step-ca root bundle for Keycloak."

  rm -f "${cert_dir}/keycloak-leaf.crt"
  chmod 0644 "${cert_dir}/keycloak.crt" "${cert_dir}/keycloak-ca-chain.pem" "${cert_dir}/keycloak-ca-roots.pem"
  chmod 0600 "${cert_dir}/keycloak.key"
  chown 1000:1000 \
    "${KEYCLOAK_DIR}/data" \
    "${cert_dir}" \
    "${cert_dir}/keycloak.crt" \
    "${cert_dir}/keycloak.key" \
    "${cert_dir}/keycloak-ca-chain.pem" \
    "${cert_dir}/keycloak-ca-roots.pem"
}

do_keycloak() {
  require_keycloak_vars
  require_keycloak_ca_vars
  common_pkgs
  docker_pkgs
  require_ca_ready_for_keycloak
  issue_keycloak_certificates
  render_template "${TEMPLATE_DIR}/docker-compose.keycloak.yml.tpl" "${WORKDIR}/keycloak/docker-compose.yml"
  (
    cd "${WORKDIR}/keycloak"
    docker compose down || true
    docker compose up -d
  )
  ufw allow 8443/tcp || true
}
