---
name: Tmux Subreddit Scanner
description: Searches recent posts on https://www.reddit.com/r/tmux/ for genuine TPM-installable tmux plugins missing from the tpack registry (https://github.com/tmuxpack/plugins-registry), then opens a branch and PR adding them. Strictly excludes standalone CLI/TUI tools, session managers, MCP servers, and other tmux-adjacent software.
---

# Tmux Subreddit Scanner

Search recent posts on https://www.reddit.com/r/tmux/ for tmux plugins missing from the tpack registry (https://github.com/tmuxpack/plugins-registry). For new plugins that pass the strict criteria below, create a feature branch, add entries per the repo's CONTRIBUTING.md and existing YAML format, and open a PR.

## Strict inclusion criteria (a repo MUST meet at least one)

A candidate qualifies as a tmux plugin only if **at least one** is true:

1. Has a `.tmux` file at the repo root (the TPM entrypoint convention).
2. The README documents TPM installation via `set -g @plugin 'owner/repo'`.
3. Ships shell scripts / tmux config snippets explicitly meant to be **sourced from `~/.tmux.conf`** (e.g., `run-shell '~/.tmux/plugins/foo/foo.tmux'`).
4. Registers tmux keybindings, status-line components, hooks, or format strings that load into a running tmux via tmux config — not as a binary the user invokes.

**Verification is mandatory.** Before adding any repo, fetch its README (try `https://raw.githubusercontent.com/OWNER/REPO/main/README.md` then `.../master/README.md`) and confirm at least one of the above signals. If none are present, do not add the repo. Do **not** infer plugin status from the repo name or description alone — many CLI tools are named `tmux-*`.

## Hard exclusions (reject regardless of name)

Reject the candidate if **any** of these apply:

- **Installation method**: distributed via `cargo install`, `npm install -g`, `brew install`, `go install`, `pip install`, `pipx install`, curl-to-bin install scripts, GitHub release binaries, or Nix flakes producing a single binary. These are CLIs, not plugins.
- **`display-popup -E <binary>` pattern**: tmux config snippet only binds a key to launch an external binary via `display-popup -E` (or `run-shell`). The popup is hosting the tool, not extending tmux.
- **Session managers / wrappers**: anything in the tmuxinator / tmuxp / smug / muxie / tmuxifier category that spawns and orchestrates tmux sessions from outside the running tmux server.
- **Git worktree managers** with tmux integration (workmux, twig, ntm-style).
- **MCP servers** (Model Context Protocol) and any AI-agent orchestrators that drive tmux via libtmux / tmux control mode / external IPC.
- **Plugin managers themselves** (TPM, tpack, coffee.tmux, tmuxedo, etc.) — registry-level meta-tools, excluded by convention.
- **Neovim/Vim plugins** that integrate with tmux but are not loaded into tmux itself (`*.nvim`, `*-vim`).
- **Standalone TUIs** that happen to run inside tmux but extend nothing in tmux.
- **Dotfile repos, configuration repos, gists**, and personal `tmux.conf` collections.
- **Tmux forks / alternative builds / ports** (psmux, tmux-windows, sixel-tmux, etc.).
- **Existing under an alias** in the registry — check `scripts/find_missing.py`'s `ALIASES` and `SKIP_REPOS` dictionaries, and look for matching repo names under different owners.
- **GitHub redirects**: if `github.com/owner/repo` 302-redirects to a different repo, check whether the target is already in the registry before adding either.

## Quality bar

In addition to passing the criteria above:

- Repo must return HTTP 200 from the GitHub API (`https://api.github.com/repos/OWNER/REPO`).
- Prefer plugins with ≥ ~5 stars unless the project is clearly novel and well-documented. Trivial single-script projects with 0 stars and a one-line README are usually not worth adding.
- If only **uncertain candidates** remain after applying the criteria, list them in the PR description as "candidates skipped pending review" rather than adding them.

## Workflow

1. Fetch recent r/tmux posts (web/JSON endpoint).
2. Extract every `github.com/OWNER/REPO` reference.
3. De-duplicate against `plugins/*.yml`, `ALIASES`, and `SKIP_REPOS`.
4. For each candidate, fetch the README and apply the inclusion criteria above. Record the specific evidence (`.tmux` file? `@plugin` line? sourced-from-config?) for each kept entry; record the rejection reason for each excluded one.
5. Add accepted plugins to the correct category YAML (`ai.yml`, `session.yml`, `statusbar.yml`, etc.) following the existing field order: `repo`, `description`, `author`. Do not add `stars` or `added_date` — CI populates those.
6. Validate locally with `yq` (same checks CI runs): YAML parses, required fields present, description 10–200 chars, repo matches `^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+$`, no duplicate repos.
7. Create a feature branch (`add-reddit-plugins-YYYY-MM-DD`), commit, push, and open a PR.
8. In the PR description, include:
   - Plugins added, grouped by category.
   - Per-plugin one-line evidence of plugin status (e.g., "has `foo.tmux` at root", "README documents `set -g @plugin`").
   - **Intentional skips** with the rejection reason for each (CLI tool, session manager, MCP server, redirect, alias, etc.).
9. If zero candidates pass the criteria, report that and do not open a PR.

## Reporting back

Return a concise summary: branch name, PR URL, count and category breakdown of added plugins, and the list of intentionally skipped candidates with reasons. Never claim a candidate is a plugin without quoting the specific evidence from its README or file tree.
