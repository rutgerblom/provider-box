#!/usr/bin/env bash

do_ntp() {
  common_pkgs
  ntp_pkgs
  systemctl disable systemd-timesyncd || true
  systemctl stop systemd-timesyncd || true
  render_template "${TEMPLATE_DIR}/chrony.conf.tpl" /etc/chrony/chrony.conf
  systemctl enable chrony
  systemctl restart chrony
  ufw allow 123/udp || true
}
