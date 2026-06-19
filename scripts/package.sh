#!/usr/bin/env bash
# Build a dashboard-installable ZIP for local_objectfs_cdn.
#
# Moodle's "Install plugin from ZIP" requires the archive to contain exactly ONE
# top-level folder named after the plugin — for component `local_objectfs_cdn`
# that folder must be `objectfs_cdn/` (the type prefix `local_` stripped). GitHub's
# auto-generated source zip names it `moodle-local_objectfs_cdn-<ref>/`, which Moodle
# rejects. This script produces dist/objectfs_cdn.zip with the correct structure.
#
# Single source of truth for packaging — used by both local testing and CI
# (.github/workflows/release.yml). Run from anywhere; resolves the repo root itself.
set -euo pipefail
cd "$(dirname "$0")/.."

PLUGIN_NAME="objectfs_cdn"            # component minus the local_ type prefix
COMPONENT="local_objectfs_cdn"
DIST="dist"

# Allowlist — only known plugin files ship (safer than a denylist: new dev/CI files
# can never leak into a release). dev/CI paths (.git, .github, scripts/, .gitignore,
# .dockerignore, dist/) are excluded simply by not being listed here.
INCLUDE=(version.php settings.php README.md LICENSE CHANGELOG.md phpunit.xml classes lang tests)

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ROOT="$STAGE/$PLUGIN_NAME"
mkdir -p "$ROOT"

for item in "${INCLUDE[@]}"; do
  if [ ! -e "$item" ]; then
    echo "ERROR: expected plugin path missing from repo: $item" >&2
    exit 1
  fi
  cp -R "$item" "$ROOT/"
done

# Strip OS cruft that cp may have carried in.
find "$ROOT" -name '.DS_Store' -delete 2>/dev/null || true

mkdir -p "$DIST"
ZIP="$PWD/$DIST/${PLUGIN_NAME}.zip"
rm -f "$ZIP"
( cd "$STAGE" && zip -r -q -X "$ZIP" "$PLUGIN_NAME" )

# ---------------------------------------------------------------------------
# Self-verify: the archive must satisfy exactly what Moodle's installer expects.
# ---------------------------------------------------------------------------
echo "==> verifying $ZIP"

roots="$(unzip -Z1 "$ZIP" | awk -F/ 'NF{print $1}' | sort -u)"
if [ "$roots" != "$PLUGIN_NAME" ]; then
  echo "ERROR: ZIP must have a single root dir '$PLUGIN_NAME/'; found: [$roots]" >&2
  exit 1
fi

if ! unzip -Z1 "$ZIP" | grep -qx "$PLUGIN_NAME/version.php"; then
  echo "ERROR: $PLUGIN_NAME/version.php is missing from the archive root" >&2
  exit 1
fi

if ! unzip -p "$ZIP" "$PLUGIN_NAME/version.php" | grep -Eq "component[[:space:]]*=[[:space:]]*'$COMPONENT'"; then
  echo "ERROR: version.php does not declare component = '$COMPONENT'" >&2
  exit 1
fi

for bad in .git .github scripts .gitignore .dockerignore; do
  if unzip -Z1 "$ZIP" | grep -q "^$PLUGIN_NAME/$bad"; then
    echo "ERROR: excluded path leaked into the archive: $bad" >&2
    exit 1
  fi
done

echo "==> OK: $(unzip -Z1 "$ZIP" | grep -c . ) entries, single root '$PLUGIN_NAME/'"
echo "==> $ZIP"
