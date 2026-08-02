# KkochiKkochi v3 병렬 서브에이전트 게이트 — 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 서브에이전트가 만든 커밋은 `pre-commit` 에서 막지 않고 원장에 적어 통과시키고, 사람에게 물을 수 있는 자리(`PostToolUse(Task)`·`Stop`·`pre-push`)에서 검증을 강제한다.

**Architecture:** `pre-commit` 은 신선한 `agent_id` 마커가 있으면 원장에 적고 통과하고, 없으면 지금처럼 막는다. `SubagentStop` 이 번들을 봉인하고 `PostToolUse(Task)` 가 부모에게 검증 요구를 밀어 넣는다. `Stop` 이 턴 종료를 막고 `pre-push` 가 최종 경계다. 상태는 전부 `$(git rev-parse --git-common-dir)/quiz-gate/` 에 모여 워크트리를 넘나든다.

**Tech Stack:** POSIX sh (`hooks/*`), bash (`scripts/*.sh`), `jq`, bats (`tests/*.bats`), shellcheck

## Global Constraints

- `hooks/pre-commit` 과 `hooks/pre-push` 는 **POSIX sh** 다. `shellcheck -s sh` 를 통과해야 한다. bash 전용 문법(`[[ ]]`, `<<<`, 배열)을 쓰지 않는다.
- `scripts/*.sh` 는 bash 다. `set -uo pipefail` 로 시작한다.
- 설치된 훅은 `.git/hooks/` 의 **사본**이므로 플러그인 루트로 돌아가는 경로가 없다. 훅은 `scripts/` 의 어떤 파일도 부르지 못한다 — 필요한 로직을 인라인으로 갖는다.
- 자기 식별 마커 문자열은 `KKOCHIKKOCHI-HOOK-v1` 을 그대로 쓴다. 판 번호를 심지 않는다 (D39).
- 신선도 창은 `FRESH_SECS=600`, pending 창은 `PENDING_FRESH_SECS=900`. 값을 바꾸지 않는다.
- `jq` 가 없으면 **게이트를 열어 통과시킨다** (D42). 새 훅도 예외 없이 따른다.
- 판정 규칙("지금 검증할 대상은 무엇인가")은 `scripts/pending.sh` 한 곳에만 둔다 (D45). 다른 파일에 같은 규칙을 다시 적지 않는다.
- 경로는 `git -c core.quotePath=false diff --cached --raw -z --abbrev=40 --no-renames` 의 원문 그대로 쓴다. 탭·개행이 든 경로는 거부한다.
- 애매한 경우는 통과시킨다 (D35). 사람이 터미널에서 직접 친 커밋(fd 1/2 가 tty)은 막지 않는다 (D41).
- **[정정, 2026-08-01: 이 전제는 거짓으로 확인됐다.]** Codex 페이로드에도 `agent_id`·`agent_type` 이 있다 (`codex-rs/hooks/schema/generated/*.schema.json`:
  `PreToolUse`·`PostToolUse` 에 optional, `SubagentStart`·`SubagentStop` 에 required).
  서브에이전트 생성 도구의 직렬화 이름은 `spawn_agent` 이고 matcher alias 는 `Agent` 다
  (`codex-rs/core/src/tools/hook_names.rs`) — Claude Code 의 `Task` 는 Codex 에서 아무것도
  매칭하지 않는다. 두 에이전트의 층 구조는 같고 이벤트 이름만 다르다. 상세는
  `docs/superpowers/specs/2026-08-01-push-scope-and-codex-design.md` §5.

## 스펙 수정 두 건

계획을 쓰면서 스펙의 구현 불가 지점을 찾았다. Task 4 와 Task 6 에서 스펙 파일도 함께 고친다.

1. **`ledger.tsv` 에서 `commit_sha` 를 뺀다.** `pre-commit` 은 커밋이 만들어지기 전에 돌아서 그 값을 모른다. 필요도 없다 — `pre-push` 는 push 범위의 `git diff --raw` 를 `covered.tsv` 와 대조하고, 원장은 번들 묶기와 `Stop` 판정에만 쓴다.
2. **`PostToolUse(Task)` 는 `agent_id` 를 받지 않는다.** SDK 정의: "Present only when the hook fires from inside a Task-spawned sub-agent; absent on the main thread." `PostToolUse(Task)` 는 부모 문맥에서 돈다. 그래서 `SubagentStop` 이 `agents/<agent_id>` 에 검증 대기 표시를 남기고, `PostToolUse` 는 그 표시를 디스크에서 읽는다.

## File Structure

| 파일 | 책임 |
|---|---|
| `hooks/pre-commit` (수정) | 모드 판별, 원장 기록 또는 차단. 인라인 전용 |
| `hooks/pre-push` (신규) | push 범위의 미검증 변경 차단. 인라인 전용 |
| `scripts/stamp-agent.sh` (수정) | `agent_id` 별 마커 기록 + 건강검진 |
| `scripts/pending.sh` (수정) | 검증 대상 판정의 유일한 구현. 세 모드 |
| `scripts/record-pass.sh` (수정) | 통과 기록. `pass_id` 충돌 수정 |
| `scripts/install.sh` (수정) | 훅 목록을 순회해 설치·제거·상태 |
| `scripts/seal-bundle.sh` (신규) | `SubagentStart`/`SubagentStop` — 번들 열고 봉인 |
| `scripts/bundle-notify.sh` (신규) | `PostToolUse(Task)` — 부모에게 검증 요구 주입 |
| `scripts/stop-gate.sh` (신규) | `Stop` — 미검증 남으면 block |
| `scripts/defer.sh` (신규) | 유예 모드 켜기·끄기·조회 |
| `hooks/hooks.json` (수정) | Claude Code 매니페스트에 새 훅 4종 등록 |
| `tests/helper.bash` (수정) | `qdir` 를 공유 디렉터리로, `stamp` 를 새 마커 형식으로, 워크트리 헬퍼 추가 |

새 스크립트는 하나씩 한 가지만 한다. `stop-gate.sh` 와 `bundle-notify.sh` 는 둘 다 "미검증이 남았나"를 묻지만, 그 판정은 각자 구현하지 않고 `pending.sh --all-unverified` / `--bundle` 을 부른다.

---

### Task 1: 상태를 공유 git 디렉터리로 옮긴다

`--git-path quiz-gate` 는 워크트리마다 따로 만들어져, 워크트리로 격리된 서브에이전트의 커밋을 메인 세션 훅이 보지 못한다. 이 태스크가 먼저 와야 뒤의 모든 태스크가 같은 곳을 본다.

**Files:**
- Modify: `hooks/pre-commit:12`
- Modify: `scripts/pending.sh:34-35`
- Modify: `scripts/record-pass.sh:50-51`
- Modify: `scripts/stamp-agent.sh:58`
- Modify: `tests/helper.bash:37` (`qdir`), 그리고 워크트리 헬퍼 추가
- Test: `tests/worktree.bats` (신규)

**Interfaces:**
- Consumes: 없음 (첫 태스크)
- Produces: 모든 파일이 `$(git rev-parse --git-common-dir)/quiz-gate` 를 상태 루트로 쓴다. 테스트 헬퍼 `qdir()` 가 그 경로를 낸다. 새 헬퍼 `add_worktree <브랜치명>` 이 워크트리 경로를 stdout 으로 낸다.

- [ ] **Step 1: 워크트리 헬퍼를 추가한다**

`tests/helper.bash` 의 `teardown_repo` 바로 앞에 넣는다.

```bash
# 링크된 워크트리를 만들고 그 경로를 stdout 으로 낸다.
# teardown_repo 가 지울 수 있도록 TEST_WORKTREES 에 모아 둔다.
add_worktree() {  # $1 = 새 브랜치 이름
  local wt
  wt="$(mktemp -d)"
  rm -rf "$wt"   # git worktree add 는 존재하지 않는 경로를 요구한다
  git worktree add -q "$wt" -b "$1" >/dev/null 2>&1 || return 1
  TEST_WORKTREES="${TEST_WORKTREES:-} $wt"
  export TEST_WORKTREES
  echo "$wt"
}
```

그리고 `teardown_repo` 를 이렇게 바꾼다.

```bash
teardown_repo() {
  cd / || return 0
  for wt in ${TEST_WORKTREES:-}; do
    [ -d "$wt" ] && rm -rf "$wt"
  done
  TEST_WORKTREES=""
  [ -n "${TEST_REPO:-}" ] && [ -d "$TEST_REPO" ] && rm -rf "$TEST_REPO"
  return 0
}
```

- [ ] **Step 2: 실패하는 테스트를 쓴다**

`tests/worktree.bats` 를 새로 만든다.

```bash
#!/usr/bin/env bats
#
# 상태는 워크트리를 넘나들어야 한다.
#
# --git-path quiz-gate 는 링크된 워크트리에서 .git/worktrees/<name>/quiz-gate 로
# 풀린다(실측). 그러면 워크트리로 격리된 서브에이전트가 만든 커밋의 원장을
# 메인 세션의 Stop 훅이 보지 못한다 — 게이트가 조용히 없는 상태가 된다.

load helper

setup() { setup_repo; seed_repo; }
teardown() { teardown_repo; }

@test "링크된 워크트리와 메인 저장소가 같은 quiz-gate 를 가리킨다" {
  main_qdir="$(cd "$TEST_REPO" && qdir)"
  main_real="$(mkdir -p "$main_qdir" && cd "$main_qdir" && pwd -P)"

  wt="$(add_worktree br1)"
  wt_qdir="$(cd "$wt" && qdir)"
  wt_real="$(mkdir -p "$wt_qdir" && cd "$wt_qdir" && pwd -P)"

  [ "$main_real" = "$wt_real" ]
}

@test "워크트리에서 훅이 남긴 pending 을 메인 저장소에서 읽는다" {
  install_hook
  wt="$(add_worktree br2)"

  cd "$wt"
  printf 'W1\n' > w.ts
  git add w.ts
  stamp
  run git commit -qm "from worktree"
  [ "$status" -ne 0 ]

  # 훅이 발표한 답을 메인 저장소 쪽에서 읽을 수 있어야 한다
  cd "$TEST_REPO"
  [ -s "$(qdir)/pending" ]
  run cat "$(qdir)/pending"
  [[ "$output" == *"w.ts"* ]]
}
```

- [ ] **Step 3: 실패를 확인한다**

```bash
bats tests/worktree.bats
```

Expected: 두 테스트 모두 FAIL. 첫째는 경로가 달라서, 둘째는 메인 쪽 `pending` 이 비어 있어서.

- [ ] **Step 4: `qdir` 헬퍼를 바꾼다**

`tests/helper.bash:37` 의 한 줄을 교체한다.

```bash
qdir() { echo "$(git rev-parse --git-common-dir)/quiz-gate"; }
```

`hooksdir()` 는 바꾸지 않는다 — `--git-path hooks` 는 이미 공유 디렉터리로 풀린다(실측).

- [ ] **Step 5: `hooks/pre-commit` 을 바꾼다**

12번째 줄을 교체한다.

```sh
QDIR="$(git rev-parse --git-common-dir)/quiz-gate"
```

`CHAINED` 줄(13번째)은 그대로 둔다 — `--git-path hooks` 는 이미 공유다.

- [ ] **Step 6: `scripts/pending.sh` 를 바꾼다**

34-35번째 줄을 교체한다.

```bash
git_common_dir="$(git rev-parse --git-common-dir 2>/dev/null)" || die "git 저장소가 아닙니다"
pending_file="$git_common_dir/quiz-gate/pending"
```

- [ ] **Step 7: `scripts/record-pass.sh` 를 바꾼다**

50-51번째 줄을 교체한다.

```bash
git_common_dir="$(git rev-parse --git-common-dir 2>/dev/null)" || die "git 저장소가 아닙니다"
qdir="$git_common_dir/quiz-gate"
```

- [ ] **Step 8: `scripts/stamp-agent.sh` 를 바꾼다**

58번째 줄을 교체한다.

```bash
qdir="$(git rev-parse --git-common-dir)/quiz-gate"
```

- [ ] **Step 9: 전체 테스트를 돌린다**

```bash
bats tests/
```

Expected: PASS. 기존 테스트는 모두 `qdir()` 헬퍼를 거치므로 그대로 통과해야 한다. 하나라도 붉으면 그 파일이 `.git/quiz-gate` 를 문자열로 박아 쓴 곳이 있다는 뜻이다 — `grep -rn 'quiz-gate' tests/ scripts/ hooks/` 로 찾아 헬퍼를 쓰게 고친다.

- [ ] **Step 10: 린트한다**

```bash
shellcheck -s sh hooks/pre-commit && shellcheck scripts/*.sh tests/helper.bash
```

Expected: 출력 없음.

- [ ] **Step 11: 커밋한다**

```bash
git add hooks/pre-commit scripts/pending.sh scripts/record-pass.sh scripts/stamp-agent.sh tests/helper.bash tests/worktree.bats
git commit -m "refactor: put quiz-gate state in the shared git dir

--git-path quiz-gate resolves per-worktree, so a worktree-isolated
subagent's commits were invisible to the main session's hooks."
```

---

### Task 2: 마커를 `agent_id` 별 파일로 쪼갠다

단일 마커 파일은 병렬에서 덮어써진다 — 실측한 스탬프 간격이 0.14초다. 그리고 현행 마커 내용(`claude-code/<session_id>`)에는 귀속 정보가 전혀 없다: 실측 결과 `session_id` 가 메인과 모든 서브에이전트에서 동일했다.

**Files:**
- Modify: `scripts/stamp-agent.sh:60-66`
- Modify: `hooks/pre-commit:76-101`
- Modify: `tests/helper.bash` (`stamp` 헬퍼)
- Test: `tests/stamp-agent.bats` (확장), `tests/pre-commit.bats` (확장)

**Interfaces:**
- Consumes: Task 1 의 `qdir()`
- Produces:
  - 마커 파일 경로: `$QDIR/marker/main` (메인 스레드) 또는 `$QDIR/marker/<sanitized agent_id>` (서브에이전트)
  - 마커 내용: 한 줄, 탭 세 개로 구분된 네 필드 — `<agent>\t<agent_id>\t<agent_type>\t<session_id>`. 메인 스레드는 `agent_id` 와 `agent_type` 이 빈 문자열이다
  - 파일명 정규화: `agent_id` 에서 `[A-Za-z0-9_-]` 이외의 문자를 `_` 로 바꾸고 앞 64자로 자른다
  - 테스트 헬퍼 `stamp [agent] [agent_id] [agent_type]` — 인자 없이 부르면 메인 스레드 마커를 남긴다

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`tests/stamp-agent.bats` 의 `stamp_run` 을 아래로 교체하고, 그 뒤에 테스트 넷을 추가한다.

```bash
stamp_run() {  # $1 = agent, $2 = command, $3 = agent_id, $4 = agent_type
  jq -n --arg c "${2:-git commit -m x}" --arg cwd "$PWD" --arg s "sess-abc" \
        --arg aid "${3:-}" --arg at "${4:-}" \
    '{tool_name:"Bash", cwd:$cwd, session_id:$s, tool_input:{command:$c}}
     + (if $aid == "" then {} else {agent_id:$aid, agent_type:$at} end)' \
  | bash "$PLUGIN_ROOT/scripts/stamp-agent.sh" --agent "${1:-claude-code}"
}

@test "agent_id 가 없으면 marker/main 에 쓴다" {
  stamp_run claude-code 'git commit -m x'
  [ -f "$(qdir)/marker/main" ]
}

@test "agent_id 가 있으면 그 이름의 마커 파일에 쓴다" {
  stamp_run claude-code 'git commit -m x' a3afdf6e2d861a6a9 general-purpose
  [ -f "$(qdir)/marker/a3afdf6e2d861a6a9" ]
  [ ! -f "$(qdir)/marker/main" ]
}

@test "마커에 agent_id 와 agent_type 이 들어간다" {
  stamp_run claude-code 'git commit -m x' a3afdf6e2d861a6a9 general-purpose
  run cat "$(qdir)/marker/a3afdf6e2d861a6a9"
  [[ "$output" == *"a3afdf6e2d861a6a9"* ]]
  [[ "$output" == *"general-purpose"* ]]
}

@test "병렬 두 에이전트의 마커가 서로를 덮지 않는다" {
  stamp_run claude-code 'git commit -m x' aaa11 general-purpose
  stamp_run claude-code 'git commit -m x' bbb22 code-reviewer
  [ -f "$(qdir)/marker/aaa11" ]
  [ -f "$(qdir)/marker/bbb22" ]
}

@test "agent_id 의 경로 문자를 정규화한다" {
  stamp_run claude-code 'git commit -m x' '../../etc/passwd' general-purpose
  [ ! -e "$(qdir)/marker/../../etc/passwd" ]
  [ "$(find "$(qdir)/marker" -type f | wc -l | tr -d ' ')" = "1" ]
}
```

기존 테스트 중 `agent-session` 을 직접 보는 것들(`"마커 파일을 만든다"`, `"마커에 에이전트 이름과 세션 ID 가 들어간다"`, `"codex 로도 동작한다"`, `"재호출하면 마커가 갱신된다"`)은 경로를 `"$(qdir)/marker/main"` 으로 바꾼다.

- [ ] **Step 2: 실패를 확인한다**

```bash
bats tests/stamp-agent.bats
```

Expected: 새 테스트 다섯 개가 FAIL — `marker/` 디렉터리가 없다.

- [ ] **Step 3: `stamp-agent.sh` 를 구현한다**

`scripts/stamp-agent.sh` 의 60-66번째 줄(`session="unknown"` 부터 `printf ... agent-session` 까지)을 교체한다.

```bash
session="unknown"
agent_id=""
agent_type=""
if command -v jq >/dev/null 2>&1; then
  session="$(jq -r '.session_id // "unknown"' <<<"$payload" 2>/dev/null || echo unknown)"
  agent_id="$(jq -r '.agent_id // ""' <<<"$payload" 2>/dev/null || echo "")"
  agent_type="$(jq -r '.agent_type // ""' <<<"$payload" 2>/dev/null || echo "")"
fi

# 마커 파일명은 agent_id 다. 페이로드에서 온 문자열이므로 경로로 쓰기 전에
# 정규화한다 — `../` 가 들어오면 quiz-gate 밖에 파일을 쓰게 된다.
# agent_id 가 없으면(메인 스레드) 이름은 main 이다.
marker_name="main"
if [ -n "$agent_id" ]; then
  marker_name="$(printf '%s' "$agent_id" | tr -c 'A-Za-z0-9_-' '_' | cut -c1-64)"
  [ -n "$marker_name" ] || marker_name="unknown-agent"
fi

mkdir -p "$qdir/marker" 2>/dev/null || exit 0
printf '%s\t%s\t%s\t%s\n' "$AGENT" "$agent_id" "$agent_type" "$session" \
  > "$qdir/marker/$marker_name" 2>/dev/null || exit 0
```

- [ ] **Step 4: 테스트가 통과하는지 확인한다**

```bash
bats tests/stamp-agent.bats
```

Expected: PASS.

- [ ] **Step 5: `stamp` 헬퍼를 새 형식으로 바꾼다**

`tests/helper.bash` 의 `stamp()` 를 교체한다.

```bash
# 핸드셰이크 마커를 신선하게 남긴다.
# 인자 없이 부르면 메인 스레드 마커, agent_id 를 주면 서브에이전트 마커다.
stamp() {  # $1 = agent, $2 = agent_id, $3 = agent_type
  local name="main"
  [ -n "${2:-}" ] && name="$2"
  mkdir -p "$(qdir)/marker"
  printf '%s\t%s\t%s\t%s\n' \
    "${1:-test-agent}" "${2:-}" "${3:-}" "sess-1" > "$(qdir)/marker/$name"
}
```

- [ ] **Step 6: `hooks/pre-commit` 이 새 마커를 읽게 한다**

`hooks/pre-commit` 의 78-91번째 줄(`# 1차: 핸드셰이크.` 부터 신선도 검사 `fi` 까지)을 교체한다. 이 단계에서는 아직 분기하지 않는다 — 판별만 새 형식으로 옮긴다.

```sh
# 1차: 핸드셰이크. 변수 이름에 의존하지 않아 버전 변경에 강하다. (D34)
#
# 마커는 agent_id 별 파일이다. 단일 파일이던 시절에는 병렬 서브에이전트가
# 서로를 덮어썼다 — 실측한 스탬프 간격이 0.14초다.
#
# `agent_id` 를 가진 신선한 마커가 하나라도 있으면 그것을 고른다. 왜
# "하나라도"인지는 다음 태스크의 분기 규칙과 함께 봐야 한다: 오판을
# "막지 않는" 쪽으로만 흐르게 하기 위해서다.
now=$(date +%s)
marker_agent_id=""
marker_agent_type=""
for marker in "$QDIR/marker"/*; do
  [ -f "$marker" ] || continue
  # GNU 는 -f 를 --file-system 으로 해석해 종료코드 0으로 헛값을 낸다. GNU
  # 형식을 먼저 시도해야 그 헛값이 아니라 진짜 실패로 폴백을 탄다.
  mtime=$(stat -c %Y "$marker" 2>/dev/null || stat -f %m "$marker" 2>/dev/null || echo 0)
  case "$mtime" in '' | *[!0-9]*) mtime=0 ;; esac
  age=$((now - mtime))
  # 미래 시각(시계 오차·NFS)이면 age 가 음수다 — 그것도 "신선함"이 아니다.
  [ "$age" -ge 0 ] && [ "$age" -le "$FRESH_SECS" ] || continue

  line="$(head -n 1 "$marker" 2>/dev/null)"
  this_agent="$(printf '%s' "$line" | cut -f1)"
  this_id="$(printf '%s' "$line" | cut -f2)"
  this_type="$(printf '%s' "$line" | cut -f3)"

  [ -n "$agent_signal" ] || agent_signal="handshake:$this_agent"
  if [ -n "$this_id" ] && [ -z "$marker_agent_id" ]; then
    marker_agent_id="$this_id"
    marker_agent_type="$this_type"
    agent_signal="handshake:$this_agent/$this_id"
  fi
done
```

- [ ] **Step 7: 전체 테스트를 돌린다**

```bash
bats tests/
```

Expected: PASS. `tests/pre-commit.bats` 는 `stamp` 헬퍼를 거치므로 그대로 통과한다.

- [ ] **Step 8: 린트한다**

```bash
shellcheck -s sh hooks/pre-commit && shellcheck scripts/*.sh tests/helper.bash
```

Expected: 출력 없음.

- [ ] **Step 9: 커밋한다**

```bash
git add scripts/stamp-agent.sh hooks/pre-commit tests/helper.bash tests/stamp-agent.bats
git commit -m "feat: key the handshake marker by agent_id

A single marker file is overwritten by parallel subagents (measured
0.14s apart), and session_id turned out to be identical across the
main thread and every subagent, so it carried no attribution at all."
```

---

### Task 3: `pass_id` 충돌을 막는다

`pass_id="p-$(date -u +%Y%m%d-%H%M%S)"` 는 초 해상도다. 같은 초에 두 건이 통과하면 `mv` 가 앞 건의 `passes/<id>.json` 을 덮고, `covered.tsv` 는 남의 문답을 가리킨다. 감사 기록이 조용히 사라진다.

**Files:**
- Modify: `scripts/record-pass.sh:62`
- Test: `tests/record-pass.bats` (확장)

**Interfaces:**
- Consumes: Task 1 의 `qdir`
- Produces: `pass_id` 형식이 `p-<YYYYmmdd-HHMMSS>-<pid>` 가 된다. `covered.tsv` 3번째 열과 `passes/<pass_id>.json` 파일명이 그 값을 쓴다

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`tests/record-pass.bats` 끝에 추가한다.

```bash
@test "같은 초에 두 건이 통과해도 감사 기록이 덮이지 않는다" {
  printf 'C1\n' > c.ts; git add c.ts
  id1="$(record_pass)"
  [ -n "$id1" ]

  printf 'D1\n' > d.ts; git add d.ts
  id2="$(record_pass)"
  [ -n "$id2" ]

  [ "$id1" != "$id2" ]
  [ -f "$(qdir)/passes/$id1.json" ]
  [ -f "$(qdir)/passes/$id2.json" ]
  [ "$(find "$(qdir)/passes" -name '*.json' | wc -l | tr -d ' ')" = "2" ]
}

@test "pass_id 에 프로세스 식별자가 붙는다" {
  printf 'C1\n' > c.ts; git add c.ts
  run record_pass
  [ "$status" -eq 0 ]
  # p-<8자리>-<6자리>-<pid>
  [[ "$output" =~ ^p-[0-9]{8}-[0-9]{6}-[0-9]+$ ]]
}
```

- [ ] **Step 2: 실패를 확인한다**

```bash
bats tests/record-pass.bats
```

Expected: `"pass_id 에 프로세스 식별자가 붙는다"` FAIL (형식 불일치). 앞 테스트는 두 호출이 다른 초에 걸리면 우연히 통과할 수 있다 — 형식 테스트가 진짜 게이트다.

- [ ] **Step 3: 구현한다**

`scripts/record-pass.sh:62` 를 교체한다.

```bash
# 초 해상도만으로는 같은 초에 통과한 두 건이 같은 pass_id 를 받아, mv 가
# 앞 건의 감사 기록을 덮는다. covered.tsv 는 그대로 그 id 를 가리키므로
# 남의 문답을 가리키는 라인이 남는다. 병렬 서브에이전트에서 실제로 일어난다.
pass_id="p-$(date -u +%Y%m%d-%H%M%S)-$$"
```

- [ ] **Step 4: 테스트가 통과하는지 확인한다**

```bash
bats tests/record-pass.bats
```

Expected: PASS.

- [ ] **Step 5: 커밋한다**

```bash
git add scripts/record-pass.sh tests/record-pass.bats
git commit -m "fix: stop pass_id from colliding within the same second

Two passes in one second shared an id, so mv silently overwrote the
first one's audit record while covered.tsv kept pointing at it."
```

---

### Task 4: 원장과 `pending.sh` 의 세 모드

원장은 훅이 발표하는 답이다 (D40). 판정 규칙은 `pending.sh` 한 곳에만 둔다 (D45).

**Files:**
- Modify: `scripts/pending.sh` (모드 인자 추가)
- Modify: `scripts/record-pass.sh:58` (인자 전달)
- Modify: `docs/superpowers/specs/2026-07-30-parallel-gate-design.md:114` (스키마에서 `commit_sha` 제거)
- Test: `tests/ledger.bats` (신규), `tests/pending.bats` (확장)

**Interfaces:**
- Consumes: Task 1 의 `qdir`
- Produces:
  - `$QDIR/ledger.tsv` 한 줄 = `<blob_sha>\t<path>\t<agent_id>\t<agent_type>\t<at>`. `at` 은 `date -u +%Y-%m-%dT%H:%M:%SZ`
  - `pending.sh` (인자 없음) → 현행 그대로
  - `pending.sh --bundle <agent_id>` → 그 `agent_id` 의 미검증 `<blob_sha>\t<path>`
  - `pending.sh --all-unverified` → 원장 전체의 미검증 `<blob_sha>\t<path>`
  - 세 모드 모두 종료 0 = 목록 출력, 1 = 대상 없음 또는 해석 불가
  - `record-pass.sh` 가 같은 인자를 그대로 받아 `pending.sh` 에 넘긴다

- [ ] **Step 1: 스펙의 스키마를 고친다**

`docs/superpowers/specs/2026-07-30-parallel-gate-design.md` 에서 이 줄을 찾는다.

```
  ledger.tsv        blob_sha  path  agent_id  agent_type  commit_sha  at
```

이렇게 바꾼다.

```
  ledger.tsv        blob_sha  path  agent_id  agent_type  at
```

같은 절에 한 문단을 덧붙인다.

```markdown
`commit_sha` 는 담지 않는다. `pre-commit` 은 커밋이 만들어지기 **전**에 도므로 그 값을 모른다. 필요도 없다 — `pre-push` 는 push 범위의 `git diff --raw` 를 `covered.tsv` 와 직접 대조하고, 원장은 번들 묶기와 `Stop` 판정에만 쓰인다.
```

- [ ] **Step 2: 원장 스텁 헬퍼를 추가한다**

세 개의 bats 파일(`ledger`·`stop-hook`·`bundle`)이 이것을 쓴다. bats 파일은 서로를 읽지 않고 `load helper` 만 공유하므로, 정의는 헬퍼 한 곳에만 둔다 — 세 벌이 되면 원장 스키마가 바뀔 때 반드시 한쪽이 낡는다.

`tests/helper.bash` 의 `stub_covered_line` 바로 뒤에 넣는다.

```bash
# ⚠ 이것은 hooks/pre-commit 이 아니다. 훅 없이 pending.sh 만 보는 테스트용으로
# 원장에 한 줄을 손으로 박아 넣는 스텁이며, SHA 를 **워크트리 파일**에서
# 계산한다. stub_covered_line 과 같은 주의가 그대로 적용된다 — 훅이 실제로
# 그런 줄을 만들어내는가를 주장하려면 진짜 훅을 태워야 한다
# (tests/pre-commit.bats 의 "서브에이전트 마커면 막지 않고 원장에 적는다").
stub_ledger_line() {  # $1 = 경로, $2 = agent_id, $3 = agent_type
  mkdir -p "$(qdir)"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$(git hash-object -- "$1")" "$1" "$2" "${3:-general-purpose}" \
    "2026-07-30T00:00:00Z" >> "$(qdir)/ledger.tsv"
}
```

- [ ] **Step 3: 실패하는 테스트를 쓴다**

`tests/ledger.bats` 를 새로 만든다.

```bash
#!/usr/bin/env bats
#
# 원장은 훅이 발표한 답이다 (D40). 판정은 pending.sh 한 곳에만 있다 (D45).

load helper

setup() { setup_repo; seed_repo; }
teardown() { teardown_repo; }

pending_sh() { bash "$PLUGIN_ROOT/scripts/pending.sh" "$@"; }

@test "--bundle 은 그 agent_id 의 항목만 낸다" {
  printf 'C1\n' > c.ts; printf 'D1\n' > d.ts
  stub_ledger_line c.ts aaa11
  stub_ledger_line d.ts bbb22
  run pending_sh --bundle aaa11
  [ "$status" -eq 0 ]
  [ "$output" = "$(git hash-object c.ts)"$'\t'"c.ts" ]
}

@test "--bundle 은 이미 검증된 항목을 빼고 낸다" {
  printf 'C1\n' > c.ts
  stub_ledger_line c.ts aaa11
  stub_covered_line c.ts
  run pending_sh --bundle aaa11
  [ "$status" -eq 1 ]
  [[ "$output" == *"검증할 것이 없습니다"* ]]
}

@test "--all-unverified 는 모든 에이전트의 미검증을 낸다" {
  printf 'C1\n' > c.ts; printf 'D1\n' > d.ts
  stub_ledger_line c.ts aaa11
  stub_ledger_line d.ts bbb22
  run pending_sh --all-unverified
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" = "2" ]
}

@test "원장이 없으면 --all-unverified 는 거부한다" {
  run pending_sh --all-unverified
  [ "$status" -eq 1 ]
}

@test "원장에 손상된 줄이 있으면 거부한다" {
  mkdir -p "$(qdir)"
  printf 'not-a-sha\tc.ts\taaa11\tgeneral-purpose\t2026-07-30T00:00:00Z\n' \
    > "$(qdir)/ledger.tsv"
  run pending_sh --all-unverified
  [ "$status" -eq 1 ]
  [[ "$output" == *"손상"* ]]
}

@test "세 모드가 같은 출력 형식을 낸다" {
  printf 'C1\n' > c.ts; git add c.ts
  stub_ledger_line c.ts aaa11
  for mode in "" "--bundle aaa11" "--all-unverified"; do
    # shellcheck disable=SC2086  # 모드 인자를 일부러 분리한다
    run pending_sh $mode
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" | awk -F'\t' '
      NF != 2 || length($1) != 40 || $2 == "" { exit 1 }' || return 1
  done
}
```

- [ ] **Step 4: 실패를 확인한다**

```bash
bats tests/ledger.bats
```

Expected: 전부 FAIL — `pending.sh` 가 인자를 모른다.

- [ ] **Step 5: `pending.sh` 를 구현한다**

`scripts/pending.sh` 의 34번째 줄(git dir 계산) 바로 뒤, `# ①` 주석 앞에 아래를 넣는다.

```bash
qdir="$git_common_dir/quiz-gate"
covered="$qdir/covered.tsv"
ledger="$qdir/ledger.tsv"

MODE="current"
BUNDLE_ID=""
while [ $# -gt 0 ]; do
  case "$1" in
    --bundle)         MODE="bundle"; BUNDLE_ID="${2:-}"; shift ;;
    --all-unverified) MODE="all" ;;
    *) die "알 수 없는 인자: $1 (사용법: pending.sh [--bundle <agent_id> | --all-unverified])" ;;
  esac
  shift
done

[ "$MODE" != "bundle" ] || [ -n "$BUNDLE_ID" ] || die "--bundle 에 agent_id 가 필요합니다"

# 원장에서 미검증 (blob_sha, path) 를 뽑는다. covered.tsv 와의 차집합이며,
# 같은 (sha, path) 가 여러 줄에 있어도 한 번만 낸다.
#
# -v 는 값에 이스케이프 처리를 한다 (back\slash.ts 의 \s 가 사라진다).
# agent_id 는 정규화된 문자열이라 안전하지만, 경로는 ENVIRON 을 거치는
# covered 쪽 비교와 철자가 어긋나지 않도록 원문 그대로 다룬다.
ledger_unverified() {  # $1 = agent_id 또는 빈 문자열(전체)
  [ -r "$ledger" ] || return 1
  KK_FILTER="$1" awk -F'\t' '
    FNR == NR { if (NF >= 2) covered[$1 FS $2] = 1; next }
    {
      if (NF != 5) { bad = 1; exit }
      if (length($1) != 40 || $1 ~ /[^0-9a-f]/ || $2 == "") { bad = 1; exit }
      want = ENVIRON["KK_FILTER"]
      if (want != "" && $3 != want) next
      key = $1 FS $2
      if (key in covered) next
      if (key in seen) next
      seen[key] = 1
      print $1 "\t" $2
    }
    END { if (bad) exit 1 }
  ' "${covered:-/dev/null}" "$ledger" 2>/dev/null
}
```

`covered` 가 없을 때 awk 가 죽지 않게, 함수 안에서 먼저 만든다. 위 함수 앞에 한 줄 넣는다.

```bash
[ -e "$covered" ] || : > "$covered" 2>/dev/null || covered=/dev/null
```

그리고 `# ①` 로 시작하는 기존 블록 앞에 모드 분기를 넣는다.

```bash
if [ "$MODE" != "current" ]; then
  filter=""
  [ "$MODE" = "bundle" ] && filter="$BUNDLE_ID"
  if ! out="$(ledger_unverified "$filter")"; then
    die "원장이 손상됐습니다 ($ledger)"
  fi
  [ -n "$out" ] || die "검증할 것이 없습니다 (근거: 원장)"
  printf '%s\n' "$out"
  exit 0
fi
```

- [ ] **Step 6: 테스트가 통과하는지 확인한다**

```bash
bats tests/ledger.bats tests/pending.bats
```

Expected: PASS.

- [ ] **Step 7: `record-pass.sh` 가 인자를 넘기게 한다**

`scripts/record-pass.sh:58` 을 교체한다.

```bash
# 대상 결정은 scripts/pending.sh 하나에만 있다 — 스킬(SKILL.md §1)도 같은
# 스크립트를 같은 인자로 부른다. 규칙을 여기 한 벌 더 두면 반드시 한쪽이
# 낡고, 그러면 사용자가 A 를 풀었는데 B 가 검증된 것으로 기록된다. (D45)
# 사유 메시지는 pending.sh 가 이미 stderr 에 냈으므로 그대로 물려받는다.
pending="$(bash "$SCRIPT_DIR/pending.sh" "$@")" || exit 1
```

- [ ] **Step 8: 왕복 테스트를 추가한다**

`tests/ledger.bats` 끝에 추가한다.

```bash
@test "번들을 통과 기록하면 그 번들이 비워진다 (왕복)" {
  printf 'C1\n' > c.ts; git add c.ts
  stub_ledger_line c.ts aaa11

  printf '%s' '{"questions":[{"axis":"facts","q":"무엇이 바뀌었나?","evidence":"x:1","format":"choice","answer":"A","correct":"A","attempts":1,"gave_up":false}]}' \
    | bash "$PLUGIN_ROOT/scripts/record-pass.sh" --bundle aaa11
  [ "$?" -eq 0 ]

  run bash "$PLUGIN_ROOT/scripts/pending.sh" --bundle aaa11
  [ "$status" -eq 1 ]
}
```

- [ ] **Step 9: 전체 테스트와 린트**

```bash
bats tests/ && shellcheck scripts/*.sh
```

Expected: PASS, 린트 출력 없음.

- [ ] **Step 10: 커밋한다**

```bash
git add scripts/pending.sh scripts/record-pass.sh tests/helper.bash \
        tests/ledger.bats tests/pending.bats \
        docs/superpowers/specs/2026-07-30-parallel-gate-design.md
git commit -m "feat: add the ledger and pending.sh's three modes

Keeping the 'what needs verifying' decision in one place is D45; four
enforcement points now call it instead of each deciding for itself.

Drops commit_sha from the ledger schema in the spec — pre-commit runs
before the commit exists and cannot know it."
```

---

### Task 5: `pre-commit` 분기와 `Stop` 훅

**둘을 하나의 커밋으로 묶는다.** 분기만 먼저 들어가면 서브에이전트 커밋이 아무 그물 없이 통과하는 창이 생긴다.

**Files:**
- Modify: `hooks/pre-commit:173-202`
- Create: `scripts/stop-gate.sh`
- Modify: `hooks/hooks.json` (Stop 항목 추가)
- Test: `tests/pre-commit.bats` (확장), `tests/stop-hook.bats` (신규)

**Interfaces:**
- Consumes: Task 2 의 `marker_agent_id`·`marker_agent_type`, Task 4 의 `ledger.tsv` 스키마와 `pending.sh --all-unverified`
- Produces:
  - `pre-commit` 은 `marker_agent_id` 가 비어 있지 않으면 `ledger.tsv` 에 추가하고 exit 0, 비어 있으면 현행대로 exit 1
  - `scripts/stop-gate.sh` — stdin 으로 Stop 페이로드를 받고, 미검증이 있으면 `{"decision":"block","reason":...}` 를 stdout 에 낸다. 없으면 stdout 이 비고 exit 0. 어느 경우든 exit 0 이다 (판정은 JSON 으로만 말한다)

- [ ] **Step 1: 실패하는 테스트를 쓴다 — `pre-commit` 분기**

`tests/pre-commit.bats` 끝에 추가한다.

```bash
@test "서브에이전트 마커면 막지 않고 원장에 적는다" {
  install_hook
  printf 'C1\n' > c.ts; git add c.ts
  stamp claude-code aaa11 general-purpose
  run git commit -qm "from subagent"
  [ "$status" -eq 0 ]
  [ -s "$(qdir)/ledger.tsv" ]
  run cat "$(qdir)/ledger.tsv"
  [[ "$output" == *"c.ts"* ]]
  [[ "$output" == *"aaa11"* ]]
  [[ "$output" == *"general-purpose"* ]]
}

@test "서브에이전트 경로는 pending 을 쓰지 않는다" {
  install_hook
  printf 'C1\n' > c.ts; git add c.ts
  stamp claude-code aaa11 general-purpose
  git commit -qm "from subagent"
  [ ! -s "$(qdir)/pending" ]
}

@test "메인 스레드 마커면 지금처럼 막는다" {
  install_hook
  printf 'C1\n' > c.ts; git add c.ts
  stamp claude-code
  run git commit -qm "from main"
  [ "$status" -ne 0 ]
  [[ "$output" == *"검증되지 않은 변경"* ]]
  [ ! -e "$(qdir)/ledger.tsv" ]
}

@test "마커가 섞여 있으면 통과 쪽으로 간다 (오판을 안전한 방향으로)" {
  install_hook
  printf 'C1\n' > c.ts; git add c.ts
  stamp claude-code
  stamp claude-code aaa11 general-purpose
  run git commit -qm "mixed markers"
  [ "$status" -eq 0 ]
}

@test "이미 검증된 변경은 원장에 적지 않는다" {
  install_hook
  printf 'C1\n' > c.ts; git add c.ts
  stub_covered_line c.ts
  stamp claude-code aaa11 general-purpose
  run git commit -qm "already covered"
  [ "$status" -eq 0 ]
  [ ! -e "$(qdir)/ledger.tsv" ]
}
```

- [ ] **Step 2: 실패하는 테스트를 쓴다 — `Stop` 훅**

`tests/stop-hook.bats` 를 새로 만든다.

```bash
#!/usr/bin/env bats
#
# Stop 훅은 미검증 번들이 남은 채로 턴이 끝나는 것을 막는다.
# 메인 에이전트만 AskUserQuestion 으로 사람에게 물을 수 있어서, 여기가
# 서브에이전트 커밋을 검증할 수 있는 유일한 마지막 자리다.

load helper

setup() { setup_repo; seed_repo; }
teardown() { teardown_repo; }

stop_run() {  # $1 = stop_hook_active
  jq -n --arg cwd "$PWD" --argjson active "${1:-false}" \
    '{hook_event_name:"Stop", session_id:"sess-1", cwd:$cwd, stop_hook_active:$active}' \
  | bash "$PLUGIN_ROOT/scripts/stop-gate.sh"
}

# stub_ledger_line 은 tests/helper.bash 에 있다 (Task 4 Step 2).

@test "미검증이 없으면 아무것도 쓰지 않는다" {
  run stop_run
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "미검증이 있으면 block 을 낸다" {
  printf 'C1\n' > c.ts
  stub_ledger_line c.ts aaa11
  run stop_run
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.decision')" = "block" ]
}

@test "block 사유에 경로가 들어간다" {
  printf 'C1\n' > c.ts
  stub_ledger_line c.ts aaa11
  run stop_run
  [[ "$(printf '%s' "$output" | jq -r '.reason')" == *"c.ts"* ]]
}

@test "stop_hook_active 가 true 여도 계속 막는다" {
  printf 'C1\n' > c.ts
  stub_ledger_line c.ts aaa11
  run stop_run true
  [ "$(printf '%s' "$output" | jq -r '.decision')" = "block" ]
}

@test "defer 가 있어도 막는다 (유예는 턴 끝까지다)" {
  printf 'C1\n' > c.ts
  stub_ledger_line c.ts aaa11
  mkdir -p "$(qdir)"; : > "$(qdir)/defer"
  run stop_run
  [ "$(printf '%s' "$output" | jq -r '.decision')" = "block" ]
}

@test "통과하면 defer 를 지운다" {
  mkdir -p "$(qdir)"; : > "$(qdir)/defer"
  run stop_run
  [ "$status" -eq 0 ]
  [ ! -e "$(qdir)/defer" ]
}

@test "통과 기록 후에는 막지 않는다 (왕복)" {
  printf 'C1\n' > c.ts; git add c.ts
  stub_ledger_line c.ts aaa11
  printf '%s' '{"questions":[{"axis":"facts","q":"무엇이 바뀌었나?","evidence":"x:1","format":"choice","answer":"A","correct":"A","attempts":1,"gave_up":false}]}' \
    | bash "$PLUGIN_ROOT/scripts/record-pass.sh" --all-unverified
  run stop_run
  [ -z "$output" ]
}

@test "git 저장소가 아니면 조용히 통과한다" {
  cd "$(mktemp -d)"
  run stop_run
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
```

- [ ] **Step 3: 실패를 확인한다**

```bash
bats tests/stop-hook.bats
```

Expected: 전부 FAIL — `scripts/stop-gate.sh` 가 없다.

- [ ] **Step 4: `pre-commit` 분기를 구현한다**

`hooks/pre-commit` 의 173번째 줄(`[ -n "$missing" ] || exit 0`) 부터 파일 끝까지를 교체한다.

```sh
[ -n "$missing" ] || exit 0

# jq 가 없으면 통과시킨다. 이 훅 자체는 jq 를 쓰지 않지만 통과를 기록하는
# record-pass.sh 는 jq 없이 한 줄도 쓰지 못한다 — 여기서 막으면(또는 원장에
# 적어 Stop 이 막으면) 퀴즈를 통과할 방법이 없는 채로 커밋이 영구히 막힌다.
# 이해와 무관한 이유로 커밋을 영구히 막는 것이 이 프로젝트에서 가장 하지
# 말아야 할 일이다. 설치기가 애초에 jq 없는 환경에서 설치를 거부하므로(D42)
# 여긴 마지막 방어선이다.
if ! command -v jq >/dev/null 2>&1; then
  echo "kkochikkochi: 경고 — jq 가 없어 퀴즈를 통과시킬 수 없으므로 이 커밋을 검증 없이 통과시킵니다 (jq 를 설치하세요)" >&2
  exit 0
fi

# ── 5. 서브에이전트 경로 — 막지 않고 원장에 적는다 ────────────────
#
# 서브에이전트는 사람에게 물을 수 없다. 여기서 막으면 통과할 방법이 없다.
# 그래서 적어 두고 통과시키고, PostToolUse(Task)·Stop·pre-push 가 검증을
# 강제한다.
#
# 마커가 섞여 있을 때 이 분기를 타는 이유(오판을 "막지 않는" 쪽으로만
# 흐르게 한다)는 설계 문서 §4 에 있다. 반대 방향으로 틀리면 서브에이전트가
# 갇히고, 이 방향으로 틀리면 검증 시점만 뒤로 밀린다.
if [ -n "$marker_agent_id" ]; then
  at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if ! { mkdir -p "$QDIR" 2>/dev/null && while IFS='	' read -r sha path; do
      [ -n "$sha" ] || continue
      printf '%s\t%s\t%s\t%s\t%s\n' \
        "$sha" "$path" "$marker_agent_id" "$marker_agent_type" "$at"
    done <<LEDGER >> "$QDIR/ledger.tsv"
$missing_pairs
LEDGER
  }; then
    echo "kkochikkochi: 경고 — $QDIR/ledger.tsv 를 쓸 수 없어 이 커밋은 검증 없이 통과합니다" >&2
  fi
  exit 0
fi

# ── 6. 메인 스레드 경로 — 지금처럼 막는다 ─────────────────────────
# 훅이 계산한 답을 파일로 남긴다. 실패해도 커밋 차단 자체는 그대로 진행하지만,
# **조용히 넘어가지는 않는다** — 이 파일이 없으면 스킬과 record-pass.sh 가
# git diff --cached 로 폴백하고, `-a` 나 `-- <path>` 커밋에서는 그 계산이 훅과
# 다른 답을 내어 C1(영구 교착)이 그대로 되살아난다. 조용히 되살아나는 것보다
# 한 줄 경고를 보는 편이 낫다.
if ! { mkdir -p "$QDIR" 2>/dev/null && printf '%s' "$missing_pairs" > "$QDIR/pending" 2>/dev/null; }; then
  echo "kkochikkochi: 경고 — $QDIR/pending 을 쓸 수 없습니다. 스킬이 검증 대상을 다시 계산하게 되며, -a 나 -- <path> 커밋에서는 그 값이 이 커밋의 내용과 다를 수 있습니다" >&2
fi

cat >&2 <<MSG
🦡 KkochiKkochi — 이 커밋에 아직 검증되지 않은 변경이 있습니다.

$missing
이 변경을 이해했는지 먼저 확인해야 합니다.
kkochikkochi 스킬을 실행해 퀴즈를 통과한 뒤 다시 커밋하세요.
(판별 신호: $agent_signal)
MSG
exit 1
```

`<<LEDGER` 히어독의 `IFS='	'` 안에 든 문자는 **탭 리터럴**이다. 공백으로 바꾸면 경로에 공백이 든 파일이 깨진다.

- [ ] **Step 5: `stop-gate.sh` 를 구현한다**

`scripts/stop-gate.sh` 를 새로 만든다.

```bash
#!/usr/bin/env bash
# Stop 훅 — 미검증 번들이 남은 채로 턴이 끝나는 것을 막는다.
#
# 사용법: <hook json> | stop-gate.sh
# 출력:   미검증 있음 → {"decision":"block","reason":...} / 없음 → 아무것도
# 종료:   항상 0. 판정은 stdout 의 JSON 으로만 말한다.
#
# 왜 여기인가: 서브에이전트는 사람에게 물을 수 없다(AskUserQuestion 은 메인
# 에이전트만 쓴다). PostToolUse(Task) 가 이미 검증을 요구했더라도 에이전트가
# 그것을 건너뛸 수 있으므로, 턴 종료 지점이 마지막 그물이다.
#
# 왜 command 훅인가: prompt 타입(LLM 판정)도 지원되지만, 이 프로젝트가 내내
# 싸워온 실패 모드가 "게이트가 조용히 꺼지는 것"이다. 판정을 LLM 에 맡기면
# 그 실패 모드를 설계에 초대한다.
#
# stop_hook_active 가 true 여도 계속 막는다. 미검증이 남은 한 막는 것이 이
# 게이트의 존재 이유이고, 원장이 비면 자연히 통과하므로 종료 조건은 있다.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

payload="$(cat)"

# jq 가 없으면 판정 JSON 을 만들 수 없다. 애매하면 통과시킨다 (D35, D42).
command -v jq >/dev/null 2>&1 || exit 0

cwd="$(jq -r '.cwd // ""' <<<"$payload" 2>/dev/null || echo "")"
[ -n "$cwd" ] && cd "$cwd" 2>/dev/null

git rev-parse --git-common-dir >/dev/null 2>&1 || exit 0

qdir="$(git rev-parse --git-common-dir)/quiz-gate"

# 판정은 pending.sh 한 곳에만 있다 (D45). 여기서 원장을 직접 읽지 않는다.
if ! unverified="$(bash "$SCRIPT_DIR/pending.sh" --all-unverified 2>/dev/null)"; then
  # 미검증이 없다(또는 원장이 없다). 유예는 턴 끝까지이므로 여기서 해제한다.
  rm -f "$qdir/defer" 2>/dev/null || :
  exit 0
fi

paths="$(printf '%s\n' "$unverified" | cut -f2 | sort -u | sed 's/^/   /')"

jq -n --arg p "$paths" '{
  decision: "block",
  reason: ("🦡 KkochiKkochi — 서브에이전트가 만든 커밋 중 아직 검증되지 않은 변경이 있습니다.\n\n"
           + $p
           + "\n\nkkochikkochi 스킬을 실행해 퀴즈를 통과한 뒤 마치세요.\n"
           + "대상 목록은 `pending.sh --all-unverified` 가 냅니다.")
}'
exit 0
```

- [ ] **Step 6: 매니페스트에 Stop 을 등록한다**

`hooks/hooks.json` 을 교체한다.

```json
{
  "description": "KkochiKkochi — records an agent handshake so the git pre-commit gate knows this commit came from an agent, and blocks the turn from ending while subagent commits remain unverified.",
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
    ],
    "Stop": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/stop-gate.sh\"",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 7: 테스트가 통과하는지 확인한다**

```bash
bats tests/pre-commit.bats tests/stop-hook.bats
```

Expected: PASS.

- [ ] **Step 8: 전체 테스트와 린트**

```bash
bats tests/ && shellcheck -s sh hooks/pre-commit && shellcheck scripts/*.sh && jq . hooks/hooks.json > /dev/null
```

Expected: PASS, 린트 출력 없음.

- [ ] **Step 9: 커밋한다**

```bash
git add hooks/pre-commit scripts/stop-gate.sh hooks/hooks.json \
        tests/pre-commit.bats tests/stop-hook.bats
git commit -m "feat: let subagent commits through and block the turn instead

Subagents cannot reach the user, so blocking them at pre-commit left
them with no way to pass. They now record to the ledger and the Stop
hook refuses to let the turn end while anything is unverified.

Ships as one commit on purpose: the branch alone would leave a window
where subagent commits pass with no net behind them."
```

---

### Task 6: `PostToolUse(Task)` 와 번들 봉인

**Files:**
- Create: `scripts/seal-bundle.sh`
- Create: `scripts/bundle-notify.sh`
- Modify: `hooks/hooks.json` (`SubagentStart`·`SubagentStop`·`PostToolUse` 추가)
- Modify: `docs/superpowers/specs/2026-07-30-parallel-gate-design.md` (§3 표의 `PostToolUse` 행)
- Test: `tests/bundle.bats` (신규), `tests/manifests.bats` (확장)

**Interfaces:**
- Consumes: Task 4 의 `pending.sh --bundle`, Task 2 의 마커 형식
- Produces:
  - `$QDIR/agents/<sanitized agent_id>` 한 줄 = `<agent_type>\t<started_at>\t<sealed_at>`. 아직 안 끝났으면 `sealed_at` 이 빈 문자열
  - `scripts/seal-bundle.sh --event start|stop` — stdin 으로 `SubagentStart`/`SubagentStop` 페이로드를 받아 위 파일을 쓴다. stdout 은 항상 비어 있다
  - `scripts/bundle-notify.sh` — stdin 으로 `PostToolUse` 페이로드를 받아, 봉인됐고 미검증이 남은 번들이 있으면 `{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":...}}` 를 낸다. 없으면 비어 있다

- [ ] **Step 1: 스펙의 `PostToolUse` 설명을 고친다**

`docs/superpowers/specs/2026-07-30-parallel-gate-design.md` 의 §3 아래 문단을 찾는다.

```
밀어 넣는 방법은 `hookSpecificOutput.additionalContext` 다. 훅이 "이 번들에 미검증 변경이 있다, kkochikkochi 스킬을 실행해 검증하라"와 `agent_id` 를 넘긴다.
```

이렇게 바꾼다.

```markdown
밀어 넣는 방법은 `hookSpecificOutput.additionalContext` 다. **`PostToolUse(Task)` 페이로드에는 `agent_id` 가 없다** — SDK 정의가 "Present only when the hook fires from inside a Task-spawned sub-agent; absent on the main thread" 라고 못 박고 있고, 이 훅은 부모 문맥에서 돈다. 그래서 `SubagentStop` 이 `agents/<agent_id>` 에 봉인 표시를 남기고, `PostToolUse` 는 그 표시를 디스크에서 읽어 어느 번들을 검증해야 하는지 안다.

`SubagentStop` 이 `PostToolUse(Task)` 보다 먼저 도는 것에 기대지만, 그것이 어긋나도 안전하다 — 봉인된 번들이 하나도 없으면 `PostToolUse` 는 원장 전체의 미검증으로 물러나 요구한다.
```

- [ ] **Step 2: 실패하는 테스트를 쓴다**

`tests/bundle.bats` 를 새로 만든다.

```bash
#!/usr/bin/env bats
#
# 번들 = 한 서브에이전트가 만든 커밋들. SubagentStop 이 봉인하고
# PostToolUse(Task) 가 부모에게 검증을 요구한다.
#
# PostToolUse(Task) 는 부모 문맥에서 돌아 agent_id 를 받지 못한다. 그래서
# 어느 번들인지는 페이로드가 아니라 디스크(agents/)에서 읽는다.

load helper

setup() { setup_repo; seed_repo; }
teardown() { teardown_repo; }

seal_run() {  # $1 = start|stop, $2 = agent_id, $3 = agent_type
  jq -n --arg cwd "$PWD" --arg aid "$2" --arg at "${3:-general-purpose}" \
        --arg ev "$([ "$1" = start ] && echo SubagentStart || echo SubagentStop)" \
    '{hook_event_name:$ev, session_id:"sess-1", cwd:$cwd,
      agent_id:$aid, agent_type:$at}' \
  | bash "$PLUGIN_ROOT/scripts/seal-bundle.sh" --event "$1"
}

notify_run() {
  jq -n --arg cwd "$PWD" \
    '{hook_event_name:"PostToolUse", session_id:"sess-1", cwd:$cwd,
      tool_name:"Task", tool_input:{}, tool_result:{}}' \
  | bash "$PLUGIN_ROOT/scripts/bundle-notify.sh"
}

# stub_ledger_line 은 tests/helper.bash 에 있다 (Task 4 Step 2).

@test "SubagentStart 가 번들 파일을 만든다" {
  seal_run start aaa11 general-purpose
  [ -f "$(qdir)/agents/aaa11" ]
}

@test "SubagentStop 이 봉인 시각을 채운다" {
  seal_run start aaa11 general-purpose
  seal_run stop aaa11 general-purpose
  run cut -f3 "$(qdir)/agents/aaa11"
  [ -n "$output" ]
}

@test "SubagentStart 없이 SubagentStop 만 와도 봉인한다" {
  seal_run stop aaa11 general-purpose
  [ -f "$(qdir)/agents/aaa11" ]
  run cut -f3 "$(qdir)/agents/aaa11"
  [ -n "$output" ]
}

@test "seal-bundle 은 stdout 에 아무것도 쓰지 않는다" {
  run seal_run start aaa11 general-purpose
  [ -z "$output" ]
}

@test "봉인된 번들에 미검증이 있으면 검증을 요구한다" {
  printf 'C1\n' > c.ts
  stub_ledger_line c.ts aaa11
  seal_run stop aaa11 general-purpose
  run notify_run
  [ "$status" -eq 0 ]
  ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  [[ "$ctx" == *"aaa11"* ]]
  [[ "$ctx" == *"general-purpose"* ]]
}

@test "아직 봉인되지 않은 번들은 요구하지 않는다" {
  printf 'C1\n' > c.ts
  stub_ledger_line c.ts aaa11
  seal_run start aaa11 general-purpose
  run notify_run
  [ -z "$output" ]
}

@test "미검증이 없으면 아무것도 쓰지 않는다" {
  seal_run stop aaa11 general-purpose
  run notify_run
  [ -z "$output" ]
}

@test "defer 가 켜져 있으면 아무것도 쓰지 않는다" {
  printf 'C1\n' > c.ts
  stub_ledger_line c.ts aaa11
  seal_run stop aaa11 general-purpose
  mkdir -p "$(qdir)"; : > "$(qdir)/defer"
  run notify_run
  [ -z "$output" ]
}

@test "봉인 기록이 없어도 원장에 미검증이 있으면 요구한다 (순서 폴백)" {
  printf 'C1\n' > c.ts
  stub_ledger_line c.ts aaa11
  run notify_run
  ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  [[ "$ctx" == *"c.ts"* ]]
}

@test "번들 둘이 봉인되면 둘 다 요구에 들어간다" {
  printf 'C1\n' > c.ts; printf 'D1\n' > d.ts
  stub_ledger_line c.ts aaa11
  stub_ledger_line d.ts bbb22
  seal_run stop aaa11 general-purpose
  seal_run stop bbb22 code-reviewer
  run notify_run
  ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  [[ "$ctx" == *"aaa11"* ]]
  [[ "$ctx" == *"bbb22"* ]]
}
```

- [ ] **Step 3: 실패를 확인한다**

```bash
bats tests/bundle.bats
```

Expected: 전부 FAIL — 두 스크립트가 없다.

- [ ] **Step 4: `seal-bundle.sh` 를 구현한다**

`scripts/seal-bundle.sh` 를 새로 만든다.

```bash
#!/usr/bin/env bash
# SubagentStart / SubagentStop — 번들을 열고 봉인한다.
#
# 사용법: <hook json> | seal-bundle.sh --event start|stop
# 출력:   없음. stdout 은 훅의 판정 채널이고 이 스크립트는 판정하지 않는다.
#
# 왜 필요한가: PostToolUse(Task) 는 부모 문맥에서 돌아 agent_id 를 받지 못한다
# (SDK: "Present only when the hook fires from inside a Task-spawned
# sub-agent"). 어느 번들이 끝났는지는 여기서만 알 수 있으므로 디스크에 남긴다.
#
# 여기서 퀴즈를 내지 않는 이유: SubagentStop 은 서브에이전트 문맥에서 돌고,
# 거기서 block 을 내면 그 서브에이전트가 계속 일하게 된다. 사람에게 묻는
# 채널이 없으므로 검증은 불가능하고, 경계를 정하는 데만 쓸 수 있다.

set -uo pipefail

EVENT="stop"
while [ $# -gt 0 ]; do
  case "$1" in
    --event) EVENT="${2:-stop}"; shift ;;
  esac
  shift
done

payload="$(cat)"

command -v jq >/dev/null 2>&1 || exit 0

cwd="$(jq -r '.cwd // ""' <<<"$payload" 2>/dev/null || echo "")"
[ -n "$cwd" ] && cd "$cwd" 2>/dev/null

git rev-parse --git-common-dir >/dev/null 2>&1 || exit 0
qdir="$(git rev-parse --git-common-dir)/quiz-gate"

agent_id="$(jq -r '.agent_id // ""' <<<"$payload" 2>/dev/null || echo "")"
agent_type="$(jq -r '.agent_type // ""' <<<"$payload" 2>/dev/null || echo "")"
[ -n "$agent_id" ] || exit 0

# 마커와 같은 정규화를 쓴다 — 두 곳의 파일명이 어긋나면 번들을 찾지 못한다.
name="$(printf '%s' "$agent_id" | tr -c 'A-Za-z0-9_-' '_' | cut -c1-64)"
[ -n "$name" ] || exit 0

mkdir -p "$qdir/agents" 2>/dev/null || exit 0
file="$qdir/agents/$name"
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

started=""
[ -r "$file" ] && started="$(cut -f2 "$file" 2>/dev/null | head -n 1)"
[ -n "$started" ] || started="$now"

if [ "$EVENT" = "start" ]; then
  # 이미 봉인된 같은 이름이 있으면(재개된 에이전트) 봉인을 푼다 — 새 커밋이
  # 이어질 수 있고, 봉인된 채로 두면 그 뒤 커밋이 요구 대상에서 빠진다.
  printf '%s\t%s\t%s\n' "$agent_type" "$started" "" > "$file" 2>/dev/null || :
else
  printf '%s\t%s\t%s\n' "$agent_type" "$started" "$now" > "$file" 2>/dev/null || :
fi
exit 0
```

- [ ] **Step 5: `bundle-notify.sh` 를 구현한다**

`scripts/bundle-notify.sh` 를 새로 만든다.

```bash
#!/usr/bin/env bash
# PostToolUse(Task) — 봉인된 번들의 검증을 부모 에이전트에게 요구한다.
#
# 사용법: <hook json> | bundle-notify.sh
# 출력:   요구할 것이 있으면 hookSpecificOutput.additionalContext / 없으면 없음
# 종료:   항상 0.
#
# 여기가 서브에이전트 작업 마무리에 가장 가까우면서 사람에게 물을 수 있는
# 자리다. 서브에이전트가 끝나 결과가 부모로 돌아오는 순간 부모 문맥에서
# 발동하므로 AskUserQuestion 을 쓸 수 있다.
#
# 훅이 직접 퀴즈를 내지 않는다 — 훅에는 사람에게 묻는 채널이 없고 timeout 이
# 걸려 있어(기본 60초, 넘으면 훅이 죽어 판정이 사라진다) 사람의 답을 기다리는
# 구조는 성립하지 않는다. 요구만 주입하고 퀴즈는 에이전트가 스킬로 낸다.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

payload="$(cat)"

command -v jq >/dev/null 2>&1 || exit 0

cwd="$(jq -r '.cwd // ""' <<<"$payload" 2>/dev/null || echo "")"
[ -n "$cwd" ] && cd "$cwd" 2>/dev/null

git rev-parse --git-common-dir >/dev/null 2>&1 || exit 0
qdir="$(git rev-parse --git-common-dir)/quiz-gate"

# 유예 모드면 조용히 지나간다. 원장은 계속 쌓이고 Stop 이 턴 끝에 막는다.
[ -e "$qdir/defer" ] && exit 0

emit() {  # $1 = additionalContext 본문
  jq -n --arg c "$1" '{
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: $c
    }
  }'
  exit 0
}

# 봉인된 번들부터 본다. 판정은 pending.sh 한 곳에만 있다 (D45).
lines=""
if [ -d "$qdir/agents" ]; then
  for f in "$qdir/agents"/*; do
    [ -f "$f" ] || continue
    sealed="$(cut -f3 "$f" 2>/dev/null | head -n 1)"
    [ -n "$sealed" ] || continue          # 아직 도는 중이다
    name="$(basename "$f")"
    atype="$(cut -f1 "$f" 2>/dev/null | head -n 1)"
    n="$(bash "$SCRIPT_DIR/pending.sh" --bundle "$name" 2>/dev/null | wc -l | tr -d ' ')"
    [ "${n:-0}" -gt 0 ] || continue
    lines="$lines   $atype ($name) — $n 개 변경
"
  done
fi

if [ -n "$lines" ]; then
  emit "🦡 KkochiKkochi — 끝난 서브에이전트의 변경이 아직 검증되지 않았습니다.

$lines
kkochikkochi 스킬을 실행해 번들마다 퀴즈를 내세요. 대상은
\`pending.sh --bundle <agent_id>\` 가 냅니다. 완료 순서대로 하나씩 처리하세요."
fi

# 폴백 — 봉인 기록이 없는데 원장에 미검증이 남아 있는 경우. SubagentStop 이
# PostToolUse 보다 늦게 돌거나 아예 발동하지 않아도 검증이 사라지지 않게 한다.
if unverified="$(bash "$SCRIPT_DIR/pending.sh" --all-unverified 2>/dev/null)"; then
  paths="$(printf '%s\n' "$unverified" | cut -f2 | sort -u | sed 's/^/   /')"
  emit "🦡 KkochiKkochi — 아직 검증되지 않은 변경이 있습니다.

$paths

kkochikkochi 스킬을 실행해 퀴즈를 통과하세요."
fi

exit 0
```

- [ ] **Step 6: 매니페스트에 세 훅을 등록한다**

`hooks/hooks.json` 의 `"Stop"` 항목 뒤에 추가한다.

```json
    "PostToolUse": [
      {
        "matcher": "Task",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/bundle-notify.sh\"",
            "timeout": 10
          }
        ]
      }
    ],
    "SubagentStart": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/seal-bundle.sh\" --event start",
            "timeout": 5
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/seal-bundle.sh\" --event stop",
            "timeout": 5
          }
        ]
      }
    ]
```

- [ ] **Step 7: 매니페스트 실행 테스트를 추가한다**

`tests/manifests.bats` 끝에 추가한다. 이 파일이 있는 이유가 "`command` 문자열이 실제로 돌아가는가"이므로 새 훅도 같은 검증을 받아야 한다.

```bash
@test "Claude Code 매니페스트의 새 훅 command 가 전부 실제로 실행된다" {
  for path in '.hooks.Stop[0].hooks[0].command' \
              '.hooks.PostToolUse[0].hooks[0].command' \
              '.hooks.SubagentStart[0].hooks[0].command' \
              '.hooks.SubagentStop[0].hooks[0].command'; do
    cmd="$(jq -r "$path" "$PLUGIN_ROOT/hooks/hooks.json")"
    [ -n "$cmd" ] && [ "$cmd" != "null" ]
    jq -n --arg cwd "$PWD" \
      '{session_id:"sess-m", cwd:$cwd, agent_id:"aaa11", agent_type:"general-purpose"}' \
      | env -u PLUGIN_ROOT CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash -c "$cmd"
    [ "$?" -eq 0 ] || return 1
  done
}

@test "Codex 매니페스트에는 서브에이전트 훅이 없다" {
  # [정정, 2026-08-01: 이 전제는 거짓으로 확인됐다.] Codex 페이로드에도
  # `agent_id`·`agent_type` 이 있다 (`PreToolUse`·`PostToolUse` 에 optional,
  # `SubagentStart`·`SubagentStop` 에 required). 이 전제가 무너지면서 이 테스트
  # 자체도 폐기됐다 — 실제 구현은 훅 4종 + `spawn_agent` 매처를 등록한다
  # (`tests/manifests.bats`, `docs/superpowers/specs/2026-08-01-push-scope-and-codex-design.md` §5).
  for key in Stop PostToolUse SubagentStart SubagentStop; do
    run jq -e --arg k "$key" '.hooks | has($k)' "$PLUGIN_ROOT/hooks.json"
    [ "$status" -ne 0 ]
  done
}
```

- [ ] **Step 8: 테스트가 통과하는지 확인한다**

```bash
bats tests/bundle.bats tests/manifests.bats
```

Expected: PASS.

- [ ] **Step 9: 전체 테스트와 린트**

```bash
bats tests/ && shellcheck scripts/*.sh && jq . hooks/hooks.json > /dev/null
```

Expected: PASS, 린트 출력 없음.

- [ ] **Step 10: 커밋한다**

```bash
git add scripts/seal-bundle.sh scripts/bundle-notify.sh hooks/hooks.json \
        tests/bundle.bats tests/manifests.bats \
        docs/superpowers/specs/2026-07-30-parallel-gate-design.md
git commit -m "feat: ask for verification when each subagent finishes

SubagentStop seals the bundle; PostToolUse(Task) fires in the parent
context where AskUserQuestion actually reaches the user.

PostToolUse(Task) gets no agent_id (the SDK scopes that field to hooks
firing inside a subagent), so it reads the sealed bundles off disk and
falls back to the whole ledger if none are recorded."
```

---

### Task 7: `pre-push` 와 설치기의 다중 훅 지원

`Stop` 훅은 에이전트를 막지만 사람은 Esc 로 빠져나간다. 미검증 커밋이 남에게 넘어가는 것은 그 다음 문제다.

**Files:**
- Create: `hooks/pre-push`
- Modify: `scripts/install.sh:18-56, 82-141, 143-156`
- Test: `tests/pre-push.bats` (신규), `tests/install.bats` (확장)

**Interfaces:**
- Consumes: Task 4 의 `covered.tsv` 철자 규칙
- Produces:
  - `hooks/pre-push` — stdin 으로 `<local ref> <local sha> <remote ref> <remote sha>` 줄들을 받고, 그 범위에 미검증 변경이 있으면 exit 1
  - `install.sh` 가 `pre-commit` 과 `pre-push` 둘 다 설치·제거한다. `status` 종료 코드 계약은 유지: 0 = 둘 다 최신, 1 = `pre-commit` 미설치, 2 = `core.hooksPath`, 3 = 우리 것인데 낡음(`pre-push` 누락 포함)

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`tests/pre-push.bats` 를 새로 만든다.

```bash
#!/usr/bin/env bats
#
# pre-push 는 최종 경계다. Stop 훅은 사람이 Esc 로 빠져나갈 수 있으므로,
# 미검증 커밋이 남에게 넘어가는 것은 여기서 막는다.
#
# 여기서는 퀴즈를 내지 않는다 — push 는 보통 명령 하나이고 사람에게 묻는
# 채널이 없다. 거부하고 안내만 한다.

load helper

setup() { setup_repo; seed_repo; }
teardown() { teardown_repo; }

install_push_hook() {
  mkdir -p "$(hooksdir)"
  cp "$PLUGIN_ROOT/hooks/pre-push" "$(hooksdir)/pre-push"
  chmod +x "$(hooksdir)/pre-push"
}

# pre-push 훅을 git 없이 직접 태운다 (stdin 계약을 그대로 준다).
run_push_hook() {  # $1 = remote sha, $2 = local sha
  printf 'refs/heads/main %s refs/heads/main %s\n' "$2" "$1" \
    | "$(hooksdir)/pre-push" origin https://example.invalid/r.git
}

@test "미검증 커밋이 없으면 통과한다" {
  install_push_hook
  base="$(git rev-parse HEAD)"
  run run_push_hook "$base" "$base"
  [ "$status" -eq 0 ]
}

@test "미검증 커밋이 섞이면 거부한다" {
  install_push_hook
  base="$(git rev-parse HEAD)"
  printf 'C1\n' > c.ts; git add c.ts
  commit_as_human -qm "unverified"
  run run_push_hook "$base" "$(git rev-parse HEAD)"
  [ "$status" -ne 0 ]
  [[ "$output" == *"c.ts"* ]]
}

@test "검증된 커밋만 있으면 통과한다" {
  install_push_hook
  base="$(git rev-parse HEAD)"
  printf 'C1\n' > c.ts; git add c.ts
  stub_covered_line c.ts
  commit_as_human -qm "verified"
  run run_push_hook "$base" "$(git rev-parse HEAD)"
  [ "$status" -eq 0 ]
}

@test "새 브랜치(remote sha 가 0)에서도 범위를 잡는다" {
  install_push_hook
  printf 'C1\n' > c.ts; git add c.ts
  commit_as_human -qm "unverified"
  run run_push_hook "$NULL_SHA" "$(git rev-parse HEAD)"
  [ "$status" -ne 0 ]
}

@test "브랜치 삭제(local sha 가 0)는 통과한다" {
  install_push_hook
  run run_push_hook "$(git rev-parse HEAD)" "$NULL_SHA"
  [ "$status" -eq 0 ]
}

@test "jq 가 없어도 거부는 동작한다" {
  # pre-push 는 jq 를 쓰지 않는다 — record-pass.sh 와 달리 판정만 하므로.
  install_push_hook
  base="$(git rev-parse HEAD)"
  printf 'C1\n' > c.ts; git add c.ts
  commit_as_human -qm "unverified"
  run env PATH=/usr/bin:/bin run_push_hook "$base" "$(git rev-parse HEAD)"
  [ "$status" -ne 0 ]
}
```

마지막 테스트는 `run_push_hook` 이 함수라 `env` 로 감쌀 수 없다. 이렇게 고쳐 쓴다.

```bash
@test "미검증 판정에 jq 를 쓰지 않는다" {
  install_push_hook
  run grep -c 'jq' "$(hooksdir)/pre-push"
  [ "$output" = "0" ]
}
```

- [ ] **Step 2: 실패를 확인한다**

```bash
bats tests/pre-push.bats
```

Expected: 전부 FAIL — `hooks/pre-push` 가 없다.

- [ ] **Step 3: `hooks/pre-push` 를 구현한다**

`hooks/pre-push` 를 새로 만든다.

```sh
#!/bin/sh
# KkochiKkochi 최종 경계 — git 이 직접 호출한다.
# KKOCHIKKOCHI-HOOK-v1  ← 자기 식별 마커. 설치기가 이 문자열로 "내 훅"을 판별한다.
#
# Stop 훅은 에이전트를 막지만 사람은 Esc 로 빠져나간다. 미검증 커밋이 남에게
# 넘어가는 것은 여기서 막는다.
#
# 여기서는 퀴즈를 내지 않는다 — push 는 보통 명령 하나이고 사람에게 묻는
# 채널이 없다. 거부하고 안내만 한다.
#
# jq 를 쓰지 않는다. 판정만 하고 아무것도 기록하지 않으므로 필요가 없고,
# jq 가 없는 환경에서 조용히 열리지 않아야 하는 유일한 층이다.

set -u

QDIR="$(git rev-parse --git-common-dir)/quiz-gate"
COVERED="$QDIR/covered.tsv"

NULL_SHA=0000000000000000000000000000000000000000

blocked=""

# stdin: <local ref> <local sha> <remote ref> <remote sha>
while read -r _local_ref local_sha _remote_ref remote_sha; do
  [ -n "${local_sha:-}" ] || continue
  # 브랜치 삭제 — 넘어가는 내용이 없다.
  [ "$local_sha" = "$NULL_SHA" ] && continue

  if [ "$remote_sha" = "$NULL_SHA" ]; then
    # 새 브랜치다. 이미 리모트에 있는 것을 빼고 이 브랜치에만 있는 것을 본다.
    range="$local_sha --not --remotes"
  else
    range="$remote_sha..$local_sha"
  fi

  # 각 커밋의 (blob sha, 경로) 를 covered.tsv 와 대조한다. 철자는
  # covered.tsv 를 쓴 쪽과 반드시 같아야 한다 — -z 로 받아 아무것도
  # 따옴표로 감싸지 않는다.
  # shellcheck disable=SC2086  # range 는 여러 인자로 펼쳐져야 한다
  for commit in $(git rev-list $range 2>/dev/null); do
    pairs="$(git -c core.quotePath=false diff-tree --no-commit-id --root \
               --raw -z --abbrev=40 --no-renames "$commit" 2>/dev/null \
             | tr '\0' '\n' \
             | awk 'NR % 2 { split($0, f, " "); sha = f[4]; next }
                           { printf "%s\t%s\n", sha, $0 }')"
    [ -n "$pairs" ] || continue

    while IFS='	' read -r sha path; do
      [ -n "$sha" ] || continue
      [ "$sha" = "$NULL_SHA" ] && continue   # 삭제된 파일
      if [ -r "$COVERED" ] && KK_PATH="$path" awk -F'\t' -v s="$sha" \
           '$1 == s && $2 == ENVIRON["KK_PATH"] { found = 1; exit }
            END { exit !found }' "$COVERED"; then
        continue
      fi
      case "$blocked" in
        *"   $path
"*) ;;
        *) blocked="$blocked   $path
" ;;
      esac
    done <<PAIRS
$pairs
PAIRS
  done
done

[ -n "$blocked" ] || exit 0

cat >&2 <<MSG
🦡 KkochiKkochi — push 하려는 커밋에 검증되지 않은 변경이 있습니다.

$blocked
kkochikkochi 스킬을 실행해 퀴즈를 통과한 뒤 다시 push 하세요.
MSG
exit 1
```

`IFS='	'` 안은 **탭 리터럴**이다.

- [ ] **Step 4: 테스트가 통과하는지 확인한다**

```bash
bats tests/pre-push.bats
```

Expected: PASS.

- [ ] **Step 5: 실패하는 설치기 테스트를 쓴다**

`tests/install.bats` 끝에 추가한다.

```bash
@test "install 이 pre-push 도 설치한다" {
  bash "$PLUGIN_ROOT/scripts/install.sh" install
  [ -x "$(hooksdir)/pre-push" ]
  run grep -c 'KKOCHIKKOCHI-HOOK-v1' "$(hooksdir)/pre-push"
  [ "$output" -ge 1 ]
}

@test "pre-push 가 없으면 status 가 3(낡음)을 낸다" {
  bash "$PLUGIN_ROOT/scripts/install.sh" install
  rm -f "$(hooksdir)/pre-push"
  run bash "$PLUGIN_ROOT/scripts/install.sh" status
  [ "$status" -eq 3 ]
}

@test "pre-push 가 낡으면 status 가 3 을 낸다" {
  bash "$PLUGIN_ROOT/scripts/install.sh" install
  printf '#!/bin/sh\n# KKOCHIKKOCHI-HOOK-v1\nexit 0\n' > "$(hooksdir)/pre-push"
  chmod +x "$(hooksdir)/pre-push"
  run bash "$PLUGIN_ROOT/scripts/install.sh" status
  [ "$status" -eq 3 ]
}

@test "둘 다 최신이면 status 가 0 을 낸다" {
  bash "$PLUGIN_ROOT/scripts/install.sh" install
  run bash "$PLUGIN_ROOT/scripts/install.sh" status
  [ "$status" -eq 0 ]
}

@test "uninstall 이 둘 다 지운다" {
  bash "$PLUGIN_ROOT/scripts/install.sh" install
  bash "$PLUGIN_ROOT/scripts/install.sh" uninstall
  [ ! -e "$(hooksdir)/pre-commit" ]
  [ ! -e "$(hooksdir)/pre-push" ]
}

@test "기존 pre-push 훅도 체이닝한다" {
  mkdir -p "$(hooksdir)"
  printf '#!/bin/sh\necho theirs-push\nexit 0\n' > "$(hooksdir)/pre-push"
  chmod +x "$(hooksdir)/pre-push"
  bash "$PLUGIN_ROOT/scripts/install.sh" install
  [ -x "$(hooksdir)/pre-push.kkochikkochi-chained" ]
  run cat "$(hooksdir)/pre-push.kkochikkochi-chained"
  [[ "$output" == *"theirs-push"* ]]
}
```

- [ ] **Step 6: `install.sh` 를 다중 훅으로 일반화한다**

`scripts/install.sh` 의 18-56번째 줄을 교체한다.

```bash
MARKER="KKOCHIKKOCHI-HOOK-v1"
CHAINED_SUFFIX=".kkochikkochi-chained"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 설치 대상 훅 목록. 순서가 곧 설치 순서다 — pre-commit 을 먼저 놓아,
# 중간에 실패해도 가장 중요한 층이 먼저 자리잡는다.
HOOK_NAMES="pre-commit pre-push"

die() { echo "kkochikkochi: $1" >&2; exit 1; }

git rev-parse --git-dir >/dev/null 2>&1 || die "git 저장소가 아닙니다"

HOOKS_DIR="$(git rev-parse --git-path hooks)"

src_for()     { echo "$SCRIPT_DIR/../hooks/$1"; }
target_for()  { echo "$HOOKS_DIR/$1"; }
chained_for() { echo "$HOOKS_DIR/$1$CHAINED_SUFFIX"; }

# "우리 훅인가" — 소유권만 가른다. 마커 문자열은 판(revision)을 구분하지
# 못하므로 이것만으로 "최신인가"를 답할 수 없다.
is_ours() { [ -f "$1" ] && grep -q "$MARKER" "$1" 2>/dev/null; }

# "지금 플러그인이 배포하는 그 훅인가" — 마커 안에 판 번호를 심는 대신
# 플러그인 원본과 내용을 통째로 비교한다. 판 번호는 사람이 손으로 올려야
# 하므로 언젠가 반드시 잊히지만, 내용 비교는 잊힐 수가 없다. 실행 권한도
# 함께 본다 — 실행 권한이 없는 훅은 git 이 그냥 무시하므로 "설치됨"이라고
# 답하면 게이트가 조용히 없는 상태가 된다.
is_current() { is_ours "$2" && [ -x "$2" ] && cmp -s "$1" "$2"; }

hookspath_set() { [ -n "$(git config --get core.hooksPath || true)" ]; }

# core.hooksPath 가 설정돼 있으면 "설치됨/아님"을 가를 수 없다 — 애초에
# 우리가 설치를 거부하는 상태이므로, install 과 같은 exit 2 로 통일해
# 호출자(예: 헬스체크)가 "바로 설치해도 됨"과 "사람 판단이 필요함"을
# 구분할 수 있게 한다.
#
# 종료 코드 계약은 훅이 하나였을 때와 같다. 1 은 "아직 아무것도 없다"이고,
# 3 은 "우리 것이 있는데 손볼 데가 있다"다 — pre-push 만 빠진 경우도 3 이다.
# 그래야 stamp-agent.sh 의 건강검진이 재설치를 안내한다 (D39).
cmd_status() {
  hookspath_set && exit 2
  is_ours "$(target_for pre-commit)" || exit 1
  for name in $HOOK_NAMES; do
    src="$(src_for "$name")"
    # 원본을 읽을 수 없으면 낡았는지 아닌지 판정할 근거가 없다. 애매한
    # 경우는 통과시킨다 (D00) — 여기서 3을 내면 헬스체크가 고칠 수 없는
    # 재설치를 영원히 요구하게 된다.
    [ -r "$src" ] || continue
    is_current "$src" "$(target_for "$name")" || exit 3
  done
  exit 0
}
```

- [ ] **Step 7: `cmd_install` 을 훅 하나 설치 함수로 쪼갠다**

82-141번째 줄(`mkdir -p "$HOOKS_DIR"` 부터 `cmd_install` 끝까지)을 교체한다. `hookspath_set` 안내와 `jq` 확인은 그대로 둔다.

```bash
  mkdir -p "$HOOKS_DIR" || die "훅 디렉터리를 만들 수 없습니다"

  for name in $HOOK_NAMES; do
    install_one "$name"
  done
}

# 훅 하나를 설치한다. 원래 cmd_install 안에 인라인으로 있던 그 로직이고,
# 원자성 논거도 그대로다 — 훅이 둘이 되었으니 함수로 뺐다.
install_one() {  # $1 = 훅 이름
  name="$1"
  src="$(src_for "$name")"
  target="$(target_for "$name")"
  chained="$(chained_for "$name")"

  [ -r "$src" ] || die "훅 원본을 찾을 수 없습니다: $src"

  # 새 훅을 같은 디렉터리의 임시 파일로 먼저 완성해 둔다. cp·chmod 가 여기서
  # 실패해도 기존 훅(있다면)은 아직 전혀 건드리지 않았으므로 안전하다.
  tmp_hook="$target.kkochikkochi-tmp.$$"
  rm -f "$tmp_hook"
  cp "$src" "$tmp_hook" || { rm -f "$tmp_hook"; die "훅을 준비할 수 없습니다: $name"; }
  chmod +x "$tmp_hook" || { rm -f "$tmp_hook"; die "실행 권한을 줄 수 없습니다: $name"; }

  # 기존 훅이 우리 것이 아니면 체이닝 이름도 함께 갖게 한다 — 새 훅이 이미
  # 완성된 뒤이므로, 여기부터 실패해도 무엇을 되돌려야 할지 알 수 있다.
  # 이미 체이닝 파일이 있으면 덮어쓰지 않는다 — 사용자의 원래 훅을 잃게 된다.
  linked_aside=0
  moved_aside=0
  if [ -f "$target" ] && ! is_ours "$target"; then
    if [ -f "$chained" ]; then
      rm -f "$tmp_hook"
      die "체이닝 파일이 이미 있습니다: $chained — 수동으로 정리하세요"
    fi
    # 하드 링크를 먼저 시도한다: mv 와 달리 target 이라는 이름이 사라지는
    # 순간이 없다. 하드 링크를 지원하지 않는 파일시스템이면 ln 이 실패하고,
    # 그때는 예전 방식(이동)으로 물러난다.
    if ln "$target" "$chained" 2>/dev/null; then
      linked_aside=1
    else
      mv "$target" "$chained" || { rm -f "$tmp_hook"; die "기존 훅을 옮길 수 없습니다: $name"; }
      moved_aside=1
    fi
    chmod +x "$chained" 2>/dev/null ||
      echo "kkochikkochi: 경고 — $chained 에 실행 권한을 줄 수 없습니다. 수동으로 chmod +x 하세요" >&2
    echo "kkochikkochi: 기존 $name 훅을 $chained 로 옮기고 체이닝합니다" >&2
  fi

  # 같은 디렉터리 안에서의 rename 은 원자적이다 — 이 한 걸음 이후 target 은
  # 옛 파일이거나 새 파일이거나 둘 중 하나이지, 결코 "둘 다 없음"이 되지
  # 않는다.
  if ! mv "$tmp_hook" "$target"; then
    rm -f "$tmp_hook"
    if [ "$linked_aside" -eq 1 ]; then
      rm -f "$chained"
      die "훅을 설치할 수 없습니다: $name (기존 훅은 그대로 있습니다)"
    fi
    if [ "$moved_aside" -eq 1 ] && mv "$chained" "$target" 2>/dev/null; then
      die "훅을 설치할 수 없습니다: $name (기존 훅을 복구했습니다)"
    fi
    die "훅을 설치할 수 없습니다: $name"
  fi

  echo "kkochikkochi: 설치 완료 — $target" >&2
}
```

- [ ] **Step 8: `cmd_uninstall` 을 목록 순회로 바꾼다**

143-156번째 줄을 교체한다.

```bash
cmd_uninstall() {
  is_ours "$(target_for pre-commit)" || die "우리 훅이 설치돼 있지 않습니다"
  for name in $HOOK_NAMES; do
    target="$(target_for "$name")"
    chained="$(chained_for "$name")"
    is_ours "$target" || continue
    if [ -f "$chained" ]; then
      # 복구를 먼저(그리고 하나의 rename 으로) 한다 — 이 rename 이 실패해도
      # 우리 훅은 target 에 그대로 남아 있다. 먼저 지우고 나중에 복구하면
      # 그 사이에 복구가 실패했을 때 저장소에 훅이 하나도 없는 상태로
      # 떨어진다.
      mv "$chained" "$target" || die "체이닝된 $name 훅을 복구할 수 없습니다 — 우리 훅이 그대로 있습니다"
      echo "kkochikkochi: 기존 $name 훅을 복구했습니다" >&2
    else
      rm -f "$target" || die "훅을 지울 수 없습니다: $name"
    fi
  done
  echo "kkochikkochi: 제거 완료" >&2
}
```

- [ ] **Step 9: `pre-push` 도 체이닝하도록 훅에 체이닝 실행을 넣는다**

`hooks/pre-push` 의 `QDIR=` 줄 앞에 넣는다.

```sh
CHAINED="$(git rev-parse --git-path hooks)/pre-push.kkochikkochi-chained"

# ── 체이닝된 기존 훅을 먼저 실행한다 ──────────────────────────────
# 자기 재귀 가드: 체이닝 파일 자체가 우리 훅의 사본이면 실행하지 않는다.
# 그 파일도 같은 방식으로 체이닝 경로를 계산해 자기 자신을 다시 부른다.
#
# stdin 은 한 번만 읽을 수 있으므로 먼저 전부 담아 두고 양쪽에 나눠 준다.
push_refs="$(cat)"

if [ -x "$CHAINED" ] && ! grep -q 'KKOCHIKKOCHI-HOOK-v1' "$CHAINED" 2>/dev/null; then
  printf '%s\n' "$push_refs" | "$CHAINED" "$@" || exit $?
fi
```

그리고 stdin 을 읽는 `while read` 의 히어독을 바꾼다.

```sh
done <<PUSH_REFS
$push_refs
PUSH_REFS
```

- [ ] **Step 10: 테스트가 통과하는지 확인한다**

`tests/pre-push.bats` 의 `run_push_hook` 은 stdin 을 파이프로 주므로 그대로 동작한다.

```bash
bats tests/pre-push.bats tests/install.bats
```

Expected: PASS.

- [ ] **Step 11: 전체 테스트와 린트**

```bash
bats tests/ && shellcheck -s sh hooks/pre-commit hooks/pre-push && shellcheck scripts/*.sh
```

Expected: PASS, 린트 출력 없음. CI 의 lint 단계도 `hooks/pre-push` 를 포함하게 `.github/workflows/ci.yml` 의 `shellcheck -s sh hooks/pre-commit` 을 `shellcheck -s sh hooks/pre-commit hooks/pre-push` 로 바꾼다.

- [ ] **Step 12: 커밋한다**

```bash
git add hooks/pre-push scripts/install.sh .github/workflows/ci.yml \
        tests/pre-push.bats tests/install.bats
git commit -m "feat: add the pre-push boundary

The Stop hook holds the agent but a human can always interrupt out of
it. This is the layer that keeps unverified commits from reaching
anyone else.

install.sh now walks a hook list instead of hardcoding pre-commit; the
status exit-code contract is unchanged, and a missing pre-push reports
3 (stale) so the health check prompts a reinstall."
```

---

### Task 8: 유예 모드

큰 작업을 돌려놓고 나중에 확인하는 흐름. 훅의 `timeout` 은 시간이 지나면 훅을 **죽여서** 판정을 잃으므로, 훅이 사람의 답을 기다리는 구조로는 만들 수 없다. 파일 상태로 만든다.

**Files:**
- Create: `scripts/defer.sh`
- Create: `commands/kk-defer.md`
- Modify: `skills/kkochikkochi/SKILL.md` (번들 모드 절 추가)
- Test: `tests/defer.bats` (신규)

**Interfaces:**
- Consumes: Task 5 의 `stop-gate.sh` (통과 시 `defer` 삭제), Task 6 의 `bundle-notify.sh` (`defer` 있으면 조용히 통과)
- Produces: `scripts/defer.sh on|off|status` — `on` 은 `$QDIR/defer` 를 만들고, `off` 는 지우고, `status` 는 `on`/`off` 를 stdout 에 낸다. 종료 0

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`tests/defer.bats` 를 새로 만든다.

```bash
#!/usr/bin/env bats
#
# 유예 모드 — 구현 중에는 묻지 않고 턴 끝에 몰아 받는다.
#
# 훅 기능으로는 만들 수 없다: 훅의 timeout(기본 60초)은 시간이 지나면 훅을
# 죽여 판정을 잃는다. 파일 상태로 만들면 세션이 죽어도 살아남고 pre-push 가
# 마지막에 잡는다.

load helper

setup() { setup_repo; seed_repo; }
teardown() { teardown_repo; }

defer_sh() { bash "$PLUGIN_ROOT/scripts/defer.sh" "$@"; }

@test "on 이 defer 파일을 만든다" {
  run defer_sh on
  [ "$status" -eq 0 ]
  [ -e "$(qdir)/defer" ]
}

@test "off 가 defer 파일을 지운다" {
  defer_sh on
  run defer_sh off
  [ "$status" -eq 0 ]
  [ ! -e "$(qdir)/defer" ]
}

@test "status 가 상태를 낸다" {
  run defer_sh status
  [ "$output" = "off" ]
  defer_sh on
  run defer_sh status
  [ "$output" = "on" ]
}

@test "이미 켜져 있을 때 on 을 또 불러도 0 을 낸다" {
  defer_sh on
  run defer_sh on
  [ "$status" -eq 0 ]
}

@test "꺼져 있을 때 off 를 불러도 0 을 낸다" {
  run defer_sh off
  [ "$status" -eq 0 ]
}

@test "알 수 없는 인자는 거부한다" {
  run defer_sh nonsense
  [ "$status" -ne 0 ]
}

@test "git 저장소가 아니면 거부한다" {
  cd "$(mktemp -d)"
  run defer_sh on
  [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: 실패를 확인한다**

```bash
bats tests/defer.bats
```

Expected: 전부 FAIL — `scripts/defer.sh` 가 없다.

- [ ] **Step 3: `defer.sh` 를 구현한다**

`scripts/defer.sh` 를 새로 만든다.

```bash
#!/usr/bin/env bash
# 유예 모드 — 구현 중에는 묻지 않고 턴 끝에 몰아 받는다.
#
# 사용법: defer.sh on|off|status
#
# 왜 파일인가: 훅의 timeout(기본 60초)은 시간이 지나면 훅을 죽여 판정을
# 잃는다. async + asyncTimeout 도 훅 실행을 미루는 것이지 사람의 답을
# 기다리는 것이 아니다. 그래서 유예를 훅 기능으로는 만들 수 없다. 파일이면
# 세션이 죽어도 살아남고, pre-push 가 마지막에 잡는다.
#
# 범위는 턴 끝까지다. Stop 훅은 유예와 무관하게 막고, 통과할 때 이 파일을
# 지운다 (scripts/stop-gate.sh). "영구히 묻지 않기"는 만들지 않는다 —
# 빠져나갈 문을 만들면 그 문이 기본 경로가 된다 (D06).

set -uo pipefail

die() { echo "kkochikkochi: $1" >&2; exit 1; }

git rev-parse --git-common-dir >/dev/null 2>&1 || die "git 저장소가 아닙니다"
qdir="$(git rev-parse --git-common-dir)/quiz-gate"
flag="$qdir/defer"

case "${1:-status}" in
  on)
    mkdir -p "$qdir" || die "상태 디렉터리를 만들 수 없습니다"
    : > "$flag" || die "유예 상태를 켤 수 없습니다"
    echo "kkochikkochi: 유예 모드 — 이번 턴 동안 서브에이전트 번들 퀴즈를 내지 않습니다." >&2
    echo "  턴을 마치려 할 때 몰아서 받습니다. push 는 그때까지 막힙니다." >&2
    ;;
  off)
    rm -f "$flag" 2>/dev/null || :
    echo "kkochikkochi: 유예 모드를 해제했습니다." >&2
    ;;
  status)
    [ -e "$flag" ] && echo "on" || echo "off"
    ;;
  *)
    die "사용법: defer.sh [on|off|status]"
    ;;
esac
exit 0
```

- [ ] **Step 4: 테스트가 통과하는지 확인한다**

```bash
bats tests/defer.bats
```

Expected: PASS.

- [ ] **Step 5: 슬래시 커맨드를 만든다**

`commands/kk-defer.md` 를 새로 만든다.

```markdown
---
description: 이번 턴은 서브에이전트 번들 퀴즈를 미루고 턴 끝에 몰아 받는다
---

유예 모드를 켠다. 큰 작업을 돌려놓고 나중에 확인할 때 쓴다.

```bash
bash "${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}/scripts/defer.sh" on
```

켜져 있는 동안 `PostToolUse(Task)` 는 서브에이전트 번들 퀴즈를 요구하지 않는다. 원장은 계속 쌓이고, 턴을 마치려 할 때 `Stop` 훅이 붙잡아 몰아서 받는다.

유예는 **턴 끝까지**다. 영구 우회가 아니다 — `Stop` 은 유예와 무관하게 막고, `pre-push` 도 그대로 막는다.

해제하려면:

```bash
bash "${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}/scripts/defer.sh" off
```
```

- [ ] **Step 6: `SKILL.md` 에 번들 모드를 적는다**

`skills/kkochikkochi/SKILL.md` 의 §1 첫 코드 블록 뒤에 넣는다.

```markdown
### 번들 단위로 부를 때

`PostToolUse(Task)` 나 `Stop` 훅이 서브에이전트 번들의 검증을 요구했다면, 그 요구가 알려준 `agent_id` 를 그대로 넘긴다.

```bash
bash "${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}/scripts/pending.sh" --bundle <agent_id>
```

여러 번들이 한 번에 도착할 수 있다 — 부모가 긴 도구 호출 안에 있으면 두 알림이 함께 온다. **완료 순서대로 하나씩** 처리하고, 번들마다 §2 의 5문항 상한을 그대로 지킨다. 번들 하나를 통과하면 그 번들의 `agent_id` 로 기록한다.

```bash
cat <<'JSON' | bash "${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}/scripts/record-pass.sh" --bundle <agent_id>
...
JSON
```

`Stop` 훅이 요구한 경우(번들 구분 없이 남은 전부)는 `--all-unverified` 를 같은 자리에 쓴다. §1 과 §5 에 **반드시 같은 인자**를 준다 — 다르면 사용자가 A 를 풀었는데 B 가 검증된 것으로 기록된다 (D45).
```

- [ ] **Step 7: 전체 테스트와 린트**

```bash
bats tests/ && shellcheck scripts/*.sh && shellcheck -s sh hooks/pre-commit hooks/pre-push
```

Expected: PASS, 린트 출력 없음.

- [ ] **Step 8: 커밋한다**

```bash
git add scripts/defer.sh commands/kk-defer.md skills/kkochikkochi/SKILL.md tests/defer.bats
git commit -m "feat: add /kk-defer for batching bundle quizzes at turn end

Hook timeouts kill the hook and lose its verdict, so deferral cannot be
a hook feature. A file survives a dead session and pre-push still
catches what it deferred.

Scoped to the turn on purpose: stop-gate clears it when it passes, and
a permanent bypass would become the default path (D06)."
```

---

## Self-Review

**1. Spec coverage**

| 스펙 절 | 태스크 |
|---|---|
| §3 `pre-commit` 두 행 | Task 5 |
| §3 `PostToolUse(Task)` 두 행 | Task 6 |
| §3 `SubagentStart`·`SubagentStop` | Task 6 |
| §3 `Stop` | Task 5 |
| §3 `pre-push` | Task 7 |
| §3 왜 `SubagentStop` 이 아닌가 | Task 6 (스펙 수정 + `seal-bundle.sh` 주석) |
| §3 `Stop` 과 무한 루프 | Task 5 (`stop-hook.bats` 의 `stop_hook_active` 테스트) |
| §3 왜 `command` 훅인가 | Task 5 (`stop-gate.sh` 주석) |
| §4 오판 규칙 | Task 2 (마커 읽기) + Task 5 (분기와 "마커가 섞여 있으면" 테스트) |
| §4 `FRESH_SECS=600` | Task 2 (Global Constraints 에도) |
| §5 `--git-common-dir` | Task 1 |
| §5 마커 쪼개기 | Task 2 |
| §5 원장 경로 표기 | Task 4 (`pending.sh` 의 형식 검증) |
| §5 `pre-push` 범위 | Task 7 |
| §5 `pass_id` 충돌 | Task 3 |
| §6 유예 모드 | Task 8 |
| §7 번들 여러 개 | Task 6 (`bundle-notify.sh` 가 전부 열거) + Task 8 (`SKILL.md` 순차 처리 규칙) |
| §8 불변 조건 | Task 4 (`pending.sh` 세 모드), Task 5·6 이 그것만 부른다 |
| §11 테스트 계획 | 각 태스크의 테스트 단계. 스펙이 든 파일 전부가 계획에 있다 |
| §12 구현 순서 | Task 1~8 이 그 순서다. 스펙의 3·4단계 묶음 요구는 Task 5 가 지킨다 |

빠진 것 없음. 스펙 §10 의 한계는 구현 대상이 아니라 문서화된 사실이므로 태스크가 없다.

**2. Placeholder scan**

"TBD"·"TODO"·"적절히"·"필요에 따라" 없음. 모든 코드 단계에 실제 코드가 있다. `<agent_id>` 는 플레이스홀더가 아니라 런타임 인자다.

**3. Type consistency**

| 이름 | 정의 | 사용 |
|---|---|---|
| `qdir()` 헬퍼 | Task 1 Step 4 | Task 2·3·4·5·6·8 의 모든 테스트 |
| `add_worktree` | Task 1 Step 1 | Task 1 Step 2 |
| `stamp [agent] [agent_id] [agent_type]` | Task 2 Step 5 | Task 5 의 `pre-commit.bats` |
| 마커 4필드 `agent\tagent_id\tagent_type\tsession_id` | Task 2 Step 3 | Task 2 Step 6 이 `cut -f1,2,3` 으로 읽는다 |
| 마커 파일명 정규화 `tr -c 'A-Za-z0-9_-' '_' \| cut -c1-64` | Task 2 Step 3 | Task 6 `seal-bundle.sh` 가 **같은 식**을 쓴다 — 어긋나면 번들을 못 찾는다 |
| `marker_agent_id`·`marker_agent_type` | Task 2 Step 6 | Task 5 Step 4 의 분기 |
| 원장 5필드 `blob_sha\tpath\tagent_id\tagent_type\tat` | Task 4 Step 1(스펙)·Step 4(`awk NF != 5`) | Task 5 Step 4 가 쓰고, Task 4·5·6 의 `stub_ledger_line` 이 같은 5필드를 낸다 |
| `pending.sh --bundle <id>` / `--all-unverified` | Task 4 Step 4 | Task 5 `stop-gate.sh`, Task 6 `bundle-notify.sh`, Task 8 `SKILL.md` |
| `record-pass.sh "$@"` | Task 4 Step 6 | Task 4 Step 7, Task 5 왕복 테스트, Task 8 `SKILL.md` |
| `$QDIR/agents/<name>` 3필드 `agent_type\tstarted_at\tsealed_at` | Task 6 Step 4 | Task 6 Step 5 가 `cut -f1,f3` 으로 읽는다 |
| `$QDIR/defer` | Task 8 Step 3 | Task 5 `stop-gate.sh` 가 지우고, Task 6 `bundle-notify.sh` 가 읽는다 |
| `HOOK_NAMES="pre-commit pre-push"` | Task 7 Step 6 | Task 7 Step 7·8 |
| `is_current "$src" "$target"` (인자 둘로 바뀜) | Task 7 Step 6 | Task 7 Step 6 의 `cmd_status` 만 부른다 |

첫 초안은 `stub_ledger_line` 을 `tests/ledger.bats`·`tests/stop-hook.bats`·`tests/bundle.bats` 세 곳에 같은 내용으로 중복해 두었다. 원장 스키마가 바뀔 때 반드시 한쪽이 낡는 형태다 — 이 저장소가 D45 로 세 번 겪은 것과 같은 모양이다. Task 4 Step 2 로 `tests/helper.bash` 에 옮기고 나머지 두 파일에서는 정의를 지웠다.

`is_current` 의 시그니처가 Task 7 에서 인자 하나(`$1` = target)에서 둘(`$1` = src, `$2` = target)로 바뀐다. 부르는 곳은 `cmd_status` 하나뿐이고 같은 스텝에서 함께 고친다 — 다른 호출부는 없다(`grep -n 'is_current' scripts/install.sh` 로 확인할 것).
