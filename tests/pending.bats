#!/usr/bin/env bats
#
# scripts/pending.sh — 검증 대상 결정 규칙의 **유일한 구현**.
#
# 이 파일이 지키는 계약은 하나다: 스킬이 문항을 만들 때 보는 집합과
# record-pass.sh 가 기록하는 집합이 **언제나 같다**. 예전에는 SKILL.md 가
# pending 을 신선도 검사 없이 읽고 record-pass.sh 는 900초를 요구해서, 창이
# 지나면 둘이 서로 다른 파일 집합을 가리켰다 — 사용자가 A 를 풀면 B 가
# 검증된 것으로 기록됐다.

load helper

setup() { setup_repo; seed_repo; }
teardown() { teardown_repo; }

pending_sh() { bash "$PLUGIN_ROOT/scripts/pending.sh"; }

# record-pass.sh 가 실제로 기록한 (sha, path) 만 뽑는다 — pass_id 는 뺀다.
recorded() { cut -f1,2 "$(qdir)/covered.tsv"; }

@test "스테이징만 있으면 git diff --cached 로 계산한다" {
  printf 'C1\n' > c.ts; git add c.ts
  run pending_sh
  [ "$status" -eq 0 ]
  [ "$output" = "$(git hash-object c.ts)"$'\t'"c.ts" ]
}

@test "커밋될 것이 없으면 거부한다" {
  run pending_sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"커밋될 내용이 없습니다"* ]]
}

@test "신선한 pending 이 있으면 그것을 쓴다 (진짜 인덱스보다 우선)" {
  printf 'C1\n' > c.ts; git add c.ts
  mkdir -p "$(qdir)"
  printf '%s\tworktree-only.ts\n' "$NULL_SHA" > "$(qdir)/pending"
  run pending_sh
  [ "$status" -eq 0 ]
  [ "$output" = "${NULL_SHA}"$'\t'"worktree-only.ts" ]
}

@test "낡은 pending 은 무시하고 폴백한다" {
  printf 'C1\n' > c.ts; git add c.ts
  mkdir -p "$(qdir)"
  printf '%s\tghost.ts\n' "$NULL_SHA" > "$(qdir)/pending"
  touch -t 202601010000 "$(qdir)/pending"
  run pending_sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"c.ts"* ]]
  [[ "$output" != *"ghost.ts"* ]]
}

# ── 계약: 스킬이 보는 것 == record-pass.sh 가 기록하는 것 ──

@test "낡은 pending 에서도 스킬과 기록자가 같은 집합을 본다" {
  # 이것이 회귀 테스트다. 예전에는 스킬이 ghost.ts 를 퀴즈하고 기록자는
  # c.ts 를 기록해서, 사용자가 한 번도 본 적 없는 c.ts 가 검증된 것으로
  # 남고 커밋이 통과했다.
  install_hook
  printf 'C1\n' > c.ts; git add c.ts
  mkdir -p "$(qdir)"
  printf '1111111111111111111111111111111111111111\tghost.ts\n' > "$(qdir)/pending"
  touch -t 202601010000 "$(qdir)/pending"

  skill_view="$(pending_sh)"
  run record_pass
  [ "$status" -eq 0 ]
  [ "$(recorded)" = "$skill_view" ]
  [[ "$skill_view" != *"ghost.ts"* ]]
}

@test "신선한 pending 에서도 스킬과 기록자가 같은 집합을 본다" {
  install_hook
  printf 'A2\n' > a.ts                       # 워크트리만 — 훅이 임시 인덱스를 본다
  stamp
  run commit_as_human -am x
  [ "$status" -ne 0 ]

  skill_view="$(pending_sh)"
  [[ "$skill_view" == *"a.ts"* ]]
  run record_pass
  [ "$status" -eq 0 ]
  [ "$(recorded)" = "$skill_view" ]
}

# ── 손상된 목록은 조용히 성공하지 않는다 ──

@test "잘린 pending 줄은 거부한다 (조용한 성공 금지)" {
  # 예전에는 record-pass.sh 가 `sha<TAB><TAB>pass_id` 를 쓰고 성공을 보고했다.
  # 사용자는 통과했다는 말을 듣지만 게이트는 그대로 막혀 있었다.
  install_hook
  printf 'C1\n' > c.ts; git add c.ts
  mkdir -p "$(qdir)"
  printf '1111111111111111111111111111111111111111\n' > "$(qdir)/pending"   # 경로 없음

  run pending_sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"손상"* ]]

  run record_pass
  [ "$status" -ne 0 ]                        # 성공을 보고하지 않는다
  [ ! -f "$(qdir)/covered.tsv" ]             # 쓰레기 줄을 남기지도 않는다
}

@test "경로에 탭이 든 pending 줄도 거부한다" {
  install_hook
  printf 'C1\n' > c.ts; git add c.ts
  mkdir -p "$(qdir)"
  printf '1111111111111111111111111111111111111111\ta\tb.ts\n' > "$(qdir)/pending"
  run pending_sh
  [ "$status" -eq 1 ]
  run record_pass
  [ "$status" -ne 0 ]
}

@test "SHA 가 40자리 16진수가 아니면 거부한다" {
  install_hook
  printf 'C1\n' > c.ts; git add c.ts
  mkdir -p "$(qdir)"
  printf 'zzzz\tc.ts\n' > "$(qdir)/pending"
  run pending_sh
  [ "$status" -eq 1 ]
}

@test "신선도 규칙이 pending.sh 한 곳에만 있다" {
  # 규칙이 두 벌이 되는 순간 이 프로젝트에서 반복된 드리프트가 다시 시작된다.
  # record-pass.sh 와 SKILL.md 는 창 값을 스스로 알아서는 안 된다.
  run grep -c 'PENDING_FRESH_SECS' "$PLUGIN_ROOT/scripts/pending.sh"
  [ "$output" -ge 1 ]
  ! grep -q 'PENDING_FRESH_SECS' "$PLUGIN_ROOT/scripts/record-pass.sh"
  ! grep -q '900' "$PLUGIN_ROOT/skills/kkochikkochi/SKILL.md"
  # 그리고 둘 다 실제로 pending.sh 를 부른다
  grep -q 'pending.sh' "$PLUGIN_ROOT/scripts/record-pass.sh"
  grep -q 'pending.sh' "$PLUGIN_ROOT/skills/kkochikkochi/SKILL.md"
}
