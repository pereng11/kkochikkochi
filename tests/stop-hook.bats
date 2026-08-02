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

# ── 판정은 종료 코드로 말한다, stderr 문구로 말하지 않는다 ──
#
# review important finding (round 3): stop-gate.sh 가 pending.sh 의 stderr
# 에 있는 "손상" 문자열을 매칭해서 판정 불가를 골라내던 시절, 리뷰는
# pending.sh 의 그 die 메시지 **문구만**(로직은 그대로) 바꿔서 재현했다 —
# 아무 것도 논리적으로는 안 고쳤는데 stop-gate.sh 가 진짜 손상을 "미검증
# 없음"으로 오판하고 defer 를 지웠다. 이제 pending.sh 는 판정 불가를 종료
# 코드 2 로 낸다(스크립트 헤더의 0/1/2 계약). 아래 테스트는 리뷰가 실제로
# 썼던 재현 방법 그대로 — pending.sh 사본의 메시지 문구만 바꾸고 — 여전히
# block 되는지 확인한다. 이 테스트가 깨진다면 누군가 다시 문자열 매칭으로
# 되돌렸다는 뜻이다.
@test "pending.sh 의 메시지 문구만 바뀌어도 rc=2 인 한 여전히 block 한다" {
  printf 'C1\n' > good.ts
  stub_ledger_line good.ts aaa11
  printf 'not-a-sha\tbad.ts\tbbb22\tgeneral-purpose\t2026-07-30T00:00:00Z\n' \
    >> "$(qdir)/ledger.tsv"

  reworded_dir="$BATS_TEST_TMPDIR/reworded-scripts"
  mkdir -p "$reworded_dir"
  # "손상" 이 들어간 die 메시지의 문구만 영어로 바꾼다 — exit 코드(2)는
  # 그대로다. stop-gate.sh 는 이제 이 문구를 보지 않으므로 영향이 없어야
  # 한다.
  sed 's/원장이 손상됐습니다/Ledger format error, please investigate/' \
    "$PLUGIN_ROOT/scripts/pending.sh" > "$reworded_dir/pending.sh"
  cp "$PLUGIN_ROOT/scripts/stop-gate.sh" "$reworded_dir/stop-gate.sh"
  chmod +x "$reworded_dir/pending.sh" "$reworded_dir/stop-gate.sh"

  mkdir -p "$(qdir)"; : > "$(qdir)/defer"
  out="$(jq -n --arg cwd "$PWD" \
      '{hook_event_name:"Stop", session_id:"sess-1", cwd:$cwd, stop_hook_active:false}' \
    | bash "$reworded_dir/stop-gate.sh")"
  [ "$(printf '%s' "$out" | jq -r '.decision')" = "block" ]
  [[ "$(printf '%s' "$out" | jq -r '.reason')" == *"Ledger format error"* ]]
  [ -e "$(qdir)/defer" ]
}
