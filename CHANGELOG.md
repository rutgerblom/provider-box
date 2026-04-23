# Changelog

All notable changes to this project will be documented in this file.

---

## 2026-04-23

### Improvements
- Align Keycloak bootstrap realm defaults with VCF 9, including client settings, redirect URI, and bootstrap user email support.
- Be sure to update your `config/provider-box.env`.

### Fixes
- Fix certificate handling for step-ca-dependent services to reuse existing certificates and reissue only on identity mismatch or expiration

## 2026-04-21

### Features
- Add nginx-based VCF offline depot service
- Add optional SFTPGo backup-user bootstrap with validation, API-based provisioning, and idempotent create-if-missing behavior

### Improvements
- Centralize container image versions in provider-box.env
- Align default Keycloak bootstrap username with admin
- Normalize default persistent service paths under `/opt/provider-box`
- Move default runtime working directory to `/opt/provider-box/runtime`

### Fixes
- Fix depot certificate issuance failure caused by incorrect directory permissions for step-ca
- Preserve nginx runtime variables correctly in depot config rendering
- Fix depot basic auth by making the managed htpasswd file readable by nginx
- Harden certificate directory preparation for step-ca-dependent services
- Add post-start readiness checks for HTTPS services to fail fast when containers do not become reachable
- Fix Keycloak readiness checks by probing the user-facing HTTPS endpoint instead of `/health`
- Fix SFTPGo startup failure caused by SQLite “readonly database” errors by ensuring rw bind-mounted persistent directories are recursively owned by the container runtime user (UID:GID 1000:1000)
- Fix NetBox PostgreSQL startup failure caused by incorrect ownership on the bind-mounted data directory

---

## 2026-04-20

**Release: v0.1.0**

### Features
- Initial Provider Box release
- Add bootstrap support for DNS, NTP, syslog, step-ca, Keycloak, NetBox, SeaweedFS, and SFTPGo
- Add an nginx-based VCF offline depot service with HTTP and HTTPS support
- Add step-ca-based certificate handling for containerized HTTPS services
- Add initial Keycloak realm bootstrap support for VCF-style integration

### Improvements
- Improve README structure, service documentation, and architecture overview
- Add Docker-service remove support for containerized services
- Improve CA password handling to avoid a repository-shipped static password file
- Improve NetBox seeding for Provider Box service endpoints
