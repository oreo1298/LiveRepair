#!/usr/bin/env bash
# Build the LiveRepair ISO.
#
# Runs as root on Arch Linux (or in an Arch Linux container: scripts/build-in-docker.sh).
#   1. builds the applications into pacman packages with their own PKGBUILDs,
#      from the default branch of their GitHub repositories
#   2. puts the packages in a local pacman repository
#   3. builds the ISO from profile/ with mkarchiso, with that repository added
#   4. checks that the ISO fits on a single-layer DVD and that firmware can boot it from one
#
# Environment:
#   OUT_DIR    where the ISO goes (default: ./out)
#   WORK_DIR   scratch space, about 10 GB (default: ./work)
#   APP_SRC_<Repository>=/path   build an application from a local checkout instead of
#                                cloning it, e.g. APP_SRC_DiskHealth=~/src/DiskHealth
#   KEEP_WORK=1                  keep the mkarchiso work directory afterwards
set -euo pipefail

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
)
# A single-layer DVD±R holds 4,700,372,992 bytes
dvd_size=4700372992

msg() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

(( EUID == 0 )) || die "run as root (mkarchiso needs it)"
[[ -e /etc/arch-release ]] || die "run on Arch Linux, or use scripts/build-in-docker.sh"

msg "Installing the build tools"
pacman -Syu --noconfirm --needed archiso git base-devel python-build python-installer \
    python-setuptools python-wheel

# makepkg refuses to run as root
id builder &>/dev/null || useradd --create-home --shell /bin/bash builder

src_dir=$work_dir/src
pkg_dir=$work_dir/pkg
repo_dir=$work_dir/repo
profile_dir=$work_dir/profile
rm -rf "$src_dir" "$pkg_dir" "$repo_dir" "$profile_dir" "$work_dir/pacman-db" "$work_dir/mkarchiso"
mkdir -p "$src_dir" "$pkg_dir" "$repo_dir" "$out_dir"
chown builder: "$pkg_dir"

release_info=$work_dir/liverepair-release
iso_version=$(date --date="@$SOURCE_DATE_EPOCH" +%Y.%m.%d)
printf 'LiveRepair %s\n\n' "$iso_version" >"$release_info"

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
    chown -R builder: "$src_dir/$repo"

    # FASTCOPY_SOURCE: FastCopyLinux's PKGBUILD clones its sources itself; build this checkout
    (cd "$src_dir/$repo/$pkgbuild_dir" &&
        runuser -u builder -- env PKGDEST="$pkg_dir" FASTCOPY_SOURCE="git+file://$src_dir/$repo" \
            makepkg --force --nodeps --nocheck --noconfirm)

    pkg=$(find "$pkg_dir" -name "$pkgname-*.pkg.tar.zst" | head -n1)
    [[ -n $pkg ]] || die "makepkg did not produce a $pkgname package"
    cp "$pkg" "$repo_dir/"

    version=$(pacman -Qp "$pkg" | cut -d' ' -f2)
    commit=$(git -c safe.directory="*" -C "$src_dir/$repo" log -1 --format='%h %cs' 2>/dev/null || echo "local")
    branch=$(git -c safe.directory="*" -C "$src_dir/$repo" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "-")
    printf '%-18s %-26s %s/%s @ %s (%s)\n' "$pkgname" "$version" "$github" "$repo" "$commit" "$branch" \
        >>"$release_info"
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

msg "Checking that every package in packages.x86_64 exists"
mkdir -p "$work_dir/pacman-db"
pacman --config "$profile_dir/pacman.conf" --dbpath "$work_dir/pacman-db" -Sy >/dev/null
mapfile -t packages < <(sed 's/#.*//' "$profile_dir/packages.x86_64" | awk 'NF { print $1 }')
pacman --config "$profile_dir/pacman.conf" --dbpath "$work_dir/pacman-db" -Sp \
    --print-format '%s' "${packages[@]}" |
    awk '{ total += $1; n++ } END { printf "%d packages, %.0f MiB to download\n", n, total / 1048576 }'

msg "Building the ISO"
mkarchiso -v -w "$work_dir/mkarchiso" -o "$out_dir" "$profile_dir"

iso=$(find "$out_dir" -maxdepth 1 -name "liverepair-$iso_version-x86_64.iso" | head -n1)
[[ -n $iso ]] || die "mkarchiso did not produce an ISO"
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

msg "Done: $iso ($(numfmt --to=iec --suffix=B "$size"), fits on and boots from a DVD)"
