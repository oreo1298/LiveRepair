#!/usr/bin/env bash
# Boot-test a LiveRepair ISO in QEMU, from an emulated DVD drive, the way users boot it.
#
#   scripts/qemu-test.sh ISO [RESULTS_DIR]
#
# 1. UEFI with Secure Boot on, Microsoft's keys in the firmware like on a PC, and the ISO's key
#    enrolled (MOK list), default boot entry: the full self-test, which checks every
#    application, its tools, services and passwordless admin access, and does real work with
#    them (see profile/airootfs/usr/local/bin/liverepair-selftest). Screenshots of each window.
# 2. UEFI with Secure Boot on, without the ISO's key (a PC it has not booted on yet): shim
#    must refuse to start GRUB and start MokManager, to enroll the key.
# 3. UEFI with Secure Boot off: checks the desktop and the theme.
# 4. BIOS, "copy to RAM" boot entry (picked with simulated key presses): checks the desktop,
#    the theme, and that the DVD is no longer in use.
# An ISO built without Secure Boot (SECUREBOOT=0) gets the full self-test with it off instead
# of 1-3.
#
# The self-test is switched on through QEMU's firmware configuration (-fw_cfg), so the ISO
# boots with its own, unchanged boot entries. It reports on the serial port.
#
# Needs qemu-system-x86_64, OVMF (UEFI firmware, also its Secure Boot build), socat, xorriso,
# openssl and virt-fw-vars (virt-firmware); uses KVM when available.
# Exits non-zero unless every boot passes.
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

# The ISO's Secure Boot key (its certificate), which MokManager would enroll from the disc
cert=""
if xorriso -osirrox on -indev "$iso" -extract /ENROLL_THIS_KEY_IN_MOKMANAGER.cer "$tmp/secureboot.cer" \
        >/dev/null 2>&1; then
    cert=$tmp/secureboot.pem
    openssl x509 -inform DER -in "$tmp/secureboot.cer" -out "$cert"
    echo "Secure Boot key: $(openssl x509 -in "$cert" -noout -subject)"
    sb_code="" sb_vars=""
    for f in /usr/share/OVMF/OVMF_CODE_4M.secboot.fd /usr/share/edk2/x64/OVMF_CODE.secboot.4m.fd \
             /usr/share/edk2/ovmf/OVMF_CODE.secboot.fd; do
        [[ -e $f ]] && { sb_code=$f; break; }
    done
    for f in /usr/share/OVMF/OVMF_VARS_4M.fd /usr/share/edk2/x64/OVMF_VARS.4m.fd /usr/share/edk2/ovmf/OVMF_VARS.fd; do
        [[ -e $f ]] && { sb_vars=$f; break; }
    done
    [[ -n $sb_code && -n $sb_vars ]] || { echo "error: no Secure Boot build of OVMF found" >&2; exit 1; }
    command -v virt-fw-vars >/dev/null ||
        { echo "error: virt-fw-vars not found (python3-virt-firmware, or: pip install virt-firmware)" >&2; exit 1; }
fi

# secureboot_firmware NAME [mok]: QEMU arguments for UEFI with Secure Boot on: Microsoft's
# keys, as on PCs (virt-fw-vars --enroll-redhat), and with "mok", the ISO's key enrolled
secureboot_firmware() {
    local vars=$tmp/$1-vars.fd mok=()
    [[ ${2-} == mok ]] && mok=(--add-mok 605dab50-e046-4300-abb6-3dd810dd8b23 "$cert")
    virt-fw-vars --input "$sb_vars" --enroll-redhat --secure-boot "${mok[@]}" --output "$vars" >/dev/null 2>&1 ||
        { echo "error: virt-fw-vars could not set up the Secure Boot keys" >&2; return 1; }
    printf '%s\n' -global driver=cfi.pflash01,property=secure,value=on \
        -drive "if=pflash,format=raw,unit=0,readonly=on,file=$sb_code" -drive "if=pflash,format=raw,unit=1,file=$vars"
}

monitor() {  # monitor NAME COMMAND: a QEMU monitor command
    echo "$2" | socat - "UNIX-CONNECT:$tmp/$1.mon" >/dev/null 2>&1
}

screenshot() {  # screenshot NAME FILE
    monitor "$1" "screendump $results/$2.png -f png"
    sleep 1
    echo "  screenshot: $2.png"
}

# boot NAME MODE EXPECTED KEYS FIRMWARE_ARGS...
#   MODE: the self-test to run (boot, full), or "mokmanager": shim must refuse to start GRUB
#         and start MokManager instead, as on a PC without the ISO's key
#   EXPECTED: what the self-test must report: BIOS, UEFI (with Secure Boot off) or UEFI+SB
#         (Secure Boot on, and the ISO's key enrolled)
#   KEYS: keys to press in the boot menu ("-" for none), e.g. "down ret"
boot() {
    local name=$1 mode=$2 expected=$3 keys=$4; shift 4
    local log=$results/serial-$name.log
    echo "Boot: $name (self-test: $mode)"
    qemu-img create -q -f qcow2 "$tmp/$name.qcow2" 8G     # a blank SATA disk for the apps to find
    # smm: OVMF's Secure Boot build needs it
    qemu-system-x86_64 -machine q35,smm=on "${accel[@]}" -smp 4 -m 6144 -vga std -display none \
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

    local shots=0 result="" requested=() refused=0
    for (( t = 0; t < timeout; t += 2 )); do
        sleep 2
        kill -0 "$pid" 2>/dev/null || { echo "  QEMU stopped" >&2; break; }
        [[ -e $log ]] || continue
        if [[ $mode == mokmanager ]]; then
            # shim: "Verification failed: (0x1A) Security Violation" [OK], then MokManager
            if (( ! refused )) && grep -aq "Verification failed" "$log"; then
                screenshot "$name" "$name-1-verification-failed"
                monitor "$name" "sendkey ret"
                refused=1
            elif (( refused )) && grep -aq "Shim UEFI key management" "$log"; then
                screenshot "$name" "$name-2-mokmanager"
                result="MokManager started"
                break
            fi
            continue
        fi
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

    if [[ $mode == mokmanager ]]; then
        if [[ -z $result ]]; then
            echo "$name: FAILED: shim did not start MokManager (refused GRUB: $refused)" >&2
            return 1
        fi
        echo "$name: passed ($result)"
        return 0
    fi

    echo "---- $name: self-test report"
    grep -a 'LIVEREPAIR-SELFTEST\|    | ' "$log" | tr -d '\r' || true
    echo "----"
    if [[ $result != "LIVEREPAIR-SELFTEST: RESULT PASS"* ]]; then
        echo "$name: FAILED: ${result:-no result within ${timeout}s}" >&2
        return 1
    fi
    local firmware=${expected%+SB} secureboot=disabled
    [[ $expected == *+SB ]] && secureboot=enabled
    if ! grep -aq "LIVEREPAIR-SELFTEST: INFO firmware $firmware" "$log"; then
        echo "$name: FAILED: did not boot with $firmware firmware" >&2
        return 1
    fi
    if [[ $firmware == UEFI ]] && ! grep -aq "LIVEREPAIR-SELFTEST: INFO secure boot: $secureboot" "$log"; then
        echo "$name: FAILED: Secure Boot is not $secureboot" >&2
        return 1
    fi
    if [[ $secureboot == enabled ]] && ! grep -aq "LIVEREPAIR-SELFTEST: INFO secure boot key: .* is already enrolled" "$log"; then
        echo "$name: FAILED: the live system does not see its Secure Boot key enrolled" >&2
        return 1
    fi
    echo "$name: passed"
}

status=0
if [[ -n $cert ]]; then
    mapfile -t firmware < <(secureboot_firmware uefi-secureboot-dvd mok)
    boot uefi-secureboot-dvd full UEFI+SB - "${firmware[@]}" || status=1
    mapfile -t firmware < <(secureboot_firmware uefi-secureboot-key-not-enrolled)
    boot uefi-secureboot-key-not-enrolled mokmanager - - "${firmware[@]}" || status=1
    boot uefi-dvd boot UEFI - -bios "$ovmf" || status=1
else
    echo "The ISO has no Secure Boot key (built with SECUREBOOT=0): testing with Secure Boot off"
    boot uefi-dvd full UEFI - -bios "$ovmf" || status=1
fi
boot bios-dvd-copytoram boot BIOS "down ret" || status=1

echo
if (( status == 0 )); then echo "All boot tests passed."; else echo "Boot tests failed." >&2; fi
exit $status
