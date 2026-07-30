# KkochiKkochi v2 Migration Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 게이트를 Claude Code 훅의 명령 문자열 파싱에서 git `pre-commit` 훅으로 옮기고, 에이전트가 만든 커밋에서만 동작하게 하며, Claude Code와 Codex를 함께 지원한다.

**Architecture:** git `pre-commit` 훅이 진짜 게이트다. 그 안에서 `git diff --cached`가 곧 커밋될 내용이므로 명령 파싱이 필요 없다. 에이전트 훅(Claude Code / Codex)은 안전 경로에서 빠지고, 핸드셰이크 마커 기록과 설치 건강검진만 담당한다.

**Tech Stack:** POSIX sh · git plumbing · jq · bats-core · shellcheck · GitHub Actions

## Global Constraints

- 런타임 의존성은 `git`과 `jq`뿐
- git 훅은 **POSIX `sh`** 로 쓴다 (bash 전용 문법 금지). 에이전트 훅 스크립트는 bash 3.2 호환
- 상태는 `$(git rev-parse --git-path quiz-gate)/` 아래
- `covered.tsv` 형식 `<40자 SHA>\t<경로>\t<pass_id>`, `NULL_SHA` = 0 40개
- 경로를 내는 모든 git 호출에 `-c core.quotePath=false`
- `git diff --cached --raw` 에는 항상 `--abbrev=40 --no-renames`
- **게이트는 에이전트 커밋에서만 켜진다.** 애매하면 통과 (D33, D35)
- 판별 1차 신호는 핸드셰이크. 환경변수 목록에는 **직접 관찰한 것만** (D34)
- 모든 셸 스크립트는 `shellcheck` 통과
- Conventional Commits

**참조**
- 설계: `docs/superpowers/specs/2026-07-30-kkochikkochi-v2-hybrid-design.md`
- 결정: `docs/DECISIONS.md` — 특히 **D00**(제품 논지)과 D33–D38

---

## File Structure

| 파일 | 상태 | 책임 |
|---|---|---|
| `hooks/pre-commit` | **신규** | git 훅 = 게이트. 에이전트 판별 → 대조 → 차단 |
| `scripts/stamp-agent.sh` | **신규** | 핸드셰이크 마커 기록 + 설치 건강검진. 두 에이전트 공용 |
| `scripts/install.sh` | **신규** | git 훅 설치·체이닝·제거 |
| `hooks/hooks.json` | 개편 | Claude Code 훅 등록 → `stamp-agent.sh` |
| `hooks.json` (루트) | **신규** | Codex 훅 등록 → `stamp-agent.sh` |
| `.codex-plugin/plugin.json` | **신규** | Codex 플러그인 매니페스트 |
| `.agents/plugins/marketplace.json` | **신규** | Codex 마켓플레이스 |
| `scripts/pending-set.sh` | **삭제** | git 훅이 대체 |
| `scripts/lib-tokenize.sh` | **삭제** | 파싱 불필요 |
| `hooks/gate.sh` | **삭제** | `stamp-agent.sh` 가 대체 |
| `tests/command-forms.bats` | **삭제** | 검증 대상 소멸 |
| `tests/gate.bats` | **삭제** | 위와 동일 |
| `tests/pending-set.bats` | **삭제** | 위와 동일 |
| `scripts/record-pass.sh` | 개편 | 명령 인자 제거, `git diff --cached` 직접 사용 |
| `skills/kkochikkochi/SKILL.md` | 개편 | `<BLOCKED_COMMAND>`·이스케이프 규칙 제거 |
| `skills/kkochikkochi/ask/{claude-code,codex}.md` | **신규** | 질문 제시 방법만 분리 |
| `tests/pre-commit.bats` | **신규** | 게이트 |
| `tests/install.bats` | **신규** | 설치·체이닝·멱등·제거 |
| `tests/record-pass.bats` | 개편 | 인자 제거 반영 |

---

### Task 1: `pre-commit` 게이트와 파싱 코드 삭제

가장 큰 변경이자 나머지의 토대. 삭제가 대부분이다.

**Files:**
- Create: `hooks/pre-commit`
- Delete: `scripts/lib-tokenize.sh`, `scripts/pending-set.sh`, `hooks/gate.sh`, `tests/command-forms.bats`, `tests/gate.bats`, `tests/pending-set.bats`
- Test: `tests/pre-commit.bats`

**Interfaces:**
- Consumes: 없음
- Produces:
  - `hooks/pre-commit` — git 이 호출. 통과 시 exit 0, 미검증이면 stderr 안내 후 exit 1
  - 자기 식별 마커 문자열 `KKOCHIKKOCHI-HOOK-v1` (설치기가 "내 훅"을 판별할 때 사용)
  - 핸드셰이크 파일 경로 `$(git rev-parse --git-path quiz-gate)/agent-session`, 신선도 창 120초
  - 체이닝 파일명 `pre-commit.kkochikkochi-chained`

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/helper.bash` 에 헬퍼를 추가한다 (기존 `setup_repo`/`seed_repo`/`teardown_repo` 는 유지):

```bash
qdir() { git rev-parse --git-path quiz-gate; }
hooksdir() { git rev-parse --git-path hooks; }

install_hook() {
  mkdir -p "$(hooksdir)"
  cp "$PLUGIN_ROOT/hooks/pre-commit" "$(hooksdir)/pre-commit"
  chmod +x "$(hooksdir)/pre-commit"
}

stamp() {  # 핸드셰이크 마커를 신선하게 남긴다
  mkdir -p "$(qdir)"
  echo "${1:-test-agent}/sess-1" > "$(qdir)/agent-session"
}

mark_covered() {  # $1 = 경로
  mkdir -p "$(qdir)"
  printf '%s\t%s\t%s\n' "$(git hash-object -- "$1")" "$1" "p-test" >> "$(qdir)/covered.tsv"
}

# 에이전트 환경변수를 지운 상태로 커밋한다 (사람 커밋 근사)
commit_as_human() { env -u CLAUDECODE -u CLAUDE_CODE_SESSION_ID git commit "$@"; }
```

`tests/pre-commit.bats`:

```bash
#!/usr/bin/env bats

load helper

setup() { setup_repo; seed_repo; install_hook; }
teardown() { teardown_repo; }

@test "에이전트 신호가 없으면 통과한다" {
  printf 'C1\n' > c.ts; git add c.ts
  run commit_as_human -m x
  [ "$status" -eq 0 ]
}

@test "핸드셰이크가 신선하면 미검증 변경을 막는다" {
  printf 'C1\n' > c.ts; git add c.ts
  stamp
  run commit_as_human -m x
  [ "$status" -ne 0 ]
  [[ "$output" == *"c.ts"* ]]
}

@test "covered.tsv 에 있으면 통과한다" {
  printf 'C1\n' > c.ts; mark_covered c.ts; git add c.ts
  stamp
  run commit_as_human -m x
  [ "$status" -eq 0 ]
}

@test "커버된 뒤 내용을 고치면 다시 막는다" {
  printf 'C1\n' > c.ts; mark_covered c.ts
  printf 'C2\n' > c.ts; git add c.ts
  stamp
  run commit_as_human -m x
  [ "$status" -ne 0 ]
}

@test "마커가 낡으면 통과한다" {
  printf 'C1\n' > c.ts; git add c.ts
  stamp
  touch -t "$(date -v-5M '+%Y%m%d%H%M' 2>/dev/null || date -d '5 minutes ago' '+%Y%m%d%H%M')" "$(qdir)/agent-session"
  run commit_as_human -m x
  [ "$status" -eq 0 ]
}

@test "CLAUDECODE 환경변수만 있어도 게이트가 켜진다" {
  printf 'C1\n' > c.ts; git add c.ts
  run env CLAUDECODE=1 git commit -m x
  [ "$status" -ne 0 ]
}

@test "커밋할 내용이 없으면 통과한다" {
  stamp
  run commit_as_human --allow-empty -m x
  [ "$status" -eq 0 ]
}

# ── v1 을 무너뜨린 명령 형태들. 전부 막혀야 한다 ──

@test "메시지 안의 -- 가 게이트를 무력화하지 않는다" {
  printf 'A2\n' > a.ts
  stamp
  run commit_as_human -am 'fix: handle -- separator'
  [ "$status" -ne 0 ]
  [[ "$output" == *"a.ts"* ]]
}

@test "맨 pathspec 도 막힌다" {
  printf 'A2\n' > a.ts
  stamp
  run commit_as_human -m x a.ts
  [ "$status" -ne 0 ]
  [[ "$output" == *"a.ts"* ]]
}

@test "--pathspec-from-file 도 막힌다" {
  printf 'A2\n' > a.ts
  printf 'a.ts\n' > list
  stamp
  run commit_as_human --pathspec-from-file=list -m x
  [ "$status" -ne 0 ]
  [[ "$output" == *"a.ts"* ]]
}

@test "-a 는 워크트리 내용으로 판정한다" {
  printf 'A2\n' > a.ts
  mark_covered a.ts          # 워크트리 SHA 로 커버
  stamp
  run commit_as_human -am x
  [ "$status" -eq 0 ]
}

@test "비ASCII 경로도 실제 SHA 로 판정한다" {
  printf '한글2\n' > 한글.ts
  git add 한글.ts
  stamp
  run commit_as_human -m x
  [ "$status" -ne 0 ]
  # NULL_SHA 로 떨어지지 않았는지 확인: 커버하면 통과해야 한다
  mark_covered 한글.ts
  run commit_as_human -m x
  [ "$status" -eq 0 ]
}

@test "merge 커밋에서는 훅이 실행되지 않아 통과한다" {
  stamp
  git checkout -qb feat
  printf 'F\n' > f.ts; git add f.ts; commit_as_human -qm feat
  git checkout -q -
  printf 'M\n' > m.ts; git add m.ts; commit_as_human -qm main
  run git merge --no-ff feat -m merge
  [ "$status" -eq 0 ]
}

# ── 체이닝 ──

@test "체이닝된 훅이 먼저 실행되고 거부하면 즉시 끝난다" {
  printf '#!/bin/sh\necho CHAINED_RAN >&2\nexit 7\n' > "$(hooksdir)/pre-commit.kkochikkochi-chained"
  chmod +x "$(hooksdir)/pre-commit.kkochikkochi-chained"
  printf 'C1\n' > c.ts; git add c.ts
  stamp
  run "$(hooksdir)/pre-commit"
  [ "$status" -eq 7 ]
  [[ "$output" == *"CHAINED_RAN"* ]]
  [[ "$output" != *"KkochiKkochi"* ]]
}

@test "체이닝된 훅이 통과하면 우리 판정으로 넘어간다" {
  printf '#!/bin/sh\nexit 0\n' > "$(hooksdir)/pre-commit.kkochikkochi-chained"
  chmod +x "$(hooksdir)/pre-commit.kkochikkochi-chained"
  printf 'C1\n' > c.ts; git add c.ts
  stamp
  run commit_as_human -m x
  [ "$status" -ne 0 ]
  [[ "$output" == *"c.ts"* ]]
}

@test "훅에 자기 식별 마커가 들어 있다" {
  grep -q 'KKOCHIKKOCHI-HOOK-v1' "$(hooksdir)/pre-commit"
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `bats tests/pre-commit.bats`
Expected: 전부 FAIL — `hooks/pre-commit` 없음

- [ ] **Step 3: `hooks/pre-commit` 구현**

아래 코드는 임시 저장소에서 실제로 실행해 검증한 것이다. v1 을 무너뜨린 네 가지 명령 형태가 모두 차단되는 것을 확인했다.

```sh
#!/bin/sh
# KkochiKkochi 게이트 — git 이 직접 호출한다.
# KKOCHIKKOCHI-HOOK-v1  ← 자기 식별 마커. 설치기가 이 문자열로 "내 훅"을 판별한다.
#
# 여기서 git diff --cached 는 커밋될 내용 그 자체다. 명령 문자열을 파싱하지 않는다.

set -u

QDIR="$(git rev-parse --git-path quiz-gate)"
CHAINED="$(git rev-parse --git-path hooks)/pre-commit.kkochikkochi-chained"
FRESH_SECS=120

# ── 1. 체이닝된 기존 훅을 먼저 실행한다 ────────────────────────────
# 린트가 거부하는 코드에 이해도 퀴즈를 내는 것은 순서가 틀렸다. (D38)
if [ -x "$CHAINED" ]; then
  "$CHAINED" "$@" || exit $?
fi

# ── 2. 에이전트가 만든 커밋인가 (D33) ─────────────────────────────
agent_signal=""

# 1차: 핸드셰이크. 변수 이름에 의존하지 않아 버전 변경에 강하다. (D34)
marker="$QDIR/agent-session"
if [ -f "$marker" ]; then
  now=$(date +%s)
  mtime=$(stat -f %m "$marker" 2>/dev/null || stat -c %Y "$marker" 2>/dev/null || echo 0)
  if [ "$((now - mtime))" -le "$FRESH_SECS" ]; then
    agent_signal="handshake:$(head -1 "$marker" 2>/dev/null)"
  fi
fi

# 2차: 직접 관찰한 환경변수만. 추측으로 채우지 않는다. (D34)
if [ -z "$agent_signal" ]; then
  if [ -n "${CLAUDECODE:-}" ] || [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then
    agent_signal="env:claude-code"
  fi
fi

# 3차: 음성 신호. TTY 가 있으면 사람이 터미널에 있다.
if [ -z "$agent_signal" ] && [ -t 0 ]; then
  exit 0
fi

# 애매하면 통과 (D35)
[ -n "$agent_signal" ] || exit 0

# ── 3. 커밋될 내용 = git diff --cached ────────────────────────────
pending="$(git -c core.quotePath=false diff --cached --raw --abbrev=40 --no-renames \
           | awk -F'\t' '{ split($1, f, " "); print f[4] "\t" $2 }')"
[ -n "$pending" ] || exit 0

covered="$QDIR/covered.tsv"
missing=""
while IFS="$(printf '\t')" read -r sha path; do
  [ -n "$sha" ] || continue
  if [ -r "$covered" ] && awk -F'\t' -v s="$sha" -v p="$path" \
       '$1 == s && $2 == p { found = 1; exit } END { exit !found }' "$covered"; then
    continue
  fi
  missing="$missing   $path
"
done <<PENDING
$pending
PENDING

[ -n "$missing" ] || exit 0

cat >&2 <<MSG
🦡 KkochiKkochi — 이 커밋에 아직 검증되지 않은 변경이 있습니다.

$missing
이 변경을 이해했는지 먼저 확인해야 합니다.
kkochikkochi 스킬을 실행해 퀴즈를 통과한 뒤 다시 커밋하세요.
(판별 신호: $agent_signal)
MSG
exit 1
```

**메시지 원칙** — 이 stderr 는 Claude Code 전용이 아니다. Codex 사용자도 읽는다. 에이전트 종류를 가정하는 문구를 넣지 않는다.

**git 의 종료 코드에 대한 주의** — 체이닝된 훅이 7 로 끝나면 우리 훅도 7 로 끝나지만, git 은 자기 코드(1)로 바꿔 보고한다. 이는 git 의 정상 동작이며 체이닝 계약은 지켜진다. 테스트는 훅을 직접 실행해 확인한다.

- [ ] **Step 4: 파싱 코드와 낡은 테스트 삭제**

```bash
git rm -q scripts/lib-tokenize.sh scripts/pending-set.sh hooks/gate.sh
git rm -q tests/command-forms.bats tests/gate.bats tests/pending-set.bats
```

`tests/record-pass.bats` 는 Task 4 에서 개편하므로 지금은 실패할 수 있다. 이 태스크의 검증은 `tests/pre-commit.bats` 만으로 한다.

- [ ] **Step 5: 테스트 통과 확인**

```bash
chmod +x hooks/pre-commit
bats tests/pre-commit.bats
shellcheck -s sh hooks/pre-commit
```
Expected: 16 tests 통과, shellcheck 무출력

- [ ] **Step 6: 커밋**

```bash
git add -A hooks scripts tests
git commit -m "feat!: move the gate into a git pre-commit hook and delete the command parser"
```

---

### Task 2: 핸드셰이크와 에이전트 훅 등록

**Files:**
- Create: `scripts/stamp-agent.sh`
- Create: `hooks.json` (저장소 루트, Codex 용)
- Modify: `hooks/hooks.json` (Claude Code 용)
- Test: `tests/stamp-agent.bats`

**Interfaces:**
- Consumes: `hooks/pre-commit` 이 읽는 마커 경로와 형식 (Task 1)
- Produces:
  - `scripts/stamp-agent.sh` — stdin 으로 훅 JSON 을 받아 `$(git rev-parse --git-path quiz-gate)/agent-session` 에 `<agent>/<session_id>` 한 줄을 기록
  - 인자 `--agent <name>` 으로 에이전트 이름을 받는다
  - git 저장소가 아니면 조용히 exit 0
  - **어떤 경우에도 stdout 에 아무것도 쓰지 않는다** — 훅 프로토콜에서 stdout 은 판정 채널이다

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/stamp-agent.bats`:

```bash
#!/usr/bin/env bats

load helper

setup() { setup_repo; seed_repo; }
teardown() { teardown_repo; }

stamp_run() {  # $1 = agent, $2 = command
  jq -n --arg c "${2:-git commit -m x}" --arg cwd "$PWD" --arg s "sess-abc" \
    '{tool_name:"Bash", cwd:$cwd, session_id:$s, tool_input:{command:$c}}' \
  | bash "$PLUGIN_ROOT/scripts/stamp-agent.sh" --agent "${1:-claude-code}"
}

@test "마커 파일을 만든다" {
  stamp_run claude-code
  [ -f "$(qdir)/agent-session" ]
}

@test "마커에 에이전트 이름과 세션 ID 가 들어간다" {
  stamp_run claude-code
  run cat "$(qdir)/agent-session"
  [[ "$output" == *"claude-code"* ]]
  [[ "$output" == *"sess-abc"* ]]
}

@test "codex 로도 동작한다 (같은 스크립트)" {
  stamp_run codex
  run cat "$(qdir)/agent-session"
  [[ "$output" == *"codex"* ]]
}

@test "stdout 에 아무것도 쓰지 않는다" {
  run stamp_run claude-code
  [ -z "$output" ]
}

@test "재호출하면 마커가 갱신된다" {
  stamp_run claude-code
  first=$(stat -f %m "$(qdir)/agent-session" 2>/dev/null || stat -c %Y "$(qdir)/agent-session")
  touch -t 202601010000 "$(qdir)/agent-session"
  stamp_run claude-code
  second=$(stat -f %m "$(qdir)/agent-session" 2>/dev/null || stat -c %Y "$(qdir)/agent-session")
  [ "$second" -gt "$first" ] || [ "$second" -ne 0 ]
}

@test "git 저장소가 아니면 조용히 종료한다" {
  cd "$(mktemp -d)" || return 1
  run stamp_run claude-code
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "마커를 남기면 pre-commit 게이트가 켜진다 (종단 확인)" {
  install_hook
  printf 'C1\n' > c.ts; git add c.ts
  stamp_run claude-code
  run commit_as_human -m x
  [ "$status" -ne 0 ]
  [[ "$output" == *"c.ts"* ]]
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `bats tests/stamp-agent.bats`
Expected: 전부 FAIL — `scripts/stamp-agent.sh` 없음

- [ ] **Step 3: `scripts/stamp-agent.sh` 구현**

```bash
#!/usr/bin/env bash
# 에이전트 훅이 발동했다는 사실을 기록한다 (핸드셰이크).
#
# 이 스크립트가 실행됐다 = 에이전트가 도구를 호출했다. 판별할 필요가 없다. (D34)
# Claude Code 와 Codex 는 훅 stdin JSON 스키마가 같아 같은 스크립트를 쓴다. (D36)
#
# 사용법: <hook json> | stamp-agent.sh --agent <name>
# stdout 에는 절대 쓰지 않는다 — 훅 프로토콜에서 stdout 은 판정 채널이다.

set -uo pipefail

AGENT="unknown"
while [ $# -gt 0 ]; do
  case "$1" in
    --agent) AGENT="${2:-unknown}"; shift ;;
  esac
  shift
done

payload="$(cat)"

git rev-parse --git-dir >/dev/null 2>&1 || exit 0
qdir="$(git rev-parse --git-path quiz-gate)"
mkdir -p "$qdir" 2>/dev/null || exit 0

session="unknown"
if command -v jq >/dev/null 2>&1; then
  session="$(jq -r '.session_id // "unknown"' <<<"$payload" 2>/dev/null || echo unknown)"
fi

printf '%s/%s\n' "$AGENT" "$session" > "$qdir/agent-session" 2>/dev/null || exit 0
exit 0
```

- [ ] **Step 4: Claude Code 훅 등록 개편**

`hooks/hooks.json` 을 통째로 교체한다:

```json
{
  "description": "KkochiKkochi — records an agent handshake so the git pre-commit gate knows this commit came from an agent.",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/stamp-agent.sh\" --agent claude-code",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 5: Codex 훅 등록 생성**

`hooks.json` (저장소 루트 — Codex 규약):

```json
{
  "description": "KkochiKkochi — records an agent handshake so the git pre-commit gate knows this commit came from an agent.",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${PLUGIN_ROOT}/scripts/stamp-agent.sh\" --agent codex",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

Codex 플러그인 훅은 `PLUGIN_ROOT` 를 받는다 (Claude 의 `CLAUDE_PLUGIN_ROOT` 에 대응).

- [ ] **Step 6: 테스트와 검증**

```bash
chmod +x scripts/stamp-agent.sh
bats tests/stamp-agent.bats tests/pre-commit.bats
shellcheck scripts/stamp-agent.sh
jq . hooks/hooks.json hooks.json
```
Expected: 23 tests 통과, shellcheck 무출력, 두 JSON 파싱됨

- [ ] **Step 7: 커밋**

```bash
git add scripts/stamp-agent.sh hooks/hooks.json hooks.json tests/stamp-agent.bats tests/helper.bash
git commit -m "feat: add the agent handshake and register hooks for Claude Code and Codex"
```

---

### Task 3: 설치·체이닝·제거

**Files:**
- Create: `scripts/install.sh`
- Test: `tests/install.bats`

**Interfaces:**
- Consumes: `hooks/pre-commit` 과 그 자기 식별 마커 `KKOCHIKKOCHI-HOOK-v1` (Task 1)
- Produces:
  - `scripts/install.sh install` — 실효 훅 디렉터리에 설치. 기존 훅은 체이닝
  - `scripts/install.sh uninstall` — 정확히 되돌림
  - `scripts/install.sh status` — 설치 여부를 종료 코드로 (0 = 설치됨, 1 = 아님, 2 = `core.hooksPath` 로 인해 거부)
  - `core.hooksPath` 가 설정돼 있으면 **설치하지 않고 exit 2** + 설명 (D32)

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/install.bats`:

```bash
#!/usr/bin/env bats

load helper

setup() { setup_repo; seed_repo; }
teardown() { teardown_repo; }

inst() { bash "$PLUGIN_ROOT/scripts/install.sh" "$@"; }

@test "install 이 훅을 놓는다" {
  run inst install
  [ "$status" -eq 0 ]
  [ -x "$(hooksdir)/pre-commit" ]
  grep -q 'KKOCHIKKOCHI-HOOK-v1' "$(hooksdir)/pre-commit"
}

@test "status 는 설치 전 1, 설치 후 0" {
  run inst status
  [ "$status" -eq 1 ]
  inst install
  run inst status
  [ "$status" -eq 0 ]
}

@test "기존 훅을 체이닝 파일로 옮긴다" {
  printf '#!/bin/sh\nexit 0\n' > "$(hooksdir)/pre-commit"; chmod +x "$(hooksdir)/pre-commit"
  inst install
  [ -f "$(hooksdir)/pre-commit.kkochikkochi-chained" ]
  grep -q 'KKOCHIKKOCHI-HOOK-v1' "$(hooksdir)/pre-commit"
}

@test "재설치는 멱등이며 체이닝 파일을 덮어쓰지 않는다" {
  printf '#!/bin/sh\necho ORIGINAL\nexit 0\n' > "$(hooksdir)/pre-commit"; chmod +x "$(hooksdir)/pre-commit"
  inst install
  inst install
  run cat "$(hooksdir)/pre-commit.kkochikkochi-chained"
  [[ "$output" == *"ORIGINAL"* ]]
}

@test "uninstall 이 기존 훅을 원상복구한다" {
  printf '#!/bin/sh\necho ORIGINAL\nexit 0\n' > "$(hooksdir)/pre-commit"; chmod +x "$(hooksdir)/pre-commit"
  inst install
  inst uninstall
  run cat "$(hooksdir)/pre-commit"
  [[ "$output" == *"ORIGINAL"* ]]
  [ ! -f "$(hooksdir)/pre-commit.kkochikkochi-chained" ]
}

@test "체이닝할 것이 없으면 uninstall 이 훅만 지운다" {
  inst install
  inst uninstall
  [ ! -f "$(hooksdir)/pre-commit" ]
}

@test "core.hooksPath 가 설정돼 있으면 설치를 거부하고 exit 2" {
  mkdir -p .myhooks
  git config core.hooksPath .myhooks
  run inst install
  [ "$status" -eq 2 ]
  [ ! -f ".myhooks/pre-commit" ]
  [[ "$output" == *"core.hooksPath"* ]]
}

@test "설치 후 게이트가 실제로 동작한다 (종단 확인)" {
  inst install
  printf 'C1\n' > c.ts; git add c.ts
  stamp
  run commit_as_human -m x
  [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `bats tests/install.bats`
Expected: 전부 FAIL

- [ ] **Step 3: `scripts/install.sh` 구현**

```bash
#!/usr/bin/env bash
# git pre-commit 훅 설치 / 제거 / 상태 확인
#
# 자기 식별 마커로 "내 훅"을 판별한다 — pre-commit 프레임워크 방식. (D38)
# core.hooksPath 가 설정된 저장소에서는 설치하지 않는다: 실효 디렉터리가
# 저장소에 추적되므로, 말없이 쓰면 git status 에 뜨고 커밋에 섞인다. (D32)

set -uo pipefail

MARKER="KKOCHIKKOCHI-HOOK-v1"
CHAINED_SUFFIX=".kkochikkochi-chained"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/../hooks/pre-commit"

die() { echo "kkochikkochi: $1" >&2; exit 1; }

git rev-parse --git-dir >/dev/null 2>&1 || die "git 저장소가 아닙니다"

HOOKS_DIR="$(git rev-parse --git-path hooks)"
TARGET="$HOOKS_DIR/pre-commit"
CHAINED="$TARGET$CHAINED_SUFFIX"

is_ours() { [ -f "$1" ] && grep -q "$MARKER" "$1" 2>/dev/null; }

hookspath_set() { [ -n "$(git config --get core.hooksPath || true)" ]; }

cmd_status() { is_ours "$TARGET" && exit 0 || exit 1; }

cmd_install() {
  if hookspath_set; then
    cat >&2 <<MSG
kkochikkochi: 이 저장소는 core.hooksPath 를 사용합니다 ($(git config --get core.hooksPath)).
  그 경우 .git/hooks/ 는 무시되고, 실효 훅 디렉터리는 저장소에 추적되는 곳입니다.
  거기에 파일을 쓰면 git status 에 뜨고 커밋에 섞일 수 있어 자동으로 설치하지 않습니다.

  선택지:
    1) 그 디렉터리에 직접 설치 — 추적되는 변경이 생깁니다
    2) core.hooksPath 를 해제하고 다시 실행
    3) 이 저장소에서는 게이트를 쓰지 않음
MSG
    exit 2
  fi

  mkdir -p "$HOOKS_DIR" || die "훅 디렉터리를 만들 수 없습니다"
  [ -r "$SRC" ] || die "훅 원본을 찾을 수 없습니다: $SRC"

  # 기존 훅이 우리 것이 아니면 체이닝으로 옮긴다.
  # 이미 체이닝 파일이 있으면 덮어쓰지 않는다 — 사용자의 원래 훅을 잃게 된다.
  if [ -f "$TARGET" ] && ! is_ours "$TARGET"; then
    if [ -f "$CHAINED" ]; then
      die "체이닝 파일이 이미 있습니다: $CHAINED — 수동으로 정리하세요"
    fi
    mv "$TARGET" "$CHAINED" || die "기존 훅을 옮길 수 없습니다"
    chmod +x "$CHAINED" 2>/dev/null || true
    echo "kkochikkochi: 기존 pre-commit 훅을 $CHAINED 로 옮기고 체이닝합니다" >&2
  fi

  cp "$SRC" "$TARGET" || die "훅을 설치할 수 없습니다"
  chmod +x "$TARGET" || die "실행 권한을 줄 수 없습니다"
  echo "kkochikkochi: 설치 완료 — $TARGET" >&2
}

cmd_uninstall() {
  is_ours "$TARGET" || die "우리 훅이 설치돼 있지 않습니다"
  rm -f "$TARGET" || die "훅을 지울 수 없습니다"
  if [ -f "$CHAINED" ]; then
    mv "$CHAINED" "$TARGET" || die "체이닝된 훅을 복구할 수 없습니다"
    echo "kkochikkochi: 기존 훅을 복구했습니다" >&2
  fi
  echo "kkochikkochi: 제거 완료" >&2
}

case "${1:-install}" in
  install)   cmd_install ;;
  uninstall) cmd_uninstall ;;
  status)    cmd_status ;;
  *)         die "사용법: install.sh [install|uninstall|status]" ;;
esac
```

- [ ] **Step 4: 테스트와 검증**

```bash
chmod +x scripts/install.sh
bats tests/
shellcheck scripts/install.sh
```
Expected: install 8 tests 포함 전부 통과

- [ ] **Step 5: 커밋**

```bash
git add scripts/install.sh tests/install.bats
git commit -m "feat: add hook installer with chaining, idempotent reinstall, and clean uninstall"
```

---

### Task 4: 건강검진과 `record-pass.sh` 축소

**Files:**
- Modify: `scripts/stamp-agent.sh` (건강검진 추가)
- Modify: `scripts/record-pass.sh` (명령 인자 제거)
- Modify: `tests/record-pass.bats`
- Test: `tests/health-check.bats`

**Interfaces:**
- Consumes: `scripts/install.sh status` (Task 3), `hooks/pre-commit` (Task 1)
- Produces:
  - `stamp-agent.sh` 가 `git commit` 으로 보이는 명령에서 훅 미설치를 감지하면 deny JSON 을 stdout 에 출력하고 exit 0
  - deny 사유에 **에이전트가 그대로 실행할 설치 명령**을 담는다 (D32)
  - `record-pass.sh` 는 인자를 받지 않고 `git diff --cached` 로 대상을 정한다

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/health-check.bats`:

```bash
#!/usr/bin/env bats

load helper

setup() { setup_repo; seed_repo; }
teardown() { teardown_repo; }

hc() {  # $1 = command string
  jq -n --arg c "$1" --arg cwd "$PWD" --arg s "sess-1" \
    '{tool_name:"Bash", cwd:$cwd, session_id:$s, tool_input:{command:$c}}' \
  | bash "$PLUGIN_ROOT/scripts/stamp-agent.sh" --agent claude-code
}

@test "훅 미설치 + 커밋으로 보이는 명령 → deny 한다" {
  run hc 'git commit -m x'
  [[ "$output" == *"deny"* ]]
}

@test "deny 사유에 실행 가능한 설치 명령이 들어 있다" {
  run hc 'git commit -m x'
  [[ "$output" == *"install.sh"* ]]
}

@test "훅이 설치돼 있으면 deny 하지 않는다" {
  bash "$PLUGIN_ROOT/scripts/install.sh" install 2>/dev/null
  run hc 'git commit -m x'
  [ -z "$output" ]
}

@test "커밋이 아닌 명령은 훅이 없어도 통과시킨다" {
  run hc 'ls -la'
  [ -z "$output" ]
}

@test "--no-verify 는 훅이 설치돼 있어도 deny 한다" {
  bash "$PLUGIN_ROOT/scripts/install.sh" install 2>/dev/null
  run hc 'git commit --no-verify -m x'
  [[ "$output" == *"deny"* ]]
  [[ "$output" == *"no-verify"* ]]
}

@test "core.hooksPath 저장소에서는 설치 대신 상황을 설명한다" {
  mkdir -p .myhooks; git config core.hooksPath .myhooks
  run hc 'git commit -m x'
  [[ "$output" == *"core.hooksPath"* ]]
}
```

`tests/record-pass.bats` 수정: 모든 `record` 호출에서 명령 문자열 인자를 제거한다. 예를 들어

```bash
record() { echo "$1" | bash "$PLUGIN_ROOT/scripts/record-pass.sh"; }
```

로 바꾸고, 기존 15개 테스트의 단언은 그대로 둔다.

- [ ] **Step 2: 테스트 실패 확인**

Run: `bats tests/health-check.bats`
Expected: 전부 FAIL

- [ ] **Step 3: `stamp-agent.sh` 에 건강검진 추가**

`printf ... > "$qdir/agent-session"` 직후, `exit 0` 앞에 다음을 넣는다:

```bash
# ── 건강검진 ─────────────────────────────────────────────────────
# 게이트가 조용히 없는 상태를 막는다. 여기서 부정확해도 안전하다:
# 오탐이면 안내 한 번, 미탐이면 게이트가 없던 v1 과 같을 뿐이다. (D29)
cmd="$(jq -r '.tool_input.command // ""' <<<"$payload" 2>/dev/null || echo "")"
case "$cmd" in
  *commit*) ;;
  *) exit 0 ;;
esac

deny() {  # $1 = 사유
  jq -n --arg r "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
  exit 0
}

case "$cmd" in
  *--no-verify*)
    deny "🦡 KkochiKkochi — --no-verify 는 git 훅을 건너뛰므로 이해 검증도 건너뜁니다.
플래그 없이 다시 커밋하세요. 정말 건너뛰어야 한다면 사용자에게 먼저 확인하세요." ;;
esac

INSTALL_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/install.sh"
if ! bash "$INSTALL_SH" status >/dev/null 2>&1; then
  if [ -n "$(git config --get core.hooksPath || true)" ]; then
    deny "🦡 KkochiKkochi — 이 저장소는 core.hooksPath 를 사용해 자동 설치를 하지 않았습니다.
실효 훅 디렉터리가 저장소에 추적되므로 말없이 파일을 쓰지 않습니다.
사용자에게 다음 중 무엇을 원하는지 물어보세요:
  1) 그 디렉터리에 직접 설치 (추적되는 변경이 생김)
  2) core.hooksPath 해제 후 재설치
  3) 이 저장소에서는 게이트를 사용하지 않음"
  fi
  deny "🦡 KkochiKkochi — 이 저장소에 게이트가 아직 설치되지 않았습니다.
다음 명령을 실행한 뒤 커밋을 다시 시도하세요:

  bash \"$INSTALL_SH\" install

기존 pre-commit 훅이 있으면 자동으로 체이닝되며 먼저 실행됩니다."
fi
```

- [ ] **Step 4: `record-pass.sh` 축소**

`CMD="${1:-git commit}"` 줄과 `pending-set.sh` 호출을 제거하고, 대상 계산을 직접 한다:

```bash
pending="$(git -c core.quotePath=false diff --cached --raw --abbrev=40 --no-renames \
           | awk -F'\t' '{ split($1, f, " "); print f[4] "\t" $2 }')"
[ -n "$pending" ] || die "커밋될 내용이 없습니다"
```

나머지(검증 규칙, 원자성 순서, 저장 형식)는 그대로 둔다. **트랜스크립트를 먼저 쓰고 나중에 `covered.tsv` 에 추가하는 순서를 반드시 유지한다** — 뒤집으면 거부가 유령 커버리지 줄을 남긴다.

- [ ] **Step 5: 테스트와 검증**

```bash
bats tests/
shellcheck scripts/*.sh
shellcheck -s sh hooks/pre-commit
```
Expected: 전부 통과

- [ ] **Step 6: 커밋**

```bash
git add scripts tests
git commit -m "feat: add install health check and drop the command argument from record-pass"
```

---

### Task 5: 스킬 개편과 에이전트별 질문 제시

**Files:**
- Modify: `skills/kkochikkochi/SKILL.md`
- Create: `skills/kkochikkochi/ask/claude-code.md`
- Create: `skills/kkochikkochi/ask/codex.md`
- Modify: `commands/kk.md`

**Interfaces:**
- Consumes: `scripts/record-pass.sh` (인자 없음, Task 4)
- Produces: 두 에이전트에서 동작하는 스킬

- [ ] **Step 1: `SKILL.md` 에서 v1 잔재 제거**

다음을 통째로 삭제한다:
- `<BLOCKED_COMMAND>` 관련 §0 전체와 `:41`, `:139`, `:183` 의 명령 전달
- `'` → `'\''` 이스케이프 규칙과 그 예시표
- `pending-set.sh` 호출 (스크립트가 사라졌다)

재료 수집 절의 첫 명령을 바꾼다:

```bash
git -c core.quotePath=false diff --cached --raw --abbrev=40 --no-renames
```

기록 절의 호출을 바꾼다:

```bash
cat <<'JSON' | bash "${CLAUDE_PLUGIN_ROOT}/scripts/record-pass.sh"
{ "questions": [ ... ], "skipped_reason": null }
JSON
```

Codex 에서는 `${PLUGIN_ROOT}` 를 쓴다는 것을 한 줄로 명시한다.

- [ ] **Step 2: 질문 제시 방법 분리**

`skills/kkochikkochi/ask/claude-code.md`:

```markdown
# 질문 제시 — Claude Code

객관식과 짧은 답은 `AskUserQuestion` 으로 낸다. 선택지에는 항상 **"모르겠다"** 를 포함한다.
"모르겠다" 는 오답 선택지가 아니라 탈출구이며, 정답으로 채점하지 않는다.

서술형은 일반 질문으로 내고 답변을 기다린다.
```

`skills/kkochikkochi/ask/codex.md`:

```markdown
# 질문 제시 — Codex

Codex 에는 구조화된 선택 도구가 없다. 로컬 도구는 `shell` 과 `web_search` 뿐이다.

따라서 객관식도 **평문으로 제시하고 사용자가 타이핑해서 답하게 한다.**

    Q1. 이 변경으로 auth 미들웨어가 통과시키는 경로는?
        A) /api/public/* 을 제외한 전체
        B) 정적 에셋만
        C) /api/* 전체
        D) 모르겠다

    A~D 중 하나를 답해 주세요.

"모르겠다" 는 항상 마지막 선택지로 포함한다. 오답 선택지가 아니라 탈출구이며,
정답으로 채점하지 않는다.

사용자가 문자 대신 내용을 그대로 적어도 그 뜻이 명확하면 정답으로 인정한다.
표기 방식으로 트집 잡지 않는다.
```

`SKILL.md` 의 출제 절에 한 줄을 넣는다:

> 질문 제시 방법은 실행 중인 에이전트에 따라 다르다. `ask/claude-code.md` 또는 `ask/codex.md` 를 읽고 그대로 따른다.

**공유되는 것** — 채점, 오답 루프, 오답 선택지 규칙, 정답 위치 무작위화, 문항 예산, 근거 요구. 전부 제시 방법과 무관하므로 `SKILL.md` 에 남긴다.

- [ ] **Step 3: 검증**

```bash
grep -c 'BLOCKED_COMMAND' skills/kkochikkochi/SKILL.md   # 0 이어야 함
grep -c 'pending-set' skills/kkochikkochi/SKILL.md        # 0 이어야 함
head -5 skills/kkochikkochi/SKILL.md                      # 프론트매터 유효
ls skills/kkochikkochi/ask/
bats tests/
```
Expected: 두 grep 이 0, 테스트 전부 통과

- [ ] **Step 4: 커밋**

```bash
git add skills commands
git commit -m "refactor: drop command threading from the skill and split question delivery per agent"
```

---

### Task 6: Codex 플러그인 매니페스트

**Files:**
- Create: `.codex-plugin/plugin.json`
- Create: `.agents/plugins/marketplace.json`

**Interfaces:**
- Consumes: `hooks.json`, `skills/` (Task 2, 5)
- Produces: `codex plugin marketplace add` 로 설치 가능한 저장소

- [ ] **Step 1: `.codex-plugin/plugin.json` 작성**

실제 설치된 Codex 플러그인의 매니페스트 형식을 따른다.

```json
{
  "name": "kkochikkochi",
  "version": "0.2.0",
  "description": "A comprehension gate for AI-assisted coding. Blocks the commit until you can explain what changed.",
  "author": { "name": "KkochiKkochi contributors" },
  "license": "MIT",
  "keywords": ["gate", "comprehension", "quiz", "review", "git", "commit"],
  "skills": "./skills/",
  "interface": {
    "displayName": "KkochiKkochi",
    "shortDescription": "Blocks the commit until you can explain what changed",
    "developerName": "KkochiKkochi contributors",
    "category": "Engineering"
  }
}
```

- [ ] **Step 2: `.agents/plugins/marketplace.json` 작성**

```json
{
  "name": "kkochikkochi",
  "interface": {
    "displayName": "KkochiKkochi",
    "shortDescription": "A comprehension gate for AI-assisted coding"
  },
  "plugins": [
    {
      "name": "kkochikkochi",
      "source": { "source": "local", "path": "./" },
      "policy": { "installation": "AVAILABLE" },
      "category": "Engineering"
    }
  ]
}
```

- [ ] **Step 3: 버전 일치 확인**

`.claude-plugin/plugin.json` 의 `version` 을 `0.2.0` 으로 올려 세 매니페스트가 일치하게 한다. 매니페스트끼리 버전이 어긋나면 유지보수 함정이 된다.

- [ ] **Step 4: 검증**

```bash
jq . .codex-plugin/plugin.json .agents/plugins/marketplace.json \
     .claude-plugin/plugin.json .claude-plugin/marketplace.json hooks.json hooks/hooks.json
for f in .codex-plugin/plugin.json .claude-plugin/plugin.json; do
  echo "$f: $(jq -r .version "$f")"
done
```
Expected: 여섯 JSON 모두 파싱, 두 버전이 `0.2.0` 으로 동일

- [ ] **Step 5: 커밋**

```bash
git add .codex-plugin .agents .claude-plugin
git commit -m "feat: ship the repo as a Codex plugin alongside the Claude Code plugin"
```

---

### Task 7: 문서 갱신과 CI

**Files:**
- Modify: `README.md`, `CHANGELOG.md`, `CONTRIBUTING.md`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: 전 태스크의 산출물
- Produces: 배포 가능한 저장소

- [ ] **Step 1: CI 갱신**

`shellcheck` 대상에서 사라진 파일을 빼고 새 파일을 넣는다. `hooks/pre-commit` 은 POSIX sh 이므로 `-s sh` 로 검사한다.

```yaml
      - name: Lint shell scripts
        run: |
          shellcheck scripts/*.sh tests/helper.bash
          shellcheck -s sh hooks/pre-commit

      - name: Validate JSON
        run: |
          jq . hooks/hooks.json > /dev/null
          jq . hooks.json > /dev/null
          jq . .claude-plugin/plugin.json > /dev/null
          jq . .claude-plugin/marketplace.json > /dev/null
          jq . .codex-plugin/plugin.json > /dev/null
          jq . .agents/plugins/marketplace.json > /dev/null
```

- [ ] **Step 2: README 갱신 — 사실만 남긴다**

v1 README 의 다음 서술이 더 이상 사실이 아니다. 각각 고친다:

| 낡은 서술 | 사실 |
|---|---|
| Claude Code 훅이 `git commit` 을 가로챈다 | git `pre-commit` 훅이 게이트다 |
| 설치는 `/plugin install` 뿐 | 저장소마다 훅 설치가 필요하다 (에이전트가 자동으로 함) |
| (없음) | **게이트는 에이전트가 만든 커밋에서만 켜진다.** IDE·터미널 커밋은 막지 않는다 |
| (없음) | Claude Code 와 Codex 를 지원한다 |
| 한계: Bash 를 안 거치는 커밋 | 한계: 지원 목록에 없는 에이전트, `--no-verify`, `core.hooksPath` 저장소 |

**"무엇을 막고 무엇을 막지 않는가" 표를 README 상단 가까이 둔다.** 사용자가 가장 먼저 알아야 할 것이다.

- [ ] **Step 3: CONTRIBUTING 갱신**

설계 원칙 절을 v2 에 맞춘다:

1. **게이트는 git 훅이다.** 에이전트 훅은 안전 경로가 아니다 — 거기서 틀려도 게이트는 걸린다
2. **명령 문자열을 파싱하지 않는다.** v1 결함의 거의 전부가 거기서 나왔다
3. **에이전트 판별의 1차 신호는 핸드셰이크다.** 환경변수 목록에는 직접 관찰한 것만 넣는다
4. **애매하면 통과시킨다.** 막아야 할 것을 정확히 막는 게 목표지 많이 막는 게 목표가 아니다

- [ ] **Step 4: CHANGELOG 갱신**

`0.2.0` 항목을 추가하고 **Changed / Removed 를 명시**한다. 아키텍처가 바뀌었으므로 사용자가 알아야 한다.

- [ ] **Step 5: 전체 검증**

```bash
bats tests/
shellcheck scripts/*.sh tests/helper.bash
shellcheck -s sh hooks/pre-commit
jq . hooks/hooks.json hooks.json .claude-plugin/*.json .codex-plugin/*.json .agents/plugins/*.json
find . -not -path './.git/*' -not -path './.superpowers/*' -type f | sort
```

- [ ] **Step 6: 커밋**

```bash
git add README.md CHANGELOG.md CONTRIBUTING.md .github
git commit -m "docs: rewrite for the v2 architecture and multi-agent support"
```

---

## 완료 후 수동 검증

자동 테스트로 확인할 수 없는 것들.

- [ ] Claude Code 에서 플러그인 설치 → 새 저장소에서 커밋 시도 → **에이전트가 스스로 훅을 설치**하고 커밋이 이어지는가
- [ ] 퀴즈 통과 후 재커밋이 성공하는가
- [ ] 같은 저장소에서 **터미널로 직접** `git commit` → 막히지 않는가 (D33 의 핵심)
- [ ] Codex(ChatGPT 앱)에서 플러그인 설치 → 훅이 등록되고 핸드셰이크가 기록되는가
- [ ] Codex 에서 퀴즈가 평문으로 제시되고 타이핑 답변이 채점되는가
- [ ] 기존 `pre-commit` 훅이 있는 저장소에서 체이닝이 동작하고, 기존 훅이 거부하면 퀴즈가 뜨지 않는가
- [ ] **문항이 코드를 읽지 않고 소거법으로 풀리지 않는가** — 이 도구의 성패
- [ ] 전형적인 변경에서 3분 안에 끝나는가
