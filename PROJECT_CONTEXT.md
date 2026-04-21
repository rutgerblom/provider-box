# Provider Box — Project Context

For AI-assisted development or onboarding, see `PROJECT_CONTEXT.md`.

## Overview

Provider Box is a small, opinionated infrastructure bootstrap project for lab and proof-of-concept environments.

It provides a single-node infrastructure services layer supporting VMware Cloud Foundation (VCF) and similar platforms.

The focus is on:
- simplicity
- reproducibility
- clarity
- minimal dependencies

---

## Core Philosophy

Provider Box is intentionally constrained:

- Single node only
- No orchestration (no Kubernetes)
- Explicit configuration (no hidden magic)
- Reproducible from scratch
- Minimal moving parts

This is a bootstrap layer, not a full platform.

---

## Runtime Model

Mixed execution model:

| Type              | Implementation        |
|------------------|----------------------|
| System services  | Native (systemd)     |
| Application services | Docker Compose  |

No clustering or orchestration.

---

## Service Model

Each service is:

- deployed individually:
  sudo bash bootstrap/provider-box.sh --<service>

- removed individually:
  --<service> --remove

Loose coupling, with some dependencies (e.g. step-ca).

---

## Core Components

### Infrastructure

- Unbound (DNS)
- Chrony (NTP)
- rsyslog (logging)

### Security & Identity

- step-ca (internal CA)
- Keycloak (OIDC identity provider)

Keycloak bootstrap includes:
- one opinionated realm
- one group
- one OIDC client
- optional bootstrap user

### Source of Truth

- NetBox (IPAM / DCIM)

### Storage & Transfer

- SeaweedFS (S3-compatible)
- SFTPGo (SFTP + admin UI)

### VCF Integration

- VCF Offline Depot (nginx)

---

## Depot Model

Nginx-based service serving VCF binaries.

### Structure

/PROD/metadata/
/PROD/COMP/
/PROD/vsan/hcl/

### Access Control

| Path                     | Auth |
|--------------------------|------|
| /healthz                | No   |
| /products/v1/bundles/all| No   |
| /PROD/vsan/hcl/         | No   |
| /PROD/metadata/         | Yes  |
| /PROD/COMP/             | Yes  |

Directory listing disabled.

---

## Configuration Model

Single source of truth:

config/provider-box.env

Principles:
- explicit values
- no hidden defaults
- service-driven configuration

---

## Container Image Model

All images are centrally defined:

CA_IMAGE=...
KEYCLOAK_IMAGE=...
NETBOX_IMAGE=...
NETBOX_POSTGRES_IMAGE=...
NETBOX_REDIS_IMAGE=...
NETBOX_NGINX_IMAGE=...
S3_IMAGE=...
SFTPGO_IMAGE=...
DEPOT_IMAGE=...

Provides a central control plane for image versions.

---

## Certificate Model

- step-ca is the internal CA
- all HTTPS services use step-ca certificates
- certificates stored locally per service
- mounted into containers
- trust via root CA

---

## Template Model

- simple env-based templating
- templates rendered before service startup

Important:
- environment variables are substituted
- runtime variables (e.g. nginx $uri) must be preserved explicitly

---

## Directory Model

Persistent data:

/opt/<service>

Examples:
- /opt/step-ca
- /opt/depot
- /opt/keycloak
- /opt/netbox

Runtime files:

/root/provider-box/<service>

---

## Removal Semantics

--remove:

- stops containers
- removes runtime files
- preserves persistent data

Example:
- keeps /opt/depot/data
- removes /root/provider-box/depot

---

## Security Model (Lab)

- basic auth for depot
- credentials stored locally
- pragmatic permissions

Focus:
usability over production-grade hardening

---

## Intended Use

- VCF labs
- PoCs
- isolated environments
- reproducible demos

---

## Non-Goals

- no HA
- no clustering
- no Kubernetes
- no advanced automation frameworks
- no dynamic service discovery

---

## Development Principles

Changes should:

- be minimal
- follow existing patterns
- be explicit and readable
- avoid unnecessary abstraction

---

## Summary

Provider Box is:

A minimal, reproducible, single-node infrastructure platform for lab environments, prioritizing clarity, simplicity, and controlled dependencies.
