#!/usr/bin/env bash
# Boot-test a LiveRepair ISO in QEMU, from an emulated DVD drive, the way users boot it.
#
#   scripts/qemu-test.sh ISO [RESULTS_DIR]
#
# 1. UEFI, default boot entry: the full self-test, which checks every application, its tools,
#    services and passwordless admin access, and does real work with them (see
#    profile/airootfs/usr/local/bin/liverepair-selftest). Screenshots of each window.
# 2. BIOS, "copy to RAM" boot entry (picked with simulated key presses): checks the desktop,
#    the theme, and that the DVD is no longer in use.
#
# The self-test is switched on through QEMU's firmware configuration (-fw_cfg), so the ISO
# boots with its own, unchanged boot entries. It reports on the serial port.
#
# Needs qemu-system-x86_64, OVMF (UEFI firmware) and socat; uses KVM when available.
# Exits non-zero unless both boots report RESULT PASS on the expected firmware.
set -euo pipefail

iso=$(realpath "$1")
results=$(realpath -m "${2:-test-results}")
mkdir -p "$results"
tmp=$(mktemp -d)
trap 'pkill -f "qemu-system-x86_64.*$tmp" 2>/dev/null || true; rm -rf "$tmp"' EXIT

if [[ -w /dev/kvm ]]; then
    accel=(-accel kvm -cpu host); timeout=900
else
    echo "warning: no KVM, using slow emulation" >&2
    accel=(-accel tcg -cpu max); timeout=5400
fi
ovmf=""
for f in /usr/share/ovmf/OVMF.fd /usr/share/edk2/x64/OVMF.4m.fd /usr/share/OVMF/OVMF.fd; do
    [[ -e $f ]] && { ovmf=$f; break; }
done
[[ -n $ovmf ]] || { echo "error: no OVMF (UEFI firmware) found" >&2; exit 1; }

monitor() {  # monitor NAME COMMAND: a QEMU monitor command
    echo "$2" | socat - "UNIX-CONNECT:$tmp/$1.mon" >/dev/null 2>&1
}

screenshot() {  # screenshot NAME FILE
    monitor "$1" "screendump $results/$2.png -f png"
    sleep 1
    echo "  screenshot: $2.png"
}

# boot NAME MODE EXPECTED_FIRMWARE KEYS FIRMWARE_ARGS...
#   KEYS: keys to press in the boot menu ("-" for none), e.g. "down ret"
boot() {
    local name=$1 mode=$2 firmware=$3 keys=$4; shift 4
    local log=$results/serial-$name.log
    echo "Boot: $name (self-test: $mode)"
    qemu-img create -q -f qcow2 "$tmp/$name.qcow2" 8G     # a blank SATA disk for the apps to find
    qemu-system-x86_64 -machine q35 "${accel[@]}" -smp 4 -m 6144 -vga std -display none \
        -monitor "unix:$tmp/$name.mon,server=on,wait=off" -serial "file:$log" \
        -fw_cfg "name=opt/liverepair/selftest,string=$mode" \
        -drive "file=$iso,if=none,id=dvd,media=cdrom,readonly=on" -device ide-cd,drive=dvd,bus=ide.0,bootindex=0 \
        -drive "file=$tmp/$name.qcow2,if=none,id=hd,format=qcow2" -device ide-hd,drive=hd,bus=ide.1,serial=LIVEREPAIR-HD \
        "$@" >"$results/qemu-$name.log" 2>&1 &
    local pid=$!

    sleep 6
    screenshot "$name" "$name-0-boot-menu"
    if [[ $keys != - ]]; then
        for key in $keys; do monitor "$name" "sendkey $key"; sleep 1; done
        screenshot "$name" "$name-1-entry-chosen"
    fi

    local shots=0 result="" requested=()
    for (( t = 0; t < timeout; t += 2 )); do
        sleep 2
        kill -0 "$pid" 2>/dev/null || { echo "  QEMU stopped" >&2; break; }
        [[ -e $log ]] || continue
        mapfile -t requested < <(grep -a -o 'LIVEREPAIR-SHOT [A-Za-z0-9_-]*' "$log" | cut -d' ' -f2)
        while (( shots < ${#requested[@]} )); do
            screenshot "$name" "$name-$(printf %02d $((shots + 2)))-${requested[$shots]}"
            shots=$((shots + 1))
        done
        result=$(grep -a -o 'LIVEREPAIR-SELFTEST: RESULT.*' "$log" | tr -d '\r') && break
    done
    [[ -n $result ]] || screenshot "$name" "$name-99-timeout"
    monitor "$name" quit || true
    for _ in {1..20}; do kill -0 "$pid" 2>/dev/null || break; sleep 0.5; done
    kill -9 "$pid" 2>/dev/null || true

    echo "---- $name: self-test report"
    grep -a 'LIVEREPAIR-SELFTEST\|    | ' "$log" | tr -d '\r' || true
    echo "----"
    if [[ $result != "LIVEREPAIR-SELFTEST: RESULT PASS"* ]]; then
        echo "$name: FAILED: ${result:-no result within ${timeout}s}" >&2
        return 1
    fi
    if ! grep -aq "LIVEREPAIR-SELFTEST: INFO firmware $firmware" "$log"; then
        echo "$name: FAILED: did not boot with $firmware firmware" >&2
        return 1
    fi
    echo "$name: passed"
}

status=0
boot uefi-dvd full UEFI - -bios "$ovmf" || status=1
boot bios-dvd-copytoram boot BIOS "down ret" || status=1

echo
if (( status == 0 )); then echo "All boot tests passed."; else echo "Boot tests failed." >&2; fi
exit $status
