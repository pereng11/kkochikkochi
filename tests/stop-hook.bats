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
