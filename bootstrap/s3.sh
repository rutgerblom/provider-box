#!/usr/bin/env bash

require_s3_vars() {
  local var
  for var in WORKDIR S3_FQDN S3_PORT S3_ACCESS_KEY S3_SECRET_KEY S3_DATA_DIR S3_IMAGE; do
    [[ -n "${!var:-}" ]] || fail "Missing required variable: $var"
  done

  validate_var_path "${WORKDIR}"
  validate_var_fqdn "${S3_FQDN}"
  validate_var_port "${S3_PORT}"
  validate_var_path "${S3_DATA_DIR}"
  [[ "${S3_IMAGE}" == *:* ]] || fail "S3_IMAGE must include an explicit image tag"
  [[ "${S3_IMAGE}" != *:latest ]] || fail "S3_IMAGE must not use the latest tag"
  validate_var_not_placeholder "${S3_ACCESS_KEY}"
  validate_var_not_placeholder "${S3_SECRET_KEY}"
}

require_s3_remove_vars() {
  local var
  for var in WORKDIR S3_DATA_DIR; do
    [[ -n "${!var:-}" ]] || fail "Missing required variable: $var"
  done

  validate_var_path "${WORKDIR}"
  validate_var_path "${S3_DATA_DIR}"
}

do_s3() {
  require_s3_vars
  common_pkgs
  docker_pkgs
  mkdir -p "${WORKDIR}/s3" "${S3_DATA_DIR}"
  render_template "${TEMPLATE_DIR}/docker-compose.s3.yml.tpl" "${WORKDIR}/s3/docker-compose.yml"
  (
    cd "${WORKDIR}/s3"
    docker compose down || true
    docker compose up -d
  )
  ufw allow "${S3_PORT}/tcp" || true
}

remove_s3() {
  local runtime_dir="${WORKDIR}/s3"
  local compose_file="${runtime_dir}/docker-compose.yml"

  require_s3_remove_vars

  if [[ -f "${compose_file}" ]]; then
    require_command docker
    (
      cd "${runtime_dir}"
      docker compose down || true
    )
  fi

  rm -rf "${runtime_dir}"
  echo "Removed SeaweedFS containers and runtime files. Persistent data in ${S3_DATA_DIR} was preserved."
}
