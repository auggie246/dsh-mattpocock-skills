#!/usr/bin/env bash
set -euo pipefail

# install.sh — install Matt Pocock's upstream skills into DeepSeek Harness.
#
# What "install" means in DSH: skills are not plugins you activate; they are
# files discovered by the `skill-filesystem` plugin row that presets mount.
# That row scans a global per-user root, ${DSH_HOME:-~/.dsh}/skills, in EVERY
# preset. Discovery is one level deep (<root>/<skill>/SKILL.md), so this
# script flattens upstream's skills/<category>/<skill> layout by symlinking
# each skill directory into that root.
#
# Because entries are symlinks into the git checkout in ./upstream-skills,
# a `git pull` (done by this script) updates the skill bodies with no
# re-install; DSH's file watcher refreshes its catalog live.
#
# The script manages ONLY entries listed in its manifest
# (~/.dsh/skills/.mattpocock-skills.manifest). Anything else you placed in
# ~/.dsh/skills is never touched. If a name we want to install already exists
# and is NOT ours, we skip it and warn.
#
# DSH overlay patches: after clone/pull, the script re-applies every patch
# under ./patches/ onto the checkout (currently: the ask-user overlay that
# routes "ask the user" moments through DSH's ask_user_question tool). A git
# pull would otherwise wipe them, so the checkout is reset to pristine before
# pulling and the patches are re-applied after. See the README.
#
# Usage:
#   ./install.sh                          pull upstream, install default categories
#   ./install.sh --categories "engineering productivity misc"
#   ./install.sh --all                    every category except deprecated/ and in-progress/
#   ./install.sh --no-pull                skip git pull, install from current checkout
#   ./install.sh --copy                   copy instead of symlink (snapshot semantics)
#   ./install.sh --uninstall              remove every manifest-managed entry

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
UPSTREAM_DIR="$REPO_ROOT/upstream-skills"
UPSTREAM_URL="https://github.com/mattpocock/skills.git"

DSH_HOME_DIR="${DSH_HOME:-$HOME/.dsh}"
DEST="$DSH_HOME_DIR/skills"
MANIFEST="$DEST/.mattpocock-skills.manifest"

DEFAULT_CATEGORIES="engineering productivity"
CATEGORIES=""
MODE="link"   # link | copy
DO_PULL=1
DO_UNINSTALL=0
ALL=0

while [ $# -gt 0 ]; do
  case "$1" in
    --categories) CATEGORIES="$2"; shift 2 ;;
    --all)        ALL=1; shift ;;
    --copy)       MODE="copy"; shift ;;
    --no-pull)    DO_PULL=0; shift ;;
    --uninstall)  DO_UNINSTALL=1; shift ;;
    -h|--help)    sed -n '2,34p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

# --- ensure the upstream checkout exists --------------------------------------
if [ ! -d "$UPSTREAM_DIR/.git" ]; then
  if [ "$DO_UNINSTALL" -eq 1 ]; then
    echo "error: no upstream checkout at $UPSTREAM_DIR; nothing to uninstall categories from." >&2
    exit 1
  fi
  echo "cloning $UPSTREAM_URL -> $UPSTREAM_DIR"
  git clone --depth 1 "$UPSTREAM_URL" "$UPSTREAM_DIR"
elif [ "$DO_PULL" -eq 1 ] && [ "$DO_UNINSTALL" -eq 0 ]; then
  echo "updating upstream checkout..."
  # drop the overlay patches first so the pull can never conflict with them;
  # they are re-applied below
  git -C "$UPSTREAM_DIR" reset --hard --quiet
  git -C "$UPSTREAM_DIR" pull --ff-only
fi

# --- (re-)apply the DSH overlay patches ----------------------------------------
# Every patch under patches/ (flat or in an overlay subdirectory) is a plain
# git diff against pristine upstream, applied after clone/pull so the
# installed skills carry the overlay. Per-skill patch files keep the blast
# radius of an upstream change to that one skill: idempotent (already-applied
# is detected), and a stale patch is skipped with a warning, never a broken
# install.
if [ "$DO_UNINSTALL" -eq 0 ]; then
  shopt -s nullglob
  for patch in "$REPO_ROOT"/patches/*.patch "$REPO_ROOT"/patches/*/*.patch; do
    pname="$(basename "$patch")"
    if git -C "$UPSTREAM_DIR" apply --check "$patch" 2>/dev/null; then
      git -C "$UPSTREAM_DIR" apply "$patch"
      echo "applied overlay patch: $pname"
    elif git -C "$UPSTREAM_DIR" apply --check --reverse "$patch" 2>/dev/null; then
      echo "overlay patch already applied: $pname"
    else
      echo "warning: overlay patch $pname no longer applies to upstream; skills stay unpatched" >&2
    fi
  done
fi

mkdir -p "$DEST"

# --- read the previous manifest (entries we own) ------------------------------
owned=()
if [ -f "$MANIFEST" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] && owned+=("$line")
  done < "$MANIFEST"
fi

is_owned() {
  local name="$1" entry
  for entry in ${owned[@]+"${owned[@]}"}; do
    [ "$entry" = "$name" ] && return 0
  done
  return 1
}

# --- uninstall ----------------------------------------------------------------
if [ "$DO_UNINSTALL" -eq 1 ]; then
  removed=0
  for entry in ${owned[@]+"${owned[@]}"}; do
    target="$DEST/$entry"
    if [ -L "$target" ] || [ -d "$target" ]; then
      rm -rf "$target"
      echo "removed $entry"
      removed=$((removed + 1))
    fi
  done
  rm -f "$MANIFEST"
  echo "uninstalled $removed skill(s) from $DEST"
  exit 0
fi

# --- collect skills from the chosen categories --------------------------------
if [ "$ALL" -eq 1 ]; then
  CATEGORIES="$(cd "$UPSTREAM_DIR/skills" && ls -d */ 2>/dev/null \
    | sed 's|/$||' | grep -vx -e deprecated -e in-progress || true)"
fi
[ -z "$CATEGORIES" ] && CATEGORIES="$DEFAULT_CATEGORIES"

echo "categories: $CATEGORIES"

names=()
srcs=()
for category in $CATEGORIES; do
  dir="$UPSTREAM_DIR/skills/$category"
  if [ ! -d "$dir" ]; then
    echo "warning: category '$category' not found upstream; skipping" >&2
    continue
  fi
  for skill_md in "$dir"/*/SKILL.md; do
    [ -f "$skill_md" ] || continue
    src="$(dirname "$skill_md")"
    name="$(basename "$src")"
    # warn on the same skill name coming from two categories
    for existing in ${names[@]+"${names[@]}"}; do
      if [ "$existing" = "$name" ]; then
        echo "warning: duplicate skill name '$name' ($src); later category wins" >&2
      fi
    done
    names+=("$name")
    srcs+=("$src")
  done
done

if [ "${#names[@]}" -eq 0 ]; then
  echo "error: no SKILL.md found under categories: $CATEGORIES" >&2
  exit 1
fi

# --- remove previously installed entries no longer present upstream ------------
wanted_joined=" ${names[*]} "
for entry in ${owned[@]+"${owned[@]}"}; do
  case "$wanted_joined" in
    *" $entry "*) ;;  # still wanted
    *)
      if [ -L "$DEST/$entry" ] || [ -d "$DEST/$entry" ]; then
        rm -rf "$DEST/$entry"
        echo "removed $entry (no longer upstream/selected)"
      fi
      ;;
  esac
done

# --- install -------------------------------------------------------------------
: > "$MANIFEST"
installed=0
skipped=0
for i in "${!names[@]}"; do
  name="${names[$i]}"
  src="${srcs[$i]}"
  target="$DEST/$name"

  if [ -e "$target" ] && [ ! -L "$target" ] && ! is_owned "$name"; then
    echo "warning: $target already exists and is not managed by this script; leaving it alone (skipped $name)" >&2
    skipped=$((skipped + 1))
    continue
  fi

  if [ "$MODE" = "link" ]; then
    # replace a stale copy of ours, or repoint an existing symlink
    if [ -e "$target" ] && [ ! -L "$target" ]; then
      rm -rf "$target"
    fi
    ln -sfn "$src" "$target"
  else
    rm -rf "$target"
    cp -R "$src" "$target"
  fi

  echo "$name" >> "$MANIFEST"
  echo "installed $name -> $target ($MODE)"
  installed=$((installed + 1))
done

echo
echo "done: $installed skill(s) installed into $DEST, $skipped skipped."
echo "DSH picks them up in every preset (no restart of this script needed;"
echo "the skill-filesystem watcher refreshes the catalog live)."
