#!/usr/bin/env bats

load helper

setup() { setup_repo; seed_repo; install_hook; }
teardown() { teardown_repo; }

@test "에이전트 신호가 없으면 통과한다" {
  printf 'C1\n' > c.ts; git add c.ts
  run commit_as_human -m x
  [ "$status" -eq 0 ]
}

@test "핸드셰이크가 신선하면 미검증 변경을 막는다" {
  printf 'C1\n' > c.ts; git add c.ts
  stamp
  run commit_as_human -m x
  [ "$status" -ne 0 ]
  [[ "$output" == *"c.ts"* ]]
}

@test "covered.tsv 에 있으면 통과한다" {
  printf 'C1\n' > c.ts; mark_covered c.ts; git add c.ts
  stamp
  run commit_as_human -m x
  [ "$status" -eq 0 ]
}

@test "커버된 뒤 내용을 고치면 다시 막는다" {
  printf 'C1\n' > c.ts; mark_covered c.ts
  printf 'C2\n' > c.ts; git add c.ts
  stamp
  run commit_as_human -m x
  [ "$status" -ne 0 ]
}

@test "마커가 낡으면 통과한다" {
  printf 'C1\n' > c.ts; git add c.ts
  stamp
  touch -t "$(date -v-5M '+%Y%m%d%H%M' 2>/dev/null || date -d '5 minutes ago' '+%Y%m%d%H%M')" "$(qdir)/agent-session"
  run commit_as_human -m x
  [ "$status" -eq 0 ]
}

@test "CLAUDECODE 환경변수만 있어도 게이트가 켜진다" {
  printf 'C1\n' > c.ts; git add c.ts
  run env CLAUDECODE=1 git commit -m x
  [ "$status" -ne 0 ]
}

@test "커밋할 내용이 없으면 통과한다" {
  stamp
  run commit_as_human --allow-empty -m x
  [ "$status" -eq 0 ]
}

# ── v1 을 무너뜨린 명령 형태들. 전부 막혀야 한다 ──

@test "메시지 안의 -- 가 게이트를 무력화하지 않는다" {
  printf 'A2\n' > a.ts
  stamp
  run commit_as_human -am 'fix: handle -- separator'
  [ "$status" -ne 0 ]
  [[ "$output" == *"a.ts"* ]]
}

@test "맨 pathspec 도 막힌다" {
  printf 'A2\n' > a.ts
  stamp
  run commit_as_human -m x a.ts
  [ "$status" -ne 0 ]
  [[ "$output" == *"a.ts"* ]]
}

@test "--pathspec-from-file 도 막힌다" {
  printf 'A2\n' > a.ts
  printf 'a.ts\n' > list
  stamp
  run commit_as_human --pathspec-from-file=list -m x
  [ "$status" -ne 0 ]
  [[ "$output" == *"a.ts"* ]]
}

@test "-a 는 워크트리 내용으로 판정한다" {
  printf 'A2\n' > a.ts
  mark_covered a.ts          # 워크트리 SHA 로 커버
  stamp
  run commit_as_human -am x
  [ "$status" -eq 0 ]
}

@test "비ASCII 경로도 실제 SHA 로 판정한다" {
  printf '한글2\n' > 한글.ts
  git add 한글.ts
  stamp
  run commit_as_human -m x
  [ "$status" -ne 0 ]
  # NULL_SHA 로 떨어지지 않았는지 확인: 커버하면 통과해야 한다
  mark_covered 한글.ts
  run commit_as_human -m x
  [ "$status" -eq 0 ]
}

@test "merge 커밋에서는 훅이 실행되지 않아 통과한다" {
  git checkout -qb feat
  printf 'F\n' > f.ts; git add f.ts; commit_as_human -qm feat
  git checkout -q -
  printf 'M\n' > m.ts; git add m.ts; commit_as_human -qm main
  stamp
  run git merge --no-ff feat -m merge
  [ "$status" -eq 0 ]
}

# ── 체이닝 ──

@test "체이닝된 훅이 먼저 실행되고 거부하면 즉시 끝난다" {
  printf '#!/bin/sh\necho CHAINED_RAN >&2\nexit 7\n' > "$(hooksdir)/pre-commit.kkochikkochi-chained"
  chmod +x "$(hooksdir)/pre-commit.kkochikkochi-chained"
  printf 'C1\n' > c.ts; git add c.ts
  stamp
  run "$(hooksdir)/pre-commit"
  [ "$status" -eq 7 ]
  [[ "$output" == *"CHAINED_RAN"* ]]
  [[ "$output" != *"KkochiKkochi"* ]]
}

@test "체이닝된 훅이 통과하면 우리 판정으로 넘어간다" {
  printf '#!/bin/sh\nexit 0\n' > "$(hooksdir)/pre-commit.kkochikkochi-chained"
  chmod +x "$(hooksdir)/pre-commit.kkochikkochi-chained"
  printf 'C1\n' > c.ts; git add c.ts
  stamp
  run commit_as_human -m x
  [ "$status" -ne 0 ]
  [[ "$output" == *"c.ts"* ]]
}

@test "훅에 자기 식별 마커가 들어 있다" {
  grep -q 'KKOCHIKKOCHI-HOOK-v1' "$(hooksdir)/pre-commit"
}
