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

    if prop ro.vendor.build.fingerprint | grep -q '^Lenovo/TB-9707F'; then
        y700_checks "$display"
    fi

    echo
    echo "$pass passed, $fail failed"
    echo "Manual: enroll a face in Settings > Security, lock, unlock with it;"
    echo "        toggle Adaptive brightness and cover the light sensor."
    [ "$fail" -eq 0 ]
}

# Lenovo Legion Y700 (2022) specifics. Runs inside check(), so it shares
# result()/prop() and the relaxed error handling.
y700_checks() {
    local display="$1" sensors rate
    echo
    echo "--- Lenovo Legion Y700 (2022)"
    "$ADB" shell cmd overlay list android | grep -qF '[x] me.phh.treble.overlay.lenovo.y700_2022'
    result "Y700 overlay enabled" $?
    ! "$ADB" shell pm list features | grep -q 'android.hardware.telephony'
    result "telephony features removed (Wi-Fi only)" $?
    [ -z "$("$ADB" shell pidof com.android.phone | tr -d '\r')" ]
    result "com.android.phone not running" $?
    rate="$(grep -m1 -oE 'renderFrameRate [0-9.]+' <<<"$display" | awk '{print int($2 + 0.5)}')"
    [ "${rate:-0}" -ge 120 ]; result "panel at 120 Hz (now ${rate:-?})" $?
    "$ADB" shell dumpsys input | grep -q 'Headset Jack'; result "headset jack input device" $?
    sensors="$("$ADB" shell dumpsys sensorservice | tr -d '\r')"
    grep -q 'ah1902 Hall Effect Sensor Wakeup' <<<"$sensors"; result "hall sensor (cover wake/sleep)" $?
    grep -qiE 'ambient light|light sensor|\| *light' <<<"$sensors"; result "light sensor" $?

    echo
    echo "--- Y700 info for manual follow-up"
    echo "cameras:       $("$ADB" shell dumpsys media.camera | grep -m1 -E 'Number of camera devices' | tr -d '\r')"
    echo "DT2W node:     $("$ADB" shell 'ls /proc/gesture_control /sys/devices/virtual/touch/tp_dev/gesture_on 2>/dev/null' | tr -d '\r' | tr '\n' ' ')"
    echo "pen input:     $("$ADB" shell dumpsys input | grep -m1 -oE 'NVTCapacitivePen' | tr -d '\r')"
    echo "color mgmt:    use_color_management=$(prop ro.surface_flinger.use_color_management) vndk=$(prop ro.vndk.version)"
    echo "DP extcon:     (system_server got EACCES here on another GSI)"
    "$ADB" shell 'ls -Z /sys/devices/platform/soc/soc:qcom,msm-ext-disp/extcon/*/cable.*/name 2>/dev/null' | sed 's/^/               /'
    echo "audio switch:  $("$ADB" shell 'ls /sys/class/switch 2>/dev/null' | tr -d '\r' | tr '\n' ' ')"
    echo "microSD:       $("$ADB" shell sm list-disks | tr -d '\r' | tr '\n' ' ')"
    echo "game lever:    $("$ADB" shell getevent -pl 2>/dev/null | grep -A6 -m1 'gpio-keys' | grep -oE 'KEY_[A-Z0-9_]+|SW_[A-Z_]+' | sort -u | tr '\n' ' ')"
    echo "Manual: headphones in the jack, DP monitor audio, pen, DT2W in Phh Treble Settings > Lenovo, cover close/open."
}

case "${1:-}" in
    install) install "${2:?usage: dsu-test.sh install <image.img.xz> [userdata GiB]}" "${3:-8}" ;;
    check) check ;;
    *) sed -n '3,15p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
