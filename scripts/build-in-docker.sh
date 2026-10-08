#!/usr/bin/env bash
# Build the LiveRepair ISO on any Linux host with Docker or Podman, in an Arch Linux container.
# The ISO lands in ./out. Needs about 10 GB of free disk space.
#
#   sudo scripts/build-in-docker.sh
#   CONTAINER_ENGINE=podman sudo -E scripts/build-in-docker.sh
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
engine=${CONTAINER_ENGINE:-docker}

# --privileged: mkarchiso mounts /proc, /sys and /dev inside the image it builds
exec "$engine" run --rm --privileged \
    --volume "$root:/liverepair" --workdir /liverepair \
    --env OUT_DIR=/liverepair/out --env WORK_DIR=/liverepair/work \
    ${SOURCE_DATE_EPOCH:+--env SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH"} \
    docker.io/archlinux/archlinux:latest \
    bash -c 'pacman-key --init && pacman-key --populate archlinux &&
             pacman -Sy --noconfirm --needed archlinux-keyring && ./build.sh'
