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

# 커밋처럼 보이는 명령을 쓴다 — 핸드셰이크는 이제 그 경우에만 남는다 (D44).
payload() {
  jq -n --arg cwd "$PWD" \
    '{tool_name:"Bash", cwd:$cwd, session_id:"sess-manifest", tool_input:{command:"git commit -m x"}}'
}

hook_command() {  # $1 = 매니페스트 경로
  jq -r '.hooks.PreToolUse[0].hooks[0].command' "$1"
}

@test "Claude Code 매니페스트의 command 가 실제로 핸드셰이크를 남긴다" {
  cmd="$(hook_command "$PLUGIN_ROOT/hooks/hooks.json")"
  [ -n "$cmd" ] && [ "$cmd" != "null" ]
  payload | env -u PLUGIN_ROOT CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash -c "$cmd"
  [ -f "$(qdir)/marker/main" ]
  run cat "$(qdir)/marker/main"
  [[ "$output" == *"claude-code"* ]]
  [[ "$output" == *"sess-manifest"* ]]
}

@test "Codex 매니페스트의 command 가 실제로 핸드셰이크를 남긴다" {
  cmd="$(hook_command "$PLUGIN_ROOT/hooks.json")"
  [ -n "$cmd" ] && [ "$cmd" != "null" ]
  payload | env -u CLAUDE_PLUGIN_ROOT PLUGIN_ROOT="$PLUGIN_ROOT" bash -c "$cmd"
  [ -f "$(qdir)/marker/main" ]
  run cat "$(qdir)/marker/main"
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

@test "Codex 매니페스트도 서브에이전트 훅을 등록한다" {
  # 계획이 서 있던 "Codex 페이로드에는 agent_id 가 없다"는 전제는 거짓이다.
  # openai/codex 의 생성된 스키마가 agent_id·agent_type 을 PreToolUse·
  # PostToolUse 에 optional, SubagentStart·SubagentStop 에 required 로
  # 정의한다. 잡는 층이 하나도 없던 상태를 닫는다.
  for key in Stop PostToolUse SubagentStart SubagentStop; do
    run jq -e --arg k "$key" '.hooks | has($k)' "$PLUGIN_ROOT/hooks.json"
    [ "$status" -eq 0 ] || { echo "$key 가 없다"; return 1; }
  done
}

@test "Codex 의 PostToolUse matcher 는 Task 가 아니라 spawn_agent 다" {
  # codex-rs/core/src/tools/hook_names.rs — 서브에이전트 생성 도구의
  # 직렬화 이름은 spawn_agent 이고 matcher alias 는 Agent 다. Task 를
  # 쓰면 등록은 되지만 아무것도 매칭하지 않아 조용히 돌지 않는다.
  run jq -r '.hooks.PostToolUse[0].matcher' "$PLUGIN_ROOT/hooks.json"
  [ "$output" = "spawn_agent" ]
}

@test "Codex 매니페스트의 새 훅 command 가 전부 실제로 실행된다" {
  for path in '.hooks.Stop[0].hooks[0].command' \
              '.hooks.PostToolUse[0].hooks[0].command' \
              '.hooks.SubagentStart[0].hooks[0].command' \
              '.hooks.SubagentStop[0].hooks[0].command'; do
    cmd="$(jq -r "$path" "$PLUGIN_ROOT/hooks.json")"
    [ -n "$cmd" ] && [ "$cmd" != "null" ]
    jq -n --arg cwd "$PWD" \
      '{session_id:"sess-m", cwd:$cwd, agent_id:"aaa11", agent_type:"general-purpose"}' \
      | env -u CLAUDE_PLUGIN_ROOT PLUGIN_ROOT="$PLUGIN_ROOT" bash -c "$cmd"
    [ "$?" -eq 0 ] || return 1
  done
}

@test "Codex 매니페스트의 모든 command 가 PLUGIN_ROOT 를 쓴다" {
  # 변수 이름이 뒤바뀌면 경로가 빈 문자열로 펼쳐져 스크립트가 아예 실행되지
  # 않는다 — 이 시스템에서 가장 조용한 실패다.
  run jq -r '[.hooks[][].hooks[].command] | .[]' "$PLUGIN_ROOT/hooks.json"
  [[ "$output" == *'${PLUGIN_ROOT}'* ]]
  [[ "$output" != *'${CLAUDE_PLUGIN_ROOT}'* ]]
}

@test "매니페스트가 없는 하네스는 마커가 없어 통과한다" {
  # 지원 목록에 없는 에이전트는 stamp-agent.sh 가 돌지 않아 marker/ 가
  # 비고, pre-commit 이 D35(애매하면 통과)로 흘려보낸다. 의도된 fallback
  # 인데 지금까지 못이 박혀 있지 않았다.
  install_hook
  printf 'C1\n' > c.ts; git add c.ts
  [ ! -d "$(qdir)/marker" ]
  run commit_as_human -m x
  [ "$status" -eq 0 ]
}

@test "여섯 개 매니페스트가 전부 올바른 JSON 이다" {
  for f in hooks/hooks.json hooks.json \
           .claude-plugin/plugin.json .claude-plugin/marketplace.json \
           .codex-plugin/plugin.json .agents/plugins/marketplace.json; do
    jq . "$PLUGIN_ROOT/$f" > /dev/null || { echo "$f 가 올바른 JSON 이 아니다"; return 1; }
  done
}
