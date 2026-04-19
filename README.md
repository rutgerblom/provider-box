# Provider Box

Provider Box is a lightweight, single-node bootstrap framework for standing up shared infrastructure services on a dedicated **provider services node**.

It is designed for lab and homelab environments, especially VMware Cloud Foundation (VCF), where external infrastructure services must be self-contained and reproducible.

---

## Table of Contents

- [Quick Start](#quick-start)
- [Choosing Services](#choosing-services)
- [Configuration Model](#configuration-model)
- [Service Overview](#service-notes)
- [VCF Lab Companion](#vcf-lab-companion)
- [Design Trade-offs](#design-trade-offs)
- [Repository Layout](#repository-layout)
- [Development Safeguards](#development-safeguards-optional)
- [Failure Handling](#failure-handling)
- [Operational Notes](#operational-notes)
- [Scope](#scope)

---

## Quick Start

1. Copy the example configuration:

cp config/provider-box.env.example config/provider-box.env
cp config/unbound.records.example config/unbound.records

2. Replace placeholder secrets:

PASSWORD='VMware1!VMware1!' \
SECRET_KEY=$(openssl rand -base64 48) \
&& sed -i \
  -e "s/CHANGE_ME_WITH_AT_LEAST_50_RANDOM_CHARACTERS_BEFORE_USE/$SECRET_KEY/g" \
  -e "s/CHANGE_ME/$PASSWORD/g" \
  config/provider-box.env

3. Deploy services:

sudo bash bootstrap/provider-box.sh --unbound
sudo bash bootstrap/provider-box.sh --ntp
sudo bash bootstrap/provider-box.sh --rsyslog
sudo bash bootstrap/provider-box.sh --ca
sudo bash bootstrap/provider-box.sh --keycloak
sudo bash bootstrap/provider-box.sh --netbox
sudo bash bootstrap/provider-box.sh --s3
sudo bash bootstrap/provider-box.sh --sftp

Or deploy everything:

sudo bash bootstrap/provider-box.sh --all

---

## Choosing Services

Minimum required:
- Unbound (DNS)
- Chrony (NTP)

Recommended:
- rsyslog
- step-ca
- Keycloak
- NetBox

Optional:
- SeaweedFS (S3)
- SFTPGo

---

## Configuration Model

All configuration is defined in:

config/provider-box.env

Validation is strict and fails fast.

---

## Service Notes

See individual service sections for details.

---

## Scope

Provider Box is intended for lab and PoC environments only.
