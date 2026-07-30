#!/usr/bin/env bats

load helper

setup() { setup_repo; seed_repo; install_hook; }
teardown() { teardown_repo; }

@test "에이전트 신호가 없으면 통과한다" {
  printf 'C1\n' > c.ts; git add c.ts
  run commit_as_human -m x
  [ "$status" -eq 0 ]
  # 대조군: 같은 훅이 신호만 있으면 (같은 조건에서) 막는다는 것도 확인한다.
  # 이게 없으면 "아무것도 안 하는" 훅도 이 테스트를 통과한다.
  printf 'C2\n' > d.ts; git add d.ts
  stamp
  run commit_as_human -m y
  [ "$status" -ne 0 ]
}

@test "핸드셰이크가 신선하면 미검증 변경을 막는다" {
  printf 'C1\n' > c.ts; git add c.ts
  stamp
  run commit_as_human -m x
  [ "$status" -ne 0 ]
  [[ "$output" == *"c.ts"* ]]
}

@test "covered.tsv 에 있으면 통과한다" {
  printf 'C1\n' > c.ts; git add c.ts
  stamp
  run commit_as_human -m x
  [ "$status" -ne 0 ]              # 대조군: 커버 전엔 막힌다
  mark_covered c.ts
  run commit_as_human -m x
  [ "$status" -eq 0 ]              # 커버 후엔 통과한다
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
  run commit_as_human -m x
  [ "$status" -ne 0 ]              # 대조군: 신선하면 막힌다
  touch -t "$(date -v-5M '+%Y%m%d%H%M' 2>/dev/null || date -d '5 minutes ago' '+%Y%m%d%H%M')" "$(qdir)/agent-session"
  run commit_as_human -m x
  [ "$status" -eq 0 ]              # 낡으면 (같은 스테이징으로) 통과한다
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
  # 대조군: 같은 신선한 핸드셰이크로 내용이 있는 커밋을 하면 막힌다.
  printf 'C1\n' > c.ts; git add c.ts
  run commit_as_human -m y
  [ "$status" -ne 0 ]
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
  stamp
  run commit_as_human -am x
  [ "$status" -ne 0 ]              # 대조군: 커버 전엔 워크트리 내용 기준으로도 막힌다
  [[ "$output" == *"a.ts"* ]]
  mark_covered a.ts                # 워크트리 SHA 로 커버
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

@test "따옴표가 든 경로도 실제 내용으로 판정한다" {
  # core.quotePath=false 는 0x80 이상 바이트만 풀어준다 — 큰따옴표는 -z 없이는
  # 여전히 C-quote 되어 절대 통과할 수 없는 경로가 생긴다.
  printf 'W1\n' > 'we"ird.ts'
  git add 'we"ird.ts'
  stamp
  run commit_as_human -m x
  [ "$status" -ne 0 ]
  [[ "$output" == *'we"ird.ts'* ]]
  mark_covered 'we"ird.ts'
  run commit_as_human -m x
  [ "$status" -eq 0 ]
}

@test "merge 커밋에서는 훅이 실행되지 않아 통과한다" {
  # 주의: git 은 클린 --no-ff 병합에 pre-commit 훅을 아예 부르지 않는다
  # (pre-merge-commit 을 대신 부른다). 그래서 이 테스트는 "돌연변이 훅도
  # 우연히 통과하는" 부류다 — 애초에 훅이 실행되지 않으니 훅 내용과 무관하게
  # 통과한다. 실제 판정 로직을 검증하는 쪽은 아래 "충돌 해소" 테스트다.
  git checkout -qb feat
  printf 'F\n' > f.ts; git add f.ts; commit_as_human -qm feat
  git checkout -q -
  printf 'M\n' > m.ts; git add m.ts; commit_as_human -qm main
  stamp
  run git merge --no-ff feat -m merge
  [ "$status" -eq 0 ]
}

@test "충돌 해소 커밋은 훅이 판정하지 않고 통과한다" {
  # a.ts 를 두 브랜치에서 서로 다르게 고쳐서 진짜 충돌을 만든다.
  git checkout -qb feat
  printf 'F\n' > a.ts; git add a.ts; commit_as_human -qm feat
  git checkout -q -
  printf 'M\n' > a.ts; git add a.ts; commit_as_human -qm main
  git merge --no-ff feat -m merge || true   # 충돌 — MERGE_HEAD 가 남는다
  printf 'RESOLVED\n' > a.ts; git add a.ts
  stamp                                     # 신선한 핸드셰이크로도
  run commit_as_human -m resolved
  [ "$status" -eq 0 ]                       # 커버 여부와 무관하게 통과해야 한다
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
  # 정적 문자열 검사다 — 아무 일도 안 하는 훅이라도 마커만 있으면 통과하는
  # 게 맞다. 판정 로직 검증은 이 테스트의 목적이 아니다.
  grep -q 'KKOCHIKKOCHI-HOOK-v1' "$(hooksdir)/pre-commit"
}

# ── 음성 신호 (TTY) ──

@test "실제 터미널이 있으면 환경변수 신호보다 우선해 통과한다" {
  # git 은 pre-commit 훅의 표준입력만 리다이렉트한다. fd 1/2 에 진짜 pty 가
  # 붙어 있으면 사람이 지금 터미널에 있다는 뜻이고, 남아 있는 CLAUDECODE 같은
  # 환경변수보다 이 신호가 우선해야 한다 (그렇지 않으면 에이전트가 띄운
  # 셸에 사람이 앉아 있어도 구제할 방법이 없다).
  printf 'C1\n' > c.ts; git add c.ts
  run with_tty env CLAUDECODE=1 git commit -m x
  [ "$status" -eq 0 ]
  # 대조군: 같은 CLAUDECODE 값이라도 진짜 터미널이 없으면 (bats 의 run 이
  # 늘 그렇듯) 여전히 막힌다 — 즉 방금 통과한 건 TTY 신호가 실제로 한 일이다.
  # (c.ts 는 이미 위에서 커밋됐으니 새 파일 d.ts 로 다시 스테이징한다 —
  # 안 그러면 "스테이징된 게 없어서" 라는 무관한 이유로 막혀 대조군이 무력해진다.)
  printf 'C2\n' > d.ts; git add d.ts
  run env CLAUDECODE=1 git commit -m y
  [ "$status" -ne 0 ]
}

# ── 신선도 계산의 내구성 ──

@test "mtime 계산이 숫자가 아닌 값을 내도 훅이 죽지 않는다" {
  # GNU coreutils 에서는 stat -f 가 --file-system 으로 해석되어 종료코드
  # 0으로 사람이 읽는 텍스트를 낸다 (실측: Ubuntu 22.04, coreutils 8.32).
  # 그 출력을 산술식에 그대로 넣으면 dash 는 "Illegal number" 로 죽는다.
  # 여기서는 실제 GNU 환경 없이도 그 실패 모드를 흉내내, 숫자가-아니면-0
  # 가드가 실제로 방어하는지 확인한다.
  fakebin="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$fakebin"
  printf '#!/bin/sh\necho "  File: fake filesystem info"\nexit 0\n' > "$fakebin/stat"
  chmod +x "$fakebin/stat"
  printf 'C1\n' > c.ts; git add c.ts
  stamp
  PATH="$fakebin:$PATH" run commit_as_human -m x
  [ "$status" -ne 2 ]
  [[ "$output" != *"Illegal number"* ]]
}
