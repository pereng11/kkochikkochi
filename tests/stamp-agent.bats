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
  # GNU stat 은 -f 를 --file-system 으로 해석해 종료코드 0으로 헛값을 낸다
  # (hooks/pre-commit 과 동일한 함정). GNU 형식(-c)을 먼저 시도해야 진짜
  # 실패일 때만 BSD 형식(-f)으로 폴백한다.
  stamp_run claude-code
  first=$(stat -c %Y "$(qdir)/agent-session" 2>/dev/null || stat -f %m "$(qdir)/agent-session")
  touch -t 202601010000 "$(qdir)/agent-session"
  stamp_run claude-code
  second=$(stat -c %Y "$(qdir)/agent-session" 2>/dev/null || stat -f %m "$(qdir)/agent-session")
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
