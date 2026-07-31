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

@test "원장이 손상되면 봉인된 번들이 있어도 손상 알림이 먼저 나가고 개별 조회로 넘어가지 않는다" {
  seal_run stop aaa11 general-purpose
  mkdir -p "$(qdir)"
  printf 'bad\tline\twithout\tenough-fields\n' > "$(qdir)/ledger.tsv"
  run notify_run
  [ "$status" -eq 0 ]
  ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  [[ "$ctx" == *"손상"* ]]
}

@test "pending.sh --bundle 도 원장이 손상되면 exit 2 를 낸다 (bundle-notify 가 기대는 계약)" {
  # bundle-notify.sh 는 --all-unverified 의 rc=2 만으로 손상을 판정하고
  # --bundle 은 그 이후로 아예 부르지 않는다(위 테스트가 확인). 그 설계가
  # 안전한 건 --bundle 도 같은 손상에 대해 반드시 rc=2 를 내기 때문이다 —
  # ledger_unverified() 의 형식 검사가 필터(agent_id) 적용 **이전에** 모든
  # 줄을 훑으므로, 어느 --bundle 을 불러도 같은 결과다. 이 계약이 깨지면
  # (예: 필터가 먼저 걸려 손상된 줄을 건너뛰게 바뀌면) bundle-notify.sh 의
  # "위에서 이미 확인했으니 안전하다"는 가정도 깨진다.
  mkdir -p "$(qdir)"
  printf 'bad\tline\twithout\tenough-fields\n' > "$(qdir)/ledger.tsv"
  run bash "$PLUGIN_ROOT/scripts/pending.sh" --bundle aaa11
  [ "$status" -eq 2 ]
}

@test "정규화가 필요한 원문 agent_id 도 --bundle 조회가 왕복한다 (Critical 수정 회귀)" {
  # 원장의 agent_id 열은 원문 그대로다(hooks/pre-commit 은 정규화하지
  # 않는다). 파일명은 정규화(마침표·슬래시·콜론이 밑줄로 바뀐다)되지만,
  # bundle-notify.sh 는 파일 안의 원문 필드를 디코드해서 조회해야 한다 —
  # 파일명(정규화된 값)을 그대로 넘기면 이 테스트가 실패한다.
  raw='sess.1/agent:9'
  printf 'C1\n' > c.ts
  stub_ledger_line c.ts "$raw"
  seal_run stop "$raw" general-purpose
  # 파일명은 정규화됐는지 확인한다(경로 순회 방지가 여전히 살아있다).
  [ -f "$(qdir)/agents/sess_1_agent_9" ]
  run notify_run
  [ "$status" -eq 0 ]
  ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  [[ "$ctx" == *"$raw"* ]]
}

@test "agent_type 에 탭이 있어도 sealed 판정이 깨지지 않는다 (파일 포맷 강건성)" {
  seal_run start aaa11 $'evil\tinjected'
  run cut -f3 "$(qdir)/agents/aaa11"
  [ -z "$output" ]
}

@test "agent_type 에 개행이 있어도 sealed 판정이 깨지지 않는다 (파일 포맷 강건성)" {
  seal_run start aaa11 $'evil\nmore'
  run cut -f3 "$(qdir)/agents/aaa11"
  [ -z "$output" ]
}

@test "역순(SubagentStart 뒤 PostToolUse, SubagentStop 은 이 턴에 더 안 옴) — PostToolUse 는 조용하고 Stop 이 대신 막는다" {
  printf 'C1\n' > c.ts
  stub_ledger_line c.ts aaa11
  seal_run start aaa11 general-purpose
  run notify_run
  [ -z "$output" ]

  # 이번이 이 턴의 마지막 서브에이전트 호출이라 더 이상 PostToolUse(Task)
  # 가 오지 않아도, Stop 은 봉인 여부와 무관하게 원장 전체를 보므로 턴
  # 끝에서 반드시 잡는다 (docs/.../design.md §3 에 이 트레이드오프를 적었다).
  run bash "$PLUGIN_ROOT/scripts/stop-gate.sh" <<< "$(jq -n --arg cwd "$PWD" \
    '{hook_event_name:"Stop", session_id:"sess-1", cwd:$cwd, stop_hook_active:false}')"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.decision')" = "block" ]
}

@test "같은 (sha,path) 를 도는 번들과 기록 없는 번들이 공유해도 기록 없는 쪽은 요구된다 (Important 2 수정 회귀)" {
  # AAA 는 도는 중(SubagentStart 만 왔다), BBB 는 agents/ 에 아무 기록도
  # 없다. 둘이 같은 경로에 같은 내용을 커밋해 (sha,path) 가 겹친다.
  # pending.sh --all-unverified 는 agent_id 를 버리고 (sha,path) 만 중복
  # 제거해 내므로, "도는 번들의 몫을 뺀다"를 (sha,path) 쌍 단위로 하면
  # BBB 의 몫까지 함께 사라진다 — agent_id 단위로 판단해야 한다.
  printf 'SAME\n' > c.ts
  stub_ledger_line c.ts aaa11
  stub_ledger_line c.ts bbb22
  seal_run start aaa11 general-purpose
  run notify_run
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  [[ "$ctx" == *"c.ts"* ]]
}
