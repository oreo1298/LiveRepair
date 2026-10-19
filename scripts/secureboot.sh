#!/usr/bin/env bash
# Secure Boot for the LiveRepair ISO, used by build.sh.
#
# With Secure Boot on, a PC starts only boot loaders signed with a key in its firmware. Almost
# every PC has Microsoft's third-party UEFI CA there, which signs shim, the small first-stage
# boot loader that Linux distributions use (this is Ubuntu's). shim starts GRUB only if it is
# signed with a key in the PC's MOK list (Machine Owner Keys) or its firmware, and GRUB starts
# the kernel and Memtest86+ only if shim says they are, too. The ISO's GRUB, kernel and
# Memtest86+ are signed with the builder's own key: made on the first build in keys/ and reused
# by the next ones, so that each PC needs it enrolled only once. Where it is not, shim starts
# MokManager by itself, to enroll it from the disc (ENROLL_THIS_KEY_IN_MOKMANAGER.cer).
#
#   scripts/secureboot.sh prepare WORK PROFILE
#       make (or check) the key, download shim, and put the key's certificate in the live
#       system: WORK is a scratch directory, PROFILE build.sh's copy of profile/
#   scripts/secureboot.sh sign WORK MKARCHISO_WORK
#       after mkarchiso, in its work directory: build GRUB for shim, sign it, the kernel and
#       Memtest86+, and put shim, MokManager, GRUB and the certificate in the ISO's files and
#       in its EFI boot image; mkarchiso then builds the ISO again from them
#
# Environment:
#   SECUREBOOT_KEY, SECUREBOOT_CERT   sign with this private key (PEM) and its certificate (PEM
#                                     or DER) instead of keys/liverepair-secureboot.*, e.g. a
#                                     key the PCs already have enrolled
set -euo pipefail
shopt -s nullglob

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
key_dir=$root/keys

# shim and MokManager, signed by Microsoft and Canonical: Ubuntu's shim-signed package
shim_deb=shim-signed_1.59+15.8-0ubuntu2_amd64.deb
shim_sha256=f8ed71ce2d91a304b6d5eb84997f846f331b554578bc02dbfe78e13ad8ac81a9
shim_urls=(
    "https://archive.ubuntu.com/ubuntu/pool/main/s/shim-signed/$shim_deb"
    "https://launchpad.net/ubuntu/+archive/primary/+files/$shim_deb"
)
# the name MokManager shows when enrolling from the disc (Ventoy's name for the same thing)
enroll_name=ENROLL_THIS_KEY_IN_MOKMANAGER.cer

# GRUB's modules: mkarchiso's, plus the commands that grub.cfg and mkarchiso's embedded
# configuration use from modules it leaves to load on demand (test: "[", probe). With Secure
# Boot on, GRUB loads no modules ("prohibited by secure boot policy"), so all must be inside it.
grub_modules=(all_video at_keyboard boot btrfs cat chain configfile echo efifwsetup efinet exfat ext2 f2fs
              fat font gfxmenu gfxterm gzio halt hfsplus iso9660 jpeg keylayouts linux loadenv loopback
              lsefi lsefimmap minicmd normal ntfs ntfscomp part_apple part_gpt part_msdos png read reboot
              regexp search search_fs_file search_fs_uuid search_label serial sleep tpm udf usb
              usbserial_common usbserial_ftdi usbserial_pl2303 usbserial_usbdebug video xfs zstd
              test true probe ls terminal gettext)

msg() { printf '\033[1;34m  ->\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# keys WORK: sets key (PEM private key), crt (PEM certificate) and cer (DER certificate)
keys() {
    local work=$1
    if [[ -n ${SECUREBOOT_KEY-}${SECUREBOOT_CERT-} ]]; then
        [[ -r ${SECUREBOOT_KEY-} && -r ${SECUREBOOT_CERT-} ]] ||
            die "SECUREBOOT_KEY and SECUREBOOT_CERT must both name readable files"
        key=$SECUREBOOT_KEY
        crt=$work/secureboot.crt
        cer=$work/secureboot.cer
        openssl x509 -in "$SECUREBOOT_CERT" -out "$crt" 2>/dev/null ||
            openssl x509 -inform DER -in "$SECUREBOOT_CERT" -out "$crt" ||
            die "$SECUREBOOT_CERT is not an X.509 certificate"
        openssl x509 -in "$crt" -outform DER -out "$cer"
    else
        key=$key_dir/liverepair-secureboot.key
        crt=$key_dir/liverepair-secureboot.crt
        cer=$key_dir/liverepair-secureboot.cer
    fi
}

prepare() {
    local work=$1 profile=$2
    mkdir -p "$work"
    keys "$work"
    if [[ -z ${SECUREBOOT_KEY-} && ! -e $key ]]; then
        msg "Making a Secure Boot signing key in $key_dir (keep it, and keep it private)"
        mkdir -p "$key_dir"
        chmod 700 "$key_dir"
        (umask 077 && openssl req -new -x509 -newkey rsa:2048 -nodes -sha256 -days 36500 \
            -subj "/CN=LiveRepair Secure Boot ($(date +%Y-%m-%d))/" \
            -addext "basicConstraints=critical,CA:FALSE" \
            -addext "keyUsage=critical,digitalSignature" \
            -addext "extendedKeyUsage=codeSigning" \
            -keyout "$key" -out "$crt" 2>/dev/null)
        openssl x509 -in "$crt" -outform DER -out "$cer"
    fi
    [[ -e $crt && -e $cer ]] || die "$key has no certificate next to it ($crt, $cer)"
    [[ $(openssl pkey -in "$key" -pubout) == "$(openssl x509 -in "$crt" -noout -pubkey)" ]] ||
        die "the Secure Boot key and certificate do not belong together ($key, ${SECUREBOOT_CERT:-$crt})"
    msg "Signing with: $(openssl x509 -in "$crt" -noout -subject -nameopt utf8,sep_comma_plus)"
    msg "              SHA-1 fingerprint $(openssl x509 -in "$crt" -noout -fingerprint -sha1 | cut -d= -f2)"

    msg "Downloading shim ($shim_deb)"
    local deb=$work/$shim_deb url
    if [[ ! -e $deb ]] || ! sha256sum --status -c <<<"$shim_sha256  $deb"; then
        rm -f "$deb"
        for url in "${shim_urls[@]}"; do
            curl -fsSL --retry 3 -o "$deb" "$url" && break
            rm -f "$deb"
        done
        [[ -e $deb ]] || die "could not download $shim_deb"
        sha256sum --status -c <<<"$shim_sha256  $deb" ||
            die "$shim_deb does not have the expected SHA-256 checksum"
    fi
    rm -rf "$work/shim"
    mkdir -p "$work/shim"
    bsdtar -xOf "$deb" 'data.tar.*' |
        bsdtar -xf - -C "$work/shim" --strip-components 4 \
            ./usr/lib/shim/shimx64.efi.signed.latest ./usr/lib/shim/mmx64.efi
    mv "$work/shim/shimx64.efi.signed.latest" "$work/shim/shimx64.efi"

    # in the live system too, for mokutil (e.g. "mokutil --test-key", or "--delete" to remove it)
    install -Dm644 "$cer" "$profile/airootfs/usr/share/liverepair/secureboot.cer"
}

sign_file() {  # sign_file FILE: sign FILE in place with the key
    sbsign --key "$key" --cert "$crt" --output "$1.signed" "$1" >/dev/null
    sbverify --cert "$crt" "$1.signed" >/dev/null || die "the signature of $1 does not verify"
    mv "$1.signed" "$1"
}

sign() {
    local work=$1 mkarchiso_work=$2
    local isofs=$mkarchiso_work/iso efiboot=$mkarchiso_work/efiboot.img embed_cfg=$mkarchiso_work/grub-embed.cfg
    local f kernels memtest=$isofs/boot/memtest86+/memtest.efi boot_efi
    keys "$work"
    # the firmware's default boot loader, GRUB from mkarchiso: BOOTx64.EFI (FAT ignores case)
    boot_efi=$(find "$isofs/EFI/BOOT" -maxdepth 1 -iname bootx64.efi 2>/dev/null | head -n1)
    for f in "$boot_efi" "$efiboot" "$embed_cfg" "$work/shim/shimx64.efi"; do
        [[ -n $f && -e $f ]] || die "${f:-$isofs/EFI/BOOT/BOOTx64.EFI} is missing (has mkarchiso changed?)"
    done

    msg "Building GRUB for shim ($(grub-mkstandalone --version | awk '{ print $NF }'), SBAT: $(grep -v '^sbat,' /usr/share/grub/sbat.csv | cut -d, -f1,2 | paste -sd' '))"
    # mkarchiso's GRUB (same configuration), except that it does not leave the checking of what
    # it starts to the firmware (--disable-shim-lock) but asks shim, which knows the MOK list
    grub-mkstandalone -O x86_64-efi \
        --modules="${grub_modules[*]}" \
        --locales="en@quot" \
        --themes="" \
        --sbat=/usr/share/grub/sbat.csv \
        -o "$isofs/EFI/BOOT/grubx64.efi" "boot/grub/grub.cfg=$embed_cfg"

    msg "Signing GRUB, the kernel and Memtest86+"
    kernels=("$isofs"/*/boot/x86_64/vmlinuz-*)
    (( ${#kernels[@]} )) || die "no kernel in $isofs"
    for f in "$isofs/EFI/BOOT/grubx64.efi" "${kernels[@]}"; do
        sign_file "$f"
    done
    [[ -e $memtest ]] && sign_file "$memtest"

    msg "Adding shim, MokManager and the certificate"
    # shim takes GRUB's place as the firmware's default boot loader (BOOTX64.EFI), and starts
    # grubx64.efi, or mmx64.efi (MokManager) from the same folder. The UEFI shell stays unsigned
    # (GRUB offers it only with Secure Boot off), so does 32-bit UEFI's GRUB (no shim for it).
    install -m644 "$work/shim/shimx64.efi" "$boot_efi"
    install -m644 "$work/shim/mmx64.efi" "$isofs/EFI/BOOT/mmx64.efi"
    install -m644 "$cer" "$isofs/$enroll_name"
    # the EFI boot image, which firmware boots from: mkarchiso leaves room in it for this
    mcopy -o -i "$efiboot" "$boot_efi" "$isofs/EFI/BOOT/grubx64.efi" \
        "$isofs/EFI/BOOT/mmx64.efi" ::/EFI/BOOT/
    mcopy -o -i "$efiboot" "$cer" "::/$enroll_name"
    mdir -i "$efiboot" ::/EFI/BOOT
}

case ${1-} in
    prepare) (( $# == 3 )) || die "usage: $0 prepare WORK PROFILE"; prepare "$2" "$3" ;;
    sign) (( $# == 3 )) || die "usage: $0 sign WORK MKARCHISO_WORK"; sign "$2" "$3" ;;
    *) die "usage: $0 prepare WORK PROFILE | sign WORK MKARCHISO_WORK" ;;
esac
