#!/usr/bin/env bash

generate_certs() {
  mkdir -p "${WORKDIR}" "${KEYCLOAK_DIR}/certs" "${KEYCLOAK_DIR}/data"

  cat > "${WORKDIR}/keycloak-openssl.cnf" <<EOF
[ req ]
default_bits       = 2048
distinguished_name = req_distinguished_name
req_extensions     = req_ext
prompt             = no

[ req_distinguished_name ]
C  = ${CERT_C}
ST = ${CERT_ST}
L  = ${CERT_L}
O  = ${CERT_O}
OU = ${CERT_OU_IDP}
CN = ${KEYCLOAK_FQDN}

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = ${KEYCLOAK_FQDN}
IP.1  = ${HOST_IP}
EOF

  openssl genrsa -out "${WORKDIR}/provider-box-ca.key" 4096
  openssl req -x509 -new -nodes \
    -key "${WORKDIR}/provider-box-ca.key" \
    -sha256 -days 3650 \
    -out "${WORKDIR}/provider-box-ca.crt" \
    -subj "/C=${CERT_C}/ST=${CERT_ST}/L=${CERT_L}/O=${CERT_O}/OU=${CERT_OU_CA}/CN=${CERT_CA_CN}"

  openssl genrsa -out "${WORKDIR}/${KEYCLOAK_FQDN}.key" 2048
  openssl req -new \
    -key "${WORKDIR}/${KEYCLOAK_FQDN}.key" \
    -out "${WORKDIR}/${KEYCLOAK_FQDN}.csr" \
    -config "${WORKDIR}/keycloak-openssl.cnf"

  openssl x509 -req \
    -in "${WORKDIR}/${KEYCLOAK_FQDN}.csr" \
    -CA "${WORKDIR}/provider-box-ca.crt" \
    -CAkey "${WORKDIR}/provider-box-ca.key" \
    -CAcreateserial \
    -out "${WORKDIR}/${KEYCLOAK_FQDN}.crt" \
    -days 825 \
    -sha256 \
    -extensions req_ext \
    -extfile "${WORKDIR}/keycloak-openssl.cnf"

  install -D -m 0644 "${WORKDIR}/${KEYCLOAK_FQDN}.crt" "${KEYCLOAK_DIR}/certs/${KEYCLOAK_FQDN}.crt"
  install -D -m 0600 "${WORKDIR}/${KEYCLOAK_FQDN}.key" "${KEYCLOAK_DIR}/certs/${KEYCLOAK_FQDN}.key"
  chown -R 1000:1000 "${KEYCLOAK_DIR}"

  cat "${WORKDIR}/${KEYCLOAK_FQDN}.crt" "${WORKDIR}/provider-box-ca.crt" > "${WORKDIR}/keycloak-chain.crt"
}

do_keycloak() {
  require_keycloak_vars
  common_pkgs
  keycloak_pkgs
  generate_certs
  mkdir -p "${WORKDIR}/keycloak"
  render_template "${TEMPLATE_DIR}/docker-compose.keycloak.yml.tpl" "${WORKDIR}/keycloak/docker-compose.yml"
  (
    cd "${WORKDIR}/keycloak"
    docker compose down || true
    docker compose up -d
  )
  ufw allow 8443/tcp || true
}
