# dsh-mattpocock-skills

Install Matt Pocock's skills into DeepSeek Harness (DSH) — download fresh, patch for DSH, copy as real directories.

[![standard-readme compliant](https://img.shields.io/badge/readme%20style-standard-brightgreen.svg?style=flat-square)](https://github.com/RichardLitt/standard-readme)

## Table of Contents

- [Background](#background)
- [Install](#install)
- [Usage](#usage)
- [The ask-user overlay (`patches/`)](#the-ask-user-overlay-patches)
- [The `mattpocock-skills` preset](#the-mattpocock-skills-preset)
- [Maintainers](#maintainers)
- [Contributing](#contributing)
- [License](#license)

## Background

This repo distributes [Matt Pocock's skills](https://github.com/mattpocock/skills) for
[DeepSeek Harness](https://github.com/deepseek-ai/DSH) (DSH). Upstream skills were written
for Claude Code. Two adaptations are needed for DSH, and both live here:

- an installer that speaks DSH's model of skill installation, and
- the ask-user overlay, which reroutes "ask the user" moments through DSH's native tool.

DSH has no skill-plugin install command. Skills are files discovered by the
`skill-filesystem` plugin row that agent presets mount in their `agent.cordis.yml`. That row
scans, in priority order:

| Rank | Root | Scope |
|---|---|---|
| 100 | `<project>/.dsh/skills` | current project |
| 200 | `<project>/.agents/skills` | current project |
| 300 | `customSkillDirs` (preset config) | that preset only |
| 400 | `~/.dsh/skills` | **every preset, globally** |
| 500 | `~/.agents/skills` | every preset, shared with other harnesses |

So "installing skills" = placing skill directories in one of those roots. No DSH restart is
needed: the filesystem provider watches its roots and refreshes the model's skill catalog
live. This repo installs into `~/.dsh/skills` (rank 400) so the skills are available in
**every** preset. Lower-rank roots (e.g. a project's own `.dsh/skills`) still override per
name.

The installer downloads both trees fresh on every run and copies the chosen skills in as
**real directories** — never symlinks — so what lands in `~/.dsh/skills` is a snapshot, not
a live view into a working tree. DSH discovers one level deep
(`<root>/<skill>/SKILL.md`), so upstream's `skills/<category>/<skill>` layout is flattened
on the way in.

## Install

No clone needed — run the installer straight from the web:

```bash
curl -fsSL https://raw.githubusercontent.com/auggie246/dsh-mattpocock-skills/main/install.sh | sh
```

### Dependencies

- POSIX `sh` (the script is dash-compatible; it is piped to `sh`, not bash)
- `curl` or `wget` for the downloads
- `tar` to unpack the GitHub tarballs
- `git` or `patch` to apply the overlay patches — without either, skills install unpatched
  with a warning

### Updating

Re-run the same one-liner any time. Every run downloads the latest upstream skills, applies
the current overlay patches, and copies the result over the previous install (snapshot
semantics). Skills that upstream removed, or that you deselected, are deleted. To pin
either source to a branch, tag, or sha, see `--ref` and `--upstream-ref` under [Usage](#usage).

## Usage

Default install covers the `engineering` and `productivity` categories:

```bash
curl -fsSL https://raw.githubusercontent.com/auggie246/dsh-mattpocock-skills/main/install.sh | sh
```

Flags go after `-s --` when piped (a bare `sh --flag` feeds the flag to the shell, not the
script):

```bash
# choose categories explicitly
curl -fsSL https://raw.githubusercontent.com/auggie246/dsh-mattpocock-skills/main/install.sh | sh -s -- --categories "engineering productivity misc"

# everything except deprecated/ and in-progress/
curl -fsSL https://raw.githubusercontent.com/auggie246/dsh-mattpocock-skills/main/install.sh | sh -s -- --all

# remove every skill this script installed
curl -fsSL https://raw.githubusercontent.com/auggie246/dsh-mattpocock-skills/main/install.sh | sh -s -- --uninstall

# pin the skills source / the patch source (branch, tag, or sha)
curl -fsSL https://raw.githubusercontent.com/auggie246/dsh-mattpocock-skills/main/install.sh | sh -s -- --upstream-ref <ref> --ref <ref>
```

### CLI

| Flag | Effect |
|---|---|
| `--categories "<list>"` | Install only these upstream categories (default: `engineering productivity`). |
| `--all` | Install every category except `deprecated/` and `in-progress/`. |
| `--uninstall` | Remove every manifest-managed entry. Offline; needs no downloads. |
| `--upstream-ref <ref>` | Pin the `mattpocock/skills` download (default `HEAD`). |
| `--ref <ref>` | Pin this repo's patch download (default `HEAD`). |
| `-h`, `--help` | Print usage. |

The installer manages **only** entries listed in
`~/.dsh/skills/.mattpocock-skills.manifest`:

- re-runs refresh manifest-owned entries and remove ones no longer upstream or deselected,
- anything else in `~/.dsh/skills` is never touched,
- a name collision with a non-managed directory is skipped with a warning.

## The ask-user overlay (`patches/`)

Upstream skills were written for Claude Code and say "ask the user" in chat prose. DSH
ships a default plugin (`@deepseek-ai/dsh-tool-ask-user`) whose model-facing tool,
`ask_user_question`, is the proper channel for those moments. This repo carries a DSH-local
overlay that says so inside every skill that can ask:

- `patches/ask-user-question/<skill>.patch` holds one patch per skill. Each appends a
  **DSH note: asking the user** section to a `SKILL.md`: 15 skills in all (10 engineering,
  3 productivity, 2 misc) whose instructions contain a genuine ask-the-user step. Grilling's
  `❓`/`➡️` round format included. Rhetorical "ask"s (tdd's "Ask: what's the public
  interface?") are deliberately untouched.
- `install.sh` downloads both trees fresh on every run, applies every patch under
  `patches/` to the downloaded tree, and only then installs. So upstream releases land
  first, and the overlay rides on top of the new version. A stale patch is skipped with a
  warning, never a broken install. One patch per skill caps the blast radius of an upstream
  change at that one skill.

When a release rewrites the tail of a patched file, that patch goes stale and that skill
stays unpatched until you regenerate it: from a pristine `upstream-skills/` checkout,
append the overlay section to the file, then rewrite the patch with
`git -C upstream-skills diff -- skills/<bucket>/<skill>/SKILL.md >
patches/ask-user-question/<skill>.patch`. (This ran for real on 19 Aug: a 110-file upstream
release landed mid-session and every patch went stale at once; the overlay was re-based onto
the new tree in minutes.) The overlay is a fork-local adaptation, not upstream content, so
upstream's docs-page and router sync rules stay untriggered. The patched note reaches DSH on
the next install run, since every run downloads and patches a fresh tree.

## The `mattpocock-skills` preset

`~/.dsh/.agent-presets/mattpocock-skills/` is an **agent preset** (a bundle of Cordis
plugin rows), not a plugin. It used to carry *copies* of these skills wired through
`customSkillDirs`; that was removed in favor of this global install, since preset-local
copies (rank 300) would shadow the live global copies (rank 400) and go stale. The preset
now just provides the persona and the standard tool/session composition; the skills
themselves come from `~/.dsh/skills`, exactly as in every other preset.

## Maintainers

- [auggie246](https://github.com/auggie246) — owner and maintainer.

## Contributing

Issues and pull requests are welcome: open an issue at
<https://github.com/auggie246/dsh-mattpocock-skills/issues> to ask questions or propose
changes. PRs are accepted.

Requirements for contributing:

- Regenerate stale overlay patches with the workflow in
  [The ask-user overlay](#the-ask-user-overlay-patches) — do not hand-edit installed
  skills in `~/.dsh/skills`; they are snapshots and the next run overwrites them.
- Keep `install.sh` POSIX `sh` compatible: it runs under dash via `curl | sh`, so no bash
  arrays or bashisms.
- Test installer changes against a throwaway home first: `DSH_HOME=$(mktemp -d) sh install.sh`.

## License

[MIT](./LICENSE) © Augustine (auggie246)

The vendored `upstream-skills/` checkout keeps its own upstream license from
[mattpocock/skills](https://github.com/mattpocock/skills); it is a source tree for patch
development, not part of what this installer ships.
