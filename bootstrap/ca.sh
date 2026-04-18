#!/usr/bin/env bash

require_ca_vars() {
  local var
  for var in CA_FQDN CA_PORT CA_DATA_DIR CA_NAME CA_PROVISIONER_NAME CA_PASSWORD_FILE CA_ENABLE_ACME; do
    [[ -n "${!var:-}" ]] || fail "Missing required variable: $var"
  done

  validate_var_fqdn "${CA_FQDN}"
  validate_var_port "${CA_PORT}"
  validate_var_path "${CA_DATA_DIR}"
  validate_var_path "${CA_PASSWORD_FILE}"
  [[ "${CA_ENABLE_ACME}" == "true" || "${CA_ENABLE_ACME}" == "false" ]] || \
    fail "CA_ENABLE_ACME must be either true or false"
  [[ "${CA_PASSWORD_FILE}" == "${CA_DATA_DIR}"/* ]] || \
    fail "CA_PASSWORD_FILE must be located under CA_DATA_DIR so it is mounted into the container"
}

do_ca() {
  require_ca_vars
  common_pkgs
  docker_pkgs
  install -d -m 0755 "${WORKDIR}/step-ca" "${CA_DATA_DIR}" "$(dirname "${CA_PASSWORD_FILE}")"
  [[ -f "${CA_PASSWORD_FILE}" ]] || fail "Missing CA password file: ${CA_PASSWORD_FILE}"

  CA_PASSWORD_FILE_IN_CONTAINER="/home/step/${CA_PASSWORD_FILE#${CA_DATA_DIR}/}"
  if [[ "${CA_ENABLE_ACME}" == "true" ]]; then
    CA_ACME_ENV_BLOCK='      DOCKER_STEPCA_INIT_ACME: "true"'
  else
    CA_ACME_ENV_BLOCK=""
  fi
  export CA_PASSWORD_FILE_IN_CONTAINER CA_ACME_ENV_BLOCK

  render_template "${TEMPLATE_DIR}/docker-compose.step-ca.yml.tpl" "${WORKDIR}/step-ca/docker-compose.yml"

  (
    cd "${WORKDIR}/step-ca"
    docker compose down || true
    docker compose up -d
  )
  ufw allow "${CA_PORT}/tcp" || true
}
