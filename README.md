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

- Ubuntu or Debian-based host (tested on Debian GNU/Linux 13 “trixie”)
- Root or `sudo` access
- Static IP already configured
- Access to package repositories
- Docker available for container-based services

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
