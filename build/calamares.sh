# Locally patched Calamares packages for Bass images, until the changes land in
# Ananda-Aropa: existing-install upgrade page (aaropa_calamares_modules_bass),
# keep-data install and multi-boot bootloader fixes (aaropa_calamares).
#
# Clones the [calamares.local] repos of aaropa.lock at their pins, applies the
# vendor/ax86-lite patches/calamares/<repo>/*.patch queues with git am, builds the
# .debs in the build/calamares Podman image against upstream Calamares
# <calamares_version>, and installs them in the installer image (04-image.sh).
# 05-export.sh then adds the existinginstall page to the image's Calamares settings.
# AAROPA_CALAMARES_PATCHES overrides the queue directory; AAROPA_CALAMARES_LOCAL=0
# skips all of it. Sourced by aaropa-prebuilt.sh.

AAROPA_CALAMARES_BUILD_TAG="localhost/bass-calamares-build:latest"

aaropa_calamares_patches_dir() {
  printf '%s\n' "${AAROPA_CALAMARES_PATCHES:-${AAROPA_ROOT}/../../vendor/ax86-lite/patches/calamares}"
}

aaropa_calamares_local_enabled() {
  case "${AAROPA_BRANDING:-}" in
    bass|bassos) ;;
    *) return 1 ;;
  esac
  [[ "${AAROPA_CALAMARES_LOCAL:-1}" == "1" ]] || return 1
  [[ -n "$(lock_get calamares.local repos)" ]]
}

aaropa_calamares_out() {
  printf '%s/calamares\n' "$AAROPA_CACHE_DIR"
}

aaropa_calamares_checkout() {
  local repo="$1" dir="$2" url ref patch
  url="$(lock_get_required calamares.local "${repo}.url")"
  ref="$(lock_get_required calamares.local "${repo}.ref")"
  if [[ -d "${dir}/.git" ]]; then
    git -C "$dir" am --abort >/dev/null 2>&1 || true
    git -C "$dir" reset -q --hard
    git -C "$dir" clean -qfdx
  fi
  aaropa_git_checkout "$url" "$ref" "$dir"
  for patch in "$(aaropa_calamares_patches_dir)/${repo}"/*.patch; do
    [[ -f "$patch" ]] || continue
    if ! git -C "$dir" -c user.name=aaropa-prebuilt -c user.email=aaropa-prebuilt@localhost \
      am -q --no-gpg-sign "$patch"; then
      git -C "$dir" am --abort >/dev/null 2>&1 || true
      aaropa_die "patch does not apply to ${repo}@${ref}: ${patch}"
    fi
    aaropa_log "${repo}: applied $(basename "$patch")"
  done
}

aaropa_build_calamares_debs() {
  local out ver repos repo src build tarball deb
  aaropa_calamares_local_enabled || return 0
  command -v podman >/dev/null 2>&1 || aaropa_die "patched Calamares needs podman (AAROPA_CALAMARES_LOCAL=0 to skip)"
  [[ -d "$(aaropa_calamares_patches_dir)" ]] \
    || aaropa_die "Calamares patch queues not found: $(aaropa_calamares_patches_dir) (set AAROPA_CALAMARES_PATCHES)"

  out="$(aaropa_calamares_out)"
  ver="$(lock_get_required calamares.local calamares_version)"
  repos="$(lock_get_required calamares.local repos)"
  mkdir -p "${out}/src"
  rm -rf "${out}/build" "${out}/debs"
  mkdir -p "${out}/build" "${out}/debs"

  tarball="${out}/calamares-${ver}.tar.gz"
  if [[ ! -d "${out}/calamares-${ver}" ]]; then
    [[ -s "$tarball" ]] || download_file "https://github.com/calamares/calamares/archive/refs/tags/v${ver}.tar.gz" "$tarball"
    tar -C "$out" -xzf "$tarball"
  fi

  aaropa_log "building Calamares build image ${AAROPA_CALAMARES_BUILD_TAG}"
  podman build -q -t "$AAROPA_CALAMARES_BUILD_TAG" -f "${AAROPA_ROOT}/build/calamares/Containerfile" \
    "${AAROPA_ROOT}/build/calamares" >/dev/null

  for repo in $repos; do
    src="${out}/src/${repo}"
    build="${out}/build/${repo}"
    aaropa_calamares_checkout "$repo" "$src"

    # Same tree as the repos' ci/setup.sh, but pinned to calamares_version instead of
    # ci/update-version.sh (latest upstream).
    mkdir -p "$build"
    git -C "$src" archive HEAD | tar -x -C "$build"
    cp -rn --update=none "${out}/calamares-${ver}/." "$build/" 2>/dev/null \
      || cp -rn "${out}/calamares-${ver}/." "$build/"
    rm -rf "${build}/debian"
    cp -r "${build}/ci/debian" "${build}/debian"
    sed -i -E "1s/\(([0-9]+\.)+[0-9]+-[0-9]+\)/(${ver}-1~bass)/" "${build}/debian/changelog"

    aaropa_log "building ${repo} .deb (Calamares ${ver})"
    podman run --rm -v "${out}/build:/build" -w "/build/${repo}" "$AAROPA_CALAMARES_BUILD_TAG" \
      dpkg-buildpackage -b -us -uc -d -j"$(nproc)" >"${out}/build/${repo}.log" 2>&1 \
      || aaropa_die "${repo} package build failed, see ${out}/build/${repo}.log"
  done

  for deb in "${out}"/build/*.deb; do
    [[ -f "$deb" ]] || continue
    case "$(basename "$deb")" in *-dbgsym_*) continue ;; esac
    mv -f "$deb" "${out}/debs/"
  done
  [[ -n "$(find "${out}/debs" -name '*.deb' -print -quit)" ]] || aaropa_die "no Calamares .deb was built"
  aaropa_log "patched Calamares packages: $(cd "${out}/debs" && echo *.deb)"
}

# Installs the built .debs in the installer image, right after its package list.
aaropa_calamares_add_to_context() {
  local ctx="$1" out
  aaropa_calamares_local_enabled || return 0
  out="$(aaropa_calamares_out)"
  [[ -n "$(find "${out}/debs" -name '*.deb' -print -quit 2>/dev/null)" ]] || return 0

  mkdir -p "${ctx}/bass-debs"
  cp -f "${out}"/debs/*.deb "${ctx}/bass-debs/"
  grep -q 'pkglist.cfg' "${ctx}/Dockerfile" || aaropa_die "installer Dockerfile has no pkglist.cfg step"
  awk '
    { print }
    !done && /^RUN .*pkglist\.cfg/ {
      print ""
      print "# Locally patched Calamares (bootable/aaropa build/calamares.sh)"
      print "COPY bass-debs /tmp/bass-debs"
      print "RUN apt install -y --allow-downgrades --no-install-recommends /tmp/bass-debs/*.deb && rm -rf /tmp/bass-debs"
      done = 1
    }
  ' "${ctx}/Dockerfile" >"${ctx}/Dockerfile.new"
  mv -f "${ctx}/Dockerfile.new" "${ctx}/Dockerfile"
  aaropa_log "installer image gets patched Calamares packages"
}

# aaropa_calamares_settings SETTINGS_CONF BOOTLOADER_CONF
# Shows existinginstall before the partition page and runs its job right after the
# partition job; gives every Bass install its own EFI directory (BassOS, BassOS1, ...).
aaropa_calamares_settings() {
  local settings="$1" bootloader="$2"
  if ! grep -qE '^[[:space:]]*-[[:space:]]+existinginstall[[:space:]]*$' "$settings"; then
    awk '
      /^- show:/ { sect = "show" }
      /^- exec:/ { sect = "exec" }
      /^[[:space:]]*-[[:space:]]+partition[[:space:]]*$/ {
        indent = $0
        sub(/-.*/, "", indent)
        if (sect == "show") { print indent "- existinginstall"; print; next }
        if (sect == "exec") { print; print indent "- existinginstall"; next }
      }
      { print }
    ' "$settings" >"${settings}.new"
    mv -f "${settings}.new" "$settings"
  fi
  [[ "$(grep -cE '^[[:space:]]*-[[:space:]]+existinginstall[[:space:]]*$' "$settings")" == 2 ]] \
    || aaropa_die "could not add existinginstall to show and exec in $settings"

  if [[ -f "$bootloader" ]]; then
    sed -i -E 's/^efiBootloaderId:.*/efiBootloaderId: "BassOS${SERIAL}"/' "$bootloader"
    grep -q '^efiBootloaderId: "BassOS${SERIAL}"' "$bootloader" \
      || printf '%s\n' 'efiBootloaderId: "BassOS${SERIAL}"' >>"$bootloader"
  fi
}

aaropa_apply_calamares_local() {
  local root="$1"
  aaropa_calamares_local_enabled || return 0
  [[ -n "$(find "$(aaropa_calamares_out)/debs" -name '*.deb' -print -quit 2>/dev/null)" ]] || return 0
  [[ -f "${root}/etc/calamares/settings.conf" ]] || aaropa_die "image has no /etc/calamares/settings.conf"
  find "${root}"/usr/lib -path '*/calamares/modules/existinginstall/module.desc' -print -quit | grep -q . \
    || aaropa_die "existinginstall module missing from the image"
  aaropa_log "adding existinginstall page to Calamares settings"
  aaropa_calamares_settings "${root}/etc/calamares/settings.conf" "${root}/etc/calamares/modules/bootloader.conf"
}
