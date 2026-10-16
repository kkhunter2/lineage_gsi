English | [한국어](README.ko.md)

# lineage_gsi — LineageOS 23.2 GSI

Unofficial LineageOS 23.2 (Android 16 QPR2) Generic System Image for arm64 A/B
Treble devices.

This continues [MisterZtr/LineageOS_gsi](https://github.com/MisterZtr/LineageOS_gsi),
which has had no updates since 2026-05-24. The patch set is the same, plus:

- **Face unlock restored.** The FaceSense stack (`co.aospa.sense`) was dropped
  upstream when 23.2 was rebased onto the RestlessOS patch set. It is a software,
  front-camera face unlock, so it needs no face HAL from the vendor.
- **Adaptive brightness works without a vendor curve.** framework-res now
  ships a default lux → backlight curve. Devices whose vendor overlay already
  defines one keep using their own.
- **Fresh LineageOS 23.2 sources.** Each release is synced against current
  LineageOS, so it carries newer security patches than the last upstream build.

## Download

Get the image from [Releases](https://github.com/kkhunter2/lineage_gsi/releases).

| Variant | Meaning |
|---|---|
| `arm64_bgN4` | arm64, GApps (MindTheGapps), ext4, userdebug |

Each release also ships a `.sha256` and `manifest-snapshot.xml`, which pins
every project revision used for that build.

## Install

1. Decompress: `xz -d lineage-23.2-*-arm64_bgN4.img.xz`
2. Reboot to fastbootd (`adb reboot fastboot`) and flash:
   ```
   fastboot flash system lineage-23.2-*-arm64_bgN4.img
   fastboot reboot
   ```
   Coming from another LineageOS 23.x GSI, a dirty flash (no wipe) works.
   From anything else, wipe data (`fastboot -w`).
3. Or try it without touching `system` using [DSU Sideloader](https://github.com/VegaBobo/DSU-Sideloader).

Builds are signed with test keys. Use at your own risk; how well a GSI runs
depends on how closely the vendor followed Treble.

### Tested devices

- Lenovo Legion Y700 2022 (TB-9707F, SD870, WiFi-only). Device support is
  built in, so no Magisk modules are needed:
  - starts at 120 Hz (AOSP otherwise caps this panel at 60 Hz),
  - 3.5 mm headset detection through the jack's input device,
  - telephony features and UI removed, which stops `com.android.phone`
    from looping on a modem that isn't there,
  - cover wake/sleep from the hall sensor (TrebleApp, which matches the
    stock `TB-9707F_PRC` vendor fingerprint).
- Samsung Galaxy A04 (SM-A045F): a user booted a build of this patch set via DSU.

## Build

```bash
mkdir los23.2 && cd los23.2
repo init -u https://github.com/LineageOS/android.git -b lineage-23.2 --git-lfs
mkdir -p .repo/local_manifests
curl -o .repo/local_manifests/lineage_gsi.xml \
    https://raw.githubusercontent.com/kkhunter2/lineage_gsi/lineage-23.2/manifest/lineage_gsi.xml
repo sync -c --force-sync --optimized-fetch --no-tags --no-clone-bundle --prune -j8

lineage_gsi/scripts/build.sh            # applies patches, builds treble_app and bgN4
lineage_gsi/scripts/build.sh --sync     # later: re-sync and rebuild from scratch
lineage_gsi/scripts/build.sh --reset    # re-apply patches after changing them, no full sync
```

`build.sh` also accepts `bvN4`, `bgNE` and `bvNE`. Output goes to
`release/<date>/`. `apply-patches.sh` exits non-zero if any patch fails to
apply, so a build never silently goes out without a patch.

treble_app needs JDK 17 (`JAVA17=/path/to/jdk17` if it isn't at the Ubuntu
default). Install ccache for faster rebuilds.

`scripts/inspect-image.sh` checks a finished build offline (patch results
inside system.img, checksums, the release metadata). Before publishing,
`scripts/dsu-test.sh install <img.xz>` boots a build on a
connected device through DSU without touching its installed system, and
`scripts/dsu-test.sh check` then verifies face unlock and adaptive brightness.
`scripts/release.sh --draft` uploads a release without publishing it;
`scripts/release.sh --publish <tag>` publishes it once the build checks out.

## Credits

- [MisterZtr](https://github.com/MisterZtr) — the LineageOS_gsi patch set this is built on
- [LineageOS Team](https://github.com/LineageOS)
- [Phhusson](https://github.com/phhusson) and [TrebleDroid](https://github.com/TrebleDroid)
- [cawilliamson](https://github.com/cawilliamson) — RestlessOS patch set
- [Evolution-X](https://github.com/Evolution-X) — packages_apps_FaceUnlock
- [AOSPA](https://github.com/AOSPA) — ParanoidSense
- [MindTheGapps](https://gitlab.com/MindTheGapps)
- [AndyYan](https://github.com/AndyCGYan), [Ponces](https://github.com/ponces),
  [Peter Cai](https://github.com/PeterCxy), [Iceows](https://github.com/Iceows),
  [ChonDoit](https://github.com/ChonDoit), [Nazim N](https://github.com/naz664),
  [Ahnet](https://github.com/ahnet-69), [mytja](https://github.com/mytja),
  [Doze-off](https://github.com/Doze-off)
