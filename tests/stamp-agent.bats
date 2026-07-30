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
  first=$(mtime_of "$(qdir)/agent-session")
  touch -t 202601010000 "$(qdir)/agent-session"
  touched=$(mtime_of "$(qdir)/agent-session")
  [ "$touched" -ne "$first" ]                 # touch 가 실제로 밀어 넣었는지 확인
  stamp_run claude-code
  second=$(mtime_of "$(qdir)/agent-session")
  [ "$second" -ne "$touched" ]                # 갱신되지 않으면 여기서 걸린다
  [ "$second" -ge "$first" ]
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
