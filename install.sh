#!/bin/sh
set -eu

# install.sh — install Matt Pocock's upstream skills into DeepSeek Harness.
#
# Designed to be run straight from the web, with no clone of this repo:
#
#   curl -fsSL https://raw.githubusercontent.com/auggie246/dsh-mattpocock-skills/main/install.sh | sh
#
# What "install" means in DSH: skills are not plugins you activate; they are
# files discovered by the `skill-filesystem` plugin row that presets mount.
# That row scans a global per-user root, ${DSH_HOME:-~/.dsh}/skills, in EVERY
# preset. Discovery is one level deep (<root>/<skill>/SKILL.md), so this
# script flattens upstream's skills/<category>/<skill> layout by COPYING each
# skill directory into that root as a real directory (no symlinks).
#
# Nothing here is stored on your machine between runs. Every run:
#   1. downloads the upstream skills tree (mattpocock/skills) as a tarball,
#   2. downloads this repo's overlay patches as a tarball and applies them
#      to the downloaded tree,
#   3. copies the chosen skills into ~/.dsh/skills as real directories,
#   4. rewrites the manifest.
#
# The script manages ONLY entries listed in its manifest
# (~/.dsh/skills/.mattpocock-skills.manifest). Anything else you placed in
# ~/.dsh/skills is never touched. If a name we want to install already exists
# and is NOT ours, we skip it and warn. Re-running installs the latest
# upstream content over the previous install (snapshot semantics).
#
# A stale patch is skipped with a warning, never a broken install. One patch
# per skill caps the blast radius of an upstream change at that one skill.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/auggie246/dsh-mattpocock-skills/main/install.sh | sh
#   ... --categories "engineering productivity misc"
#   ... --all                  every category except deprecated/ and in-progress/
#   ... --uninstall            remove every manifest-managed entry
#   ... --ref <ref>            pin the patch source to a branch/tag/sha
#   ... --upstream-ref <ref>   pin the skills source to a branch/tag/sha
#   ... --help

REPO="auggie246/dsh-mattpocock-skills"
UPSTREAM="mattpocock/skills"
UPSTREAM_URL="https://github.com/$UPSTREAM"

DSH_HOME_DIR="${DSH_HOME:-$HOME/.dsh}"
DEST="$DSH_HOME_DIR/skills"
MANIFEST="$DEST/.mattpocock-skills.manifest"

DEFAULT_CATEGORIES="engineering productivity"
CATEGORIES=""
ALL=0
DO_UNINSTALL=0
REF="HEAD"
UPSTREAM_REF="HEAD"

usage() {
  cat <<'EOF'
install.sh — install Matt Pocock's skills into DeepSeek Harness (~/.dsh/skills).

Usage:
  curl -fsSL https://raw.githubusercontent.com/auggie246/dsh-mattpocock-skills/main/install.sh | sh
  ... --categories "engineering productivity misc"
  ... --all                  every category except deprecated/ and in-progress/
  ... --uninstall            remove every manifest-managed entry
  ... --ref <ref>            pin the patch source to a branch/tag/sha
  ... --upstream-ref <ref>   pin the skills source to a branch/tag/sha
  ... --help

Skills are downloaded fresh on every run and copied in as real directories.
Only entries listed in ~/.dsh/skills/.mattpocock-skills.manifest are managed;
anything else in ~/.dsh/skills is never touched.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --categories)    CATEGORIES="$2"; shift 2 ;;
    --all)           ALL=1; shift ;;
    --uninstall)     DO_UNINSTALL=1; shift ;;
    --ref)           REF="$2"; shift 2 ;;
    --upstream-ref)  UPSTREAM_REF="$2"; shift 2 ;;
    -h|--help)       usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

# --- uninstall (offline; needs no downloads) -----------------------------------
if [ "$DO_UNINSTALL" -eq 1 ]; then
  if [ ! -f "$MANIFEST" ]; then
    echo "error: no manifest at $MANIFEST; nothing to uninstall." >&2
    exit 1
  fi
  removed=0
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    if [ -L "$DEST/$entry" ] || [ -d "$DEST/$entry" ]; then
      rm -rf "$DEST/$entry"
      echo "removed $entry"
      removed=$((removed + 1))
    fi
  done < "$MANIFEST"
  rm -f "$MANIFEST"
  echo "uninstalled $removed skill(s) from $DEST"
  exit 0
fi

# --- download helpers -----------------------------------------------------------
fetch() {
  # fetch <url> <output-file>
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$1" -o "$2"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$2" "$1"
  else
    echo "error: need curl or wget to download $1" >&2
    exit 1
  fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM

mkdir -p "$TMP/upstream" "$TMP/repo"
touch "$TMP/old-manifest" "$TMP/names"

echo "downloading skills from $UPSTREAM_URL (ref: $UPSTREAM_REF)..."
fetch "https://codeload.github.com/$UPSTREAM/tar.gz/$UPSTREAM_REF" "$TMP/upstream.tar.gz"
tar -xzf "$TMP/upstream.tar.gz" -C "$TMP/upstream"
UPROOT="$(find "$TMP/upstream" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
if [ -z "$UPROOT" ] || [ ! -d "$UPROOT/skills" ]; then
  echo "error: downloaded upstream tree has no skills/ directory" >&2
  exit 1
fi

echo "downloading overlay patches from github.com/$REPO (ref: $REF)..."
fetch "https://codeload.github.com/$REPO/tar.gz/$REF" "$TMP/repo.tar.gz"
tar -xzf "$TMP/repo.tar.gz" -C "$TMP/repo"
REPOROOT="$(find "$TMP/repo" -mindepth 1 -maxdepth 1 -type d | head -n 1)"

# --- apply the DSH overlay patches to the downloaded tree -----------------------
if [ -d "$REPOROOT/patches" ]; then
  if command -v git >/dev/null 2>&1; then
    for patch in "$REPOROOT"/patches/*.patch "$REPOROOT"/patches/*/*.patch; do
      [ -f "$patch" ] || continue
      pname="$(basename "$patch")"
      if (cd "$UPROOT" && git apply --check "$patch") 2>/dev/null; then
        (cd "$UPROOT" && git apply "$patch")
        echo "applied overlay patch: $pname"
      elif (cd "$UPROOT" && git apply --check --reverse "$patch") 2>/dev/null; then
        echo "overlay patch already applied: $pname"
      else
        echo "warning: overlay patch $pname no longer applies to upstream; that skill stays unpatched" >&2
      fi
    done
  elif command -v patch >/dev/null 2>&1; then
    for patch in "$REPOROOT"/patches/*.patch "$REPOROOT"/patches/*/*.patch; do
      [ -f "$patch" ] || continue
      pname="$(basename "$patch")"
      if patch --forward --silent -p1 -d "$UPROOT" < "$patch" >/dev/null 2>&1; then
        echo "applied overlay patch: $pname"
      else
        echo "warning: overlay patch $pname no longer applies to upstream; that skill stays unpatched" >&2
      fi
    done
  else
    echo "warning: neither git nor patch found; skills install unpatched" >&2
  fi
else
  echo "warning: no patches/ directory in $REPO@$REF; skills install unpatched" >&2
fi

# --- read the previous manifest (entries we own) --------------------------------
if [ -f "$MANIFEST" ]; then
  cp "$MANIFEST" "$TMP/old-manifest"
fi

is_owned() {
  grep -Fxq "$1" "$TMP/old-manifest"
}

mkdir -p "$DEST"

# --- collect skills from the chosen categories ----------------------------------
if [ "$ALL" -eq 1 ]; then
  CATEGORIES="$(cd "$UPROOT/skills" && find . -mindepth 1 -maxdepth 1 -type d \
    | sed 's|^\./||' | grep -vx -e deprecated -e in-progress || true)"
fi
[ -n "$CATEGORIES" ] || CATEGORIES="$DEFAULT_CATEGORIES"

echo "categories: $CATEGORIES"

: > "$TMP/pairs"
for category in $CATEGORIES; do
  dir="$UPROOT/skills/$category"
  if [ ! -d "$dir" ]; then
    echo "warning: category '$category' not found upstream; skipping" >&2
    continue
  fi
  for skill_md in "$dir"/*/SKILL.md; do
    [ -f "$skill_md" ] || continue
    src="$(dirname "$skill_md")"
    name="$(basename "$src")"
    # warn on the same skill name coming from two categories
    if grep -Fxq "$name" "$TMP/names"; then
      echo "warning: duplicate skill name '$name' ($src); later category wins" >&2
    else
      echo "$name" >> "$TMP/names"
    fi
    printf '%s\t%s\n' "$name" "$src" >> "$TMP/pairs"
  done
done

if [ ! -s "$TMP/pairs" ]; then
  echo "error: no SKILL.md found under categories: $CATEGORIES" >&2
  exit 1
fi

# --- remove previously installed entries no longer present upstream -------------
awk -F'\t' '{ print $1 }' "$TMP/pairs" | sort -u > "$TMP/wanted"
while IFS= read -r entry; do
  [ -n "$entry" ] || continue
  if ! grep -Fxq "$entry" "$TMP/wanted" \
     && { [ -L "$DEST/$entry" ] || [ -d "$DEST/$entry" ]; }; then
    rm -rf "$DEST/$entry"
    echo "removed $entry (no longer upstream/selected)"
  fi
done < "$TMP/old-manifest"

# --- install (copy, never symlink) ----------------------------------------------
: > "$MANIFEST.tmp"
installed=0
skipped=0
while IFS="$(printf '\t')" read -r name src; do
  [ -n "$name" ] || continue
  target="$DEST/$name"

  if [ -e "$target" ] && [ ! -L "$target" ] && ! is_owned "$name"; then
    echo "warning: $target already exists and is not managed by this script; leaving it alone (skipped $name)" >&2
    skipped=$((skipped + 1))
    continue
  fi

  # replace a previous install of ours (real dir or symlink) with a fresh copy
  rm -rf "$target"
  cp -R "$src" "$target"

  echo "$name" >> "$MANIFEST.tmp"
  echo "installed $name -> $target"
  installed=$((installed + 1))
done < "$TMP/pairs"

mv -f "$MANIFEST.tmp" "$MANIFEST"

echo
echo "done: $installed skill(s) installed into $DEST, $skipped skipped."
echo "DSH picks them up in every preset (no restart needed;"
echo "the skill-filesystem watcher refreshes the catalog live)."
