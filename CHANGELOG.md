# Changelog

All notable changes to this project will be documented in this file.

## Unreleased

### Features
- Add nginx-based VCF offline depot service

### Improvements
- Centralize container image versions in provider-box.env
- Align default Keycloak bootstrap username with admin

### Fixes
- Fix depot certificate issuance failure caused by incorrect directory permissions for step-ca
- Fix: preserve nginx variables in depot config rendering

## v0.1.0 - 2026-04-20

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
