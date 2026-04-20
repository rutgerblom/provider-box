services:
  keycloak:
    image: ${KEYCLOAK_IMAGE}
    restart: unless-stopped
    environment:
      KC_BOOTSTRAP_ADMIN_USERNAME: "${KEYCLOAK_ADMIN_USER}"
      KC_BOOTSTRAP_ADMIN_PASSWORD: "${KEYCLOAK_ADMIN_PASSWORD}"
      KC_HTTPS_CERTIFICATE_FILE: /opt/keycloak/certs/keycloak.crt
      KC_HTTPS_CERTIFICATE_KEY_FILE: /opt/keycloak/certs/keycloak.key
    ports:
      - "8443:8443"
    volumes:
      - ${KEYCLOAK_DIR}/certs:/opt/keycloak/certs:ro
      - ${KEYCLOAK_DIR}/data:/opt/keycloak/data
      - ${WORKDIR}/keycloak/import:/opt/keycloak/data/import:ro
    command:
      - start
      - --import-realm
      - --hostname=https://${KEYCLOAK_FQDN}:8443
