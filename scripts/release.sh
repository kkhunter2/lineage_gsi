#!/bin/bash
#
# Publish a directory produced by build.sh as a GitHub release.
#
# Usage:
#   GITHUB_TOKEN=... lineage_gsi/scripts/release.sh [--draft] <tree>/release/<date> [notes.md]
#   GITHUB_TOKEN=... lineage_gsi/scripts/release.sh --publish <tag> [notes.md]
#
# The release is created as a draft and every file in the directory is
# uploaded before it is published, so a half-uploaded release is never
# visible. --draft stops there (e.g. to boot-test the build first);
# --publish later publishes that draft, optionally replacing its notes.

set -euo pipefail

REPO="${REPO:-kkhunter2/lineage_gsi}"
: "${GITHUB_TOKEN:?set GITHUB_TOKEN}"

api="https://api.github.com/repos/$REPO"
auth=(-H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json")

json_field() {
    python3 -I -c 'import json, sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1"
}

publish() {
    local id=$1 notes=$2 payload
    payload="$(python3 -I -c 'import json, sys
d = {"draft": False}
if sys.argv[1]:
    d["body"] = open(sys.argv[1]).read()
print(json.dumps(d))' "$notes")"
    curl -fsS "${auth[@]}" -X PATCH "$api/releases/$id" -d "$payload" |
        json_field html_url | sed 's/^/### Published /'
}

if [ "${1:-}" = "--publish" ]; then
    tag="${2:?usage: release.sh --publish <tag> [notes.md]}"
    # Drafts are not reachable through /releases/tags/<tag>, so search the list.
    id="$(curl -fsS "${auth[@]}" "$api/releases?per_page=100" |
        python3 -I -c 'import json, sys
ids = [r["id"] for r in json.load(sys.stdin) if r["tag_name"] == sys.argv[1] and r["draft"]]
print(ids[0] if ids else "")' "$tag")"
    [ -n "$id" ] || { echo "no draft release with tag $tag" >&2; exit 1; }
    publish "$id" "${3:-}"
    exit 0
fi

draft_only=0
if [ "${1:-}" = "--draft" ]; then
    draft_only=1
    shift
fi

dir="${1:?usage: release.sh [--draft] <release-dir> [notes.md]}"
notes="${2:-}"
date_tag="$(basename "$dir")"
tag="v${date_tag:0:4}.${date_tag:4:2}.${date_tag:6:2}-lineage23.2"
commit="$(cat "$dir/.commit" 2>/dev/null || echo lineage-23.2)"

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

id="$(curl -fsS "${auth[@]}" -X POST "$api/releases" -d "$payload" | json_field id)"
echo "### Draft release $tag (id $id)"

for f in "$dir"/*; do
    name="$(basename "$f")"
    echo "### Uploading $name"
    curl -fsS "${auth[@]}" -X POST -H "Content-Type: application/octet-stream" \
        -T "$f" "https://uploads.github.com/repos/$REPO/releases/$id/assets?name=$name" > /dev/null
done

if [ "$draft_only" -eq 1 ]; then
    echo "### Left as draft; publish with: release.sh --publish $tag [notes.md]"
else
    publish "$id" ""
fi
