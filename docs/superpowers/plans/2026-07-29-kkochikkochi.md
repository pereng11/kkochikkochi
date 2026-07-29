# KkochiKkochi Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 커밋 직전에 사용자가 변경 내용을 이해했는지 퀴즈로 검증하고, 통과하지 못하면 커밋을 실제로 차단하는 Claude Code 플러그인을 만든다.

**Architecture:** PreToolUse 훅(순수 셸, LLM 없음)이 `git commit`을 가로채, 커밋될 파일의 blob SHA가 `covered.tsv`에 기록되어 있는지 대조한다. 없으면 deny하고 스킬(LLM)이 출제·채점한 뒤 통과를 기록한다. 판정 로직에 LLM이 없으므로 셸 스크립트를 결정적으로 테스트할 수 있다.

**Tech Stack:** Bash · git plumbing (`diff --cached --raw`, `hash-object`) · jq · bats-core · shellcheck · GitHub Actions

## Global Constraints

- 런타임 의존성은 `git`과 `jq`뿐. 그 외 도구를 요구하지 않는다
- 플러그인 내부 경로는 반드시 `${CLAUDE_PLUGIN_ROOT}` 를 쓴다
- 상태 파일은 `$(git rev-parse --git-dir)/quiz-gate/` 아래에 둔다. 절대 `.claude/`나 워킹트리에 쓰지 않는다
- `NULL_SHA` = 0이 40개 (`0000000000000000000000000000000000000000`)
- `git diff --cached --raw` 호출에는 항상 `--abbrev=40 --no-renames` 를 붙인다
- **fail-open**: 판정에 실패하면 통과시킨다. 게이트 버그가 커밋을 영구 차단해서는 안 된다
- 훅 `timeout` 은 10초
- 모든 셸 스크립트는 `shellcheck` 를 통과해야 한다
- 라이선스 MIT. 식별자는 소문자 `kkochikkochi`, 표시명은 `KkochiKkochi`
- 커밋 메시지는 Conventional Commits (`feat:`, `fix:`, `test:`, `docs:`, `chore:`)
- 문항은 상한 5 · 하한 1(질문거리가 없으면 0 + 사유 기록). 시간 목표 3분

**참조 문서**
- 설계: `docs/superpowers/specs/2026-07-29-kkochikkochi-design.md`
- 결정 로그: `docs/DECISIONS.md`

---

## File Structure

| 파일 | 책임 |
|---|---|
| `.claude-plugin/plugin.json` | 플러그인 메타데이터 |
| `hooks/hooks.json` | PreToolUse 등록 |
| `hooks/gate.sh` | 훅 진입점. 커맨드 매칭 → 판정 → deny JSON 출력 |
| `scripts/pending-set.sh` | "이 커밋에 담길 (SHA, 경로)" 계산. 훅·스킬 공용 |
| `scripts/record-pass.sh` | 통과 기록. `covered.tsv` 추가 + `passes/*.json` 저장 |
| `skills/kkochikkochi/SKILL.md` | 출제·채점·오답 루프 (유일한 LLM 컴포넌트) |
| `commands/kk.md` | 수동 출제 |
| `commands/kk-log.md` | 기록 조회 |
| `tests/helper.bash` | 픽스처 레포 생성 헬퍼 |
| `tests/*.bats` | 스크립트별 테스트 |
| `.github/workflows/ci.yml` | bats + shellcheck |

의존 방향은 단방향이다. `gate.sh` → `pending-set.sh`, `record-pass.sh` → `pending-set.sh`. `pending-set.sh` 는 아무것도 의존하지 않는다.

---

### Task 1: 저장소 스캐폴딩과 `pending-set.sh`

가장 위험한 조각이자 나머지 전부의 토대다. "무엇이 커밋되는가"의 정의가 훅과 스킬로 갈라지면 영원히 통과하지 못하는 교착이 나므로, 단일 스크립트로 못박고 먼저 검증한다.

**Files:**
- Create: `.gitignore`, `.editorconfig`, `LICENSE`
- Create: `.claude-plugin/plugin.json`
- Create: `scripts/pending-set.sh`
- Create: `tests/helper.bash`
- Test: `tests/pending-set.bats`

**Interfaces:**
- Consumes: 없음
- Produces:
  - `scripts/pending-set.sh <command-string>` → stdout에 `<40자 SHA>\t<경로>` 라인들
  - 종료코드 `0` = 정상(빈 출력 가능), `2` = 게이트 무관(git 레포 아님 / rebase·merge·cherry-pick 진행 중)
  - 상수 `NULL_SHA` = 0 40개 (삭제된 파일의 SHA)

- [ ] **Step 1: bats-core 설치**

```bash
brew install bats-core        # macOS
# Linux: sudo apt-get install -y bats  또는 npm i -g bats
bats --version
```

- [ ] **Step 2: 저장소 기본 파일 생성**

`.gitignore`:

```gitignore
.DS_Store
node_modules/
tests/tmp/
*.log
```

`.editorconfig`:

```ini
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true

[*.sh]
indent_style = space
indent_size = 2

[*.md]
trim_trailing_whitespace = false
```

`LICENSE`:

```
MIT License

Copyright (c) 2026 KkochiKkochi contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

`.claude-plugin/plugin.json`:

```json
{
  "name": "kkochikkochi",
  "version": "0.1.0",
  "description": "A comprehension gate for AI-assisted coding. Blocks the commit until you can explain what changed.",
  "author": {
    "name": "KkochiKkochi contributors"
  },
  "license": "MIT",
  "keywords": ["gate", "comprehension", "quiz", "review", "git", "commit"]
}
```

`homepage` 와 `repository` 는 GitHub 저장소를 만든 뒤 Task 7에서 채운다.

- [ ] **Step 3: 테스트 헬퍼 작성**

`tests/helper.bash`:

```bash
#!/usr/bin/env bash
# 픽스처 git 레포를 만들고 그 안으로 이동한다.

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PLUGIN_ROOT
export NULL_SHA=0000000000000000000000000000000000000000

setup_repo() {
  TEST_REPO="$(mktemp -d)"
  export TEST_REPO
  cd "$TEST_REPO" || return 1
  git init -q .
  git config user.email "test@example.com"
  git config user.name "test"
  git config commit.gpgsign false
}

teardown_repo() {
  cd / || return 0
  [ -n "${TEST_REPO:-}" ] && [ -d "$TEST_REPO" ] && rm -rf "$TEST_REPO"
  return 0
}

# 초기 커밋 하나를 만든다: a.ts, b.ts, old.ts
seed_repo() {
  printf 'A1\n' > a.ts
  printf 'B1\n' > b.ts
  printf 'OLD\n' > old.ts
  git add .
  git commit -qm init
}

pending() {
  bash "$PLUGIN_ROOT/scripts/pending-set.sh" "$1"
}
```

- [ ] **Step 4: 실패하는 테스트 작성**

`tests/pending-set.bats`:

```bash
#!/usr/bin/env bats

load helper

setup() { setup_repo; seed_repo; }
teardown() { teardown_repo; }

@test "기본 커밋: 스테이징된 것만, unstaged 는 제외" {
  printf 'A2\n' > a.ts          # unstaged 수정
  printf 'C1\n' > c.ts
  git add c.ts
  run pending 'git commit -m "x"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"$(git hash-object c.ts)"$'\t'"c.ts"* ]]
  [[ "$output" != *"a.ts"* ]]
}

@test "삭제된 파일은 NULL_SHA 로 나온다" {
  git rm -q old.ts
  run pending 'git commit -m "x"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"$NULL_SHA"$'\t'"old.ts"* ]]
}

@test "-am 은 추적 파일의 워크트리 내용을 포함한다" {
  printf 'A2\n' > a.ts
  run pending 'git commit -am "x"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"$(git hash-object a.ts)"$'\t'"a.ts"* ]]
}

@test "짧은 옵션 묶음(-va)에서도 -a 를 인식한다" {
  printf 'A2\n' > a.ts
  run pending 'git commit -va -m "x"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"a.ts"* ]]
}

@test "pathspec 지정 시 해당 경로만" {
  printf 'A2\n' > a.ts
  printf 'B2\n' > b.ts
  run pending 'git commit -m "x" -- a.ts'
  [ "$status" -eq 0 ]
  [[ "$output" == *"a.ts"* ]]
  [[ "$output" != *"b.ts"* ]]
}

@test "amend 메시지만 수정하면 빈 출력" {
  run pending 'git commit --amend -m "new"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "amend 로 내용을 얹으면 그 델타만" {
  printf 'A2\n' > a.ts
  git add a.ts
  run pending 'git commit --amend --no-edit'
  [ "$status" -eq 0 ]
  [[ "$output" == *"$(git hash-object a.ts)"$'\t'"a.ts"* ]]
}

@test "git 레포가 아니면 종료코드 2" {
  cd "$(mktemp -d)" || return 1
  run pending 'git commit -m "x"'
  [ "$status" -eq 2 ]
}

@test "머지 진행 중이면 종료코드 2" {
  git checkout -qb feat
  printf 'feat\n' > a.ts
  git commit -qam feat
  git checkout -q -
  printf 'main\n' > a.ts
  git commit -qam main
  git merge feat >/dev/null 2>&1 || true
  run pending 'git commit -m merge'
  [ "$status" -eq 2 ]
}

@test "cherry-pick 진행 중이면 종료코드 2" {
  git checkout -qb feat
  printf 'feat\n' > a.ts
  git commit -qam feat
  git checkout -q -
  printf 'main\n' > a.ts
  git commit -qam main
  git cherry-pick feat >/dev/null 2>&1 || true
  run pending 'git commit -m pick'
  [ "$status" -eq 2 ]
}

@test "SHA 는 항상 40자리다" {
  printf 'C1\n' > c.ts
  git add c.ts
  run pending 'git commit -m "x"'
  sha="${output%%$'\t'*}"
  [ "${#sha}" -eq 40 ]
}
```

- [ ] **Step 5: 테스트 실패 확인**

Run: `bats tests/pending-set.bats`
Expected: 전부 FAIL — `scripts/pending-set.sh: No such file or directory`

- [ ] **Step 6: `pending-set.sh` 구현**

`scripts/pending-set.sh`:

```bash
#!/usr/bin/env bash
# 이 커밋에 담길 (blob SHA, 경로) 집합을 계산한다.
#
# 사용법: pending-set.sh "<원본 커맨드 문자열>"
# 출력:   <40자 SHA>\t<경로>   (0줄 이상)
# 종료:   0 = 정상 / 2 = 게이트 무관
#
# 훅과 스킬이 같은 파일 집합을 보게 하는 단일 진실 공급원이다.
# 이 정의가 갈라지면 영원히 통과하지 못하는 교착이 난다.

set -uo pipefail

NULL_SHA=0000000000000000000000000000000000000000
CMD="${1:-}"

git rev-parse --git-dir >/dev/null 2>&1 || exit 2
GIT_DIR_PATH="$(git rev-parse --git-dir)"

# rebase / cherry-pick / revert / merge 진행 중에 만들어지는 커밋은
# 사용자가 새로 쓴 코드가 아니므로 게이트 대상이 아니다.
for marker in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply; do
  [ -e "$GIT_DIR_PATH/$marker" ] && exit 2
done

# --- 커맨드 인자 파싱 -------------------------------------------------
# `git commit` 이후의 인자만 본다.
ARGS="${CMD#*git }"
ARGS="${ARGS#*commit}"

use_all=0
pathspecs=()
seen_ddash=0

# shellcheck disable=SC2086
set -- $ARGS
while [ $# -gt 0 ]; do
  if [ "$seen_ddash" -eq 1 ]; then
    pathspecs+=("$1"); shift; continue
  fi
  case "$1" in
    --) seen_ddash=1 ;;
    --all) use_all=1 ;;
    --*) case "$1" in
           --message|--file|--reuse-message|--author|--date) shift ;;
         esac ;;
    -*)
      # 짧은 옵션 묶음(-am, -va 등) 안의 a 를 인식한다.
      case "$1" in *a*) use_all=1 ;; esac
      # 값이 따라오는 옵션은 값을 건너뛴다.
      case "$1" in -m|-F|-C|-c) shift ;; esac
      ;;
  esac
  shift
done

# --- 출력 -------------------------------------------------------------
emit_worktree() {  # $1 = 경로
  if [ -e "$1" ]; then
    printf '%s\t%s\n' "$(git hash-object -- "$1")" "$1"
  else
    printf '%s\t%s\n' "$NULL_SHA" "$1"
  fi
}

if [ "${#pathspecs[@]}" -gt 0 ]; then
  # pathspec 지정: 해당 경로의 워크트리 내용이 커밋된다.
  git diff HEAD --name-only -- "${pathspecs[@]}" | while IFS= read -r p; do
    emit_worktree "$p"
  done
elif [ "$use_all" -eq 1 ]; then
  # -a: 추적 파일의 워크트리 내용 + 이미 스테이징된 신규 파일
  { git diff HEAD --name-only; git diff --cached --name-only; } | sort -u |
    while IFS= read -r p; do emit_worktree "$p"; done
else
  # 기본: index 내용. git 이 이미 완성된 형태로 준다.
  git diff --cached --raw --abbrev=40 --no-renames |
    awk -F'\t' '{ split($1, f, " "); print f[4] "\t" $2 }'
fi
```

**주의** — `set -- $ARGS` 는 단어 분리를 하므로 `-m "fix -a bug"` 처럼 메시지 안에 `-a` 가 독립 단어로 들어가면 `use_all` 이 잘못 켜진다. 이 오탐은 **커밋되지 않을 파일까지 퀴즈 대상에 넣는 방향**이라 안전하다(누락이 아니라 과잉). 누락은 게이트 실패지만 과잉은 문항 몇 개 늘어나는 것뿐이다. v1에서 감수한다.

- [ ] **Step 7: 실행 권한 부여 후 테스트 통과 확인**

```bash
chmod +x scripts/pending-set.sh
bats tests/pending-set.bats
```
Expected: 11 tests, 11 passed

- [ ] **Step 8: shellcheck 통과 확인**

Run: `shellcheck scripts/pending-set.sh tests/helper.bash`
Expected: 출력 없음

- [ ] **Step 9: 커밋**

```bash
git add .gitignore .editorconfig LICENSE .claude-plugin scripts tests
git commit -m "feat: add pending-set.sh, the single source of truth for commit contents"
```

---

### Task 2: `gate.sh` — 커맨드 매칭과 판정

**Files:**
- Create: `hooks/gate.sh`
- Test: `tests/gate.bats`

**Interfaces:**
- Consumes: `scripts/pending-set.sh` (Task 1) — `<SHA>\t<경로>` 출력, 종료코드 0/2
- Produces:
  - `hooks/gate.sh` — stdin으로 훅 JSON을 받아, 차단 시 stdout에 deny JSON을 내고 종료코드 0. 통과 시 출력 없이 종료코드 0
  - `covered.tsv` 형식 확정: `<40자 SHA>\t<경로>\t<pass_id>` (탭 구분, 앞 두 필드만 판정에 사용)
  - 상태 디렉터리 `$(git rev-parse --git-dir)/quiz-gate/`

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/gate.bats`:

```bash
#!/usr/bin/env bats

load helper

setup() { setup_repo; seed_repo; }
teardown() { teardown_repo; }

# 훅 stdin JSON 을 만들어 gate.sh 에 흘려넣는다.
run_gate() {  # $1 = command 문자열
  local payload
  payload=$(jq -n --arg c "$1" --arg cwd "$PWD" \
    '{tool_name:"Bash", cwd:$cwd, tool_input:{command:$c}}')
  echo "$payload" | bash "$PLUGIN_ROOT/hooks/gate.sh"
}

covered_dir() { echo "$(git rev-parse --git-dir)/quiz-gate"; }

mark_covered() {  # $1 = 경로
  mkdir -p "$(covered_dir)"
  printf '%s\t%s\t%s\n' "$(git hash-object -- "$1")" "$1" "p-test" \
    >> "$(covered_dir)/covered.tsv"
}

@test "미검증 변경이 있으면 deny 한다" {
  printf 'C1\n' > c.ts
  git add c.ts
  run run_gate 'git commit -m "x"'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"permissionDecision": "deny"'* ]] \
    || [[ "$output" == *'"permissionDecision":"deny"'* ]]
}

@test "deny 사유에 미검증 파일명이 들어간다" {
  printf 'C1\n' > c.ts
  git add c.ts
  run run_gate 'git commit -m "x"'
  [[ "$output" == *"c.ts"* ]]
}

@test "covered.tsv 에 있으면 통과(출력 없음)" {
  printf 'C1\n' > c.ts
  mark_covered c.ts
  git add c.ts
  run run_gate 'git commit -m "x"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "커버된 뒤 파일을 고치면 다시 deny 한다" {
  printf 'C1\n' > c.ts
  mark_covered c.ts
  printf 'C2\n' > c.ts        # 내용이 바뀌면 SHA 가 달라진다
  git add c.ts
  run run_gate 'git commit -m "x"'
  [[ "$output" == *"deny"* ]]
}

@test "분할 커밋: 한 번 커버하면 나눠 커밋해도 재퀴즈 없음" {
  printf 'C1\n' > c.ts; printf 'D1\n' > d.ts
  mark_covered c.ts; mark_covered d.ts
  git add c.ts && git commit -qm "c"
  git add d.ts
  run run_gate 'git commit -m "d"'
  [ -z "$output" ]
}

@test "Bash 가 아닌 툴은 무시한다" {
  run bash -c "echo '{\"tool_name\":\"Read\",\"tool_input\":{}}' | bash '$PLUGIN_ROOT/hooks/gate.sh'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "git commit 이 아닌 명령은 무시한다" {
  printf 'C1\n' > c.ts; git add c.ts
  run run_gate 'git status'
  [ -z "$output" ]
}

@test "git revert 는 게이트하지 않는다" {
  printf 'C1\n' > c.ts; git add c.ts
  run run_gate 'git revert HEAD'
  [ -z "$output" ]
}

@test "commit-tree 는 commit 으로 오인하지 않는다" {
  printf 'C1\n' > c.ts; git add c.ts
  run run_gate 'git commit-tree abc123'
  [ -z "$output" ]
}

@test "복합 커맨드(cd x && git commit)도 잡는다" {
  printf 'C1\n' > c.ts; git add c.ts
  run run_gate "cd '$PWD' && git commit -m 'x'"
  [[ "$output" == *"deny"* ]]
}

@test "git -C 형태도 잡는다" {
  printf 'C1\n' > c.ts; git add c.ts
  run run_gate "git -C '$PWD' commit -m 'x'"
  [[ "$output" == *"deny"* ]]
}

@test "문자열 안의 git commit 은 잡지 않는다" {
  printf 'C1\n' > c.ts; git add c.ts
  run run_gate 'echo "run git commit later"'
  [ -z "$output" ]
}

@test "빈 커밋(스테이징 없음)은 통과한다" {
  run run_gate 'git commit -m "x"'
  [ -z "$output" ]
}

@test "fail-open: covered.tsv 가 깨져도 판정을 계속한다" {
  printf 'C1\n' > c.ts
  mkdir -p "$(covered_dir)"
  printf 'garbage line without tabs\n' >> "$(covered_dir)/covered.tsv"
  mark_covered c.ts
  git add c.ts
  run run_gate 'git commit -m "x"'
  [ -z "$output" ]
}

@test "fail-open: git 레포가 아니면 통과한다" {
  cd "$(mktemp -d)" || return 1
  run run_gate 'git commit -m "x"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `bats tests/gate.bats`
Expected: 전부 FAIL — `hooks/gate.sh: No such file or directory`

- [ ] **Step 3: `gate.sh` 구현**

`hooks/gate.sh`:

```bash
#!/usr/bin/env bash
# PreToolUse 훅. git commit 을 가로채 이해 검증 여부를 판정한다.
#
# 판정만 한다. LLM 을 부르지 않고, 파일을 고치지 않고, git 상태를 바꾸지 않는다.
# 실패하면 통과시킨다(fail-open) — 게이트 버그가 커밋을 영구 차단해서는 안 된다.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PENDING_SET="$SCRIPT_DIR/../scripts/pending-set.sh"

allow() { exit 0; }   # 출력 없이 종료 = 판정 없음 = 정상 권한 흐름

command -v jq >/dev/null 2>&1 || allow

payload="$(cat)"
tool_name="$(jq -r '.tool_name // ""' <<<"$payload" 2>/dev/null)" || allow
[ "$tool_name" = "Bash" ] || allow

cmd="$(jq -r '.tool_input.command // ""' <<<"$payload" 2>/dev/null)" || allow
cwd="$(jq -r '.cwd // ""' <<<"$payload" 2>/dev/null)" || allow

# --- 이 커맨드가 git commit 인가 -------------------------------------
# 접두 매칭(`Bash(git commit:*)`)은 `cd x && git commit` 을 놓치므로 쓰지 않는다.
# 게이트에서는 누락이 곧 실패다. 직접 토큰 단위로 판정한다.
is_git_commit() {
  local segment tok found_git stripped
  # 따옴표 안의 내용은 실행되는 커맨드가 아니므로 지운다.
  # 이걸 하지 않으면 `echo "run git commit later"` 가 오탐된다.
  stripped="$(printf '%s' "$cmd" | sed "s/'[^']*'/''/g; s/\"[^\"]*\"/\"\"/g")"
  # 구분자(; && || |)로 쪼갠다.
  # BSD sed 는 치환문에서 \n 을 개행으로 해석하지 않으므로 awk 를 쓴다.
  while IFS= read -r segment; do
    found_git=0
    # shellcheck disable=SC2086
    set -- $segment
    while [ $# -gt 0 ]; do
      tok="$1"
      if [ "$found_git" -eq 0 ]; then
        case "$tok" in
          git|*/git) found_git=1 ;;
        esac
      else
        case "$tok" in
          # git 레벨 옵션은 값까지 건너뛴다
          -C|-c|--git-dir|--work-tree|--namespace) shift ;;
          --*=*|-*) : ;;
          commit) return 0 ;;
          *) found_git=0 ;;   # 다른 서브커맨드 → 이 git 은 아님
        esac
      fi
      shift
    done
  done < <(printf '%s\n' "$stripped" | awk '{gsub(/&&|\|\||[;|]/, "\n"); print}')
  return 1
}

is_git_commit || allow

# --- 판정 -------------------------------------------------------------
[ -d "$cwd" ] && cd "$cwd" 2>/dev/null
[ -r "$PENDING_SET" ] || allow

pending="$(bash "$PENDING_SET" "$cmd" 2>/dev/null)"
rc=$?
[ "$rc" -eq 0 ] || allow          # 2 = 게이트 무관, 그 외 = 오류 → fail-open
[ -n "$pending" ] || allow        # 커밋될 내용 없음

git_dir="$(git rev-parse --git-dir 2>/dev/null)" || allow
covered="$git_dir/quiz-gate/covered.tsv"

missing=""
while IFS=$'\t' read -r sha path; do
  [ -n "$sha" ] || continue
  if [ -r "$covered" ] &&
     awk -F'\t' -v s="$sha" -v p="$path" \
       '$1 == s && $2 == p { found = 1; exit } END { exit !found }' "$covered"; then
    continue
  fi
  missing+="   $path"$'\n'
done <<<"$pending"

[ -n "$missing" ] || allow

reason="🦡 KkochiKkochi — 미검증 변경이 있습니다.

$missing
이 변경을 이해했는지 먼저 확인해야 합니다.
kkochikkochi 스킬을 실행해 퀴즈를 통과한 뒤 다시 커밋하세요."

jq -n --arg r "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $r
  }
}'
exit 0
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
chmod +x hooks/gate.sh
bats tests/gate.bats
```
Expected: 15 tests, 15 passed

- [ ] **Step 5: shellcheck 통과 확인**

Run: `shellcheck hooks/gate.sh`
Expected: 출력 없음

- [ ] **Step 6: 커밋**

```bash
git add hooks/gate.sh tests/gate.bats
git commit -m "feat: add gate.sh, the PreToolUse decision hook"
```

---

### Task 3: `record-pass.sh` — 통과 기록

**Files:**
- Create: `scripts/record-pass.sh`
- Test: `tests/record-pass.bats`

**Interfaces:**
- Consumes: `scripts/pending-set.sh` (Task 1), `covered.tsv` 형식 (Task 2)
- Produces:
  - `scripts/record-pass.sh <command-string>` — stdin으로 transcript JSON을 받아 기록. 성공 시 종료코드 0, 거부 시 1
  - transcript JSON 스키마:
    ```json
    { "questions": [ { "axis": "impact", "q": "...", "evidence": "src/a.ts:42",
                       "format": "choice", "answer": "B", "correct": "B",
                       "attempts": 1, "gave_up": false } ],
      "skipped_reason": null }
    ```
  - 기록 산출물: `covered.tsv` 추가 라인, `passes/<pass_id>.json`
  - `pass_id` 형식: `p-YYYYmmdd-HHMMSS`

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/record-pass.bats`:

```bash
#!/usr/bin/env bats

load helper

setup() { setup_repo; seed_repo; }
teardown() { teardown_repo; }

record() {  # $1 = transcript JSON, $2 = command
  echo "$1" | bash "$PLUGIN_ROOT/scripts/record-pass.sh" "${2:-git commit -m x}"
}

qdir() { echo "$(git rev-parse --git-dir)/quiz-gate"; }

VALID='{"questions":[{"axis":"facts","q":"무엇이 바뀌었나?","evidence":"c.ts:1","format":"choice","answer":"A","correct":"A","attempts":1,"gave_up":false}]}'

@test "통과를 기록하면 covered.tsv 에 라인이 생긴다" {
  printf 'C1\n' > c.ts; git add c.ts
  run record "$VALID"
  [ "$status" -eq 0 ]
  grep -q "$(git hash-object c.ts)" "$(qdir)/covered.tsv"
}

@test "covered.tsv 라인은 SHA/경로/pass_id 세 필드다" {
  printf 'C1\n' > c.ts; git add c.ts
  record "$VALID"
  line="$(head -1 "$(qdir)/covered.tsv")"
  [ "$(awk -F'\t' '{print NF}' <<<"$line")" -eq 3 ]
}

@test "문답 전문이 passes/ 에 저장된다" {
  printf 'C1\n' > c.ts; git add c.ts
  record "$VALID"
  [ "$(find "$(qdir)/passes" -name 'p-*.json' | wc -l)" -eq 1 ]
}

@test "저장된 JSON 에 questions 가 보존된다" {
  printf 'C1\n' > c.ts; git add c.ts
  record "$VALID"
  f="$(find "$(qdir)/passes" -name 'p-*.json' | head -1)"
  [ "$(jq -r '.transcript.questions[0].axis' "$f")" = "facts" ]
}

@test "SHA 는 인자가 아니라 스크립트가 직접 계산한다" {
  printf 'C1\n' > c.ts; git add c.ts
  record "$VALID"
  grep -q "$(git hash-object c.ts)"$'\t'"c.ts" "$(qdir)/covered.tsv"
}

@test "문항이 0개면 거부한다" {
  printf 'C1\n' > c.ts; git add c.ts
  run record '{"questions":[]}'
  [ "$status" -eq 1 ]
  [ ! -f "$(qdir)/covered.tsv" ]
}

@test "서술형 답변이 공백이면 거부한다" {
  printf 'C1\n' > c.ts; git add c.ts
  bad='{"questions":[{"axis":"intent","q":"왜?","evidence":"대화","format":"free","answer":"   ","correct":null,"attempts":1,"gave_up":false}]}'
  run record "$bad"
  [ "$status" -eq 1 ]
}

@test "skipped_reason 이 있으면 문항 0개라도 기록한다" {
  printf 'C1\n' > c.ts; git add c.ts
  run record '{"questions":[],"skipped_reason":"lockfile 재생성만 포함"}'
  [ "$status" -eq 0 ]
  grep -q "c.ts" "$(qdir)/covered.tsv"
}

@test "잘못된 JSON 은 거부한다" {
  printf 'C1\n' > c.ts; git add c.ts
  run record 'not json at all'
  [ "$status" -eq 1 ]
}

@test "여러 번 기록하면 covered.tsv 에 누적된다" {
  printf 'C1\n' > c.ts; git add c.ts
  record "$VALID"
  printf 'D1\n' > d.ts; git add d.ts
  record "$VALID"
  [ "$(wc -l < "$(qdir)/covered.tsv")" -ge 2 ]
}

@test "기록 후 gate.sh 가 통과시킨다 (종단 확인)" {
  printf 'C1\n' > c.ts; git add c.ts
  record "$VALID"
  payload=$(jq -n --arg c 'git commit -m x' --arg cwd "$PWD" \
    '{tool_name:"Bash", cwd:$cwd, tool_input:{command:$c}}')
  run bash -c "echo '$payload' | bash '$PLUGIN_ROOT/hooks/gate.sh'"
  [ -z "$output" ]
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `bats tests/record-pass.bats`
Expected: 전부 FAIL — `scripts/record-pass.sh: No such file or directory`

- [ ] **Step 3: `record-pass.sh` 구현**

`scripts/record-pass.sh`:

```bash
#!/usr/bin/env bash
# 퀴즈 통과를 기록한다.
#
# 사용법: echo "<transcript json>" | record-pass.sh "<원본 커맨드 문자열>"
# 종료:   0 = 기록됨 / 1 = 거부
#
# SHA 는 인자로 받지 않고 스크립트가 직접 계산한다.
# 에이전트가 건네준 해시를 신뢰하지 않기 위해서다.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PENDING_SET="$SCRIPT_DIR/pending-set.sh"
CMD="${1:-git commit}"

die() { echo "kkochikkochi: $1" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || die "jq 가 필요합니다"

transcript="$(cat)"
jq -e . >/dev/null 2>&1 <<<"$transcript" || die "transcript 가 올바른 JSON 이 아닙니다"

n_questions="$(jq '.questions | length' <<<"$transcript" 2>/dev/null)" \
  || die "questions 배열을 읽을 수 없습니다"
skipped="$(jq -r '.skipped_reason // ""' <<<"$transcript")"

# 문항 0개는 사유가 명시된 경우에만 허용한다.
if [ "$n_questions" -eq 0 ] && [ -z "$skipped" ]; then
  die "문항이 없습니다. 출제를 건너뛰려면 skipped_reason 을 명시하세요"
fi

# 서술형 답변이 공백이면 거부한다.
if jq -e '.questions[]? | select(.format == "free")
          | select((.answer // "") | gsub("\\s"; "") == "")' \
     >/dev/null <<<"$transcript"; then
  die "서술형 답변이 비어 있습니다"
fi

pending="$(bash "$PENDING_SET" "$CMD" 2>/dev/null)" || die "커밋 대상을 계산할 수 없습니다"
[ -n "$pending" ] || die "커밋될 내용이 없습니다"

git_dir="$(git rev-parse --git-dir 2>/dev/null)" || die "git 저장소가 아닙니다"
qdir="$git_dir/quiz-gate"
mkdir -p "$qdir/passes" || die "상태 디렉터리를 만들 수 없습니다"

pass_id="p-$(date -u +%Y%m%d-%H%M%S)"

# covered.tsv 에 추가
while IFS=$'\t' read -r sha path; do
  [ -n "$sha" ] || continue
  printf '%s\t%s\t%s\n' "$sha" "$path" "$pass_id" >> "$qdir/covered.tsv"
done <<<"$pending"

# 문답 전문 저장
covered_json="$(
  while IFS=$'\t' read -r sha path; do
    [ -n "$sha" ] || continue
    jq -n --arg p "$path" --arg s "$sha" '{key: $p, value: $s}'
  done <<<"$pending" | jq -s 'from_entries'
)"

jq -n \
  --arg id "$pass_id" \
  --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg head "$(git rev-parse --short HEAD 2>/dev/null || echo '')" \
  --argjson covered "$covered_json" \
  --argjson transcript "$transcript" \
  '{v: 1, pass_id: $id, at: $at, head: $head,
    covered: $covered, transcript: $transcript}' \
  > "$qdir/passes/$pass_id.json" || die "기록 파일을 쓸 수 없습니다"

echo "$pass_id"
exit 0
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
chmod +x scripts/record-pass.sh
bats tests/record-pass.bats
```
Expected: 11 tests, 11 passed

- [ ] **Step 5: 전체 테스트와 shellcheck**

```bash
bats tests/
shellcheck scripts/*.sh hooks/*.sh tests/helper.bash
```
Expected: 37 tests 전부 통과, shellcheck 출력 없음

- [ ] **Step 6: 커밋**

```bash
git add scripts/record-pass.sh tests/record-pass.bats
git commit -m "feat: add record-pass.sh to persist quiz results"
```

---

### Task 4: 훅 등록과 CI

셸 3종이 완성됐으므로 플러그인으로 배선하고 CI를 건다.

**Files:**
- Create: `hooks/hooks.json`
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `hooks/gate.sh` (Task 2)
- Produces: 설치 가능한 플러그인. `git commit` 시 `gate.sh` 가 자동 실행됨

- [ ] **Step 1: `hooks/hooks.json` 작성**

```json
{
  "description": "Comprehension gate before commit — blocks git commit until you can explain the change.",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/gate.sh\"",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

`matcher` 를 `Bash` 로 넓게 잡고 `gate.sh` 안에서 판정하는 이유는 설계 문서 §9 참조. `if: "Bash(git commit:*)"` 은 접두 매칭이라 `cd x && git commit` 을 놓친다.

- [ ] **Step 2: JSON 유효성 확인**

```bash
jq . hooks/hooks.json && jq . .claude-plugin/plugin.json
```
Expected: 두 파일 모두 파싱됨

- [ ] **Step 3: CI 워크플로 작성**

`.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install bats
        run: sudo apt-get update && sudo apt-get install -y bats

      - name: Configure git identity
        run: |
          git config --global user.email "ci@example.com"
          git config --global user.name "ci"
          git config --global init.defaultBranch main

      - name: Run tests
        run: bats tests/

      - name: Lint shell scripts
        run: shellcheck scripts/*.sh hooks/*.sh tests/helper.bash

      - name: Validate JSON
        run: |
          jq . hooks/hooks.json > /dev/null
          jq . .claude-plugin/plugin.json > /dev/null
```

- [ ] **Step 4: 로컬에서 CI 단계를 그대로 재현**

```bash
bats tests/
shellcheck scripts/*.sh hooks/*.sh tests/helper.bash
jq . hooks/hooks.json > /dev/null && jq . .claude-plugin/plugin.json > /dev/null
echo "모든 CI 단계 통과"
```
Expected: `모든 CI 단계 통과`

- [ ] **Step 5: 커밋**

```bash
git add hooks/hooks.json .github/workflows/ci.yml
git commit -m "feat: register PreToolUse hook and add CI"
```

---

### Task 5: `SKILL.md` — 출제와 채점

유일한 LLM 컴포넌트. 셸이 만들어낸 사실(무엇이 커밋되는가)을 받아 문항을 만들고 채점한다.

**Files:**
- Create: `skills/kkochikkochi/SKILL.md`

**Interfaces:**
- Consumes: `scripts/pending-set.sh` (Task 1), `scripts/record-pass.sh` (Task 3)
- Produces: `kkochikkochi` 스킬. `gate.sh` 의 deny 사유에서 이름으로 지목됨

- [ ] **Step 1: `skills/kkochikkochi/SKILL.md` 작성**

````markdown
---
name: kkochikkochi
description: Use when a commit is blocked by the KkochiKkochi gate, or when the user asks to be quizzed on the current change. Quizzes the user on staged changes and records the result so the commit can proceed.
---

# KkochiKkochi — 이해 검증 게이트

커밋될 변경 내용에 대해 사용자를 퀴즈하고, 통과하면 기록해 커밋을 풀어준다.

**핵심 원칙: 문항 품질이 이 도구의 성패다.** 코드를 읽지 않고 소거법으로 풀 수 있는 문항은 게이트를 무력화한다.

## 1. 재료 수집

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/pending-set.sh" "git commit"
```

출력이 비어 있으면 검증할 것이 없다. 사용자에게 알리고 종료한다.

이어서 세 가지 재료를 모은다.

| 재료 | 얻는 법 | 어느 축에 쓰이나 |
|---|---|---|
| 변경 본문 | `git diff --cached` | 변경 사실, 영향·리스크 |
| 호출부·의존 | 변경된 심볼을 레포에서 Grep | 영향·리스크 |
| 설계 근거 | **현재 대화 맥락** | 설계 의도 |
| 레포 구조 | 관련 파일 읽기 | 재현 가능성 |

**설계 의도의 근거는 diff에 없다.** 대화에서 "왜 이 방식을 골랐는지"가 논의되지 않았다면 그 축은 출제하지 않는다.

## 2. 문항 생성

### 축 우선순위

| 순위 | 축 | 형식 | 생략 조건 |
|---|---|---|---|
| 1 | 변경 사실 확인 | 객관식 | 거의 없음 |
| 2 | 영향·리스크 | 객관식 | 호출부·의존이 전혀 없는 고립된 변경 |
| 3 | 설계 의도 | 서술(한 문장) | 대화에 명확한 설계 결정이 없을 때 |
| 4 | 재현 가능성 | 짧은 답 | 레포 구조상 물을 지점이 없을 때 |

### 예산

- **상한 5문항.** 억지로 채우지 않는다. 근거 있는 문항만 낸다
- **하한 1문항.** 질문거리가 전혀 없으면(lockfile 재생성, 포매팅만) 0문항으로 하고 `skipped_reason` 에 사유를 적는다
- 상한 5는 4축을 전부 담고 한 자리가 남는다. 남는 자리는 **영향·리스크** 축에 준다
- 시간 목표 3분

### 출제 순서

우선순위 순으로 내되 **서술형은 항상 마지막**이다. 앞선 객관식이 변경 내용을 상기시켜 서술 답변의 질이 올라간다.

### 오답 선택지 규칙 — 반드시 지킨다

1. **"그럴듯한 오해"에서 뽑는다.** 이전 버전의 실제 동작, 인접 함수가 실제로 하는 일
2. **레포의 실제 문자열을 쓴다.** 실존하는 다른 경로·함수명. 지어낸 이름 금지
3. **금지 선택지**: "변함 없음", "위 전부", "해당 없음", "모름"
4. **정답 위치를 무작위화한다.** B·C 편향을 경계하라

### 근거 없는 문항은 폐기한다

> 모든 문항은 정답 근거를 `파일:줄` 또는 `대화 내 발언`으로 특정할 수 있어야 한다.

특정하지 못하면 **출제하지 말고 버린다.** 하드 게이트에서 가장 치명적인 실패는 정답이 틀린 것이다. 사용자가 맞는 답을 하는데 계속 오답 처리되면 진짜로 갇힌다.

근거는 각 문항의 `evidence` 필드에 기록한다.

## 3. 출제

객관식과 짧은 답은 `AskUserQuestion` 으로 낸다. 선택지에는 항상 **"모르겠다"** 를 포함한다.

서술형은 일반 질문으로 내고 답변을 기다린다.

## 4. 채점과 오답 루프

```
정답      → 다음 문항

오답      → 해설한다 (반드시 실제 코드를 인용할 것. 추상적 설명 금지)
           → 같은 축, 다른 각도로 재출제
           → attempts 증가
           ※ 같은 문항을 반복하지 않는다. 반복하면 이해가 아니라
             정답을 외워서 통과하게 된다

"모르겠다" → 해당 지점을 실제 코드를 인용해 가르친다
           → 사용자가 이해했다고 확인하면 다른 각도로 재출제
           → gave_up = true 로 기록
```

전 문항을 통과할 때까지 계속한다. 통과 전에 기록하지 않는다.

## 5. 기록

전 문항 통과 후:

```bash
cat <<'JSON' | bash "${CLAUDE_PLUGIN_ROOT}/scripts/record-pass.sh" "git commit"
{
  "questions": [
    {
      "axis": "facts",
      "q": "이 변경으로 auth 미들웨어가 통과시키는 경로는?",
      "evidence": "src/auth/middleware.ts:42",
      "format": "choice",
      "answer": "B",
      "correct": "B",
      "attempts": 1,
      "gave_up": false
    }
  ],
  "skipped_reason": null
}
JSON
```

`axis` 는 `facts` · `impact` · `intent` · `reproduce` 중 하나. `format` 은 `choice` · `short` · `free` 중 하나.

기록이 끝나면 사용자에게 커밋을 다시 시도하라고 알린다.

## 6. 하지 말아야 할 것

- 퀴즈를 건너뛰고 `record-pass.sh` 를 호출하는 것. 게이트의 존재 이유가 사라진다
- 사용자가 답하기 전에 정답을 알려주는 것
- 근거를 특정하지 못한 문항을 출제하는 것
- 같은 문항을 그대로 재출제하는 것
````

- [ ] **Step 2: 스킬 프론트매터 유효성 확인**

```bash
head -5 skills/kkochikkochi/SKILL.md
grep -q '^name: kkochikkochi$' skills/kkochikkochi/SKILL.md && echo "name OK"
grep -q '^description: ' skills/kkochikkochi/SKILL.md && echo "description OK"
```
Expected: `name OK` 와 `description OK`

- [ ] **Step 3: 커밋**

```bash
git add skills/kkochikkochi/SKILL.md
git commit -m "feat: add kkochikkochi skill for question generation and grading"
```

---

### Task 6: 슬래시 커맨드

**Files:**
- Create: `commands/kk.md`
- Create: `commands/kk-log.md`

**Interfaces:**
- Consumes: `skills/kkochikkochi/SKILL.md` (Task 5), `scripts/pending-set.sh` (Task 1)
- Produces: `/kk`, `/kk-log`

- [ ] **Step 1: `commands/kk.md` 작성**

```markdown
---
description: 지금 스테이징된 변경에 대해 이해도 퀴즈를 받는다
---

kkochikkochi 스킬을 실행해 현재 스테이징된 변경에 대해 나에게 퀴즈를 내라.

커밋이 차단되지 않았더라도 실행한다 — 커밋 전에 미리 확인하고 싶을 때 쓰는 명령이다.
```

- [ ] **Step 2: `commands/kk-log.md` 작성**

````markdown
---
description: 지금까지의 이해도 검증 기록을 보여준다
---

이 저장소의 KkochiKkochi 기록을 요약해서 보여줘라.

```bash
QDIR="$(git rev-parse --git-dir)/quiz-gate"
echo "=== 커버된 파일 수 ==="
[ -f "$QDIR/covered.tsv" ] && wc -l < "$QDIR/covered.tsv" || echo 0
echo "=== 검증 횟수 ==="
[ -d "$QDIR/passes" ] && find "$QDIR/passes" -name 'p-*.json' | wc -l || echo 0
echo "=== 최근 5건 ==="
[ -d "$QDIR/passes" ] && find "$QDIR/passes" -name 'p-*.json' | sort | tail -5
```

찾은 기록 파일들을 읽고 다음을 표로 정리해 보여줘라.

- 축별 1차 정답률 (`attempts == 1` 인 비율)
- `gave_up` 이 true 인 문항 수
- 가장 자주 틀린 축

기록이 없으면 아직 검증 이력이 없다고 알려줘라.
````

- [ ] **Step 3: 프론트매터 확인**

```bash
for f in commands/kk.md commands/kk-log.md; do
  head -1 "$f" | grep -q '^---$' && echo "$f OK"
done
```
Expected: 두 줄 모두 `OK`

- [ ] **Step 4: 커밋**

```bash
git add commands
git commit -m "feat: add /kk and /kk-log slash commands"
```

---

### Task 7: 공개 문서

오픈소스 배포를 위한 문서. 어원 설명이 없으면 비한국어권 사용자가 이름을 이해할 수 없다.

**Files:**
- Create: `README.md`, `CHANGELOG.md`, `CONTRIBUTING.md`
- Modify: `.claude-plugin/plugin.json` (homepage/repository 추가)

**Interfaces:**
- Consumes: 전 태스크의 산출물
- Produces: 배포 가능한 저장소

- [ ] **Step 1: `README.md` 작성**

````markdown
# KkochiKkochi 🦡

> **KkochiKkochi** *(kko-chi-kko-chi)* — Korean, adv. *questioning in relentless, minute detail.*
> It won't let you commit code you can't explain.

AI 코딩 에이전트는 사람이 읽는 속도보다 빠르게 코드를 만든다. 그래서 **사람의 이해가 병목이자 리스크**가 된다. 린터와 테스트는 코드를 검증하지만 사람의 이해는 검증하지 않는다.

KkochiKkochi 는 커밋 직전에 당신이 방금 무엇을 바꿨는지 묻는다. 답하지 못하면 커밋이 막힌다.

## 동작

```
$ git commit -m "add auth middleware"

🦡 KkochiKkochi — 미검증 변경이 있습니다.

   src/auth/middleware.ts
   src/lib/session.ts

   이 변경을 이해했는지 먼저 확인해야 합니다.

Q1. 이 변경으로 auth 미들웨어가 통과시키는 경로는?
    A) /api/* 전체
    B) /api/public/* 을 제외한 전체
    C) 정적 에셋만
    D) 모르겠다

→ B  ✓

Q2. 세션 저장소를 Redis 대신 JWT 로 간 이유를 한 문장으로 적으세요.
→ ...

통과했습니다. 다시 커밋하세요.
```

## 설치

```
/plugin marketplace add <owner>/kkochikkochi
/plugin install kkochikkochi
```

필요 도구: `git`, `jq`

## 무엇을 묻는가

| 축 | 예시 |
|---|---|
| 변경 사실 | 어떤 파일의 무엇이 바뀌었나 |
| 영향·리스크 | 이 변경으로 무엇이 깨질 수 있나 |
| 설계 의도 | 왜 이 방식을 골랐고 무엇을 버렸나 |
| 재현 가능성 | X 를 바꾸려면 어디를 건드려야 하나 |

문항은 최대 5개, 목표 3분. 근거를 코드나 대화에서 특정할 수 없는 문항은 출제되지 않는다.

## 언제 막지 않는가

- `git revert` — 롤백은 비상 레버다. 게이트를 걸면 사고를 키운다
- `git cherry-pick`, `git merge` — 남의 커밋
- `git commit --amend` 로 메시지만 고칠 때
- 게이트 자체에 문제가 생겼을 때 (fail-open)

## 어떻게 기억하는가

파일 내용의 blob SHA 를 `.git/quiz-gate/covered.tsv` 에 기록한다. 파일을 한 글자라도 고치면 SHA 가 바뀌어 그 파일만 다시 물어본다. 한 번 통과한 변경은 여러 커밋으로 나눠 올려도 다시 묻지 않는다.

기록은 `.git/` 안에만 있고 절대 커밋되지 않는다.

## 명령

| 명령 | 설명 |
|---|---|
| `/kk` | 지금 스테이징된 변경으로 퀴즈를 받는다 |
| `/kk-log` | 지금까지의 검증 기록과 취약한 축을 본다 |

## 한계

- Bash 를 거치지 않는 커밋(IDE 커밋 버튼, git MCP 도구)은 훅을 타지 않는다
- 에이전트가 퀴즈를 건너뛰고 통과를 기록할 수 있다. 이것은 보안 경계가 아니라 규율 장치다

설계 근거는 [docs/DECISIONS.md](docs/DECISIONS.md) 참조.

## License

MIT
````

- [ ] **Step 2: `CHANGELOG.md` 작성**

```markdown
# Changelog

이 프로젝트는 [Keep a Changelog](https://keepachangelog.com/) 형식과
[Semantic Versioning](https://semver.org/) 을 따른다.

## [Unreleased]

### Added
- `git commit` 을 가로채는 PreToolUse 이해 검증 게이트
- 파일 단위 blob SHA 바인딩으로 분할 커밋 지원
- 4축 문항 생성 (변경 사실 · 영향·리스크 · 설계 의도 · 재현 가능성)
- 오답 시 다른 각도로 재출제하는 학습 루프
- `/kk`, `/kk-log` 슬래시 커맨드
```

- [ ] **Step 3: `CONTRIBUTING.md` 작성**

````markdown
# Contributing

## 개발 환경

```bash
brew install bats-core shellcheck jq     # macOS
sudo apt-get install -y bats shellcheck jq   # Debian/Ubuntu
```

## 테스트

```bash
bats tests/                                        # 전체
bats tests/pending-set.bats                        # 개별
shellcheck scripts/*.sh hooks/*.sh tests/helper.bash
```

테스트는 매번 `mktemp -d` 로 새 git 저장소를 만든다. 커밋된 `.git` 픽스처를 저장소에 넣지 않는다.

## 설계 원칙

1. **훅에 LLM 을 넣지 않는다.** 판정은 결정적이어야 테스트할 수 있다
2. **fail-open.** 게이트 버그가 커밋을 영구 차단해서는 안 된다
3. **`pending-set.sh` 는 단일 진실 공급원이다.** "무엇이 커밋되는가"의 정의가 갈라지면 교착이 난다
4. **근거 없는 문항은 출제하지 않는다.** 틀린 정답은 사용자를 가둔다

설계 결정과 기각된 대안은 [docs/DECISIONS.md](docs/DECISIONS.md) 에 있다. 결정을 바꿀 때는 항목을 지우지 말고 상태와 변경 이력을 덧붙인다.

## 커밋 메시지

Conventional Commits 를 쓴다: `feat:`, `fix:`, `test:`, `docs:`, `chore:`
````

- [ ] **Step 4: `plugin.json` 에 저장소 주소 추가**

`.claude-plugin/plugin.json` 의 `"license"` 줄 앞에 두 줄을 넣는다. `<owner>` 는 실제 GitHub 계정으로 바꾼다.

```json
  "homepage": "https://github.com/<owner>/kkochikkochi",
  "repository": "https://github.com/<owner>/kkochikkochi",
```

- [ ] **Step 5: 전체 검증**

```bash
bats tests/
shellcheck scripts/*.sh hooks/*.sh tests/helper.bash
jq . hooks/hooks.json > /dev/null && jq . .claude-plugin/plugin.json > /dev/null
echo "--- 파일 구조 ---"
find . -not -path './.git/*' -not -name '.git' -type f | sort
```
Expected: 37 tests 통과, shellcheck 무출력, JSON 유효

- [ ] **Step 6: 커밋**

```bash
git add README.md CHANGELOG.md CONTRIBUTING.md .claude-plugin/plugin.json
git commit -m "docs: add README, changelog, and contributing guide"
```

---

## 완료 후 수동 검증

자동 테스트로는 확인할 수 없는 것들이다. 플러그인을 실제로 설치해 확인한다.

- [ ] 플러그인 설치 후 임시 저장소에서 `git commit` 이 실제로 차단되는가
- [ ] deny 사유가 사용자에게 읽히는 형태로 표시되는가
- [ ] 스킬이 자동으로 호출되는가, 아니면 사용자가 `/kk` 를 쳐야 하는가
- [ ] 퀴즈 통과 후 재커밋이 성공하는가
- [ ] **문항이 코드를 읽지 않고 소거법으로 풀리지 않는가** — 이 도구의 성패다. 실제 diff 몇 개로 출제시켜 문항 품질을 사람이 평가한다
- [ ] 전형적인 변경에서 소요 시간이 3분 안에 들어오는가
