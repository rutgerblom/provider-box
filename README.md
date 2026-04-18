# Provider Box

Provider Box is a small Ubuntu/Debian bootstrap project for standing up shared infrastructure services on a single host. It is currently opinionated around lab and homelab environments and ships templates for:

- Unbound for internal DNS
- Chrony for internal NTP
- Keycloak for identity
- SeaweedFS for S3-compatible object storage

The repository is intentionally simple: copy the example configuration, update values for your environment, and run the bootstrap script for the services you want.

`bootstrap/provider-box.sh` remains the entrypoint and loads service-specific modules from `bootstrap/dns.sh`, `bootstrap/ntp.sh`, `bootstrap/keycloak.sh`, and `bootstrap/s3.sh`.

## What This Repository Is

- A reusable shell-based starter for a "provider box" or shared-services VM
- A template-driven setup that keeps generated service config separate from repo-managed source files
- A good fit for lab, PoC, or homelab environments where you want fast repeatable setup

## What It Assumes

- Ubuntu or Debian-based host
- Root or `sudo` access
- Static IP already configured
- Access to Ubuntu/Debian package repositories
- `bind9-dnsutils` available from the host package manager for DNS tooling
- Docker packages available from the host package manager when deploying Keycloak or SeaweedFS S3

## Repository Layout

```text
bootstrap/
  dns.sh
  keycloak.sh
  ntp.sh
  provider-box.sh
  s3.sh

config/
  provider-box.env.example
  unbound.records.example

templates/
  unbound.conf.tpl
  chrony.conf.tpl
  docker-compose.keycloak.yml.tpl
  docker-compose.s3.yml.tpl
```

## Quick Start

1. Copy the example files:

```bash
cp config/provider-box.env.example config/provider-box.env
cp config/unbound.records.example config/unbound.records
```

2. Update `config/provider-box.env` and `config/unbound.records` for your environment.
   If you enable S3, make sure `S3_FQDN` is also present in `config/unbound.records` so Unbound generates the matching A and PTR records.
3. Run the bootstrap script for the component you want:

```bash
sudo bash bootstrap/provider-box.sh --unbound
sudo bash bootstrap/provider-box.sh --ntp
sudo bash bootstrap/provider-box.sh --keycloak
sudo bash bootstrap/provider-box.sh --s3
sudo bash bootstrap/provider-box.sh --all
```

## Development Safeguards

This repository includes local `pre-commit` hooks to catch small hygiene issues and help prevent committing secrets to a public repository.

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

`config/provider-box.env` defines host, DNS, NTP, certificate, Keycloak, and S3 settings.

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

Keycloak-specific validation only runs for `--keycloak` and `--all`. S3-specific validation only runs for `--s3` and `--all`.

## Service Notes

### Unbound

- Serves the configured search domain as a static local zone
- Generates both forward and reverse records from `config/unbound.records`
- Uses the configured upstream forwarder for external lookups

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

### Keycloak

- Deploys with Docker Compose
- Exposes HTTPS on `https://<KEYCLOAK_FQDN>:8443`
- Generates an internal CA and a host certificate containing both DNS and IP SANs

Important output files in `${WORKDIR}`:

- `provider-box-ca.crt` for client trust import
- `keycloak-chain.crt` for full certificate chain distribution

### SeaweedFS S3

- Deploys as a single-node SeaweedFS server with the S3 API enabled
- Uses Docker Compose
- Exposes the S3-compatible endpoint on `http://<S3_FQDN>:<S3_PORT>`
- Persists object data under `S3_DATA_DIR`
- Requires the `S3_FQDN` hostname to be present in `config/unbound.records` if you want it resolvable through the built-in DNS setup

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
- Import the generated CA certificate into client trust stores if you use the generated Keycloak certs
- `configure_resolv_conf()` rewrites `/etc/resolv.conf` and disables `systemd-resolved`

## Scope

This repository keeps the current structure intact and focuses on a lightweight bootstrap workflow. The `legacy/` directory remains in place as historical reference and is not used by the main bootstrap path.
