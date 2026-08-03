[![CI](https://github.com/pereng11/kkochikkochi/actions/workflows/ci.yml/badge.svg)](https://github.com/pereng11/kkochikkochi/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Claude Code · Codex](https://img.shields.io/badge/Claude%20Code-%C2%B7%20Codex-black)

# KkochiKkochi 🦡

> **KkochiKkochi** *(kko-chi-kko-chi)* — Korean, adv. *questioning in relentless, minute detail.*

**Not a tool to ship faster.
A tool to ship responsibly.**

How many lines did you merge today? How many did you actually read?

The bottleneck in agentic coding was never typing speed. It's your own
comprehension — and the cheapest thing to skip is understanding.

KkochiKkochi puts a wall exactly where the skipping happens: your agent
stops, and waits for *your* answer. Miss it, and the commit does not land.

Works with Claude Code and Codex.

**English** · [한국어](README.ko.md)

## See it work

```
$ git commit -m "add auth middleware"

🦡 KkochiKkochi — this commit still contains changes nobody has verified.
   src/auth/middleware.ts
   src/lib/session.ts
Run the kkochikkochi skill, pass the quiz, then commit again.

Q1. Which paths does the auth middleware let through after this change?
    A) all of /api/*                    C) static assets only
    B) everything except /api/public/*  D) I don't know
→ B  ✓

Q2. In one sentence: why JWT for the session store instead of Redis?
→ ...
Passed. Commit again.
```

In Claude Code the multiple-choice questions arrive through `AskUserQuestion` and you click an answer. Codex has no equivalent tool, so they are printed as plain text and you type the answer — the questions, the grading, and the wrong-answer loop are the same on both.

## Install

**Claude Code**
```
/plugin marketplace add pereng11/kkochikkochi
/plugin install kkochikkochi
```
**Codex**
```
codex plugin marketplace add pereng11/kkochikkochi
codex plugin add kkochikkochi@kkochikkochi
```

Git hooks are per repository, and you rarely have to install them yourself: the first time an agent tries to commit here, the agent hook notices that the git hook is absent or stale, refuses that commit, and hands the agent a runnable install command — the agent runs it and then tries the commit again, since the refused commit does not resume on its own. The exception is a repository using `core.hooksPath`, where the effective hook directory is tracked by the repository, so the agent asks you before writing to it ([D32](docs/DECISIONS.md)).

By hand: `bash scripts/install.sh install|uninstall|status`, where `status` exits `0` installed and current, `1` not installed, `2` refused because the repository uses `core.hooksPath`, `3` ours but stale. An existing `pre-commit` hook is chained rather than replaced, and runs first. The gate reads what an agent is about to commit. It never touches commits you type yourself.

Requires `git` and `jq`. Optionally the `humanize-korean` skill from [im-not-ai](https://github.com/epoko77-ai/im-not-ai), which polishes the wording of questions — the gate works the same without it ([D46](docs/DECISIONS.md)).

Setting this up with an agent? See [AGENTS.md](AGENTS.md).

## What gets gated

| This commit is... | Gate |
|---|---|
| made by Claude Code or Codex | **On.** This is the reason the tool exists. |
| typed by a human, in a terminal or an IDE | **Off.** By design — they were there, so comprehension is not the bottleneck ([D41](docs/DECISIONS.md), [D44](docs/DECISIONS.md)). |
| `git revert` · `cherry-pick` · `merge` | **Off at commit time.** git never calls `pre-commit` for these (measured). `pre-push` still re-reads what a merge commit newly created ([D13](docs/DECISIONS.md), [D47](docs/DECISIONS.md)). |
| `git commit --no-verify` (or `-n`) | **Bypassable.** The agent hook tries to refuse it — best effort, not a guarantee ([D29](docs/DECISIONS.md)). |

A commit made by an agent that is not on that list is treated as an ambiguous case, and ambiguous cases pass ([D35](docs/DECISIONS.md)).

## What it asks

| Axis | Example |
|---|---|
| What changed | Which file, and what in it |
| Impact and risk | What could this break |
| Design intent | Why this way, and what was rejected |
| Reproducibility | Where would you go to change X |

At most five questions, and as a rule at least one — the exception is a change with nothing to ask about, such as a regenerated lockfile or formatting alone, which passes with zero questions and a recorded reason. The three-minute target counts the wrong-answer retry loop, not only a clean first pass, and a question whose grounds cannot be pointed at in the code or the conversation is never asked ([D14](docs/DECISIONS.md), [D17](docs/DECISIONS.md), [D19](docs/DECISIONS.md)).

## How it holds

Two hooks split the work. The agent hook (`PreToolUse`) does anything only when the command contains `commit`: it leaves a handshake saying an agent is about to commit, and it health-checks whether the git hook is installed and current. It is not itself the gate — nothing about safety breaks if it misses something there. The gate is git's `pre-commit`, and because git calls it directly, the `git diff --cached` inside it is the content of the commit itself, so no command string has to be parsed ([D28](docs/DECISIONS.md), [D30](docs/DECISIONS.md), [D44](docs/DECISIONS.md)).

| Trigger | What it does |
|---|---|
| `SubagentStart` / `SubagentStop` | Opens and seals a bundle (`agents/<hash>`) |
| `PostToolUse` (Claude Code `Task`, Codex `spawn_agent`) | Asks the parent agent to verify the sealed bundle |
| `Stop` | Refuses to end the turn with unverified changes left |
| git `pre-push` | Final boundary — `Stop` can be escaped with Esc |

Subagents cannot ask a human, so blocking them at `pre-commit` would leave
them no way through. They are recorded in a ledger and enforced later instead.

Everything the gate records lives inside `.git/` and is never committed ([D08](docs/DECISIONS.md), [D11](docs/DECISIONS.md)).

## Commands

| Command | What it does |
|---|---|
| `/kk` | Quiz me on what's staged right now |
| `/kk-log` | Show my verification history and my weakest axes |
| `/kk-defer` | Batch this turn's subagent bundle quizzes to the end of the turn — this turn only, not a permanent bypass |

## What it misses

Measured during the v2 and v3 migrations, not guessed. The reasoning behind
each is in [docs/DECISIONS.md](docs/DECISIONS.md).

| | |
|---|---|
| **Ways out** — someone who wants past this gets past it | `--no-verify` ([D29](docs/DECISIONS.md)) · a commit hidden inside `make release` or `bash deploy.sh` · an agent we don't recognize ([D35](docs/DECISIONS.md)) · a harness that wraps its tools in a pty ([D41](docs/DECISIONS.md)) · `git -C <other repo> commit` ([D44](docs/DECISIONS.md)) |
| **Ways it over-blocks** — you can be stopped when you shouldn't be | `pre-push` does not look at who wrote the commit ([D47](docs/DECISIONS.md)) · work cherry-picked or squashed in from others · paths containing a tab ([D08](docs/DECISIONS.md)) or a newline ([D43](docs/DECISIONS.md)) |
| **Operational** | no `jq` opens the gate ([D42](docs/DECISIONS.md)) · records are never trimmed ([D18](docs/DECISIONS.md)) · `uninstall` deletes your audit log, and worktrees share it ([D11](docs/DECISIONS.md)) · a stale remote-tracking ref re-checks commits that are already pushed — `git fetch` clears it |

None of these lock you out. Every over-block has a way through, and the last
resort is always `--no-verify`.

> This is a discipline device, not a security boundary.
> It is not built to survive someone who wants around it.
> It is built so that *not thinking* is no longer the path of least resistance.

## Docs · License

- [docs/DECISIONS.md](docs/DECISIONS.md) — every design decision and every rejected alternative. Start at D00; it is the premise the rest answer to.
- [CONTRIBUTING.md](CONTRIBUTING.md) — development setup, tests, and the design rules this codebase holds to. Written in Korean.
- [AGENTS.md](AGENTS.md) — install runbook for an agent doing this for you.
- [v2 architecture](docs/superpowers/specs/2026-07-30-kkochikkochi-v2-hybrid-design.md) — why the gate moved into a git hook.

MIT.
