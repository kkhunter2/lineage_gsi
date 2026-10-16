#!/bin/bash
#
# Boot-test a build on a connected device with DSU (Dynamic System Updates).
# The installed system and its data stay untouched; a reboot returns to them.
#
# Usage:
#   lineage_gsi/scripts/dsu-test.sh install <image.img.xz> [userdata GiB, default 8]
#   lineage_gsi/scripts/dsu-test.sh check
#
# install  Pushes the image and starts the DSU installer. When its notification
#          says the install finished, tap Restart to boot the GSI.
# check    Run against the booted GSI (set up Wi-Fi and turn wireless debugging
#          back on there first). Prints PASS/FAIL per check, exits 1 on any FAIL.
#
# Set ADB=/path/to/adb (and ANDROID_SERIAL for several devices) as needed.

set -euo pipefail
ADB="${ADB:-adb}"

install() {
    local img="$1" userdata_gb="$2" work size dest
    work="$(mktemp -d)"
    trap 'rm -rf "$work"' EXIT

    # DSU reads raw or gzip images, not xz.
    echo "### Recompressing $(basename "$img") for DSU"
    xz -dc "$img" > "$work/system.img"
    size="$(stat -c %s "$work/system.img")"
    gzip -1 "$work/system.img"

    dest=/storage/emulated/0/Download/dsu-system.img.gz
    "$ADB" push "$work/system.img.gz" "$dest"
    "$ADB" shell setprop persist.sys.fflag.override.settings_dynamic_system true
    "$ADB" shell am start-activity \
        -n com.android.dynsystem/com.android.dynsystem.VerificationActivity \
        -a android.os.image.action.START_INSTALL \
        -d "file://$dest" \
        --el KEY_SYSTEM_SIZE "$size" \
        --el KEY_USERDATA_SIZE "$((userdata_gb * 1024 * 1024 * 1024))"
    echo "### Confirm on the device if asked, then tap Restart in the DSU notification."
}

check() {
    # A failing check must not abort the run, and "cmd | grep -q" must report
    # grep's status rather than the SIGPIPE the early exit gives cmd.
    set +e +o pipefail
    local pass=0 fail=0
    prop() { "$ADB" shell getprop "$1" | tr -d '\r'; }
    result() {
        if [ "$2" -eq 0 ]; then echo "PASS  $1"; pass=$((pass + 1));
        else echo "FAIL  $1"; fail=$((fail + 1)); fi
    }

    echo "build:           $(prop ro.lineage.display.version)"
    echo "fingerprint:     $(prop ro.build.fingerprint)"
    echo "security patch:  $(prop ro.build.version.security_patch)"
    echo "vendor:          $(prop ro.vendor.build.fingerprint)"
    echo "running via DSU: $( [ "$(prop ro.gsid.image_running)" = 1 ] && echo yes || echo no)"
    echo

    [ "$(prop sys.boot_completed)" = 1 ]; result "boot completed" $?

    [ "$(prop ro.face.sense_service)" = true ]; result "ro.face.sense_service=true" $?
    "$ADB" shell pm path co.aospa.sense | grep -q '^package:'; result "FaceUnlock app (co.aospa.sense) installed" $?
    # SenseProvider dumps a JSON blob with "service":"SenseProvider".
    "$ADB" shell dumpsys face | grep -q '"service":"SenseProvider"'; result "SenseProvider registered in dumpsys face" $?

    local display
    display="$("$ADB" shell dumpsys display | tr -d '\r')"
    grep -q 'mUseSoftwareAutoBrightnessConfig=true' <<<"$display"; result "auto-brightness enabled in config" $?
    # This section only exists when a brightness mapper was built from the curve.
    grep -q 'Automatic Brightness Controller Configuration:' <<<"$display"; result "auto-brightness controller created" $?

    "$ADB" shell pm path me.phh.treble.app | grep -q '^package:'; result "TrebleApp installed" $?

    echo
    echo "$pass passed, $fail failed"
    echo "Manual: enroll a face in Settings > Security, lock, unlock with it;"
    echo "        toggle Adaptive brightness and cover the light sensor."
    [ "$fail" -eq 0 ]
}

case "${1:-}" in
    install) install "${2:?usage: dsu-test.sh install <image.img.xz> [userdata GiB]}" "${3:-8}" ;;
    check) check ;;
    *) sed -n '3,15p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
