# Provider Box

Provider Box is a lightweight bootstrap framework for standing up shared infrastructure services on a single host acting as a dedicated **provider services node**.

It is opinionated for lab and homelab environments and includes templates for:

- Unbound for internal DNS
- Chrony for internal NTP
- rsyslog for centralized syslog collection
- step-ca for a lightweight private certificate authority
- Keycloak for identity
- SeaweedFS for S3-compatible object storage
- SFTPGo for SFTP file transfer

The repository is intentionally simple: copy the example configuration, update values for your environment, and execute the bootstrap script for the services you need.

`bootstrap/provider-box.sh` is the entrypoint. It loads service-specific modules from `bootstrap/dns.sh`, `bootstrap/ntp.sh`, `bootstrap/rsyslog.sh`, `bootstrap/ca.sh`, `bootstrap/keycloak.sh`, `bootstrap/s3.sh`, and `bootstrap/sftp.sh`.

---

## VCF Lab Companion

Provider Box provides a lightweight **external infrastructure services platform** for VMware Cloud Foundation (VCF) lab and PoC environments.

VCF deployments depend on external services that are not provided by the platform itself.

### VCF dependency chain

**Pre-deployment (hard requirements):**
- DNS (forward and reverse resolution)
- NTP (time synchronization)

**Post-deployment (operational dependencies):**
- Identity provider (OIDC / federation)
- Logging (syslog)
- Certificate authority
- Object storage and file transfer (optional)

Provider Box enables these services to be delivered from a single, reproducible node, making it easier to build and operate VCF environments without relying on external enterprise infrastructure.

This is particularly useful in homelab or isolated environments where all supporting services must be self-contained.

---

## What This Repository Is

- A shell-based bootstrap framework for shared infrastructure services
- A template-driven configuration model with strict validation
- Designed for fast, repeatable lab and PoC deployments

---

## Design Trade-offs

Provider Box is intentionally single-node and not highly available.

It prioritizes:
- simplicity
- reproducibility
- low resource footprint

over:
- redundancy
- production-grade resilience

---

## What It Assumes

- Ubuntu or Debian-based host (tested on Debian GNU/Linux 13 “trixie”)
- Root or `sudo` access
- Static IP already configured
- Network connectivity from the VCF environment to this host
- Access to Ubuntu/Debian package repositories
- `bind9-dnsutils` available for DNS tooling
- Docker packages available when deploying step-ca, Keycloak, SeaweedFS, or SFTPGo

Provider Box uses Docker Compose via `docker compose`. On Debian GNU/Linux 13, the `docker-compose` package provides this functionality.

---

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

---

## Quick Start

1. Copy the example files:

```bash
cp config/provider-box.env.example config/provider-box.env
cp config/unbound.records.example config/unbound.records
```

2. Update configuration files:

- `config/provider-box.env` defines all service configuration
- `config/unbound.records` defines external/custom DNS records

Provider Box service FQDNs are generated automatically based on values in `provider-box.env`.

3. Execute the bootstrap script:

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

---

## Choosing Services

**Minimum required for VCF bring-up:**
- Unbound (DNS)
- Chrony (NTP)

**Recommended for realistic lab environments:**
- rsyslog
- step-ca
- Keycloak

**Optional depending on use case:**
- SeaweedFS (S3)
- SFTPGo

---

## Development Safeguards (Optional)

This repository can optionally be used with local `pre-commit` hooks to catch hygiene issues and prevent committing secrets.

Install:

```bash
pipx install pre-commit
pre-commit install
```

Run manually:

```bash
pre-commit run --all-files
```

The configured Gitleaks hook scans for secrets before commits are created.

---

## Configuration Model

`config/provider-box.env` defines all service configuration.

Validation is strict and designed to fail fast before any service is deployed:

- Required variables must be set
- IP addresses must be valid IPv4 values
- Network allow lists must be valid CIDR ranges
- FQDN/domain values must be syntactically valid
- Paths must be absolute where required
- Placeholder values (e.g. `CHANGE_ME`) are rejected
- DNS records must follow `<fqdn> <ip>` format

Environment variables are exported before template rendering so `envsubst` can correctly populate all templates.

Validation is executed per service based on selected flags.

---

## Service Notes

### Unbound

- Acts as the authoritative DNS server for the lab domain
- Serves the configured domain as a static local zone
- Generates Provider Box service records automatically
- Uses `config/unbound.records` only for external/custom records
- Uses `DNS_FQDN` as PTR for `HOST_IP`
- Uses configured upstream forwarder for external resolution

Record format:

```text
<fqdn> <ip>
```

---

### Chrony

- Uses configured upstream NTP servers
- Provides NTP service to internal networks

---

### rsyslog

- Runs natively on the host
- Exposes centralized syslog via UDP and TCP
- Intended for log aggregation, not long-term analytics
- Stores logs per host and program under `SYSLOG_LOG_DIR`

---

### step-ca

- Runs as a single-node Smallstep CA via Docker Compose
- Acts as the internal PKI for Provider Box services
- Exposed at `https://<CA_FQDN>:<CA_PORT>`
- Persists data under `CA_DATA_DIR`

Behavior:
- Initializes automatically on first start
- Generates CA password file if missing

Important:
- Reinitialization requires deleting `CA_DATA_DIR`
- Root certificate available at `/roots.pem`

---

### Keycloak

- Runs via Docker Compose
- Requires step-ca to be initialized first
- Uses certificates issued by step-ca
- Exposed at `https://<KEYCLOAK_FQDN>:8443`

Key files:

- `keycloak.crt` (leaf + intermediate)
- `keycloak.key` (private key)
- `keycloak-ca-chain.pem` (for VCF OIDC trust)
- `keycloak-ca-roots.pem` (roots-only bundle)

---

### SeaweedFS S3

- Single-node S3-compatible object storage
- Exposed at `http://<S3_FQDN>:<S3_PORT>`
- Data persisted under `S3_DATA_DIR`

---

### SFTPGo

- Single-node SFTP service via Docker Compose
- Exposes:
  - SFTP endpoint
  - Admin UI
- No admin user is created automatically

---

## Failure Handling

The bootstrap process fails fast if:

- required files are missing
- package installation fails
- required commands are unavailable
- validation fails

This ensures predictable and reproducible deployments.

---

## Operational Notes

- Use FQDNs instead of IPs where possible
- Ensure both forward and reverse DNS are configured
- Import `keycloak-ca-chain.pem` into VCF when configuring OIDC
- Use `keycloak-ca-roots.pem` where roots-only trust is required

### DNS behavior warning

`configure_resolv_conf()` rewrites `/etc/resolv.conf` and disables `systemd-resolved`.

This overrides local DNS resolution behavior on the host.

---

## Scope

Provider Box focuses on a simple, modular, and reproducible way to deploy shared infrastructure services on a single host for lab and PoC environments.
