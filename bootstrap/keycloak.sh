#!/usr/bin/env bash

require_keycloak_ca_vars() {
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

require_keycloak_remove_vars() {
  local var
  for var in WORKDIR KEYCLOAK_DIR; do
    [[ -n "${!var:-}" ]] || fail "Missing required variable: $var"
  done

  validate_var_path "${WORKDIR}"
  validate_var_path "${KEYCLOAK_DIR}"
}

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "${value}"
}

validate_keycloak_bootstrap_value() {
  local value="$1"
  local name="$2"
  [[ -n "${value}" ]] || fail "${name} must not be empty"
  validate_var_not_placeholder "${value}"
}

validate_keycloak_redirect_uri() {
  local uri="$1"
  [[ "${uri}" == https://* ]] || fail "KEYCLOAK_BOOTSTRAP_CLIENT_REDIRECT_URIS entries must start with https://: ${uri}"
  [[ "${uri}" != *'"'* ]] || fail "KEYCLOAK_BOOTSTRAP_CLIENT_REDIRECT_URIS entries must not contain double quotes"
}

build_keycloak_redirect_uris_json() {
  local uris="${KEYCLOAK_BOOTSTRAP_CLIENT_REDIRECT_URIS}"
  local uri
  local redirect_uris_json=""

  IFS=',' read -r -a keycloak_redirect_uris <<< "${uris}"
  ((${#keycloak_redirect_uris[@]} > 0)) || fail "KEYCLOAK_BOOTSTRAP_CLIENT_REDIRECT_URIS must not be empty"

  for uri in "${keycloak_redirect_uris[@]}"; do
    [[ -n "${uri}" ]] || fail "KEYCLOAK_BOOTSTRAP_CLIENT_REDIRECT_URIS contains an empty entry"
    validate_keycloak_redirect_uri "${uri}"
    if [[ -n "${redirect_uris_json}" ]]; then
      redirect_uris_json="${redirect_uris_json}, "
    fi
    redirect_uris_json="${redirect_uris_json}\"$(json_escape "${uri}")\""
  done

  KEYCLOAK_BOOTSTRAP_CLIENT_REDIRECT_URIS_JSON="${redirect_uris_json}"
  export KEYCLOAK_BOOTSTRAP_CLIENT_REDIRECT_URIS_JSON
}

build_keycloak_bootstrap_user_block() {
  local username_escaped password_escaped group_escaped

  if [[ -z "${KEYCLOAK_BOOTSTRAP_USERNAME:-}" && -z "${KEYCLOAK_BOOTSTRAP_USER_PASSWORD:-}" ]]; then
    KEYCLOAK_BOOTSTRAP_USERS_BLOCK=""
    export KEYCLOAK_BOOTSTRAP_USERS_BLOCK
    return
  fi

  [[ -n "${KEYCLOAK_BOOTSTRAP_USERNAME:-}" ]] || \
    fail "KEYCLOAK_BOOTSTRAP_USERNAME is required when KEYCLOAK_BOOTSTRAP_USER_PASSWORD is set"
  [[ -n "${KEYCLOAK_BOOTSTRAP_USER_PASSWORD:-}" ]] || \
    fail "KEYCLOAK_BOOTSTRAP_USER_PASSWORD is required when KEYCLOAK_BOOTSTRAP_USERNAME is set"

  validate_keycloak_bootstrap_value "${KEYCLOAK_BOOTSTRAP_USERNAME}" "KEYCLOAK_BOOTSTRAP_USERNAME"
  validate_keycloak_bootstrap_value "${KEYCLOAK_BOOTSTRAP_USER_PASSWORD}" "KEYCLOAK_BOOTSTRAP_USER_PASSWORD"

  username_escaped="$(json_escape "${KEYCLOAK_BOOTSTRAP_USERNAME}")"
  password_escaped="$(json_escape "${KEYCLOAK_BOOTSTRAP_USER_PASSWORD}")"
  group_escaped="$(json_escape "/${KEYCLOAK_BOOTSTRAP_GROUP_NAME}")"

  KEYCLOAK_BOOTSTRAP_USERS_BLOCK=$(cat <<EOF
  ,
  "users": [
    {
      "username": "${username_escaped}",
      "enabled": true,
      "emailVerified": true,
      "groups": [
        "${group_escaped}"
      ],
      "credentials": [
        {
          "type": "password",
          "value": "${password_escaped}",
          "temporary": false
        }
      ]
    }
  ]
EOF
)
  export KEYCLOAK_BOOTSTRAP_USERS_BLOCK
}

render_keycloak_realm_import() {
  local import_dir="${WORKDIR}/keycloak/import"

  build_keycloak_redirect_uris_json
  build_keycloak_bootstrap_user_block
  install -d -m 0755 "${import_dir}"
  render_template "${TEMPLATE_DIR}/keycloak-realm.json.tpl" "${import_dir}/provider-box-realm.json"
}

require_ca_ready_for_keycloak() {
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
    smallstep/step-ca:0.29.0 \
    step ca certificate "${KEYCLOAK_FQDN}" /out/keycloak-leaf.crt /out/keycloak.key \
      --san "${KEYCLOAK_FQDN}" \
      --issuer "${CA_PROVISIONER_NAME}" \
      --provisioner-password-file "${password_file_in_container}" \
      --ca-url "https://${CA_FQDN}:${CA_PORT}" \
      --root /home/step/certs/root_ca.crt || \
      fail "Failed to issue a Keycloak certificate from step-ca."

  mv "${cert_dir}/keycloak-leaf.crt" "${cert_dir}/keycloak.crt" || \
    fail "Failed to store the Keycloak certificate chain."

  cat "${CA_DATA_DIR}/certs/intermediate_ca.crt" "${CA_DATA_DIR}/certs/root_ca.crt" > "${cert_dir}/keycloak-ca-chain.pem" || \
    fail "Failed to build the Keycloak CA chain bundle."

  docker run --rm --network host \
    -v "${CA_DATA_DIR}:/home/step" \
    -v "${cert_dir}:/out" \
    smallstep/step-ca:0.29.0 \
    step ca roots /out/keycloak-ca-roots.pem \
      --ca-url "https://${CA_FQDN}:${CA_PORT}" \
      --root /home/step/certs/root_ca.crt || \
      fail "Failed to fetch the step-ca root bundle for Keycloak."

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
  render_keycloak_realm_import
  issue_keycloak_certificates
  render_template "${TEMPLATE_DIR}/docker-compose.keycloak.yml.tpl" "${WORKDIR}/keycloak/docker-compose.yml"
  (
    cd "${WORKDIR}/keycloak"
    docker compose down || true
    docker compose up -d
  )
  ufw allow 8443/tcp || true
}

remove_keycloak() {
  local runtime_dir="${WORKDIR}/keycloak"
  local compose_file="${runtime_dir}/docker-compose.yml"

  require_keycloak_remove_vars

  if [[ -f "${compose_file}" ]]; then
    require_command docker
    (
      cd "${runtime_dir}"
      docker compose down || true
    )
  fi

  rm -rf "${runtime_dir}"
  echo "Removed Keycloak containers and runtime files. Persistent data in ${KEYCLOAK_DIR} was preserved."
}
