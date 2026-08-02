#!/usr/bin/env bats
#
# 원장은 훅이 발표한 답이다 (D40). 판정은 pending.sh 한 곳에만 있다 (D45).

load helper

setup() { setup_repo; seed_repo; }
teardown() { teardown_repo; }

pending_sh() { bash "$PLUGIN_ROOT/scripts/pending.sh" "$@"; }

@test "--bundle 은 그 agent_id 의 항목만 낸다" {
  printf 'C1\n' > c.ts; printf 'D1\n' > d.ts
  stub_ledger_line c.ts aaa11
  stub_ledger_line d.ts bbb22
  run pending_sh --bundle aaa11
  [ "$status" -eq 0 ]
  [ "$output" = "$(git hash-object c.ts)"$'\t'"c.ts" ]
}

@test "--bundle 은 이미 검증된 항목을 빼고 낸다" {
  printf 'C1\n' > c.ts
  stub_ledger_line c.ts aaa11
  stub_covered_line c.ts
  run pending_sh --bundle aaa11
  [ "$status" -eq 1 ]
  [[ "$output" == *"검증할 것이 없습니다"* ]]
}

@test "--all-unverified 는 모든 에이전트의 미검증을 낸다" {
  printf 'C1\n' > c.ts; printf 'D1\n' > d.ts
  stub_ledger_line c.ts aaa11
  stub_ledger_line d.ts bbb22
  run pending_sh --all-unverified
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" = "2" ]
}

@test "원장이 없으면 --all-unverified 는 거부한다" {
  run pending_sh --all-unverified
  [ "$status" -eq 1 ]
}

@test "원장이 없으면 covered.tsv 부트스트랩도 생기지 않는다 (review important 3 재발 방지)" {
  # Task 4 는 covered.tsv 부트스트랩을 --bundle/--all-unverified 분기 안으로
  # 옮겨서, qdir 조차 없는 새 레포에서 인자 없이 pending.sh 를 부르는 정상
  # 경로가 covered.tsv 를 생성하는 부작용을 막았다. 이 태스크에서 원장
  # 존재/읽기 검사를 그 부트스트랩보다 **뒤에** 두면, 원장이 없는 (그리고
  # stop-gate.sh 가 매 턴 타는) 흔한 경로에서 다시 그 부작용이 살아난다 —
  # 이번엔 "드문 사고"가 아니라 "항상 일어나는 일"이 되어 더 나쁘다.
  run pending_sh --all-unverified
  [ "$status" -eq 1 ]
  [ ! -e "$(qdir)/covered.tsv" ]
}

@test "원장에 손상된 줄이 있으면 거부한다 (2, 1 이 아니다)" {
  # 종료 코드는 1(미검증 없음)이 아니라 2(판정 불가)다 — "원장이 없다"와
  # "원장이 있는데 못 읽는다"는 서로 다른 사유이고, 두 사유가 같은 코드를
  # 쓰면 stop-gate.sh 같은 호출자가 종료 코드만으로 못 가른다(review critical
  # finding 1 이 재발한 지점 — 자세한 내막은 이 파일 끝의 "종료 코드 계약"
  # 절 참고).
  mkdir -p "$(qdir)"
  printf 'not-a-sha\tc.ts\taaa11\tgeneral-purpose\t2026-07-30T00:00:00Z\n' \
    > "$(qdir)/ledger.tsv"
  run pending_sh --all-unverified
  [ "$status" -eq 2 ]
  [ "$status" -ne 1 ]
  [[ "$output" == *"손상"* ]]
}

@test "세 모드가 같은 출력 형식을 낸다" {
  printf 'C1\n' > c.ts; git add c.ts
  stub_ledger_line c.ts aaa11
  for mode in "" "--bundle aaa11" "--all-unverified"; do
    # shellcheck disable=SC2086  # 모드 인자를 일부러 분리한다
    run pending_sh $mode
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" | awk -F'\t' '
      NF != 2 || length($1) != 40 || $2 == "" { exit 1 }' || return 1
  done
}

@test "번들을 통과 기록하면 그 번들이 비워진다 (왕복)" {
  printf 'C1\n' > c.ts; git add c.ts
  stub_ledger_line c.ts aaa11

  printf '%s' '{"questions":[{"axis":"facts","q":"무엇이 바뀌었나?","evidence":"x:1","format":"choice","answer":"A","correct":"A","attempts":1,"gave_up":false}]}' \
    | bash "$PLUGIN_ROOT/scripts/record-pass.sh" --bundle aaa11
  [ "$?" -eq 0 ]

  run bash "$PLUGIN_ROOT/scripts/pending.sh" --bundle aaa11
  [ "$status" -eq 1 ]
}

# ── 종료 코드 계약: 0 = 목록 / 1 = 미검증 없음 / 2 = 판정 불가 (원장 모드) ──
#
# review: stop-gate.sh 는 이제 이 세 코드만 보고 분기한다(prose 매칭 아님).
# 이 절은 그 계약을 원장 모드(--bundle/--all-unverified)에서 코드
# 하나하나 못박는다 — current 모드 쪽은 tests/pending.bats 에 있다.

@test "종료 코드 계약(원장) — 미검증 목록이 있으면 0" {
  printf 'C1\n' > c.ts
  stub_ledger_line c.ts aaa11
  run pending_sh --all-unverified
  [ "$status" -eq 0 ]
}

@test "종료 코드 계약(원장) — 원장이 없으면 1" {
  run pending_sh --all-unverified
  [ "$status" -eq 1 ]
}

@test "종료 코드 계약(원장) — 원장 형식이 깨지면 2, 1 이 아니다" {
  mkdir -p "$(qdir)"
  printf 'not-a-sha\tc.ts\taaa11\tgeneral-purpose\t2026-07-30T00:00:00Z\n' \
    > "$(qdir)/ledger.tsv"
  run pending_sh --all-unverified
  [ "$status" -eq 2 ]
  [ "$status" -ne 1 ]
}
