services:
  sftpgo:
    image: drakkan/sftpgo:latest
    restart: unless-stopped
    ports:
      - "${SFTP_PORT}:2022"
      - "${SFTP_ADMIN_PORT}:8080"
    volumes:
      - ${SFTP_DATA_DIR}:/srv/sftpgo
      - ${SFTP_HOME_DIR}:/var/lib/sftpgo
