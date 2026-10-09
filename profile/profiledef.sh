#!/usr/bin/env bash
# shellcheck disable=SC2034
#
# archiso profile for LiveRepair (based on the archiso "releng" profile, archiso v91).
# See https://gitlab.archlinux.org/archlinux/archiso/-/blob/master/docs/README.profile.rst

iso_name="liverepair"
iso_label="LIVEREPAIR_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="LiveRepair <https://github.com/oreo1298/LiveRepair>"
iso_application="LiveRepair Live/Rescue Media"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="arch"
bootmodes=('bios.syslinux'
           'uefi.grub')
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')
file_permissions=(
  ["/etc/sudoers.d"]="0:0:750"
  ["/etc/sudoers.d/10-liverepair"]="0:0:440"
  ["/usr/local/bin/liverepair-mkuser"]="0:0:755"
  ["/usr/local/bin/liverepair-session"]="0:0:755"
  ["/usr/local/bin/liverepair-selftest"]="0:0:755"
)
