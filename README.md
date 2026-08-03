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

An agent commits, the gate stops it, the agent runs the skill, and the quiz follows. The gate's message is verbatim; the quiz under it is representative, because the skill writes those questions fresh for each change. Text after `#` is an English gloss added here, part of neither.

```
$ git commit -m "add auth middleware"

🦡 KkochiKkochi — 이 커밋에 아직 검증되지 않은 변경이 있습니다.
#  this commit still contains changes nobody has verified

   src/auth/middleware.ts
   src/lib/session.ts

이 변경을 이해했는지 먼저 확인해야 합니다.
kkochikkochi 스킬을 실행해 퀴즈를 통과한 뒤 다시 커밋하세요.
#  confirm you understood these changes: run the kkochikkochi skill, pass the quiz, commit again
(판별 신호: handshake:claude-code)   #  the signal that classified this commit as an agent's

Q1. 이 변경으로 auth 미들웨어가 통과시키는 경로는?
#   which paths does the auth middleware let through after this change?
    A) /api/* 전체                    #  all of /api/*
    B) /api/public/* 을 제외한 전체   #  everything except /api/public/*
    C) 정적 에셋만                    #  static assets only
    D) 모르겠다                       #  I don't know

→ B  ✓

Q2. 세션 저장소를 Redis 대신 JWT 로 간 이유를 한 문장으로 적으세요.
#   in one sentence, why JWT instead of Redis for the session store?
→ ...

통과했습니다. 다시 커밋하세요.   #  passed — commit again
```

The gate's messages and its questions are Korean today, because the hook text and the skill that writes the questions are both authored in Korean; localization is planned. In Claude Code the multiple-choice questions arrive through `AskUserQuestion` and you click an answer. Codex has no equivalent tool, so they are printed as plain text and you type the answer. The questions, the grading, and the wrong-answer loop are the same on both.

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

Git hooks live in `.git/hooks/`, which git does not track. That makes them per repository, and it means they do not survive a `git clone` — a fresh clone starts ungated until the gate is installed there too. You rarely have to do that yourself. The first time an agent tries to commit in a repository, the agent hook notices the git hook is absent or stale, refuses that commit, and hands the agent a runnable install command. The agent runs it and then commits again; the refused commit does not resume on its own. Repositories that set `core.hooksPath` are the exception — the effective hook directory there is tracked by the repository, so the agent asks you before writing to it ([D32](docs/DECISIONS.md)).

To do it by hand, run `bash <plugin-dir>/scripts/install.sh install`, `uninstall`, or `status` from inside the repository you want gated. `status` exits `0` when the gate is installed and current, `1` when it is not installed, `2` when it refused because the repository sets `core.hooksPath`, and `3` when the installed hook is KkochiKkochi's but out of date — rerun `install` to refresh it. An existing `pre-commit` hook is chained rather than replaced: it runs first, and if it exits non-zero the commit ends there with that exit code ([D31](docs/DECISIONS.md)).

At commit time the gate reads what an agent is about to commit and leaves commits you type yourself alone ([D33](docs/DECISIONS.md), [D41](docs/DECISIONS.md)). `pre-push` is the caveat: it cannot tell after the fact who wrote a commit, so it re-checks yours too ([D47](docs/DECISIONS.md)).

Requires `git` and `jq`. Optionally the `humanize-korean` skill from [im-not-ai](https://github.com/epoko77-ai/im-not-ai), which polishes the wording of questions — the gate works the same without it ([D46](docs/DECISIONS.md)). Setting this up with an agent? See [AGENTS.md](AGENTS.md).

## What gets gated

| This commit is... | Gate |
|---|---|
| made by Claude Code or Codex | **On.** This is the reason the tool exists. |
| typed by a human, in a terminal or an IDE | **Off.** By design — they were there, so comprehension is not the bottleneck ([D41](docs/DECISIONS.md), [D44](docs/DECISIONS.md)). |
| `git revert` · `cherry-pick` · `merge` | **Off at commit time.** git never calls `pre-commit` for these (measured). `pre-push` still re-reads what a merge commit newly created ([D13](docs/DECISIONS.md), [D47](docs/DECISIONS.md)). |
| `git commit --no-verify` (or `-n`) | **Bypassable.** The agent hook tries to refuse it — best effort, not a guarantee ([D29](docs/DECISIONS.md)). |

`git push --no-verify` is the same story: the agent hook watches `push` as well and tries to refuse it, still best effort and not a guarantee. That refusal only engages when the command carries a `git` or `g` token, so `--no-verify` under some other alias goes unnoticed, and the prefilter that writes the handshake still looks at `commit` alone ([D29](docs/DECISIONS.md), [D44](docs/DECISIONS.md)). A commit made by an agent that is not on the list above is treated as an ambiguous case, and ambiguous cases pass ([D35](docs/DECISIONS.md)).

A `git commit` you run to finish a conflicted merge, cherry-pick, revert, or rebase is excluded too: the gate sees the in-progress marker (`MERGE_HEAD`, `CHERRY_PICK_HEAD`, `REVERT_HEAD`, or a rebase directory) and steps aside. `git commit --amend` needs no rule of its own — amending the message alone stages no new delta and passes, while an amend that adds content is gated on exactly what it added ([D12](docs/DECISIONS.md)).

## What it asks

| Axis | Example |
|---|---|
| What changed | Which file, and what in it |
| Impact and risk | What could this break |
| Design intent | Why this way, and what was rejected |
| Reproducibility | Where would you go to change X |

At most five questions, and as a rule at least one — the exception is a change with nothing to ask about, such as a regenerated lockfile or formatting alone, which passes with zero questions and a recorded reason. The three-minute target counts the wrong-answer retry loop, not only a clean first pass, and a question whose grounds cannot be pointed at in the code or the conversation is never asked ([D14](docs/DECISIONS.md), [D17](docs/DECISIONS.md), [D19](docs/DECISIONS.md)).

## How it holds

Two hooks split the work, and only one of them is the gate. The agent hook (`PreToolUse`) does two separate jobs. It tries to refuse `--no-verify` and its short form `-n` on any command that names `git` and looks like a commit or a push. Then, only when the command contains `commit`, it leaves a handshake saying an agent is about to commit and health-checks whether this repository's git hook is installed and current. Neither job is the gate: if the agent hook misses a case, what sits underneath is unaffected. That is git's `pre-commit`. git calls it directly, so the `git diff --cached` inside it is the content of the commit itself, and no command string has to be parsed ([D28](docs/DECISIONS.md), [D30](docs/DECISIONS.md), [D44](docs/DECISIONS.md)).

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
| **Ways out** — someone who wants past this gets past it | `--no-verify` ([D29](docs/DECISIONS.md)) · a commit hidden inside `make release` or `bash deploy.sh` · an agent we don't recognize ([D35](docs/DECISIONS.md)) · a harness that wraps its tools in a pty ([D41](docs/DECISIONS.md)) · `git -C <other repo> commit` ([D44](docs/DECISIONS.md)) · an agent that calls `record-pass.sh` without running the quiz — empty answers are rejected, and past that only reading the record shows it ([D10](docs/DECISIONS.md)) |
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
