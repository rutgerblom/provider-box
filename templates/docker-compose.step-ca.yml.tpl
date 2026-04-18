services:
  step-ca:
    image: smallstep/step-ca:latest
    restart: unless-stopped
    environment:
      DOCKER_STEPCA_INIT_NAME: "${CA_NAME}"
      DOCKER_STEPCA_INIT_DNS_NAMES: "${CA_FQDN}"
      DOCKER_STEPCA_INIT_PROVISIONER_NAME: "${CA_PROVISIONER_NAME}"
      DOCKER_STEPCA_INIT_PASSWORD_FILE: "${CA_PASSWORD_FILE_IN_CONTAINER}"
${CA_ACME_ENV_BLOCK}
    ports:
      - "${CA_PORT}:9000"
    volumes:
      - ${CA_DATA_DIR}:/home/step
