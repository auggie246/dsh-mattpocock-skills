# dsh-mattpocock-skills

Install [Matt Pocock's skills](https://github.com/mattpocock/skills) into
[DeepSeek Harness](https://github.com/deepseek-ai/DSH) (DSH).

## How DSH "installs" skills (mental model)

DSH has no skill-plugin install command. Skills are files discovered by the
`skill-filesystem` plugin row that agent presets mount in their
`agent.cordis.yml`. That row scans, in priority order:

| Rank | Root | Scope |
|---|---|---|
| 100 | `<project>/.dsh/skills` | current project |
| 200 | `<project>/.agents/skills` | current project |
| 300 | `customSkillDirs` (preset config) | that preset only |
| 400 | `~/.dsh/skills` | **every preset, globally** |
| 500 | `~/.agents/skills` | every preset, shared with other harnesses |

So "installing skills" = placing skill directories in one of those roots. No
DSH restart is needed: the filesystem provider watches its roots and refreshes
the model's skill catalog live.

This repo installs into `~/.dsh/skills` (rank 400) so the skills are available
in **every** preset — `standard`, `cordis`, and the `mattpocock-skills` preset
alike. Lower-rank roots (e.g. a project's own `.dsh/skills`) still override
per name.

## Usage

No clone needed — run the installer straight from the web:

```bash
curl -fsSL https://raw.githubusercontent.com/auggie246/dsh-mattpocock-skills/main/install.sh | sh
```

Flags go after `-s --` when piped:

```bash
curl -fsSL https://raw.githubusercontent.com/auggie246/dsh-mattpocock-skills/main/install.sh | sh -s -- --categories "engineering productivity misc"
curl -fsSL https://raw.githubusercontent.com/auggie246/dsh-mattpocock-skills/main/install.sh | sh -s -- --all          # everything except deprecated/ and in-progress/
curl -fsSL https://raw.githubusercontent.com/auggie246/dsh-mattpocock-skills/main/install.sh | sh -s -- --uninstall    # remove every skill this script installed
curl -fsSL https://raw.githubusercontent.com/auggie246/dsh-mattpocock-skills/main/install.sh | sh -s -- --upstream-ref <ref>   # pin the skills source
curl -fsSL https://raw.githubusercontent.com/auggie246/dsh-mattpocock-skills/main/install.sh | sh -s -- --ref <ref>            # pin the patch source
```

What it does (every run, from scratch — nothing is stored between runs):

1. Downloads the `mattpocock/skills` tree as a GitHub tarball.
2. Downloads this repo's tarball and applies every patch under `patches/`
   to the downloaded tree.
3. Copies the chosen `skills/<category>/<skill>` directories into
   `~/.dsh/skills/<skill>` as **real directories** (no symlinks; DSH
   discovers one level deep, so upstream's two-level layout can't be
   copied as-is).
4. Tracks what it installed in `~/.dsh/skills/.mattpocock-skills.manifest`:
   - re-runs install the latest upstream content over the previous install
     (snapshot semantics), and remove skills that were deleted upstream or
     deselected,
   - anything in `~/.dsh/skills` that is NOT in the manifest is never touched,
   - a name collision with a non-managed directory is skipped with a warning.

Run the installer again any time you want fresh skill bodies or membership
changes (new/removed skills) synced.

## The ask-user overlay (`patches/`)

Upstream skills were written for Claude Code and say "ask the user" in chat
prose. DSH ships a default plugin (`@deepseek-ai/dsh-tool-ask-user`) whose
model-facing tool, `ask_user_question`, is the proper channel for those
moments. This repo carries a DSH-local overlay that says so inside every
skill that can ask:

- `patches/ask-user-question/<skill>.patch` holds one patch per skill. Each
  appends a **DSH note: asking the user** section to a `SKILL.md`: 15 skills
  in all (10 engineering, 3 productivity, 2 misc) whose instructions contain
  a genuine ask-the-user step. Grilling's `❓`/`➡️` round format included.
  Rhetorical "ask"s (tdd's "Ask: what's the public interface?") are
  deliberately untouched.
- `install.sh` downloads both trees (upstream skills and this repo's patches)
   fresh on every run, applies every patch under `patches/` to the downloaded
   tree, and only then installs. So upstream releases land first, and the
   overlay rides on top of the new version. A stale patch is skipped with a
   warning, never a broken install. One patch per skill caps the blast radius
   of an upstream change at that one skill.

When a release rewrites the tail of a patched file, that patch goes stale and
that skill stays unpatched until you regenerate it: from a pristine checkout,
append the overlay section to the file, then rewrite the patch with
`git -C upstream-skills diff -- skills/<bucket>/<skill>/SKILL.md >
patches/ask-user-question/<skill>.patch`. (This ran for real on 19 Aug: a
110-file upstream release landed mid-session and every patch went stale at
once; the overlay was re-based onto the new tree in minutes.) The overlay is
a fork-local adaptation, not upstream content, so upstream's docs-page and
router sync rules stay untriggered. The patched note reaches DSH on the next
install run, since every run downloads and patches a fresh tree.

## The `mattpocock-skills` preset

`~/.dsh/.agent-presets/mattpocock-skills/` is an **agent preset** (a bundle of
Cordis plugin rows), not a plugin. It used to carry *copies* of these skills
wired through `customSkillDirs`; that was removed in favor of this global
install, since preset-local copies (rank 300) would shadow the live global
copies (rank 400) and go stale. The preset now just provides the persona and
the standard tool/session composition; the skills themselves come from
`~/.dsh/skills`, exactly as in every other preset.
