#!/bin/bash
#
# Publish a directory produced by build.sh as a GitHub release.
#
# Usage: GITHUB_TOKEN=... lineage_gsi/scripts/release.sh <tree>/release/<date> [notes.md]
#
# The release is created as a draft, every file in the directory is uploaded,
# and only then is it published, so a half-uploaded release is never visible.

set -euo pipefail

REPO="${REPO:-kkhunter2/lineage_gsi}"
: "${GITHUB_TOKEN:?set GITHUB_TOKEN}"

dir="${1:?usage: release.sh <release-dir> [notes.md]}"
notes="${2:-}"
date_tag="$(basename "$dir")"
tag="v${date_tag:0:4}.${date_tag:4:2}.${date_tag:6:2}-lineage23.2"
commit="$(cat "$dir/.commit" 2>/dev/null || echo lineage-23.2)"

api="https://api.github.com/repos/$REPO"
auth=(-H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json")

# GitHub rejects release assets of 2 GiB or more.
for f in "$dir"/*; do
    if [ "$(stat -c %s "$f")" -ge 2147483648 ]; then
        echo "$f is 2 GiB or larger; GitHub will not accept it" >&2
        exit 1
    fi
done

body=""
[ -n "$notes" ] && body="$(cat "$notes")"
payload="$(python3 -I -c 'import json, sys
print(json.dumps({"tag_name": sys.argv[1], "target_commitish": sys.argv[2],
                  "name": sys.argv[3], "body": sys.argv[4], "draft": True}))' \
    "$tag" "$commit" "LineageOS 23.2 $date_tag" "$body")"

id="$(curl -fsS "${auth[@]}" -X POST "$api/releases" -d "$payload" |
    python3 -I -c 'import json, sys; print(json.load(sys.stdin)["id"])')"
echo "### Draft release $tag (id $id)"

for f in "$dir"/*; do
    name="$(basename "$f")"
    echo "### Uploading $name"
    curl -fsS "${auth[@]}" -X POST -H "Content-Type: application/octet-stream" \
        -T "$f" "https://uploads.github.com/repos/$REPO/releases/$id/assets?name=$name" > /dev/null
done

curl -fsS "${auth[@]}" -X PATCH "$api/releases/$id" -d '{"draft": false}' |
    python3 -I -c 'import json, sys; print("### Published", json.load(sys.stdin)["html_url"])'
