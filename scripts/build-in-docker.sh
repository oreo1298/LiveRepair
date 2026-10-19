#!/usr/bin/env bash
# Build the LiveRepair ISO on any Linux host with Docker or Podman, in an Arch Linux container.
# The ISO lands in ./out, the Secure Boot signing key in ./keys. Needs about 10 GB of free
# disk space.
#
#   sudo scripts/build-in-docker.sh
#   sudo CONTAINER_ENGINE=podman scripts/build-in-docker.sh
#   sudo SECUREBOOT_KEY=my.key SECUREBOOT_CERT=my.crt scripts/build-in-docker.sh
#   sudo SECUREBOOT=0 scripts/build-in-docker.sh
#
# Uses Docker, or Podman when Docker is not installed or not running.
# On Arch Linux and Arch-based systems (CachyOS, EndeavourOS, Manjaro...) "sudo ./build.sh"
# also works, without a container.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

arch_hint=""
command -v pacman >/dev/null &&
    arch_hint=$'\n\nThis is an Arch-based system, so you can also build without a container:\n    sudo ./build.sh'

engine=${CONTAINER_ENGINE-}
if [[ -z $engine ]]; then
    if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
        engine=docker
    elif command -v podman >/dev/null; then
        engine=podman
    elif command -v docker >/dev/null && [[ -S /var/run/docker.sock ]]; then
        die "Docker is running, but this user may not use it. Run the script with sudo:
    sudo scripts/build-in-docker.sh$arch_hint"
    elif command -v docker >/dev/null; then
        die "Docker is installed, but its service is not running. Start it, then run this again:
    sudo systemctl start docker
(\"sudo systemctl enable --now docker\" also starts it at every boot)$arch_hint"
    else
        die "neither Docker nor Podman is installed. Install one of them (e.g. the \"docker\" or
\"podman\" package of your distribution), start it, and run this again$arch_hint"
    fi
fi

# a Secure Boot key of your own (see build.sh), passed in read-only
secureboot=(${SECUREBOOT:+--env SECUREBOOT="$SECUREBOOT"})
if [[ -n ${SECUREBOOT_KEY-}${SECUREBOOT_CERT-} ]]; then
    [[ -r ${SECUREBOOT_KEY-} && -r ${SECUREBOOT_CERT-} ]] ||
        die "SECUREBOOT_KEY and SECUREBOOT_CERT must both name readable files"
    secureboot+=(--volume "$(realpath "$SECUREBOOT_KEY"):/run/secureboot/key:ro"
                 --volume "$(realpath "$SECUREBOOT_CERT"):/run/secureboot/cert:ro"
                 --env SECUREBOOT_KEY=/run/secureboot/key --env SECUREBOOT_CERT=/run/secureboot/cert)
fi

# --privileged: mkarchiso mounts /proc, /sys and /dev inside the image it builds
# LIVEREPAIR_CONTAINER: build.sh may update the (throwaway) container's packages
exec "$engine" run --rm --privileged \
    --volume "$root:/liverepair" --workdir /liverepair \
    --env OUT_DIR=/liverepair/out --env WORK_DIR=/liverepair/work --env LIVEREPAIR_CONTAINER=1 \
    ${SOURCE_DATE_EPOCH:+--env SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH"} "${secureboot[@]}" \
    docker.io/archlinux/archlinux:latest \
    bash -c 'pacman-key --init && pacman-key --populate archlinux &&
             pacman -Sy --noconfirm --needed archlinux-keyring && ./build.sh'
