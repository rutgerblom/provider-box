# Homelab Infrastructure

This repository contains bootstrap scripts and configuration for non-Kubernetes infrastructure in the homelab.

## Scope

- DNS (Unbound)
- NTP (Chrony)
- Identity (Keycloak)

These services run on dedicated infrastructure (NUC) and are intentionally kept separate from Kubernetes (k3s).

## Structure

- bootstrap/ → scripts to provision hosts
- services/ → service-specific configs (source of truth)

## Notes

Kubernetes workloads are managed separately via GitOps in another repository.
