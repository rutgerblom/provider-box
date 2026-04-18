#!/usr/bin/env bash

cleanup_legacy_unbound_config() {
  local legacy_conf="/etc/unbound/unbound.conf.d/sddc.conf"
  local target_conf="/etc/unbound/unbound.conf.d/provider-box.conf"

  if [[ -f "${legacy_conf}" && "${legacy_conf}" != "${target_conf}" ]]; then
    rm -f "${legacy_conf}"
  fi
}

do_unbound() {
  validate_records_file
  common_pkgs
  unbound_pkgs
  configure_resolv_conf
  cleanup_legacy_unbound_config
  build_dns_record_block
  render_template "${TEMPLATE_DIR}/unbound.conf.tpl" /etc/unbound/unbound.conf.d/provider-box.conf
  require_command unbound-checkconf
  unbound-checkconf
  systemctl enable unbound
  systemctl restart unbound
  ufw allow 53/tcp || true
  ufw allow 53/udp || true
}
