#!/usr/bin/env bash

do_unbound() {
  validate_records_file
  common_pkgs
  unbound_pkgs
  configure_resolv_conf
  build_dns_record_block
  render_template "${TEMPLATE_DIR}/unbound.conf.tpl" /etc/unbound/unbound.conf.d/provider-box.conf
  require_command unbound-checkconf
  unbound-checkconf
  systemctl enable unbound
  systemctl restart unbound
  ufw allow 53/tcp || true
  ufw allow 53/udp || true
}
