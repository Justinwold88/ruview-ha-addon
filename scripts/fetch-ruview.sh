#!/bin/sh
# Check RuView out into ruview-src/ at the commit in ruview/RUVIEW_COMMIT,
# with submodules, for a local image build. CI does the same with
# actions/checkout.
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
commit="$(tr -d '[:space:]' < "$root/ruview/RUVIEW_COMMIT")"
case "$commit" in
    *[!0-9a-f]*|'') echo "ruview/RUVIEW_COMMIT must be a full commit hash" >&2; exit 64 ;;
esac
[ "${#commit}" -eq 40 ] || { echo "ruview/RUVIEW_COMMIT must be 40 hex characters" >&2; exit 64; }
dest="$root/ruview-src"
if [ ! -d "$dest/.git" ]; then
    git init -q "$dest"
    git -C "$dest" remote add origin https://github.com/Justinwold88/RuView
fi
git -C "$dest" fetch -q --depth 1 origin "$commit"
git -C "$dest" checkout -q --detach FETCH_HEAD
git -C "$dest" submodule update -q --init --recursive --depth 1
echo "RuView $commit is in $dest"
