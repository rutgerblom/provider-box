# AGENTS.md

## Purpose

This repository implements "Provider Box": a lightweight, single-node bootstrap framework for shared infrastructure services used in lab and PoC environments, especially VMware Cloud Foundation (VCF).

Agents must preserve:
- simplicity
- reproducibility
- readability
- strict validation
- single-node design

---

## Core Principles

- Single-node, lab-oriented design only
- Explicit shell logic over abstraction
- Template-driven configuration
- Fail fast on invalid input
- Keep implementations understandable
- Prefer reproducibility over flexibility

---

## Scope Discipline

- Keep diffs tightly scoped
- Do not refactor unrelated services
- Extend existing patterns, do not invent new ones
- Maintain consistency across all services

---

## Repository Patterns

### Bootstrap Flow (All Services)

Every service must follow this structure:

1. Validation (service-specific)
2. Directory creation
3. Template rendering
4. Service startup
5. Basic verification / output

Do not deviate from this model.

---

### Environment Model

- All configuration comes from `config/provider-box.env`
- Example values in `provider-box.env.example`
- No hardcoded environment values in scripts
- Validate before use

---

## Existing Services – Rules

The following services already exist and are considered **stable**:

- Unbound (DNS)
- Chrony (NTP)
- rsyslog
- step-ca
- Keycloak
- SeaweedFS (S3)
- SFTPGo

### Modification Rules

- Do not change behavior of existing services unless explicitly required
- Do not refactor existing service modules for style or consistency alone
- Do not introduce new dependencies into existing services
- Do not change existing configuration variables or naming
- Do not alter service exposure (ports, protocols, etc.)

### Allowed Changes

- Bug fixes
- Minimal adjustments required for new service integration
- Shared helper improvements (if they do not break existing behavior)

### DNS Integration

All services must:

- Have an FQDN defined in `provider-box.env`
- Be included in the generated DNS block
- Be resolvable via Unbound

---

### Canonical Host Identity

- `PROVIDER_BOX_FQDN` defines the canonical host identity for the Provider Box node
- All built-in service FQDNs resolve to the same host IP
- Reverse PTR records for the Provider Box host IP must point to `PROVIDER_BOX_FQDN`
- Service FQDNs must not be used as PTR targets
- The Provider Box host IP must always have exactly one canonical IP object in NetBox

---

## IP Address Modeling

- `HOST_IP` must use CIDR notation (e.g. `192.168.12.121/24`)
- The raw IPv4 address must be derived when needed for services
- CIDR information must be preserved when available

### DNS Records

- Records may use:
  - `<fqdn> <ip>`
  - `<fqdn> <ip/cidr>`

Plain IP values are treated as host addresses and will be imported as `/32` in NetBox.

- If CIDR is present:
  - The subnet must be derived

- If CIDR is not present:
  - The address must be treated as `/32`
  - No subnet assumptions are allowed

---

## Validation Rules

- Validation must be service-scoped
- Do not require config for unrelated services
- Reject:
  - empty values
  - invalid FQDNs, IPs, CIDRs
  - placeholder values (`CHANGE_ME`)
- Fail fast with clear messages

---

## Filesystem Rules

- Never assume global writable paths (e.g. `/out`, `/tmp` for persistent data)
- Always use managed directories:
  - `${WORKDIR}`
  - `${SERVICE_DIR}`
- Create directories explicitly
- Ensure correct permissions before use

---

## Docker / Compose Rules

- Use `docker compose`
- Use explicit image tags (never `latest`)
- Use bind mounts for persistence
- Keep stacks self-contained per service
- Do not introduce orchestration layers

---

## TLS / Certificate Rules

- Reuse step-ca integration patterns
- Store certs under service-specific directories
- Do not write certs to global paths
- Keep certificate handling consistent across services

---

## NetBox-Specific Rules

- Must follow all general service rules
- Must include:
  - NetBox
  - PostgreSQL
  - Redis
- Must remain single-node

NetBox requires step-ca for certificate issuance in the current Provider Box design.
This is an intentional bootstrap dependency, not an accidental runtime coupling.

### IPAM Seeding Model

- Create one IP address object per unique address (including mask)
- Do not create duplicate IP objects for multiple FQDNs pointing to the same address

- The canonical Provider Box host IP must not be created from DNS record imports
- It must be created explicitly using `HOST_IP` and `PROVIDER_BOX_FQDN`

- Use:
  - `PROVIDER_BOX_FQDN` as the canonical dns_name for the host IP
  - Built-in service FQDNs must be stored in the IP object description as generated metadata

- When CIDR is available:
  - Use the provided mask for the IP address object
  - Create the corresponding prefix object
  - When CIDR information is available, a corresponding prefix object must be created in NetBox

- When CIDR is not available:
  - Use `/32` for the IP address object
  - Do not infer or guess prefixes

- All NetBox seeding must remain idempotent

### Configuration

- Enforce strong `NETBOX_SECRET_KEY` (>= 50 chars)
- Reject placeholder credentials
- Use explicit image tag

### Filesystem

- All data under `${NETBOX_DIR}`
- Certificates under `${NETBOX_DIR}/certs`
- Never use `/out`

### Seeding (if implemented)

- Use NetBox API only
- Import:
  - Provider Box service endpoints
  - DNS records from `config/unbound.records`
- Keep model simple
- Ensure idempotency

---

## Service Independence

Unless a dependency is already intentional and documented, services must remain independently deployable.

Examples:
- NetBox must not require Unbound
- Unbound must not require NetBox

Cross-service integrations must be additive, not mandatory.

### Cross-Service Behavior

- NetBox seeding must not require Unbound to be deployed
- Unbound configuration must not depend on NetBox
- Shared configuration (e.g. DNS records) must be usable independently by each service
- NetBox must not depend on Unbound-generated DNS blocks for its data model

---

## Implementation Guidelines

- Read existing modules before writing new ones
- Match naming and structure
- Keep functions small and readable
- Avoid introducing new languages

---

## What NOT to Do

- No Kubernetes
- No HA / clustering
- No production-grade patterns
- No reverse proxies unless already established
- No silent error handling
- No floating versions

---

## Testing & Validation

After changes:

1. Run service bootstrap
2. Verify containers/services
3. Verify DNS resolution
4. Check expected files exist
5. Re-run bootstrap (idempotency check where applicable)

---

## Output Expectations

- Short summary
- Minimal diffs or full files
- No TODOs
- Code must be runnable

---

## Decision Rule

If unsure:

- Choose the simplest solution
- Stay consistent with existing services
- Do not change working behavior
