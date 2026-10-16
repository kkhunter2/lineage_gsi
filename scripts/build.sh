#!/bin/bash
#
# Build a LineageOS 23.2 GSI with the lineage_gsi patch set.
#
# Expects this repo at <tree>/lineage_gsi (as placed by manifest/lineage_gsi.xml).
#
# Usage: lineage_gsi/scripts/build.sh [--sync|--reset] [variant ...]
#   --sync     discard applied patches, repo sync, re-apply patches
#   --reset    discard applied patches and re-apply them without a network sync
#              (only lineage_gsi itself is fetched, to pick up patch changes)
#   variant    bgN4 (default), bvN4, bgNE, bvNE
#
# Output: <tree>/release/<date>/ with the compressed image, its sha256 and a
# pinned manifest snapshot.

set -euo pipefail

TREE="${LOS_TREE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
RELEASE_CONFIG="${RELEASE_CONFIG:-bp4a}"
JOBS="${JOBS:-$(nproc --all)}"
JAVA17="${JAVA17:-/usr/lib/jvm/java-17-openjdk-amd64}"

sync=0
reset=0
variants=()
for arg in "$@"; do
    case "$arg" in
        --sync) sync=1 ;;
        --reset) reset=1 ;;
        bgN4|bvN4|bgNE|bvNE) variants+=("$arg") ;;
        *) echo "unknown argument: $arg" >&2; exit 2 ;;
    esac
done
[ ${#variants[@]} -eq 0 ] && variants=(bgN4)

cd "$TREE"
marker="$TREE/.lineage_gsi_patched"

if [ "$sync" -eq 1 ] || [ "$reset" -eq 1 ]; then
    echo "### Discarding applied patches"
    repo forall -c 'git am --abort >/dev/null 2>&1; git reset -q --hard; git clean -qfd' || true
    rm -f "$marker"
    if [ "$sync" -eq 1 ]; then
        repo sync -c --force-sync --optimized-fetch --no-tags --no-clone-bundle --prune -j"$JOBS"
    else
        repo sync -l -j"$JOBS"
        repo sync -c --force-sync --no-tags --no-clone-bundle lineage_gsi
    fi
fi

if [ ! -f "$marker" ]; then
    echo "### Applying patches"
    bash lineage_gsi/patches/apply-patches.sh .
    git -C lineage_gsi rev-parse HEAD > "$marker"
else
    echo "### Patches already applied ($(cat "$marker")); use --sync to start over"
fi

echo "### Building treble_app"
(cd treble_app && JAVA_HOME="$JAVA17" PATH="$JAVA17/bin:$PATH" bash build.sh)

if command -v ccache >/dev/null; then
    export USE_CCACHE=1 CCACHE_EXEC="$(command -v ccache)" CCACHE_COMPRESS=1
    ccache -M 50G >/dev/null
fi

date_tag="$(date +%Y%m%d)"
outdir="$TREE/release/$date_tag"
mkdir -p "$outdir"

set +u
source build/envsetup.sh
set -u

for variant in "${variants[@]}"; do
    echo "### Building lineage_arm64_$variant"
    # breakfast/lunch mis-parse this product name, so set the target directly.
    export TARGET_PRODUCT="lineage_arm64_$variant" TARGET_RELEASE="$RELEASE_CONFIG" TARGET_BUILD_VARIANT=userdebug
    m -j"$JOBS" systemimage

    img="$(ls -t out/target/product/*/system.img | head -1)"
    name="lineage-23.2-$date_tag-UNOFFICIAL-arm64_$variant.img"
    echo "### Compressing $img -> $outdir/$name.xz"
    xz -T0 -c "$img" > "$outdir/$name.xz"
    (cd "$outdir" && sha256sum "$name.xz" > "$name.xz.sha256")
done

repo manifest -r -o "$outdir/manifest-snapshot.xml"
cp "$marker" "$outdir/.commit"
ls -lh "$outdir"
