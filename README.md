# Provider Box

Provider Box is a small Ubuntu/Debian bootstrap project for standing up shared infrastructure services on a single host. It is opinionated around lab and homelab environments and ships templates for:

- Unbound for internal DNS
- Chrony for internal NTP
- rsyslog for centralized syslog collection
- step-ca for a lightweight private certificate authority
- Keycloak for identity
- SeaweedFS for S3-compatible object storage
- SFTPGo for SFTP file transfer

The repository is intentionally simple: copy the example configuration, update values for your environment, and run the bootstrap script for the services you want.

`bootstrap/provider-box.sh` remains the entrypoint and loads service-specific modules from `bootstrap/dns.sh`, `bootstrap/ntp.sh`, `bootstrap/rsyslog.sh`, `bootstrap/ca.sh`, `bootstrap/keycloak.sh`, `bootstrap/s3.sh`, and `bootstrap/sftp.sh`.

## VCF Lab Companion

Provider Box is a natural companion for VMware Cloud Foundation (VCF) lab environments, particularly VCF 9 deployments.

VCF deployments depend on a set of external infrastructure services that are not provided by the platform itself. DNS and NTP must be available and correctly configured before deployment and are critical for successful bring-up. Identity providers and other services are typically integrated after deployment to support ongoing operation.

Provider Box provides a lightweight way to run these supporting services on a single host, making it easier to build and operate VCF lab and PoC environments without relying on external enterprise infrastructure.

This is particularly useful in homelab or isolated environments where DNS, NTP, identity, logging, and storage services need to be self-contained.

## What This Repository Is

- A reusable shell-based starter for a "provider box" or shared-services VM
- A template-driven setup that keeps generated service config separate from repo-managed source files
- A good fit for lab, PoC, or homelab environments where you want fast repeatable setup

## What It Assumes

- Ubuntu or Debian-based host. Tested on Debian GNU/Linux 13 (trixie)
- Root or `sudo` access
- Static IP already configured
- Access to Ubuntu/Debian package repositories
- `bind9-dnsutils` available from the host package manager for DNS tooling
- Docker packages available from the host package manager when deploying step-ca, Keycloak, SeaweedFS S3, or SFTPGo
- Provider Box uses Docker Compose via `docker compose`. On Debian GNU/Linux 13 (trixie), the `docker-compose` package provides this functionality.

## Repository Layout

```text
bootstrap/
  ca.sh
  dns.sh
  keycloak.sh
  ntp.sh
  provider-box.sh
  rsyslog.sh
  s3.sh
  sftp.sh

config/
  provider-box.env.example
  unbound.records.example

templates/
  unbound.conf.tpl
  chrony.conf.tpl
  rsyslog.conf.tpl
  docker-compose.step-ca.yml.tpl
  docker-compose.keycloak.yml.tpl
  docker-compose.s3.yml.tpl
  docker-compose.sftpgo.yml.tpl
```

## Quick Start

1. Copy the example files:

```bash
cp config/provider-box.env.example config/provider-box.env
cp config/unbound.records.example config/unbound.records
```

2. Update `config/provider-box.env` and `config/unbound.records` for your environment.
   Provider Box service FQDNs are generated automatically from `config/provider-box.env`. Use `config/unbound.records` only for external or custom records that should also get generated A and PTR entries.
3. Run the bootstrap script for the component you want:

```bash
sudo bash bootstrap/provider-box.sh --unbound
sudo bash bootstrap/provider-box.sh --ntp
sudo bash bootstrap/provider-box.sh --rsyslog
sudo bash bootstrap/provider-box.sh --ca
sudo bash bootstrap/provider-box.sh --keycloak
sudo bash bootstrap/provider-box.sh --s3
sudo bash bootstrap/provider-box.sh --sftp
sudo bash bootstrap/provider-box.sh --all
```

## Development Safeguards (Optional)

This repository can optionally be used with local `pre-commit` hooks to catch small hygiene issues and help prevent committing secrets to a public repository.

Install `pre-commit` locally:

```bash
pipx install pre-commit
```

Install the hooks for this repository:

```bash
pre-commit install
```

Run all configured checks manually:

```bash
pre-commit run --all-files
```

The configured Gitleaks hook scans for accidentally committed secrets before a commit is created. The real `config/provider-box.env` file is intentionally gitignored and should never be committed.

## Configuration Model

`config/provider-box.env` defines host, DNS, NTP, rsyslog, CA, Keycloak, S3, and SFTP settings.

The bootstrap script now validates configuration more strictly before making changes:

- Required variables must be set
- IP addresses must be valid IPv4 values
- Network allow lists must be valid CIDR values
- FQDN/domain values must be syntactically valid
- `WORKDIR` and `KEYCLOAK_DIR` must be absolute paths
- Keycloak password placeholders such as `CHANGE_ME` are rejected
- S3 credentials cannot be left as placeholder values
- DNS record entries must follow `<fqdn> <ip>` format
- Environment variables from `config/provider-box.env` are exported before template rendering so `envsubst` can populate all template values correctly

rsyslog-specific validation only runs for `--rsyslog` and `--all`. CA-specific validation only runs for `--ca` and `--all`. Keycloak-specific validation only runs for `--keycloak` and `--all`. S3-specific validation only runs for `--s3` and `--all`. SFTP-specific validation only runs for `--sftp` and `--all`.

## Service Notes

### Unbound

- Serves the configured search domain as a static local zone
- Generates Provider Box service records automatically from `config/provider-box.env`
- Uses `config/unbound.records` only for external/custom records
- Uses `DNS_FQDN` as the canonical PTR name for `HOST_IP`
- Uses the configured upstream forwarder for external lookups
- The example configuration allows DNS queries from all RFC1918 ranges: `10.0.0.0/8`, `172.16.0.0/12`, and `192.168.0.0/16`

Record format:

```text
<fqdn> <ip>
```

Example:

```text
pod-240-vc01.sddc.lab 10.203.240.10
```

### Chrony

- Uses configured upstream NTP servers
- Allows NTP service for the configured internal networks
- The example configuration allows all RFC1918 ranges: `10.0.0.0/8`, `172.16.0.0/12`, and `192.168.0.0/16`

### rsyslog

- Runs natively on the host, not in Docker
- Exposes a centralized syslog endpoint on `syslog://<SYSLOG_FQDN>:<SYSLOG_PORT>` using both UDP and TCP
- Intended for log forwarding from VCF-related systems such as ESXi, NSX, and vCenter
- Writes per-host, per-program logs under `SYSLOG_LOG_DIR`
- `SYSLOG_FQDN` is generated automatically from `config/provider-box.env`

### step-ca

- Deploys a single-node Smallstep `step-ca` using Docker Compose
- Exposes the CA at `https://<CA_FQDN>:<CA_PORT>`
- Persists all CA data under `CA_DATA_DIR`
- Automatically initializes on first start and issues certificates for Provider Box services (including Keycloak)

Requirement:

- `CA_PASSWORD_FILE` must exist under `CA_DATA_DIR` and be readable by UID 1000

Notes:

- Delete `CA_DATA_DIR` to reinitialize the CA
- Root certificate: `https://<CA_FQDN>:<CA_PORT>/roots.pem`

Notes:

- Reinitializing the CA requires removing the contents of `CA_DATA_DIR`
- The root certificate is available at `https://<CA_FQDN>:<CA_PORT>/roots.pem`
- Optional bootstrap parameters: `CA_NAME`, `CA_FQDN`, `CA_PROVISIONER_NAME`, `CA_ENABLE_ACME`

### Keycloak

- Deploys with Docker Compose
- Requires step-ca to be initialized and reachable first; run `--ca` before `--keycloak`
- Exposes HTTPS on `https://<KEYCLOAK_FQDN>:8443`
- Uses a server certificate issued by Provider Box step-ca
- Stores the Keycloak HTTPS certificate file expected by Keycloak in `${KEYCLOAK_DIR}/certs/keycloak.crt`
- `keycloak.crt` contains the leaf certificate and intermediate chain returned by step-ca
- The root CA is not included in `keycloak.crt`
- Stores the private key in `${KEYCLOAK_DIR}/certs/keycloak.key`
- Stores the CA chain bundle in `${KEYCLOAK_DIR}/certs/keycloak-ca-chain.pem`
- Stores the CA/root bundle in `${KEYCLOAK_DIR}/certs/keycloak-ca-roots.pem`
- Import `${KEYCLOAK_DIR}/certs/keycloak-ca-chain.pem` into VCF 9 Operations when configuring Keycloak as the OIDC IdP
- Clients must trust the root CA separately

Important output files for the current Keycloak TLS flow:

- `${KEYCLOAK_DIR}/certs/keycloak.crt` for the Keycloak HTTPS certificate file (leaf + intermediate chain)
- `${KEYCLOAK_DIR}/certs/keycloak.key` for the Keycloak HTTPS private key
- `${KEYCLOAK_DIR}/certs/keycloak-ca-chain.pem` for VCF 9 Operations OIDC IdP trust import
- `${KEYCLOAK_DIR}/certs/keycloak-ca-roots.pem` for the roots-only CA bundle

### SeaweedFS S3

- Deploys as a single-node SeaweedFS server with the S3 API enabled
- Uses Docker Compose
- Exposes the S3-compatible endpoint on `http://<S3_FQDN>:<S3_PORT>`
- Persists object data under `S3_DATA_DIR`
- `S3_FQDN` is generated automatically from `config/provider-box.env`

### SFTPGo

- Deploys as a single-node SFTPGo container using Docker Compose
- Exposes the SFTP endpoint on `sftp://<SFTP_FQDN>:<SFTP_PORT>`
- Exposes the admin UI on `http://<SFTP_FQDN>:<SFTP_ADMIN_PORT>`
- Persists service data under `SFTP_DATA_DIR`
- Persists the container home and generated host keys under `SFTP_HOME_DIR`
- `SFTP_FQDN` is generated automatically from `config/provider-box.env`
- Expected SFTP settings in `config/provider-box.env`: `SFTP_FQDN`, `SFTP_PORT`, `SFTP_ADMIN_PORT`, `SFTP_DATA_DIR`, `SFTP_HOME_DIR`
- After deployment, open the admin UI and create the first admin account there
- No SFTPGo admin credentials are bootstrapped automatically by Provider Box

## Failure Handling

The bootstrap script now fails fast when important dependencies or inputs are missing. That includes:

- missing config or template files
- failed `apt-get update` or package installation
- packages reported missing after installation
- required commands such as `apt-get`, `envsubst`, `docker`, or `unbound-checkconf` not being available

This makes the project safer to reuse in new environments where package availability can differ.

## Operational Notes

- Use FQDNs instead of raw IPs where possible
- Ensure both forward and reverse DNS exist for managed hosts
- Import `${KEYCLOAK_DIR}/certs/keycloak-ca-chain.pem` into VCF 9 Operations when configuring Keycloak as the OIDC IdP
- Use `${KEYCLOAK_DIR}/certs/keycloak-ca-roots.pem` when a roots-only CA bundle is specifically required
- `configure_resolv_conf()` rewrites `/etc/resolv.conf` and disables `systemd-resolved`

## Scope

This repository focuses on a lightweight, modular bootstrap workflow for shared infrastructure services on a single host. The main path is template-driven, shell-based, and intended to stay simple to understand, adapt, and reuse.
