#!/bin/bash
#
# Offline checks on a built GSI before it is released: reads the ext4
# system.img directly, no device needed.
#
# Usage: lineage_gsi/scripts/inspect-image.sh [system.img] [release-dir]
#   Defaults: the newest out/target/product/*/system.img and the newest
#   release/<date>/ directory in the tree.
#
# Needs 7z (p7zip-full), e2fsck and the tree's prebuilt aapt2.
# Prints PASS/FAIL per check and exits 1 on any FAIL.

# No pipefail: "cmd | grep -q" must report grep's status, not the SIGPIPE cmd
# gets when grep exits on the first match.
set -u

TREE="${LOS_TREE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
RELEASE_CONFIG="${RELEASE_CONFIG:-bp4a}"
AAPT2="$TREE/prebuilts/sdk/tools/linux/bin/aapt2"
img="${1:-$(ls -t "$TREE"/out/target/product/*/system.img 2>/dev/null | head -1)}"
rel="${2:-$(ls -td "$TREE"/release/2*/ 2>/dev/null | head -1)}"
rel="${rel%/}"

for tool in 7z "$AAPT2"; do
    command -v "$tool" >/dev/null || { echo "missing: $tool" >&2; exit 2; }
done
e2fsck="$(command -v e2fsck || echo /usr/sbin/e2fsck)"
[ -f "$img" ] || { echo "no system.img (got '$img')" >&2; exit 2; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
pass=0; fail=0
result() {
    if [ "$2" -eq 0 ]; then echo "PASS  $1"; pass=$((pass + 1));
    else echo "FAIL  $1"; fail=$((fail + 1)); fi
}
get() { 7z x -so "$img" "$1" 2>/dev/null; }

echo "image:   $img ($(du -h "$img" | cut -f1))"
echo "release: ${rel:-none}"
"$e2fsck" -fn "$img" > "$work/fsck" 2>&1; result "e2fsck clean" $?

7z l -ba "$img" 2>/dev/null | awk '{print $NF}' > "$work/files"
echo "files in image: $(wc -l < "$work/files")"

for f in $(grep -E '(^|/)build\.prop$' "$work/files"); do get "$f"; done > "$work/props"
p() { grep -m1 "^$1=" "$work/props" | cut -d= -f2-; }
fingerprint="$(p ro.system.build.fingerprint)"
spl_tree="$(grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' \
    "$TREE/vendor/lineage/release/flag_values/$RELEASE_CONFIG/RELEASE_PLATFORM_SECURITY_PATCH.textproto" 2>/dev/null)"
echo "lineage version:   $(p ro.lineage.display.version)"
echo "build fingerprint: $fingerprint"
echo "security patch:    $(p ro.build.version.security_patch) (tree: ${spl_tree:-?})"
[ -n "$spl_tree" ] && [ "$(p ro.build.version.security_patch)" = "$spl_tree" ]
result "security patch matches the tree" $?

# Face unlock (FaceSense)
[ "$(p ro.face.sense_service)" = true ]; result "ro.face.sense_service=true" $?
grep -qE '/priv-app/FaceUnlock/FaceUnlock\.apk$' "$work/files"; result "FaceUnlock.apk present" $?
grep -qE 'permissions/android\.hardware\.biometrics\.face\.xml$' "$work/files"; result "face feature XML present" $?
get system/framework/services.jar > "$work/services.jar"
unzip -p "$work/services.jar" 'classes*.dex' | grep -aq 'com/android/server/biometrics/sensors/face/sense/SenseProvider'
result "SenseProvider compiled into services.jar" $?
grep -qiE 'TrebleApp[^/]*\.apk$' "$work/files"; result "TrebleApp present" $?

# Default auto-brightness curve (personal/platform_frameworks_base 0003)
get system/framework/framework-res.apk > "$work/fres.apk"
"$AAPT2" dump resources "$work/fres.apk" > "$work/res" 2>/dev/null
grep -A3 'bool/config_automatic_brightness_available' "$work/res" | grep -qE '^\s+\(\) true$'
result "config_automatic_brightness_available=true" $?
# aapt2 prints arrays as "() (array) size=N" followed by "[a, b, ...]".
arr() { python3 -I -c 'import re, sys
text = open(sys.argv[1]).read()
m = re.search(r"array/%s\n\s+\(\) \(array\) size=\d+\n\s+\[([^\]]*)\]" % re.escape(sys.argv[2]), text)
print(" ".join(re.findall(r"\d+", m.group(1))) if m else "")' "$work/res" "$1"; }
levels="$(arr config_autoBrightnessLevels)"
backlight="$(arr config_autoBrightnessLcdBacklightValues)"
echo "brightness levels:    $levels"
echo "brightness backlight: $backlight"
[ "$levels" = "2 8 30 120 400 1200 4000" ] && [ "$backlight" = "2 4 12 45 90 120 160 255" ]
result "default brightness curve in framework-res" $?

# Lenovo Legion Y700 (2022) (personal/platform_vendor_hardware_overlay 0002,
# personal/device_phh_treble 0011)
ov="$(grep -E 'overlay/treble-overlay-lenovo-y700_2022\.apk$' "$work/files" | head -1)"
[ -n "$ov" ]; result "Y700-2022 overlay in image (${ov:-missing})" $?
if [ -n "$ov" ]; then
    get "$ov" > "$work/y700.apk"
    "$AAPT2" dump resources "$work/y700.apk" > "$work/y700res" 2>/dev/null
    grep -A1 'integer/config_defaultRefreshRate$' "$work/y700res" | grep -qE '\(\) 120$'
    result "overlay: config_defaultRefreshRate=120" $?
    grep -A1 'bool/config_useDevInputEventForAudioJack' "$work/y700res" | grep -qE '\(\) true$'
    result "overlay: config_useDevInputEventForAudioJack=true" $?
    "$AAPT2" dump xmltree --file AndroidManifest.xml "$work/y700.apk" 2>/dev/null |
        grep -q '"+^Lenovo/TB-9707F"'
    result "overlay: matched on +^Lenovo/TB-9707F" $?
fi
xml="$(get system/phh/wifi-only-telephony.xml)"
grep -q 'unavailable-feature name="android.hardware.telephony"' <<<"$xml"
result "wifi-only-telephony.xml in /system/phh" $?
grep -q '<feature name="android.software.telecom"' <<<"$xml"
result "wifi-only-telephony.xml keeps android.software.telecom" $?
get system/bin/rw-system.sh | grep -qF "grep -qE '^Lenovo/TB-9707F'"
result "rw-system.sh has the Y700 telephony block" $?

# Release files
if [ -n "$rel" ]; then
    variant="$(sed -nE 's|^[^/]*/lineage_arm64_([^/]*)/.*|\1|p' <<<"$fingerprint")"
    for x in "$rel"/*.img.xz; do
        [ -e "$x" ] || { result "release has an .img.xz" 1; break; }
        (cd "$rel" && sha256sum -c --quiet "$(basename "$x").sha256"); result "sha256 of $(basename "$x")" $?
        [ "$(stat -c %s "$x")" -lt 2147483648 ]
        result "under GitHub's 2 GiB asset limit ($(du -h "$x" | cut -f1))" $?
        if [[ "$x" == *"arm64_$variant.img.xz" ]]; then
            [ "$(xz -dc "$x" | sha256sum | cut -d' ' -f1)" = "$(sha256sum "$img" | cut -d' ' -f1)" ]
            result "$(basename "$x") decompresses to this system.img" $?
        fi
    done
    [ -s "$rel/manifest-snapshot.xml" ]; result "manifest-snapshot.xml present" $?
    [ "$(cat "$rel/.commit" 2>/dev/null)" = "$(git -C "$TREE/lineage_gsi" rev-parse HEAD)" ]
    result "release .commit is the tree's lineage_gsi HEAD" $?
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
