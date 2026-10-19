#!/usr/bin/env bash
# Build the LiveRepair ISO.
#
# Runs as root on Arch Linux or an Arch-based system (CachyOS, EndeavourOS, Manjaro...), or in an
# Arch Linux container (scripts/build-in-docker.sh). On a computer of its own it installs the
# build tools it is missing and a "builder" user (makepkg does not run as root), but does not
# update the system; the packages in the ISO are downloaded fresh either way.
#   1. builds the applications into pacman packages with their own PKGBUILDs,
#      from the default branch of their GitHub repositories, and the tools in packages/
#      that are not in Arch's repositories (hfsprogs and apfsprogs for ManageDisks)
#   2. puts the packages in a local pacman repository
#   3. builds the ISO from profile/ with mkarchiso, with that repository added
#   4. makes it boot with Secure Boot on (scripts/secureboot.sh): shim, and GRUB, the kernel and
#      Memtest86+ signed with this computer's own key, made in keys/ on the first build
#   5. checks that the ISO fits on a single-layer DVD and that firmware can boot it from one
#
# Environment:
#   OUT_DIR    where the ISO goes (default: ./out)
#   WORK_DIR   scratch space, about 10 GB (default: ./work)
#   APP_SRC_<Repository>=/path   build an application from a local checkout instead of
#                                cloning it, e.g. APP_SRC_DiskHealth=~/src/DiskHealth
#   KEEP_WORK=1                  keep the mkarchiso work directory afterwards
#   SECUREBOOT=0                 leave Secure Boot out (the ISO then boots only with it off)
#   SECUREBOOT_KEY, SECUREBOOT_CERT   sign with this key and certificate instead of keys/
set -euo pipefail
shopt -s inherit_errexit   # also stop on errors inside $(...), e.g. in build_pkg

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
out_dir=$(realpath -m "${OUT_DIR:-$here/out}")
work_dir=$(realpath -m "${WORK_DIR:-$here/work}")
github=https://github.com/oreo1298
# one timestamp for the whole build: the ISO's version, label and file dates
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(date +%s)}

# repository           package             directory of its PKGBUILD
apps=(
    "CloneAndRecover    cloneandrecover     ."
    "RecoverAll         recoverall          ."
    "DiskHealth         diskhealth          ."
    "TM5Linux           tm5linux            packaging/arch"
    "FastCopyLinux      fastcopy-linux-git  packaging/arch"
    "ImgBurnLinux       linburn             packaging/arch/local"
    "WindowsUSBLinux    rufux               ."
    "VirtConvert        virtconvert         ."
    "ManageDisks        managedisks-git     packaging/arch"
    "WizTreeLinux       dendro              packaging/arch"
)
# A single-layer DVD±R holds 4,700,372,992 bytes
dvd_size=4700372992

msg() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

(( EUID == 0 )) || die "run as root (mkarchiso needs it): sudo ./build.sh"
command -v pacman >/dev/null ||
    die "run on Arch Linux or an Arch-based system, or build in a container: sudo scripts/build-in-docker.sh"

msg "Installing the build tools"
# grub: mkarchiso builds the UEFI boot loader with the host's grub-mkstandalone.
# sbsigntools: scripts/secureboot.sh signs with it.
# Each PKGBUILD's own makedepends are installed before it is built (build_pkg).
tools=(archiso grub git base-devel sbsigntools)
if [[ ${LIVEREPAIR_CONTAINER-} == 1 ]]; then
    pacman -Syu --noconfirm --needed "${tools[@]}"     # a throwaway container: bring it up to date
else
    pacman -S --noconfirm --needed "${tools[@]}" ||    # this computer: leave its updates to its owner
        die "could not install the build tools; update this system (sudo pacman -Syu) and try again"
fi

# makepkg refuses to run as root
id builder &>/dev/null || useradd --create-home --shell /bin/bash builder

src_dir=$work_dir/src
pkg_dir=$work_dir/pkg
repo_dir=$work_dir/repo
profile_dir=$work_dir/profile
rm -rf "$src_dir" "$pkg_dir" "$repo_dir" "$profile_dir" "$work_dir/pacman-db" "$work_dir/mkarchiso"
mkdir -p "$src_dir" "$pkg_dir" "$repo_dir" "$out_dir"
chown builder: "$pkg_dir"

# The ISO's programs must run on any x86-64 PC, whatever this computer's makepkg.conf says (some
# Arch-based systems, such as CachyOS, may compile for newer CPUs only): its settings, with Arch's
# generic compiler flags and package format
makepkg_conf=$work_dir/makepkg.conf
{
    cat /etc/makepkg.conf
    cat <<'CONF'

# ---- LiveRepair (build.sh): Arch Linux's generic x86-64 flags
CFLAGS="-march=x86-64 -mtune=generic -O2 -pipe -fno-plt -fexceptions -Wp,-D_FORTIFY_SOURCE=3 -Wformat -Werror=format-security -fstack-clash-protection -fcf-protection -fno-omit-frame-pointer -mno-omit-leaf-frame-pointer"
CXXFLAGS="$CFLAGS -Wp,-D_GLIBCXX_ASSERTIONS"
LDFLAGS="-Wl,-O1 -Wl,--sort-common -Wl,--as-needed -Wl,-z,relro -Wl,-z,now -Wl,-z,pack-relative-relocs"
LTOFLAGS="-flto=auto"
RUSTFLAGS="-Cforce-frame-pointers=yes"
PKGEXT='.pkg.tar.zst'
CONF
} >"$makepkg_conf"

release_info=$work_dir/liverepair-release
iso_version=$(date --date="@$SOURCE_DATE_EPOCH" +%Y.%m.%d)
printf 'LiveRepair %s\n\n' "$iso_version" >"$release_info"

# build_pkg DIR [CHECKOUT]: install the makedepends of DIR/PKGBUILD, build it as the builder
# user and copy the package to the local repository; prints the package file.
# CHECKOUT: FastCopyLinux's PKGBUILD clones its sources itself unless FASTCOPY_SOURCE says otherwise
build_pkg() {
    local dir=$1 checkout=${2-} name deps pkg
    name=$(cd "$dir" && runuser -u builder -- makepkg --config "$makepkg_conf" --printsrcinfo |
        awk -F ' = ' '/^pkgname = / { print $2; exit }')
    mapfile -t deps < <(cd "$dir" && runuser -u builder -- makepkg --config "$makepkg_conf" --printsrcinfo |
        awk -F ' = ' '/^\tmakedepends(_x86_64)? = / { sub(/[<>=].*/, "", $2); print $2 }' | sort -u)
    if (( ${#deps[@]} )); then
        pacman -S --noconfirm --needed --asdeps "${deps[@]}" >&2
    fi
    (cd "$dir" &&
        runuser -u builder -- env PKGDEST="$pkg_dir" ${checkout:+FASTCOPY_SOURCE="git+file://$checkout"} \
            makepkg --config "$makepkg_conf" --force --nodeps --nocheck --noconfirm >&2)
    # (compiled packages also get a -debug package, which the ISO does not need)
    pkg=$(find "$pkg_dir" -name "$name-*.pkg.tar.zst" ! -name "$name-debug-*" | head -n1)
    [[ -n $pkg ]] || die "makepkg did not produce a $name package"
    cp "$pkg" "$repo_dir/"
    echo "$pkg"
}

for app in "${apps[@]}"; do
    read -r repo pkgname pkgbuild_dir <<<"$app"
    msg "Building $repo ($pkgname)"
    var=APP_SRC_$repo
    if [[ -n "${!var-}" ]]; then
        cp -a "${!var}" "$src_dir/$repo"
        rm -rf "$src_dir/$repo"/{src,pkg,dist,build}
    else
        git clone --quiet "$github/$repo.git" "$src_dir/$repo"
    fi
    # PKGBUILDs that clone their own repository from GitHub (ManageDisks): build this checkout
    sed -i "s#git+$github/$repo\.git#git+file://$src_dir/$repo#" "$src_dir/$repo/$pkgbuild_dir/PKGBUILD"
    chown -R builder: "$src_dir/$repo"

    pkg=$(build_pkg "$src_dir/$repo/$pkgbuild_dir" "$src_dir/$repo")
    [[ $(pacman -Qp "$pkg" | cut -d' ' -f1) == "$pkgname" ]] || die "$repo built $(basename "$pkg"), not $pkgname"
    version=$(pacman -Qp "$pkg" | cut -d' ' -f2)
    commit=$(git -c safe.directory="*" -C "$src_dir/$repo" log -1 --format='%h %cs' 2>/dev/null || echo "local")
    branch=$(git -c safe.directory="*" -C "$src_dir/$repo" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "-")
    printf '%-18s %-26s %s/%s @ %s (%s)\n' "$pkgname" "$version" "$github" "$repo" "$commit" "$branch" \
        >>"$release_info"
done

# Tools that are not in Arch's repositories, from packages/ in this repository
for dir in "$here"/packages/*/; do
    name=$(basename "$dir")
    msg "Building $name (packages/$name)"
    cp -a "$dir" "$src_dir/packages-$name"
    chown -R builder: "$src_dir/packages-$name"
    pkg=$(build_pkg "$src_dir/packages-$name")
    printf '%-18s %-26s %s\n' "$(pacman -Qp "$pkg" | cut -d' ' -f1)" "$(pacman -Qp "$pkg" | cut -d' ' -f2)" \
        "packages/$name in LiveRepair" >>"$release_info"
done

msg "Creating the local package repository"
repo-add --quiet "$repo_dir/liverepair.db.tar.gz" "$repo_dir"/*.pkg.tar.zst
cat "$release_info"

msg "Preparing the archiso profile"
cp -a "$here/profile" "$profile_dir"
install -Dm644 "$release_info" "$profile_dir/airootfs/etc/liverepair-release"
# the local repository goes first, so that its packages win
awk -v repo="$repo_dir" '
    /^\[core\]/ && !done { print "[liverepair]\nSigLevel = Optional TrustAll\nServer = file://" repo "\n"; done = 1 }
    { print }' "$here/profile/pacman.conf" >"$profile_dir/pacman.conf"
if [[ ${SECUREBOOT-1} != 0 ]]; then
    msg "Preparing for Secure Boot"
    "$here/scripts/secureboot.sh" prepare "$work_dir/secureboot" "$profile_dir"
fi

msg "Checking that every package in packages.x86_64 exists"
mkdir -p "$work_dir/pacman-db"
pacman --config "$profile_dir/pacman.conf" --dbpath "$work_dir/pacman-db" -Sy >/dev/null
mapfile -t packages < <(sed 's/#.*//' "$profile_dir/packages.x86_64" | awk 'NF { print $1 }')
pacman --config "$profile_dir/pacman.conf" --dbpath "$work_dir/pacman-db" -Sp \
    --print-format '%s' "${packages[@]}" |
    awk '{ total += $1; n++ } END { printf "%d packages, %.0f MiB to download\n", n, total / 1048576 }'

msg "Building the ISO"
mkarchiso -v -w "$work_dir/mkarchiso" -o "$out_dir" "$profile_dir"

if [[ ${SECUREBOOT-1} != 0 ]]; then
    msg "Signing for Secure Boot"
    "$here/scripts/secureboot.sh" sign "$work_dir/secureboot" "$work_dir/mkarchiso"
    msg "Building the ISO again, with the signed files"
    # mkarchiso skips the steps its work directory says are done: all but writing the ISO
    for step in iso._build_iso_image build._build_buildmode_iso; do
        [[ -e $work_dir/mkarchiso/$step ]] || die "mkarchiso's work directory has no $step (has mkarchiso changed?)"
        rm "$work_dir/mkarchiso/$step"
    done
    mkarchiso -v -w "$work_dir/mkarchiso" -o "$out_dir" "$profile_dir"
fi

iso=$(find "$out_dir" -maxdepth 1 -name "liverepair-$iso_version-x86_64.iso" | head -n1)
[[ -n $iso ]] || die "mkarchiso did not produce an ISO"
if [[ ${SECUREBOOT-1} != 0 ]]; then
    xorriso -indev "$iso" -find /EFI/BOOT -name grubx64.efi 2>/dev/null | grep -q grubx64 ||
        die "$(basename "$iso") was not built again with the signed files"
fi
cp "$release_info" "$out_dir/liverepair-$iso_version-apps.txt"
pkglist=$work_dir/mkarchiso/iso/arch/pkglist.x86_64.txt
[[ -e $pkglist ]] && cp "$pkglist" "$out_dir/liverepair-$iso_version-packages.txt"
(cd "$out_dir" && sha256sum "$(basename "$iso")" >"$(basename "$iso").sha256")
[[ ${KEEP_WORK-} == 1 ]] || rm -rf "$work_dir/mkarchiso"

size=$(stat -c %s "$iso")
(( size <= dvd_size )) ||
    die "$(basename "$iso") is $size bytes, too big for a single-layer DVD ($dvd_size bytes)"

# Booting from a DVD, UEFI firmware reads the EFI boot image only as far as its El Torito boot
# catalog entry says: a 16-bit count of 512-byte sectors, so 32 MiB at most. A bigger image is
# recorded as 0, which some firmware takes as "the rest of the disc" (QEMU does) and much real
# firmware does not ("Error opening root path: Device error").
bad=$(xorriso -indev "$iso" -report_el_torito plain 2>/dev/null | awk '
    /^El Torito boot img :/ { platform[$6] = $7; load[$6] = $12 }
    /^El Torito img blks :/ { blocks[$6] = $7 }
    END {
        for (i in platform)
            if (platform[i] == "UEFI" && (load[i] == 0 || load[i] * 512 < blocks[i] * 2048))
                printf "%d MiB EFI boot image, but the boot catalog covers %d KiB\n", blocks[i] * 2048 / 1048576, load[i] / 2
    }')
[[ -z $bad ]] || die "$(basename "$iso") would not boot from a DVD on many PCs: $bad"
grep -q "El Torito boot img : .* UEFI " < <(xorriso -indev "$iso" -report_el_torito plain 2>/dev/null) ||
    die "$(basename "$iso") has no UEFI El Torito boot image"

if [[ ${SECUREBOOT-1} != 0 ]]; then
    secureboot="boots with Secure Boot on or off"
else
    secureboot="boots with Secure Boot off"
fi
msg "Done: $iso ($(numfmt --to=iec --suffix=B "$size"), fits on and boots from a DVD, $secureboot)"
