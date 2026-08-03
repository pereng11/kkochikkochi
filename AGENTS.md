# For coding agents

This file is for an agent **installing and operating KkochiKkochi** for a user.
If you are contributing to this repository, read
[CONTRIBUTING.md](CONTRIBUTING.md) instead.

KkochiKkochi blocks a commit until the human can explain what changed.
Do not work around it. See [README.md](README.md) for what it is.

## 1. Install the plugin

Slash commands like `/plugin install` cannot be run by an agent. Use the CLI.

```bash
claude plugin marketplace add pereng11/kkochikkochi
claude plugin install kkochikkochi@kkochikkochi
```

Claude Code must be restarted before the plugin loads. Tell the user this —
you cannot restart it yourself.

For Codex:

```bash
codex plugin marketplace add pereng11/kkochikkochi
codex plugin add kkochikkochi@kkochikkochi
```

## 2. Install the git hook, once per repository

The plugin only places scripts in the plugin cache. The actual gate is a git
`pre-commit` hook, and `.git/hooks/` is not tracked by git — so it does not
survive `git clone` and must be installed in every repository.

You normally do not have to do this by hand. The first time you try to commit
in a repository, the agent hook detects a missing or stale git hook, refuses
that commit, and hands you the exact command. Run it, then **retry the commit**
— the refused commit does not resume on its own.

```bash
bash scripts/install.sh install
bash scripts/install.sh status
```

`status` exit codes:

| Code | Meaning | What to do |
|---|---|---|
| `0` | installed and current | nothing |
| `1` | not installed | run `install` |
| `2` | refused — this repo sets `core.hooksPath` | see below |
| `3` | ours, but stale | run `install` again |

Any existing `pre-commit` hook is chained, not replaced. It runs first, and a
non-zero exit from it still blocks the commit.

## 3. Repositories that set `core.hooksPath`

If `status` returns `2`, the repository redirects hooks elsewhere (husky and
similar). That directory is tracked by git, so writing to it is a tracked
change. **Do not do it silently — ask the user first.**

## 4. When the gate blocks you

Run the `kkochikkochi` skill. It quizzes the user on the staged change and
records the result, which unlocks the commit. Then **retry the commit.**

Do not use `git commit --no-verify` or `git push --no-verify` to get past it.
The agent hook tries to refuse both, but that check is best-effort — the real
reason not to do it is that bypassing the gate defeats the whole point.

## 5. Requirements

`git` and `jq`. Without `jq` the gate cannot record a pass, so the installer
refuses to install; if `jq` disappears afterwards, the hook warns and lets the
commit through.
