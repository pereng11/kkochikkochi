#!/usr/bin/env bats
#
# 훅 매니페스트의 `command` 문자열을 **실제로 실행해** 본다.
#
# 왜 이 파일이 있는가: CI 는 두 hooks.json 을 jq 로 문법 검사만 했다. 그런데
# 두 파일은 의도적으로 서로 다른 변수를 쓴다 — Claude Code 는
# `${CLAUDE_PLUGIN_ROOT}`, Codex 는 `${PLUGIN_ROOT}`. 둘 중 하나라도 틀리면
# 경로가 빈 문자열로 펼쳐져 stamp-agent.sh 가 아예 실행되지 않고, 핸드셰이크가
# 남지 않으며, **모든 에이전트 커밋이 "사람" 으로 분류된다.** 이 시스템에서
# 가장 조용하고 가장 파급이 큰 실패인데 행동 커버리지가 전혀 없었다.
#
# 각 매니페스트는 자기 변수만 준 채로 실행한다 (다른 변수는 지운다) —
# 그래야 변수 이름이 뒤바뀐 회귀가 실제로 붉게 뜬다.

load helper

setup() { setup_repo; seed_repo; }
teardown() { teardown_repo; }

payload() {
  jq -n --arg cwd "$PWD" \
    '{tool_name:"Bash", cwd:$cwd, session_id:"sess-manifest", tool_input:{command:"ls -la"}}'
}

hook_command() {  # $1 = 매니페스트 경로
  jq -r '.hooks.PreToolUse[0].hooks[0].command' "$1"
}

@test "Claude Code 매니페스트의 command 가 실제로 핸드셰이크를 남긴다" {
  cmd="$(hook_command "$PLUGIN_ROOT/hooks/hooks.json")"
  [ -n "$cmd" ] && [ "$cmd" != "null" ]
  payload | env -u PLUGIN_ROOT CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash -c "$cmd"
  [ -f "$(qdir)/agent-session" ]
  run cat "$(qdir)/agent-session"
  [[ "$output" == *"claude-code"* ]]
  [[ "$output" == *"sess-manifest"* ]]
}

@test "Codex 매니페스트의 command 가 실제로 핸드셰이크를 남긴다" {
  cmd="$(hook_command "$PLUGIN_ROOT/hooks.json")"
  [ -n "$cmd" ] && [ "$cmd" != "null" ]
  payload | env -u CLAUDE_PLUGIN_ROOT PLUGIN_ROOT="$PLUGIN_ROOT" bash -c "$cmd"
  [ -f "$(qdir)/agent-session" ]
  run cat "$(qdir)/agent-session"
  [[ "$output" == *"codex"* ]]
  [[ "$output" == *"sess-manifest"* ]]
}

@test "매니페스트가 남긴 핸드셰이크로 게이트가 실제로 켜진다 (종단)" {
  # 두 매니페스트 각각에 대해, 그 command 만으로 게이트가 켜지는 데까지 간다.
  for m in "hooks/hooks.json:CLAUDE_PLUGIN_ROOT:PLUGIN_ROOT" "hooks.json:PLUGIN_ROOT:CLAUDE_PLUGIN_ROOT"; do
    manifest="${m%%:*}"; rest="${m#*:}"; var="${rest%%:*}"; other="${rest#*:}"
    setup_repo; seed_repo; install_hook
    printf 'C1\n' > c.ts; git add c.ts

    # 대조군: 핸드셰이크가 없으면 통과한다
    run commit_as_human -m x
    [ "$status" -eq 0 ] || { echo "$manifest: 핸드셰이크 없이도 막혔다"; return 1; }

    printf 'C2\n' > d.ts; git add d.ts
    cmd="$(hook_command "$PLUGIN_ROOT/$manifest")"
    payload | env -u "$other" "$var=$PLUGIN_ROOT" bash -c "$cmd"

    run commit_as_human -m y
    [ "$status" -ne 0 ] || { echo "$manifest: 핸드셰이크 뒤에도 게이트가 켜지지 않았다"; return 1; }
    [[ "$output" == *"d.ts"* ]]
    teardown_repo
  done
}

@test "두 매니페스트가 서로 다른 변수를 쓴다 (뒤섞이지 않았다)" {
  claude="$(hook_command "$PLUGIN_ROOT/hooks/hooks.json")"
  codex="$(hook_command "$PLUGIN_ROOT/hooks.json")"
  [[ "$claude" == *'${CLAUDE_PLUGIN_ROOT}'* ]]
  [[ "$codex" == *'${PLUGIN_ROOT}'* ]]
  [[ "$codex" != *'${CLAUDE_PLUGIN_ROOT}'* ]]
  # 에이전트 이름도 갈려야 한다 — 핸드셰이크 내용에 그대로 들어간다
  [[ "$claude" == *"claude-code"* ]]
  [[ "$codex" == *"codex"* ]]
}

@test "여섯 개 매니페스트가 전부 올바른 JSON 이다" {
  for f in hooks/hooks.json hooks.json \
           .claude-plugin/plugin.json .claude-plugin/marketplace.json \
           .codex-plugin/plugin.json .agents/plugins/marketplace.json; do
    jq . "$PLUGIN_ROOT/$f" > /dev/null || { echo "$f 가 올바른 JSON 이 아니다"; return 1; }
  done
}
