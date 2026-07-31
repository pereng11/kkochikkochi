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

# ── 원장이 있는데 못 읽는 경우는 "미검증 없음"과 다르게 취급한다 ──
#
# review critical finding 1: 예전에는 pending.sh 가 무슨 이유로 실패하든
# (원장이 없어서 / 원장이 있는데 형식이 깨져서) 전부 "미검증 없음"으로
# 뭉뚱그려 defer 를 지우고 조용히 통과시켰다. 그러면 나쁜 줄 하나가 같은
# 원장에 있는 **다른 정상 파일의 미검증 상태까지** 가려버린다. 아래
# 세 테스트는 그 세 가지 재현(형식이 깨진 줄 / 중간에 끊긴 append / 권한
# 문제)이 전부 block 을 내고 defer 를 지우지 않는지 확인한다.

@test "원장에 형식이 깨진 줄이 있으면 조용히 넘어가지 않고 defer 도 지키지 않는다" {
  printf 'C1\n' > good.ts
  stub_ledger_line good.ts aaa11
  # good.ts 는 정상적으로 미검증인데, 같은 원장에 형식이 깨진 줄이 하나
  # 더 있다 (예: 탭 경로가 잘못 기록된 경우를 흉내).
  printf 'not-a-sha\tbad.ts\tbbb22\tgeneral-purpose\t2026-07-30T00:00:00Z\n' \
    >> "$(qdir)/ledger.tsv"
  mkdir -p "$(qdir)"; : > "$(qdir)/defer"
  run stop_run
  [ "$status" -eq 0 ]
  [ -n "$output" ]                                          # 조용히 넘어가지 않는다
  [ "$(printf '%s' "$output" | jq -r '.decision')" = "block" ]
  [[ "$(printf '%s' "$output" | jq -r '.reason')" == *"손상"* ]]
  [ -e "$(qdir)/defer" ]                                    # 유예를 지우지 않는다
}

@test "원장의 마지막 줄이 중간에 끊겨도 조용히 넘어가지 않는다" {
  printf 'C1\n' > good.ts
  stub_ledger_line good.ts aaa11
  # append 도중 끊긴 것을 흉내: 개행 없이 필드가 모자란 조각만 덧붙인다.
  printf 'deadbeef' >> "$(qdir)/ledger.tsv"
  mkdir -p "$(qdir)"; : > "$(qdir)/defer"
  run stop_run
  [ "$(printf '%s' "$output" | jq -r '.decision')" = "block" ]
  [ -e "$(qdir)/defer" ]
}

@test "원장을 권한 때문에 못 읽어도 조용히 넘어가지 않는다" {
  printf 'C1\n' > good.ts
  stub_ledger_line good.ts aaa11
  mkdir -p "$(qdir)"; : > "$(qdir)/defer"
  chmod 000 "$(qdir)/ledger.tsv"
  run stop_run
  chmod 644 "$(qdir)/ledger.tsv"   # teardown_repo 의 rm -rf 가 확실히 지울 수 있게 되돌린다
  [ "$(printf '%s' "$output" | jq -r '.decision')" = "block" ]
  [ -e "$(qdir)/defer" ]
}
