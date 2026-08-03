# README 재작성 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** README 를 "왜 이 도구가 존재하는가"로 여는 영어 문서로 새로 쓰고, 한국어 미러와 에이전트용 설치 런북을 분리한다.

**Architecture:** 코드는 건드리지 않는다. 현재 `README.md` 188줄이 담고 있는 여섯 가지 역할을 독자별로 네 파일에 나눈다 — 처음 온 사람은 `README.md`(영어, 약 120줄), 한국어 독자는 `README.ko.md`, 설치를 대행하는 에이전트는 `AGENTS.md`, 설계 근거는 기존 `docs/DECISIONS.md`. README 에서 잘려나가는 세부는 **먼저** `DECISIONS.md` 에 흡수시킨 뒤 지운다.

**Tech Stack:** Markdown 뿐이다. 새 스크립트를 만들지 않는다 — 검증은 전부 셸 일회성 명령으로 한다.

## Global Constraints

- **설계 스펙:** `docs/superpowers/specs/2026-08-03-readme-rewrite-design.md`. 이 계획과 어긋나면 스펙이 정본이다
- **코드 변경 없음.** `scripts/`, `hooks/`, `tests/`, `hooks.json`, `.claude-plugin/`, `.codex-plugin/` 을 건드리지 않는다
- **새 파일은 `README.ko.md`, `AGENTS.md` 둘뿐이다.** `LIMITS.md`, `HOW-IT-WORKS.md`, `TROUBLESHOOTING.md`, `ARCHITECTURE.md` 를 만들지 않는다 (스펙 §3)
- **사용자 문서는 영어, 기여자 문서는 한국어.** `CONTRIBUTING.md` 와 `docs/DECISIONS.md` 는 한국어를 유지한다
- **용어:** `agentic coding` 을 쓴다. `AI-assisted coding` 과 `vibe coding` 을 쓰지 않는다 (스펙 §5.0)
- **한국어는 리터럴로 쓴다.** `\uXXXX` 이스케이프를 쓰지 않는다
- **`<details>` 를 쓰지 않는다** (스펙 §8)
- **`DECISIONS.md` 링크는 D 번호로 건다.** 절 제목이 아니라 번호로 (스펙 §8)
- **새로 만들어낸 주장을 넣지 않는다.** 모든 사실 진술은 현재 `README.md` 또는 `docs/DECISIONS.md` 에서 근거를 찾을 수 있어야 한다
- **커밋 메시지:** Conventional Commits (`docs:`, `fix:` 등)

---

### Task 1: `DECISIONS.md` 에 README 에서 사라질 세부를 흡수시킨다

README 한계 표 19행 중 12행은 설계 근거가 이미 `DECISIONS.md` 에 있다. 나머지 **7건은 집이 없다.** README 를 먼저 지우면 이 7건이 저장소에서 사라지므로, 흡수를 **먼저** 한다.

덤으로 D44 와 D47 이 "한계 표에 적었다"고 README 를 가리키는데, 표가 줄면 이 참조가 낡는다. 같이 고친다.

**Files:**
- Modify: `docs/DECISIONS.md`

**Interfaces:**
- Consumes: 없음 (첫 태스크)
- Produces: Task 2 가 README 에서 삭제해도 되는 항목 목록. Task 2 는 D08 · D11 · D29 · D44 · D47 로 링크를 건다

- [ ] **Step 1: 기준점 태그를 찍고, 흡수 대상 7건이 정말 없는지 확인한다**

뒤의 태스크들이 "재작성 전 README" 와 "코드를 건드리지 않았다" 를 확인할 때 이 태그를 쓴다. 커밋 개수에 의존하는 `HEAD~N` 을 쓰지 않기 위해서다.

```bash
cd /Users/ellis/Documents/project/kkochikkochi
git tag -f readme-rewrite-base HEAD
git rev-parse readme-rewrite-base   # SHA 가 찍히면 성공

grep -c '탭' docs/DECISIONS.md                    # 기대: 0
grep -c '워크트리 공유\|quiz-gate 를 공유' docs/DECISIONS.md   # 기대: 0
grep -c 'passes/\*.json' docs/DECISIONS.md         # 기대: 0
grep -c 'stale' docs/DECISIONS.md                  # 기대: 0
```

네 개가 전부 `0` 이어야 한다. `0` 이 아니면 이미 흡수된 것이므로 그 항목은 Step 2~6 에서 건너뛰고, 무엇을 건너뛰었는지 기록한다.

- [ ] **Step 2: D08 에 탭 경로 한계를 붙인다**

`### D08. 토큰을 파일 단위 blob SHA에 바인딩한다 ✅` 절 **본문 맨 끝**에 추가한다.

```markdown
**한계 — 경로에 탭 문자가 있으면 기록할 수 없다.** `covered.tsv` 가 탭으로 필드를 구분하므로, 파일명에 실제 탭 바이트가 든 경로는 커버리지를 남길 수 없고 따라서 퀴즈로 통과시킬 수도 없다. 매우 드문 사례다. 갇히지는 않는다 — `git commit --no-verify` 로 그 커밋을 통과시키거나 `bash scripts/install.sh uninstall` 로 게이트를 걷어내면 된다. `pre-push` 도 같은 이유로 같은 커밋을 막으므로 push 할 때는 `git push --no-verify` 가 추가로 필요하다.
```

- [ ] **Step 3: D11 에 uninstall 손실과 워크트리 공유를 붙인다**

`### D11. 저장 구조를 검증용과 감사용으로 분리한다 🔄` 절 **본문 맨 끝**에 추가한다.

```markdown
**한계 — `uninstall` 은 감사 기록을 함께 지운다.** `scripts/install.sh uninstall` 이 `.git/quiz-gate/` 를 통째로 지우므로 `/kk-log` 가 읽는 `passes/*.json` 도 사라지고 복구되지 않는다. 무엇을 지웠는지 stderr 에 알린다.

**한계 — 워크트리는 상태를 공유한다.** `quiz-gate` 가 `--git-common-dir` 아래 있어 한 워크트리에서 `uninstall` 하면 전부 사라진다. 훅(`.git/hooks/`)도 공유되므로 동작 자체는 일관된다.
```

- [ ] **Step 4: D29 에 `--no-verify` 감지의 실제 규칙을 붙인다**

`### D29. Claude 훅의 새 역할은 게이트의 존재 보장이다 ✅` 절에서 `**따라서** \`--no-verify\` 감지는 단순 문자열 포함 검사로 충분하다.` 로 시작하는 문단 **바로 뒤**에 추가한다.

```markdown
**실제로 구현된 규칙 (2026-08-01, `3274a1b`).** 검사는 `--no-verify` 와 짧은 형태 `-n`(`-nm`·`-qn` 등 묶음 포함)을 본다. 오탐 방향으로 헐겁게 잡는다 — **하이픈 하나로 시작하는 낱말 안에 `n` 이 있으면 무엇이든 걸린다.** 커밋 메시지 안의 ` -n `, 그리고 `git log --oneline | head -n 20 && git commit -m x` 처럼 커밋과 무관한 `-n` 도 포함된다. 오탐은 왕복 한 번이고 미탐은 게이트가 흔적 없이 사라지는 것이기 때문이다.

단, 이 판정은 명령에 `git`·`g` 토큰이 있을 때만 들어간다 — `grep -rn push src/` 처럼 `commit`·`push` 글자와 짧은 `-n` 묶음을 우연히 담는(그러나 git 과 무관한) 명령의 오탐을 줄이기 위해서다. **대가:** `git`·`g` 가 아닌 다른 git 별칭(`gc`, `gcmsg`, 셸에 직접 만든 별칭)으로 `--no-verify` 를 곁들여 commit·push 하면 이 검사가 잡지 못한다. 좁지만 실재하는 미탐이며, 사람이 받아들인 트레이드오프다.
```

- [ ] **Step 5: D44 에 `git -C` 미탐을 붙이고 README 참조를 고친다**

`### D44.` 절에서 `**대가 (한계 표에 적었다)**` 로 시작하는 문단을 찾는다. 두 가지를 한다.

첫째, 그 문단의 머리말 `**대가 (한계 표에 적었다)**` 를 `**대가**` 로 바꾼다. README 한계 표가 3그룹 요약으로 줄어 더 이상 이 항목을 통째로 담지 않는다.

둘째, 그 문단 **바로 뒤**에 추가한다.

```markdown
**같은 뿌리의 두 번째 대가 — `git -C <다른 저장소> commit`.** 핸드셰이크는 에이전트 훅이 도는 **현재 디렉터리의 저장소**에 남는다. 에이전트가 다른 저장소를 커밋하면 그쪽엔 마커가 없어 환경변수 신호에만 기대게 된다 — Claude Code 는 `CLAUDECODE` 덕에 우연히 걸리지만 Codex 는 식별용 환경변수를 아예 내보내지 않아 전혀 걸리지 않는다.
```

- [ ] **Step 6: D47 에 pre-push 의 무차별성과 stale ref 를 붙이고 README 참조를 고친다**

`### D47.` 절에서 `**대가.**` 로 시작하는 문단을 찾는다. 두 가지를 한다.

첫째, 그 문단의 마지막 문장 `둘 다 README 한계 표에 적었다.` 를 삭제한다.

둘째, 그 문단 **바로 뒤**에 추가한다.

```markdown
**이 층은 커밋의 출처를 보지 않는다.** 커밋 시점의 TTY·핸드셰이크 신호를 사후에 복원할 방법이 없기 때문이다. 그래서 `pre-commit` 이 통과시킨 사람 커밋도 push 때는 퀴즈를 요구한다. 갇히지는 않는다 — 커밋이 이미 리모트에 있는데 로컬의 추적 ref 가 stale 해서 걸렸을 뿐이라면 `git fetch` 로 먼저 풀리는지 보고, 그래도 막히면 `git push --no-verify` 가 최후 수단이다.

**리모트 추적 ref 가 stale 하면 이미 리모트에 있는 커밋도 검사한다.** `git fetch` 하면 풀린다. 안전 방향이라 그대로 둔다.
```

- [ ] **Step 7: 흡수가 됐는지 확인한다**

```bash
cd /Users/ellis/Documents/project/kkochikkochi
grep -c '탭' docs/DECISIONS.md              # 기대: 1 이상
grep -c '워크트리는 상태를 공유' docs/DECISIONS.md   # 기대: 1
grep -c 'passes/\*.json' docs/DECISIONS.md   # 기대: 1
grep -c 'stale' docs/DECISIONS.md            # 기대: 2 이상
grep -c 'git -C <다른 저장소>' docs/DECISIONS.md    # 기대: 1
grep -c 'gcmsg' docs/DECISIONS.md            # 기대: 1
grep -c '한계 표에 적었다' docs/DECISIONS.md  # 기대: 0
```

마지막 줄이 `0` 이어야 한다. 낡은 README 참조가 남아 있으면 안 된다.

- [ ] **Step 8: 커밋**

```bash
cd /Users/ellis/Documents/project/kkochikkochi
git add docs/DECISIONS.md
git commit -m "docs: absorb the limits detail that the new README will drop"
```

---

### Task 2: `README.md` 를 영어로 새로 쓴다

**Files:**
- Modify: `README.md` (전면 재작성, 188줄 → 약 120줄)

**Interfaces:**
- Consumes: Task 1 이 흡수한 D08 · D11 · D29 · D44 · D47 항목
- Produces: Task 3 이 가리킬 `## Install` 섹션, Task 4 가 1:1 로 미러링할 H2 8개 — `See it work`, `Install`, `What gets gated`, `What it asks`, `How it holds`, `Commands`, `What it misses`, `Docs · License`

- [ ] **Step 1: 현재 상태를 기록해 둔다**

```bash
cd /Users/ellis/Documents/project/kkochikkochi
wc -l README.md                    # 기대: 188
grep -c '^## ' README.md           # 기대: 10
```

- [ ] **Step 2: 도입부를 쓴다 (H2 이전, 약 22줄)**

배지 한 줄 → 제목 → 정의 인용 → 선언문 4문단 → 언어 링크. 선언문은 아래 문면을 **그대로** 쓴다. 스펙 §5.0 에서 승인된 문장이다.

```markdown
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
```

- [ ] **Step 3: `## See it work` 을 쓴다 (약 20줄)**

현재 `README.md:29-58` 의 두 코드 블록을 **하나로 합쳐** 영어로 옮긴다. 차단 화면과 이어지는 퀴즈가 한 덩어리로 읽혀야 한다. 블록 뒤에 한 문장을 남긴다 — Claude Code 에서는 객관식이 `AskUserQuestion` 으로 클릭 선택되고 Codex 에는 그 대응 도구가 없어 평문으로 제시되어 타이핑으로 답하지만, 문항 내용·채점·오답 루프는 두 에이전트에서 동일하다는 것.

- [ ] **Step 4: `## Install` 을 쓴다 (약 22줄)**

네 덩어리를 순서대로 넣는다.

1. Claude Code 슬래시 2줄 (`/plugin marketplace add pereng11/kkochikkochi`, `/plugin install kkochikkochi`) 과 Codex 슬래시 2줄 (`codex plugin marketplace add pereng11/kkochikkochi`, `codex plugin add kkochikkochi@kkochikkochi`)
2. 저장소별 git 훅. **보통 직접 할 필요가 없다**는 것 — 이 저장소에서 에이전트가 처음 커밋을 시도하면 에이전트 훅이 git 훅의 부재나 낡음을 감지해 그 커밋을 거부하고 실행 가능한 설치 명령을 준다. 에이전트가 그 명령을 실행한 뒤 **커밋을 다시 시도**하면 된다(거부된 커밋 자체가 이어지는 것은 아니다). 예외는 `core.hooksPath` 저장소뿐이며 그때는 사용자에게 확인을 구한다 ([D32](docs/DECISIONS.md)). 수동 명령 `bash scripts/install.sh install|uninstall|status` 와 `status` 종료 코드 `0` 설치됨(최신) · `1` 미설치 · `2` `core.hooksPath` 라 거부 · `3` 낡음. 기존 `pre-commit` 훅은 자동 체이닝되며 먼저 실행된다는 것
3. 필요 도구 `git`, `jq`. 선택 도구 [im-not-ai](https://github.com/epoko77-ai/im-not-ai) 의 `humanize-korean` — 없어도 게이트는 그대로 동작한다 ([D46](docs/DECISIONS.md))
4. 에이전트 포인터 — `Setting this up with an agent? See [AGENTS.md](AGENTS.md).`

**이 섹션에 안심 문장을 반드시 넣는다.** `It never touches commits you type yourself.` 다음 섹션의 표를 8행에서 4행으로 줄이면서 빠지는 정보인데 설치 결정에 영향을 주므로 산문으로 살린다 (스펙 §5.2).

- [ ] **Step 5: `## What gets gated` 를 쓴다 (약 10줄)**

표를 **그대로** 쓴다. 현재 8행 표(`README.md:14-23`)의 압축본이다.

```markdown
| This commit is... | Gate |
|---|---|
| made by Claude Code or Codex | **On.** This is the reason the tool exists. |
| typed by a human, in a terminal or an IDE | **Off.** By design — they were there, so comprehension is not the bottleneck ([D41](docs/DECISIONS.md), [D44](docs/DECISIONS.md)). |
| `git revert` · `cherry-pick` · `merge` | **Off at commit time.** git never calls `pre-commit` for these (measured). `pre-push` still re-reads what a merge commit newly created ([D13](docs/DECISIONS.md), [D47](docs/DECISIONS.md)). |
| `git commit --no-verify` (or `-n`) | **Bypassable.** The agent hook tries to refuse it — best effort, not a guarantee ([D29](docs/DECISIONS.md)). |
```

표 아래에 한 문장을 붙인다 — 목록에 없는 에이전트가 만든 커밋은 "애매한 경우"로 분류돼 통과한다는 것, 근거는 [D35](docs/DECISIONS.md).

현재 README 의 별도 절 `게이트가 통과시키는 git 커맨드`(`README.md:129-136`) 6항목은 **이 표에 흡수하고 절 자체를 삭제한다.** 상세는 D13 · D47 링크가 대신한다.

- [ ] **Step 6: `## What it asks` 를 쓴다 (약 12줄)**

표를 **그대로** 쓴다.

```markdown
| Axis | Example |
|---|---|
| What changed | Which file, and what in it |
| Impact and risk | What could this break |
| Design intent | Why this way, and what was rejected |
| Reproducibility | Where would you go to change X |
```

표 아래 문항 예산을 산문 두 문장으로 — 최대 5문항, 원칙적으로 최소 1문항이며 질문거리가 전혀 없는 경우(lockfile 재생성, 포매팅만)에 한해 예외적으로 0개 + 사유 기록으로 통과, 목표 3분은 오답 재시도 루프까지 포함한 시간, 근거를 코드나 대화에서 특정할 수 없는 문항은 출제되지 않는다 ([D14](docs/DECISIONS.md), [D17](docs/DECISIONS.md), [D19](docs/DECISIONS.md)).

- [ ] **Step 7: `## How it holds` 를 쓴다 (약 16줄)**

먼저 두 훅의 역할 분담을 한 문단으로. 에이전트 훅(`PreToolUse`)은 커맨드에 `commit` 이 들어 있을 때만 핸드셰이크를 남기고 설치 상태를 건강검진하며 **그 자체는 게이트가 아니다** — 거기서 뭔가 놓쳐도 안전은 깨지지 않는다. 실제 게이트는 git `pre-commit` 이고, git 이 직접 호출하므로 그 안의 `git diff --cached` 가 **커밋될 내용 그 자체**여서 커맨드 문자열을 파싱하지 않는다 ([D28](docs/DECISIONS.md), [D30](docs/DECISIONS.md), [D44](docs/DECISIONS.md)).

그다음 표를 **그대로** 쓴다.

```markdown
| Trigger | What it does |
|---|---|
| `SubagentStart` / `SubagentStop` | Opens and seals a bundle (`agents/<hash>`) |
| `PostToolUse` (Claude Code `Task`, Codex `spawn_agent`) | Asks the parent agent to verify the sealed bundle |
| `Stop` | Refuses to end the turn with unverified changes left |
| git `pre-push` | Final boundary — `Stop` can be escaped with Esc |

Subagents cannot ask a human, so blocking them at `pre-commit` would leave
them no way through. They are recorded in a ledger and enforced later instead.
```

마지막에 기록 위치 한 문장 — 검증 기록은 `.git/` 안에만 있고 절대 커밋되지 않는다는 것 ([D08](docs/DECISIONS.md), [D11](docs/DECISIONS.md)).

**판별 순서(TTY → 핸드셰이크 → 환경변수), 핸드셰이크 신선도 600초, `covered.tsv`·`passes/`·`marker/`·`ledger.tsv`·`epoch` 의 파일 포맷은 넣지 않는다.** 현재 README 의 `어떻게 기억하는가` 절(`README.md:138-148`)은 통째로 삭제되고 D 링크가 대신한다 (스펙 §5.5).

- [ ] **Step 8: `## Commands` 를 쓴다 (약 8줄)**

```markdown
| Command | What it does |
|---|---|
| `/kk` | Quiz me on what's staged right now |
| `/kk-log` | Show my verification history and my weakest axes |
| `/kk-defer` | Batch this turn's subagent bundle quizzes to the end of the turn — this turn only, not a permanent bypass |
```

- [ ] **Step 9: `## What it misses` 를 쓴다 (약 16줄)**

표와 인용구를 **그대로** 쓴다.

```markdown
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
```

- [ ] **Step 10: `## Docs · License` 를 쓴다 (약 8줄)**

아래를 **그대로** 쓴다.

```markdown
- [docs/DECISIONS.md](docs/DECISIONS.md) — every design decision and every
  rejected alternative. Start at D00; it is the premise the rest answer to.
- [CONTRIBUTING.md](CONTRIBUTING.md) — development setup, tests, and the
  design rules this codebase holds to. Written in Korean.
- [AGENTS.md](AGENTS.md) — install runbook for an agent doing this for you.
- [v2 architecture](docs/superpowers/specs/2026-07-30-kkochikkochi-v2-hybrid-design.md)
  — why the gate moved into a git hook.

MIT.
```

- [ ] **Step 11: 분량과 구조를 검증한다**

```bash
cd /Users/ellis/Documents/project/kkochikkochi
wc -l README.md                    # 기대: 105~140
grep -c '^## ' README.md           # 기대: 8
grep -n '^## ' README.md           # 순서 확인
grep -c 'AI-assisted' README.md    # 기대: 0
grep -c 'vibe coding' README.md    # 기대: 0
grep -c '<details>' README.md      # 기대: 0
grep -c 'agentic coding' README.md # 기대: 1
```

- [ ] **Step 12: 링크가 전부 유효한지 검증한다**

상대 링크가 실제 파일을 가리키는지, D 번호가 `DECISIONS.md` 에 실재하는지 본다.

```bash
cd /Users/ellis/Documents/project/kkochikkochi
grep -o '](\([^)#h][^)]*\))' README.md | sed 's/](\(.*\))/\1/' | sort -u | \
  while IFS= read -r p; do [ -e "$p" ] || echo "MISSING FILE: $p"; done

grep -o 'D[0-9][0-9]' README.md | sort -u | \
  while IFS= read -r d; do grep -q "^#\{2,3\} $d\." docs/DECISIONS.md || echo "MISSING DECISION: $d"; done
```

두 명령 모두 아무것도 출력하지 않아야 한다. `AGENTS.md` 는 Task 3 에서 만들므로 이 시점에는 `MISSING FILE: AGENTS.md` 가 나온다 — **이것만은 예상된 실패**이고 Task 3 이후 사라져야 한다.

- [ ] **Step 13: 커밋**

```bash
cd /Users/ellis/Documents/project/kkochikkochi
git add README.md
git commit -m "docs: rewrite the README around why the gate exists"
```

---

### Task 3: `AGENTS.md` 를 만든다

**Files:**
- Create: `AGENTS.md`

**Interfaces:**
- Consumes: Task 2 의 `README.md` — 이 파일이 README 의 `## Install` 을 대신하는 것이 아니라 보완한다
- Produces: Task 5 의 링크 검증이 해소할 `AGENTS.md` 참조

- [ ] **Step 1: 파일을 만든다**

아래 내용을 **그대로** 쓴다. 산문을 늘리지 않는다 — 에이전트가 위에서 아래로 실행하는 런북이다.

````markdown
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
````

- [ ] **Step 2: 참조하는 파일이 실재하는지 검증한다**

```bash
cd /Users/ellis/Documents/project/kkochikkochi
grep -o '](\([^)#h][^)]*\))' AGENTS.md | sed 's/](\(.*\))/\1/' | sort -u | \
  while IFS= read -r p; do [ -e "$p" ] || echo "MISSING FILE: $p"; done
```

아무것도 출력하지 않아야 한다.

- [ ] **Step 3: 문서에 적힌 CLI 표면이 실재하는지 확인한다**

```bash
claude plugin marketplace --help | grep -q '^  add ' && echo "marketplace add OK"
claude plugin install --help    | grep -q 'plugin@marketplace' && echo "install OK"
```

두 줄 다 나와야 한다. 안 나오면 `claude` CLI 가 바뀐 것이므로 문서를 그 출력에 맞춘다.

`codex plugin ...` 형식은 현재 README 표기를 그대로 옮긴 것이다. 2026-08-03 이 환경에서는 로컬 `codex` 바이너리가 `ENOENT` 로 깨져 있어 실행 확인을 하지 못했다. 확인 가능하면 하고, 다르면 문서를 고친다.

- [ ] **Step 4: 커밋**

```bash
cd /Users/ellis/Documents/project/kkochikkochi
git add AGENTS.md
git commit -m "docs: add an agent-facing install runbook"
```

---

### Task 4: `README.ko.md` 미러를 만든다

**Files:**
- Create: `README.ko.md`
- Modify: `README.md` (언어 링크가 이미 Task 2 에서 들어갔다면 수정 없음 — 확인만)

**Interfaces:**
- Consumes: Task 2 의 `README.md` H2 8개
- Produces: 없음 (말단)

- [ ] **Step 1: 파일을 만든다**

`README.md` 의 한국어 미러다. **H2 8개의 순서와 개수를 1:1 로 맞춘다.** 표의 행 수와 내용도 대응시킨다.

상단에 정본 표기를 넣는다.

```markdown
> 이 문서는 [README.md](README.md) 의 한국어판입니다. 정본은 영어판이며, 두 문서가 어긋나면 영어판을 따르세요.

[English](README.md) · **한국어**
```

번역 규칙 셋을 지킨다.

- `agentic coding` 은 `에이전틱 코딩` 으로 음차한다. 문맥상 어색하면 `에이전트가 코드를 쓰는 개발` 처럼 풀어 쓴다. **`AI 보조 코딩` 으로 옮기지 않는다** — 영어에서 피한 우산 범주를 한국어로 되살리는 셈이 된다 (스펙 §6)
- 한글은 리터럴로 쓴다. `\uXXXX` 이스케이프를 쓰지 않는다
- 번역투를 남기지 않는다. 재작성 전 `README.md`(`git show readme-rewrite-base:README.md`)의 한국어 문장이 이 저장소의 문체 기준이다 — 그대로 재활용할 수 있는 곳은 재활용한다

- [ ] **Step 2: 구조가 1:1 인지 검증한다**

```bash
cd /Users/ellis/Documents/project/kkochikkochi
a=$(grep -c '^## ' README.md); b=$(grep -c '^## ' README.ko.md)
echo "en=$a ko=$b"; [ "$a" = "$b" ] || echo "H2 COUNT MISMATCH"
```

`H2 COUNT MISMATCH` 가 나오면 안 된다.

- [ ] **Step 3: 한글 이스케이프가 없는지 검증한다**

```bash
cd /Users/ellis/Documents/project/kkochikkochi
grep -n '\\u[0-9a-fA-F]\{4\}' README.ko.md && echo "ESCAPED HANGUL FOUND" || echo "clean"
grep -c 'AI 보조 코딩' README.ko.md    # 기대: 0
```

`clean` 이 나오고 둘째 줄이 `0` 이어야 한다.

- [ ] **Step 4: 링크를 검증한다**

```bash
cd /Users/ellis/Documents/project/kkochikkochi
grep -o '](\([^)#h][^)]*\))' README.ko.md | sed 's/](\(.*\))/\1/' | sort -u | \
  while IFS= read -r p; do [ -e "$p" ] || echo "MISSING FILE: $p"; done
```

아무것도 출력하지 않아야 한다.

- [ ] **Step 5: 커밋**

```bash
cd /Users/ellis/Documents/project/kkochikkochi
git add README.ko.md
git commit -m "docs: add the Korean mirror of the README"
```

---

### Task 5: 교차 검증하고 스펙의 완료 기준을 확인한다

세 파일이 다 있어야만 할 수 있는 검사다.

**Files:**
- Modify: 앞선 태스크의 산출물 중 검사에 걸리는 것

**Interfaces:**
- Consumes: Task 1~4 전부
- Produces: 없음 (말단)

- [ ] **Step 1: 전 문서 링크를 한 번에 검증한다**

```bash
cd /Users/ellis/Documents/project/kkochikkochi
for f in README.md README.ko.md AGENTS.md docs/DECISIONS.md CONTRIBUTING.md; do
  grep -o '](\([^)#h][^)]*\))' "$f" | sed 's/](\(.*\))/\1/' | sort -u | \
    while IFS= read -r p; do [ -e "$p" ] || echo "$f -> MISSING: $p"; done
done
```

아무것도 출력하지 않아야 한다. Task 2 Step 12 에서 예상됐던 `MISSING FILE: AGENTS.md` 도 이제 사라져야 한다.

- [ ] **Step 2: D 번호 참조가 전부 실재하는지 검증한다**

```bash
cd /Users/ellis/Documents/project/kkochikkochi
for f in README.md README.ko.md; do
  grep -o 'D[0-9][0-9]' "$f" | sort -u | \
    while IFS= read -r d; do grep -q "^#\{2,3\} $d\." docs/DECISIONS.md || echo "$f -> MISSING DECISION: $d"; done
done
```

아무것도 출력하지 않아야 한다.

- [ ] **Step 3: 삭제된 사실이 전부 어딘가에 살아 있는지 확인한다**

스펙 §5.7 의 "정보 손실은 없다" 주장을 검사한다. 아래 각 키워드가 저장소 어딘가(README · README.ko · AGENTS · DECISIONS)에 남아 있어야 한다.

```bash
cd /Users/ellis/Documents/project/kkochikkochi
for k in "core.hooksPath" "pty" "deploy.sh" "git -C" "gcmsg" "cherry-pick" \
         "no-verify" "워크트리" "passes/" "epoch" "jq" "탭"; do
  n=$(grep -l "$k" README.md README.ko.md AGENTS.md docs/DECISIONS.md 2>/dev/null | wc -l | tr -d ' ')
  [ "$n" = "0" ] && echo "LOST: $k"
done
```

`LOST:` 가 하나도 나오면 안 된다. 나오면 그 사실이 문서 세트에서 사라진 것이므로, 해당 D 항목에 흡수하거나 README 요약에 되살린다.

- [ ] **Step 4: CI 가 여전히 통과하는지 확인한다**

문서만 바꿨으므로 통과해야 한다. 통과하지 않으면 코드를 건드린 것이다.

```bash
cd /Users/ellis/Documents/project/kkochikkochi
git status --porcelain                      # 기대: 비어 있음
git diff --stat readme-rewrite-base -- scripts hooks tests hooks.json \
  .claude-plugin .codex-plugin skills commands    # 기대: 비어 있음
shellcheck scripts/*.sh tests/helper.bash
shellcheck -s sh hooks/pre-commit
```

`git diff --stat` 이 무언가 출력하면 Global Constraints 의 "코드 변경 없음" 을 어긴 것이다.

전부 끝나면 기준점 태그를 지운다.

```bash
git tag -d readme-rewrite-base
```

- [ ] **Step 5: 스펙 완료 기준 7개를 하나씩 확인한다**

`docs/superpowers/specs/2026-08-03-readme-rewrite-design.md` §9 를 열고 7개 항목을 직접 대조한다. 자동으로 검사할 수 없는 것은 3번(새로 만들어낸 주장이 없는가)과 4번(AGENTS.md 만 읽은 에이전트가 설치를 끝낼 수 있는가)이다. 3번은 `README.md` 의 사실 진술을 하나씩 훑으며 `git show readme-rewrite-base:README.md` 또는 `docs/DECISIONS.md` 에서 근거를 찾는다. 4번은 `AGENTS.md` 를 위에서 아래로 읽으며 슬래시 명령 없이 끝까지 갈 수 있는지 확인한다.

- [ ] **Step 6: 필요하면 고치고 커밋**

앞 단계에서 고칠 것이 나왔을 때만.

```bash
cd /Users/ellis/Documents/project/kkochikkochi
git add -A
git commit -m "docs: fix cross-document links and restore dropped facts"
```

고칠 것이 없으면 이 태스크는 커밋 없이 끝난다.
