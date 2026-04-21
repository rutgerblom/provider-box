# Provider Box — Project Context

For AI-assisted development or onboarding, see `PROJECT_CONTEXT.md`.

## Interaction Guidance (for AI assistants)

- Do not introduce abstraction layers unless explicitly requested
- Do not add migration logic unless explicitly requested
- Prefer explicit, service-scoped changes over generic frameworks
- Preserve the single-node, deterministic model

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
  sudo bash bootstrap/provider-box.sh --<service> --remove

Loose coupling, with some dependencies (e.g. step-ca).

- services may have startup dependencies (e.g. step-ca)

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
- no implicit defaults
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

Provides a central control plane for all container image versions used by Provider Box.
All containerized services must source their image from `provider-box.env`.

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
- runtime variables (e.g. nginx $uri) must be preserved explicitly (e.g. via escaping)

---

## Directory Model

Persistent service data defaults to:

/opt/provider-box/<service>

Examples:
- /opt/provider-box/step-ca
- /opt/provider-box/depot
- /opt/provider-box/keycloak
- /opt/provider-box/netbox

Runtime files

Runtime-generated files are written to:

/opt/provider-box/runtime/<service>

This directory is managed by Provider Box and is separate from both the repository location and persistent service data.

Examples:
- /opt/provider-box/runtime/depot
- /opt/provider-box/runtime/step-ca

### Path changes

Default persistent service paths now live under `/opt/provider-box`.
Default runtime-generated files now live under `/opt/provider-box/runtime`.

Existing installations using the previous `/opt/<service>` layout are not migrated automatically. Path changes must be handled manually or by updating `provider-box.env`.

---

## Removal Semantics

--remove:

- stops containers
- removes runtime files
- preserves persistent data

Example:
- keeps /opt/provider-box/depot/data
- removes the corresponding runtime directory (e.g. /opt/provider-box/runtime/depot by default)

---

## Security Model (Lab)

- basic auth for depot
- credentials stored locally
- pragmatic permissions

Focus:
usability over production-grade hardening

---

## Operational Constraints

- Services are started sequentially, not dependency-aware
- Readiness checks validate service availability after startup
- A container being "started" does not imply readiness
- Operators may need to re-run individual services if dependencies were not yet available

### Readiness Model

Provider Box uses service-specific readiness checks to verify that services are reachable on their user-facing interfaces.

- Readiness checks probe the externally exposed HTTPS endpoints
- Internal health endpoints (e.g. `/health`) are not used for readiness
- Redirect responses (e.g. 301/302) are considered valid readiness signals
- A container being "started" does not imply readiness

This ensures that services are validated based on actual usability rather than internal health mechanisms.

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
- avoid implicit behavior (e.g. hidden migrations or automatic state changes)
- prefer external readiness checks over internal health probes

---

## Summary

Provider Box is:

A minimal, reproducible, single-node infrastructure platform for lab environments, prioritizing clarity, simplicity, and controlled dependencies.
