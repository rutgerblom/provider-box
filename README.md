# Provider Box

Provider Box is a lightweight Ubuntu/Linux-based shared-services host for external dependencies commonly required around a VCF 9 environment.

## Current scope

- Unbound (DNS)
- Chrony (NTP)
- Keycloak (Identity)

---

## Repository layout

bootstrap/
  provider-box.sh

config/
  provider-box.env.example
  unbound.records.example

templates/
  unbound.conf.tpl
  chrony.conf.tpl
  docker-compose.keycloak.yml.tpl

legacy/

---

## Prerequisites

- Ubuntu / Debian-based system
- Root or sudo access
- Static IP configured on the host

---

## Setup

cp config/provider-box.env.example config/provider-box.env
cp config/unbound.records.example config/unbound.records

Edit both files before running anything.

---

## Usage

sudo bash bootstrap/provider-box.sh --unbound
sudo bash bootstrap/provider-box.sh --ntp
sudo bash bootstrap/provider-box.sh --keycloak
sudo bash bootstrap/provider-box.sh --all

---

## Configuration validation

The script validates required variables before execution.

- Missing core variables will stop all operations
- Keycloak-specific variables are validated only when running:
  --keycloak or --all

---

## DNS (Unbound)

- Authoritative for the configured domain (e.g. sddc.lab)
- Forward and reverse records are generated automatically

### Record format

config/unbound.records:

<fqdn> <ip>

Example:

pod-240-vc01.sddc.lab 10.203.240.10

This generates:

- A record
- PTR record

This is required for proper VCF functionality.

---

## NTP (Chrony)

- Uses upstream NTP servers defined in config
- Serves time to allowed internal networks

---

## Keycloak

- Runs as a Docker container
- Exposed on:

https://<KEYCLOAK_FQDN>:8443

### Certificates

Certificates are generated automatically using an internal CA.

The certificate includes:
- FQDN (DNS SAN)
- IP address (IP SAN)

Output location:

${WORKDIR}

Important files:
- provider-box-ca.crt → import into clients / VCF trust store
- keycloak-chain.crt → full certificate chain

---

## Notes

- Always use FQDN, not IP
- DNS must provide both forward and reverse resolution
- Import the CA certificate into:
  - browser
  - OS trust store
  - VCF SSO configuration

---

## Future improvements

- External database for Keycloak (PostgreSQL)
- Environment templating improvements
- Optional Ansible-based deployment

---

## Related

Kubernetes workloads are managed separately via GitOps.