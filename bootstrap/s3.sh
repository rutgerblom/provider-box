#!/usr/bin/env bash

require_s3_vars() {
  local var
  for var in S3_FQDN S3_PORT S3_ACCESS_KEY S3_SECRET_KEY S3_DATA_DIR; do
    [[ -n "${!var:-}" ]] || fail "Missing required variable: $var"
  done

  validate_var_fqdn "${S3_FQDN}"
  validate_var_port "${S3_PORT}"
  validate_var_path "${S3_DATA_DIR}"
  validate_var_not_placeholder "${S3_ACCESS_KEY}"
  validate_var_not_placeholder "${S3_SECRET_KEY}"
}

do_s3() {
  require_s3_vars
  common_pkgs
  keycloak_pkgs
  mkdir -p "${WORKDIR}/s3" "${S3_DATA_DIR}"
  render_template "${TEMPLATE_DIR}/docker-compose.s3.yml.tpl" "${WORKDIR}/s3/docker-compose.yml"
  (
    cd "${WORKDIR}/s3"
    docker compose down || true
    docker compose up -d
  )
  ufw allow "${S3_PORT}/tcp" || true
}
