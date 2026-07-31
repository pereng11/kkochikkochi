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

@test "원장이 손상되면 폴백 대신 손상 알림을 낸다 (exit 2 를 미검증-없음과 뭉개지 않는다)" {
  # ledger.tsv 에 필드 수가 4개인 손상된 줄을 심는다 (정상은 5개).
  # pending.sh --all-unverified 는 이 경우 exit 2("판정 불가")를 낸다 —
  # exit 1("미검증 없음")과 뭉개면 이 훅이 조용히 통과시켜 버린다.
  mkdir -p "$(qdir)"
  printf 'bad\tline\twithout\tenough-fields\n' > "$(qdir)/ledger.tsv"
  run notify_run
  [ "$status" -eq 0 ]
  ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  [[ "$ctx" == *"손상"* ]]
}
