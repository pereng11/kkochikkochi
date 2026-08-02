#!/usr/bin/env bats

load helper

setup() { setup_repo; seed_repo; }
teardown() { teardown_repo; }

stamp_run() {  # $1 = agent, $2 = command, $3 = agent_id, $4 = agent_type
  jq -n --arg c "${2:-git commit -m x}" --arg cwd "$PWD" --arg s "sess-abc" \
        --arg aid "${3:-}" --arg at "${4:-}" \
    '{tool_name:"Bash", cwd:$cwd, session_id:$s, tool_input:{command:$c}}
     + (if $aid == "" then {} else {agent_id:$aid, agent_type:$at} end)' \
  | bash "$PLUGIN_ROOT/scripts/stamp-agent.sh" --agent "${1:-claude-code}"
}

@test "마커 파일을 만든다" {
  stamp_run claude-code
  [ -f "$(qdir)/marker/main" ]
}

@test "마커에 에이전트 이름과 세션 ID 가 들어간다" {
  stamp_run claude-code
  run cat "$(qdir)/marker/main"
  [[ "$output" == *"claude-code"* ]]
  [[ "$output" == *"sess-abc"* ]]
}

@test "codex 로도 동작한다 (같은 스크립트)" {
  stamp_run codex
  run cat "$(qdir)/marker/main"
  [[ "$output" == *"codex"* ]]
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

# ── F2: pre-push 최종 경계를 --no-verify 로 무저항 우회하지 못한다 ──
#
# `hooks/pre-push` 는 Stop 을 Esc 로 빠져나간 에이전트를 잡는 최종 경계다.
# 프리필터가 *commit* 만 봤을 때는 `git push --no-verify` 가 "commit" 이란
# 글자를 담지 않아 이 스크립트에 아예 들어오지 못했다(실측: deny() 미호출).
# 아래는 그 구멍이 막혔는지 직접 확인한다.

@test "git push --no-verify 는 deny 한다" {
  run stamp_run claude-code 'git push --no-verify'
  [[ "$output" == *"deny"* ]]
  [[ "$output" == *"no-verify"* ]]
}

@test "git push -n 도 (짧은 형태 묶음 포함) deny 한다" {
  run stamp_run claude-code 'git push -n origin main'
  [[ "$output" == *"deny"* ]]
  [[ "$output" == *"no-verify"* ]]
}

# 회귀 방지: --no-verify 판정 범위를 *push* 로 넓히면서 프리필터 자체(마커
# 쓰기 게이트)까지 같이 넓히면 D44 가 되살아난다(주석 참고, stamp-agent.sh).
# 플래그 없는 평범한 push 는 여전히 마커를 남기지 않아야 한다.
@test "git push (플래그 없음) 은 여전히 마커를 남기지 않는다" {
  stamp_run claude-code 'git push origin main'
  [ ! -f "$(qdir)/marker/main" ]
}

# ── F2: git 토큰이 없으면 --no-verify/-n 판정을 하지 않는다 ──
#
# *commit*|*push* 프리필터를 넓힌 대가로 늘어난 오탐(JS/TS 저장소의 grep/rg/find
# 같은 명령이 "commit"·"push" 글자와 짧은 -n 묶음을 우연히 담는 경우)을 줄인다.
# git 호출로 보이는 토큰(`git` 또는 `g`)이 없으면 애초에 --no-verify/-n 검사를
# 하지 않는다.

@test "여전히 거부: git commit --no-verify" {
  run stamp_run claude-code 'git commit --no-verify'
  [[ "$output" == *"deny"* ]]
  [[ "$output" == *"no-verify"* ]]
}

@test "여전히 거부: git push --no-verify" {
  run stamp_run claude-code 'git push --no-verify'
  [[ "$output" == *"deny"* ]]
  [[ "$output" == *"no-verify"* ]]
}

@test "여전히 거부: git push -n origin main" {
  run stamp_run claude-code 'git push -n origin main'
  [[ "$output" == *"deny"* ]]
  [[ "$output" == *"no-verify"* ]]
}

@test "여전히 거부: g commit --no-verify (바이너리 별칭 g, 서브커맨드는 풀어 씀)" {
  run stamp_run claude-code 'g commit --no-verify'
  [[ "$output" == *"deny"* ]]
  [[ "$output" == *"no-verify"* ]]
}

@test "여전히 거부: 절대경로 /usr/bin/git commit --no-verify" {
  run stamp_run claude-code '/usr/bin/git commit --no-verify'
  [[ "$output" == *"deny"* ]]
  [[ "$output" == *"no-verify"* ]]
}

@test "여전히 거부: bash -c 로 감싼 git commit --no-verify" {
  run stamp_run claude-code 'bash -c "git commit --no-verify"'
  [[ "$output" == *"deny"* ]]
  [[ "$output" == *"no-verify"* ]]
}

@test "이제 통과: grep -rn push src/ (git 토큰 없음)" {
  run stamp_run claude-code 'grep -rn push src/'
  [ -z "$output" ]
}

@test "이제 통과: rg -n push (git 토큰 없음)" {
  run stamp_run claude-code 'rg -n push'
  [ -z "$output" ]
}

@test "이제 통과: find . -name '*push*' (git 토큰 없음)" {
  run stamp_run claude-code "find . -name '*push*'"
  [ -z "$output" ]
}

@test "이제 통과: grep -rn commit docs/ (git 토큰 없음)" {
  # "commit" 을 담고 있어 마커 쓰기·건강검진 프리필터(아래, git 토큰 요건과
  # 무관하게 *commit* 만 본다)에는 계속 걸린다. 훅을 온전히 설치해(pre-commit
  # ·pre-push 둘 다) 건강검진 자체의 deny 를 없애 둬야, 여기서 관찰하려는
  # --no-verify/-n 판정만 남는다 — 안 그러면 "게이트 미설치/낡음" deny 와
  # 뒤섞여 무엇이 고쳐졌는지 알 수 없다.
  bash "$PLUGIN_ROOT/scripts/install.sh" install
  run stamp_run claude-code 'grep -rn commit docs/'
  [ -z "$output" ]
}

@test "이제 통과: grep -rn push .github/ (git 토큰 아님 — 경계 검사)" {
  # ".github" 안의 "git" 은 앞 경계('.' 바로 뒤)와 뒤 경계('h' 앞) 양쪽에서
  # 걸러져야 한다. 이 테스트는 그 둘 다를 실제로 확인한다.
  run stamp_run claude-code 'grep -rn push .github/'
  [ -z "$output" ]
}

@test "stdout 에 아무것도 쓰지 않는다" {
  # 커밋으로 보이는 명령 + 훅 미설치 조합의 stdout(건강검진 deny)은
  # tests/health-check.bats 가 다룬다. 여기서는 핸드셰이크 기록 경로
  # 자체가 조용한지만 본다.
  run stamp_run claude-code 'ls -la'
  [ -z "$output" ]
}

@test "재호출하면 마커가 갱신된다" {
  # GNU stat 은 -f 를 --file-system 으로 해석해 종료코드 0으로 헛값을 낸다
  # (hooks/pre-commit 과 동일한 함정). GNU 형식(-c)을 먼저 시도해야 진짜
  # 실패일 때만 BSD 형식(-f)으로 폴백한다.
  #
  # 이 저장소에서 마커 갱신을 지키는 유일한 주장이다. 갱신이 회귀하면 120초가
  # 지난 모든 세션이 "사람"으로 강등돼 커밋이 아무 표시 없이 게이트를 빠져나간다.
  #
  # 예전 판의 `|| [ "$second" -ne 0 ]` 는 이 테스트를 반증 불가능하게 만들었다:
  # touch 로 밀어 넣은 2026-01-01 은 0 이 아니므로 둘째 항이 무조건 참이라
  # 갱신을 전혀 하지 않는 돌연변이도 초록이었다. `-gt "$first"` 만 남기는
  # 것으로도 부족하다 — 갱신된 시각이 first 와 같은 초일 수 있다. 그래서
  # "touch 로 밀어 넣은 값이 아니다" 를 직접 주장한다.
  mtime_of() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }
  stamp_run claude-code
  first=$(mtime_of "$(qdir)/marker/main")
  touch -t 202601010000 "$(qdir)/marker/main"
  touched=$(mtime_of "$(qdir)/marker/main")
  [ "$touched" -ne "$first" ]                 # touch 가 실제로 밀어 넣었는지 확인
  stamp_run claude-code
  second=$(mtime_of "$(qdir)/marker/main")
  [ "$second" -ne "$touched" ]                # 갱신되지 않으면 여기서 걸린다
  [ "$second" -ge "$first" ]
}

# ── D44: 커밋처럼 보이는 명령에서만 마커를 남긴다 ──

@test "커밋이 아닌 명령에서는 마커를 남기지 않는다" {
  # 매 Bash 호출마다 남기면 에이전트가 이 저장소에서 무엇이든 하고 있는 동안
  # 마커가 늘 신선해서, 그 창에 들어온 모든 커밋이 출처와 무관하게 에이전트
  # 커밋으로 보인다. IDE 커밋이 실제로 그렇게 막혔다.
  for c in 'ls -la' 'npm test' 'git status' 'git log --oneline' 'cat README.md'; do
    rm -f "$(qdir)/marker/main"
    stamp_run claude-code "$c"
    [ ! -f "$(qdir)/marker/main" ] || { echo "[$c] 가 마커를 남겼다"; return 1; }
  done
}

@test "커밋처럼 보이는 명령에서는 마커를 남긴다" {
  for c in 'git commit -m x' 'npm test && git commit -am x' 'git commit'; do
    rm -f "$(qdir)/marker/main"
    stamp_run claude-code "$c"
    [ -f "$(qdir)/marker/main" ] || { echo "[$c] 가 마커를 남기지 않았다"; return 1; }
  done
}

# ── D44 종단: 누가 커밋했는지로 갈린다 ──

@test "에이전트가 다른 일을 하는 동안 IDE 커밋은 통과한다" {
  # IDE·GUI git 클라이언트는 git 을 pty 가 아니라 파이프로 띄우므로 TTY
  # 구제(D41)가 닿지 않는다. 유일한 방어선은 "마커가 없다"는 것뿐이다.
  install_hook
  printf 'C1\n' > c.ts; git add c.ts
  stamp_run claude-code 'npm test'          # 에이전트는 커밋이 아닌 일을 하는 중
  run commit_as_human -m x                  # IDE 커밋: 파이프, tty 없음, 에이전트 변수 없음
  [ "$status" -eq 0 ]
}

@test "에이전트가 커밋하려 하면 여전히 막힌다 (대조군)" {
  # 위 테스트가 "게이트를 통째로 꺼서" 통과한 것이 아님을 못 박는다.
  install_hook
  printf 'C1\n' > c.ts; git add c.ts
  stamp_run claude-code 'git commit -m x'   # 에이전트가 커밋 직전
  run commit_as_human -m x
  [ "$status" -ne 0 ]
  [[ "$output" == *"c.ts"* ]]
}

@test "에이전트가 커밋 직전이어도 진짜 터미널 커밋은 통과한다 (TTY 층 유지)" {
  # 에이전트가 찍고 거부당한 직후 사람이 손으로 커밋하는 경우를 구제한다.
  install_hook
  printf 'C1\n' > c.ts; git add c.ts
  stamp_run claude-code 'git commit -m x'
  with_tty env -u CLAUDECODE -u CLAUDE_CODE_SESSION_ID git commit -m x || {
    echo "pty 를 할당하지 못했다 — 이 테스트는 pty 없이는 아무것도 증명하지 못한다" >&2
    return 1
  }
  [ "$TTY_RC" -eq 0 ]
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
