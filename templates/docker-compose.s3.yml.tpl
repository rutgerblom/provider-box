services:
  seaweedfs-s3:
    image: chrislusf/seaweedfs:4.20
    restart: unless-stopped
    environment:
      AWS_ACCESS_KEY_ID: "${S3_ACCESS_KEY}"
      AWS_SECRET_ACCESS_KEY: "${S3_SECRET_KEY}"
    command:
      - server
      - -dir=/data
      - -s3
      - -ip.bind=0.0.0.0
      - -s3.port=${S3_PORT}
    ports:
      - "${S3_PORT}:${S3_PORT}"
    volumes:
      - ${S3_DATA_DIR}:/data
