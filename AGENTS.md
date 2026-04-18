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
