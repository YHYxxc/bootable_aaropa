# Bass OS repair overlay for the live USB. Sourced by aaropa-prebuilt.sh.
#
#   ISO:    boot/grub/repair.cfg and a hook in boot/grub/grub.cfg that adds
#           "Repair an existing installation" (start installs without their
#           android.cfg, or boot into the repair tool with BASS_REPAIR=1).
#   rootfs: /usr/bin/bass-repair, /usr/bin/bass-live-start, JWM start + menu entry.
#
# Android.mk later runs sed s|CMDLINE|..| (also OS_TITLE, VER, BlissOSLive) on
# grub.cfg, first match per line. The hook only uses CMDLINE on the bass_safe_args
# line and keeps the other words out entirely.

AAROPA_REPAIR_OVERLAY="${AAROPA_ROOT}/overlay"
AAROPA_REPAIR_BEGIN="# Bass: repair menu for installed systems (overlay/iso/boot/grub/repair.cfg)"
AAROPA_REPAIR_END="# Bass: end of repair menu"

# aaropa_repair_grub_hook TOOL -> grub.cfg lines; TOOL=1 when install.sfs has bass-repair.
aaropa_repair_grub_hook() {
  echo "$AAROPA_REPAIR_BEGIN"
  cat <<'EOF'
set bass_safe_args="CMDLINE"
set bass_usb="$root"
EOF
  [[ "${1:-0}" == 1 ]] && echo 'set bass_repair_tool=1'
  cat <<'EOF'
export bass_safe_args
export bass_usb
export bass_repair_tool
export KERNEL
export KERNEL_ARGS
export INITRD
export iso
source /boot/grub/repair.cfg
bass_repair_menu
EOF
  echo "$AAROPA_REPAIR_END"
}

# aaropa_apply_repair_iso ISO_DIR TOOL
aaropa_apply_repair_iso() {
  local iso="$1" tool="${2:-0}" cfg
  cfg="${iso}/boot/grub/grub.cfg"
  [[ -f "$cfg" ]] || aaropa_die "no boot/grub/grub.cfg in $iso"
  install -m 644 "${AAROPA_REPAIR_OVERLAY}/iso/boot/grub/repair.cfg" "${iso}/boot/grub/repair.cfg"
  HOOK="$(aaropa_repair_grub_hook "$tool")" BEGIN="$AAROPA_REPAIR_BEGIN" END="$AAROPA_REPAIR_END" awk '
    $0 == ENVIRON["BEGIN"] { skip = 1; next }
    skip && $0 == ENVIRON["END"] { skip = 0; next }
    skip { next }
    !done && /^efi_detect[[:space:]]*$/ { print ENVIRON["HOOK"]; done = 1 }
    { print }
    END { if (!done) print ENVIRON["HOOK"] }
  ' "$cfg" >"${cfg}.tmp"
  mv -f "${cfg}.tmp" "$cfg"
  aaropa_log "added repair menu to boot/grub/grub.cfg (repair tool: ${tool})"
}

# aaropa_apply_repair_rootfs ROOTFS_DIR -> 0 when the tool is wired into the session.
aaropa_apply_repair_rootfs() {
  local root="$1" jwmrc
  install -D -m 755 "${AAROPA_REPAIR_OVERLAY}/rootfs/usr/bin/bass-repair" "${root}/usr/bin/bass-repair"
  install -D -m 755 "${AAROPA_REPAIR_OVERLAY}/rootfs/usr/bin/bass-live-start" "${root}/usr/bin/bass-live-start"

  jwmrc="${root}/root/.jwmrc"
  if [[ ! -f "$jwmrc" ]]; then
    aaropa_log "warning: no /root/.jwmrc in rootfs; bass-repair not wired into the live session"
    return 1
  fi
  local menu_done=0
  grep -q 'bass-repair</Program>' "$jwmrc" && menu_done=1
  awk -v menu_done="$menu_done" '
    /<StartupCommand>/ { in_start = 1 }
    in_start { sub(/bash -c \/usr\/bin\/aaropa-calamares/, "/usr/bin/bass-live-start") }
    /<\/StartupCommand>/ { in_start = 0 }
    { print }
    !menu_done && /aaropa-calamares<\/Program>/ {
      line = $0
      sub(/label="[^"]*"/, "label=\"Repair an existing installation\"", line)
      sub(/bash -c \/usr\/bin\/aaropa-calamares/, "qterminal -e /usr/bin/bass-repair", line)
      print line
      menu_done = 1
    }
  ' "$jwmrc" >"${jwmrc}.tmp"
  mv -f "${jwmrc}.tmp" "$jwmrc"

  if ! grep -q '/usr/bin/bass-live-start' "$jwmrc" || ! grep -q 'bass-repair</Program>' "$jwmrc"; then
    aaropa_log "warning: could not wire bass-repair into /root/.jwmrc"
    return 1
  fi
  aaropa_log "added bass-repair to the live session"
  return 0
}

# aaropa_apply_repair_sfs SFS -> unpack a fetched install.sfs, add the rootfs overlay,
# repack. Needs podman (unshare keeps file ownership without sudo).
aaropa_apply_repair_sfs() {
  local sfs="$1" work rc=0
  if ! command -v podman >/dev/null 2>&1 || ! command -v unsquashfs >/dev/null 2>&1 ||
    ! command -v mksquashfs >/dev/null 2>&1; then
    aaropa_log "warning: podman/squashfs-tools missing; fetched install.sfs keeps no bass-repair tool"
    return 1
  fi
  work="${AAROPA_CACHE_DIR}/repair-sfs"
  podman unshare rm -rf "$work"
  mkdir -p "$work"
  aaropa_log "adding bass-repair to fetched install.sfs"
  podman unshare unsquashfs -q -d "${work}/root" "$sfs" >/dev/null || aaropa_die "unsquashfs failed: $sfs"
  # Inside the namespace: unpacked files keep their image owners (subuids outside it).
  podman unshare bash -c "$(declare -f aaropa_log aaropa_apply_repair_rootfs)
    AAROPA_REPAIR_OVERLAY=\"\$1\"
    aaropa_apply_repair_rootfs \"\$2\"" bash "$AAROPA_REPAIR_OVERLAY" "${work}/root" || rc=1
  if [[ "$rc" -eq 0 ]]; then
    podman unshare mksquashfs "${work}/root" "${sfs}.new" -noappend -comp zstd >/dev/null ||
      aaropa_die "mksquashfs failed for $sfs"
    mv -f "${sfs}.new" "$sfs"
  fi
  podman unshare rm -rf "$work"
  return "$rc"
}
