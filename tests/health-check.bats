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
