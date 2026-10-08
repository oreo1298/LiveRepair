#!/usr/bin/env bash
# Boot-test a LiveRepair ISO in QEMU.
#
#   scripts/qemu-test.sh ISO [RESULTS_DIR]
#
# 1. Self-test: boots the ISO's kernel with "liverepair.selftest" (and the serial console),
#    which makes the live session check every application (see
#    profile/airootfs/usr/local/bin/liverepair-selftest) and report on the serial port.
#    A screenshot is taken of the desktop and of each application's window.
# 2. UEFI and BIOS boots of the ISO as it is, with screenshots of the boot menu and the desktop.
#
# Needs qemu-system-x86_64, OVMF (UEFI firmware), socat and xorriso; uses KVM when available.
# Exits non-zero unless the self-test reports RESULT PASS.
set -euo pipefail

iso=$(realpath "$1")
results=$(realpath -m "${2:-test-results}")
mkdir -p "$results"
tmp=$(mktemp -d)
trap 'pkill -f "qemu-system-x86_64.*$tmp" 2>/dev/null || true; rm -rf "$tmp"' EXIT

if [[ -w /dev/kvm ]]; then
    accel=(-accel kvm -cpu host); boot_wait=150; selftest_timeout=900
else
    echo "warning: no KVM, using slow emulation" >&2
    accel=(-accel tcg -cpu max); boot_wait=900; selftest_timeout=3600
fi
ovmf=""
for f in /usr/share/ovmf/OVMF.fd /usr/share/edk2/x64/OVMF.4m.fd /usr/share/OVMF/OVMF.fd; do
    [[ -e $f ]] && { ovmf=$f; break; }
done

qemu() {  # qemu NAME ARGS...: start QEMU in the background with a monitor socket
    local name=$1; shift
    qemu-system-x86_64 -machine q35 "${accel[@]}" -smp 4 -m 4096 -vga std -display none \
        -monitor "unix:$tmp/$name.mon,server=on,wait=off" \
        -serial "file:$results/serial-$name.log" "$@" >"$results/qemu-$name.log" 2>&1 &
    echo $!
}

screenshot() {  # screenshot NAME FILE
    echo "screendump $results/$2.png -f png" | socat - "UNIX-CONNECT:$tmp/$1.mon" >/dev/null
    sleep 1
    echo "screenshot: $2.png"
}

stop() {  # stop NAME PID (QEMU runs detached, so poll instead of wait)
    echo quit | socat - "UNIX-CONNECT:$tmp/$1.mon" >/dev/null 2>&1 || true
    for _ in {1..20}; do kill -0 "$2" 2>/dev/null || return 0; sleep 0.5; done
    kill -9 "$2" 2>/dev/null || true
}

disk() {  # a blank SATA disk for the applications to find
    qemu-img create -q -f qcow2 "$tmp/$1.qcow2" 8G
    echo "-drive file=$tmp/$1.qcow2,if=none,id=$1,format=qcow2 -device ide-hd,drive=$1,bus=ide.1,serial=LIVEREPAIR-$1"
}

# ---- 1. self-test
xorriso -osirrox on -indev "$iso" \
    -extract /arch/boot/x86_64/vmlinuz-linux "$tmp/vmlinuz" \
    -extract /arch/boot/x86_64/initramfs-linux.img "$tmp/initramfs.img" >/dev/null 2>&1
uuid=$(blkid -p -o value -s UUID "$iso")
echo "Self-test boot (ISO UUID $uuid)"
# shellcheck disable=SC2046
pid=$(qemu selftest -kernel "$tmp/vmlinuz" -initrd "$tmp/initramfs.img" \
    -append "archisobasedir=arch archisosearchuuid=$uuid cow_spacesize=50% console=tty0 console=ttyS0,115200 liverepair.selftest" \
    -drive "file=$iso,if=none,id=cd,media=cdrom,readonly=on" -device ide-cd,drive=cd,bus=ide.0 \
    $(disk selftest))

log=$results/serial-selftest.log
shots=0
result=""
for (( t = 0; t < selftest_timeout; t += 2 )); do
    sleep 2
    kill -0 "$pid" 2>/dev/null || { echo "QEMU stopped" >&2; break; }
    [[ -e $log ]] || continue
    mapfile -t requested < <(grep -a -o 'LIVEREPAIR-SHOT [A-Za-z0-9_-]*' "$log" | cut -d' ' -f2)
    while (( shots < ${#requested[@]} )); do
        screenshot selftest "selftest-$(printf %02d $shots)-${requested[$shots]}"
        shots=$((shots + 1))
    done
    if result=$(grep -a -o 'LIVEREPAIR-SELFTEST: RESULT.*' "$log"); then
        break
    fi
done
[[ -n $result ]] || screenshot selftest selftest-timeout
stop selftest "$pid"

echo
echo "---- self-test report"
grep -a 'LIVEREPAIR-SELFTEST\|    | ' "$log" | tr -d '\r' || true
echo "----"

# ---- 2. the ISO as users boot it
boot() {  # boot NAME FIRMWARE_ARGS...
    local name=$1; shift
    echo "Boot: $name"
    local pid
    # shellcheck disable=SC2046
    pid=$(qemu "$name" "$@" -drive "file=$iso,if=none,id=cd,media=cdrom,readonly=on" \
        -device ide-cd,drive=cd,bus=ide.0,bootindex=0 $(disk "$name"))
    sleep 6
    screenshot "$name" "$name-1-menu"
    sleep "$boot_wait"
    screenshot "$name" "$name-2-desktop"
    stop "$name" "$pid"
}
if [[ -n $ovmf ]]; then
    boot uefi -bios "$ovmf"
else
    echo "warning: no OVMF firmware found, skipping the UEFI boot" >&2
fi
boot bios

echo
if [[ $result == "LIVEREPAIR-SELFTEST: RESULT PASS"* ]]; then
    echo "Self-test passed."
else
    echo "Self-test failed: ${result:-no result (timed out)}" >&2
    exit 1
fi
