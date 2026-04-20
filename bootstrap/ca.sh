#!/usr/bin/env bash

require_ca_vars() {
  local var
  for var in WORKDIR CA_FQDN CA_PORT CA_DATA_DIR CA_NAME CA_PROVISIONER_NAME CA_ENABLE_ACME; do
    [[ -n "${!var:-}" ]] || fail "Missing required variable: $var"
  done

  validate_var_path "${WORKDIR}"
  validate_var_fqdn "${CA_FQDN}"
  validate_var_port "${CA_PORT}"
  validate_var_path "${CA_DATA_DIR}"
  resolve_ca_password_file
  validate_var_path "${CA_PASSWORD_FILE}"
  [[ "${CA_ENABLE_ACME}" == "true" || "${CA_ENABLE_ACME}" == "false" ]] || \
    fail "CA_ENABLE_ACME must be either true or false"
  [[ "${CA_PASSWORD_FILE}" == "${CA_DATA_DIR}"/* ]] || \
    fail "CA_PASSWORD_FILE must be located under CA_DATA_DIR so it is mounted into the container"
  if [[ -n "${CA_PASSWORD:-}" ]]; then
    validate_ca_password_value "${CA_PASSWORD}"
  fi
}

require_ca_remove_vars() {
  local var
  for var in WORKDIR CA_DATA_DIR; do
    [[ -n "${!var:-}" ]] || fail "Missing required variable: $var"
  done

  validate_var_path "${WORKDIR}"
  validate_var_path "${CA_DATA_DIR}"
}

do_ca() {
  local password_dir password_value

  require_ca_vars
  common_pkgs
  docker_pkgs
  password_dir="$(dirname "${CA_PASSWORD_FILE}")"
  install -d -m 0755 "${WORKDIR}/step-ca" "${CA_DATA_DIR}"
  install -d -m 0700 "${password_dir}"

  if [[ -f "${CA_PASSWORD_FILE}" ]]; then
    chmod 600 "${CA_PASSWORD_FILE}"
    echo "Using existing CA password file: ${CA_PASSWORD_FILE}"
  else
    if [[ -n "${CA_PASSWORD:-}" ]]; then
      password_value="${CA_PASSWORD}"
      echo "Materializing CA_PASSWORD to managed file: ${CA_PASSWORD_FILE}"
    else
      echo "CA password input not provided. Generating one..."
      require_command openssl
      password_value="$(openssl rand -base64 32)"
      echo "Generated CA password at: ${CA_PASSWORD_FILE}"
    fi

    install -m 0600 /dev/null "${CA_PASSWORD_FILE}"
    printf '%s\n' "${password_value}" > "${CA_PASSWORD_FILE}"
    chmod 600 "${CA_PASSWORD_FILE}"
  fi

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

remove_ca() {
  local runtime_dir="${WORKDIR}/step-ca"
  local compose_file="${runtime_dir}/docker-compose.yml"

  require_ca_remove_vars

  if [[ -f "${compose_file}" ]]; then
    require_command docker
    (
      cd "${runtime_dir}"
      docker compose down || true
    )
  fi

  rm -rf "${runtime_dir}"
  echo "Removed step-ca containers and runtime files. Persistent data in ${CA_DATA_DIR} was preserved."
}
