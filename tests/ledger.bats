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

@test "원장에 손상된 줄이 있으면 거부한다" {
  mkdir -p "$(qdir)"
  printf 'not-a-sha\tc.ts\taaa11\tgeneral-purpose\t2026-07-30T00:00:00Z\n' \
    > "$(qdir)/ledger.tsv"
  run pending_sh --all-unverified
  [ "$status" -eq 1 ]
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
