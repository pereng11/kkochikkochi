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
  stub_covered_line c.ts
  run commit_as_human -m x
  [ "$status" -eq 0 ]              # 커버 후엔 통과한다
}

@test "커버된 뒤 내용을 고치면 다시 막는다" {
  printf 'C1\n' > c.ts; stub_covered_line c.ts
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
  # FRESH_SECS(600초) 밖으로 넉넉히 민다. 창 값을 바꿀 때 이 숫자도 함께
  # 봐야 한다 — 창보다 짧게 밀면 "낡았다"를 검증하지 못하고 조용히 통과한다.
  touch -t "$(date -v-30M '+%Y%m%d%H%M' 2>/dev/null || date -d '30 minutes ago' '+%Y%m%d%H%M')" "$(qdir)/marker/main"
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
  stub_covered_line a.ts                # 워크트리 SHA 로 커버 (훅 단독 판정만 본다)
  run commit_as_human -am x
  [ "$status" -eq 0 ]
}

@test "C1: git commit -am 이 진짜 record-pass.sh 왕복으로 풀린다" {
  # 예전에는 여기서 stub_covered_line 을 썼고, 그 스텁이 *올바른*
  # record-pass.sh 가 낼 법한 줄을 내주는 바람에 이 테스트가 초록인 채로
  # 실제 writer 는 그 줄을 만들어낼 수조차 없었다 (영구 교착).
  #
  # git 은 -a 커밋에서 훅에게 임시 인덱스를 물려주므로(GIT_INDEX_FILE=
  # .../index.lock), 훅 밖에서 도는 record-pass.sh 의 git diff --cached 는
  # 진짜 인덱스(비어 있음)를 본다. 훅이 pending 을 발표하지 않으면
  # record-pass.sh 는 "커밋될 내용이 없습니다"로 죽고, 다시 커밋해도 같은
  # 곳에서 막혀 HEAD 가 영원히 움직이지 않는다.
  printf 'A2\n' > a.ts             # 워크트리만 수정, 스테이징 안 함
  stamp
  run commit_as_human -am x
  [ "$status" -ne 0 ]
  [[ "$output" == *"a.ts"* ]]

  run record_pass
  [ "$status" -eq 0 ]

  run commit_as_human -am x
  [ "$status" -eq 0 ]              # 라운드 2 는 통과해야 한다
  run git log --oneline
  [[ "$output" == *"x"* ]]         # HEAD 가 실제로 움직였다
}

@test "C1: git commit -- <path> 가 그 커밋에 없는 파일을 기록하지 않는다" {
  printf 'T\n' > tracked.txt; printf 'O\n' > other.txt
  git add tracked.txt other.txt; commit_as_human -qm base
  printf 'T2\n' > tracked.txt      # 워크트리만
  printf 'O2\n' > other.txt; git add other.txt   # 이쪽은 스테이징됨
  stamp
  run commit_as_human -m x -- tracked.txt
  [ "$status" -ne 0 ]
  [[ "$output" == *"tracked.txt"* ]]

  run record_pass
  [ "$status" -eq 0 ]
  # 기록된 것은 이 커밋에 실제로 담기는 tracked.txt 여야 한다.
  # 폴백(진짜 인덱스)을 타면 other.txt — 이 커밋에 들어가지도 않는 파일 — 이 기록된다.
  run cut -f2 "$(qdir)/covered.tsv"
  [[ "$output" == *"tracked.txt"* ]]
  [[ "$output" != *"other.txt"* ]]

  run commit_as_human -m x -- tracked.txt
  [ "$status" -eq 0 ]
}

@test "C1: pending 은 기록에 성공하면 소비되어 사라진다" {
  printf 'A2\n' > a.ts
  stamp
  run commit_as_human -am x
  [ "$status" -ne 0 ]
  [ -f "$(qdir)/pending" ]         # 훅이 자기 답을 발표했다
  run record_pass
  [ "$status" -eq 0 ]
  [ ! -f "$(qdir)/pending" ]       # 소비됐다 — 다음 /kk 가 낡은 집합을 집어먹지 않는다
}

@test "C1: 낡은 pending 은 무시하고 git diff --cached 로 폴백한다" {
  printf 'C1\n' > c.ts; git add c.ts
  stamp
  run commit_as_human -m x
  [ "$status" -ne 0 ]
  [ -f "$(qdir)/pending" ]
  # pending 에 지금 스테이징과 무관한 쓰레기를 넣고 신선도 창(900초) 밖으로 민다
  printf '%s\tghost.ts\n' "$NULL_SHA" > "$(qdir)/pending"
  touch -t 202601010000 "$(qdir)/pending"
  run record_pass
  [ "$status" -eq 0 ]
  run cut -f2 "$(qdir)/covered.tsv"
  [[ "$output" == *"c.ts"* ]]
  [[ "$output" != *"ghost.ts"* ]]
}

@test "비ASCII 경로도 실제 SHA 로 판정한다" {
  printf '한글2\n' > 한글.ts
  git add 한글.ts
  stamp
  run commit_as_human -m x
  [ "$status" -ne 0 ]
  # NULL_SHA 로 떨어지지 않았는지 확인: 커버하면 통과해야 한다
  stub_covered_line 한글.ts
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
  stub_covered_line 'we"ird.ts'
  run commit_as_human -m x
  [ "$status" -eq 0 ]
}

@test "역슬래시가 든 경로도 실제 내용으로 판정한다" {
  # -z 로 따옴표 문제는 풀었지만, covered.tsv 대조에 awk -v 를 쓰면 그
  # 값 자체에 이스케이프 처리가 걸려 역슬래시가 사라진다 (awk -v p='a\sb'
  # 는 'asb' 가 된다). ENVIRON 을 거치지 않으면 이 경로는 아무리 커버해도
  # 영원히 통과하지 못한다.
  #
  # 주의: \s 는 표준 이스케이프가 아니라서 mawk(우분투 기본 awk)는 애초에
  # 안 건드린다 — 이 케이스 하나만으로는 CI의 기본 awk에서 회귀가 나도
  # 안 걸린다. 모든 방언에서 걸리는 대조군은 바로 아래 \t 케이스다.
  printf 'W2\n' > 'back\slash.ts'
  git add 'back\slash.ts'
  stamp
  run commit_as_human -m x
  [ "$status" -ne 0 ]
  [[ "$output" == *'back\slash.ts'* ]]
  stub_covered_line 'back\slash.ts'
  run commit_as_human -m x
  [ "$status" -eq 0 ]
}

@test "역슬래시-t 경로는 모든 awk 방언에서 회귀를 잡는다" {
  # \t 는 \s 와 달리 표준 이스케이프라서 gawk·BSD awk·mawk 전부 -v 값에서
  # 진짜 탭으로 바꿔 버린다. 그러니 이 경로(문자 그대로 \ 다음에 t) 하나면
  # ENVIRON 없이 -v 로 되돌리는 회귀를 CI의 기본 awk(mawk)에서도 잡는다.
  # (파일명 안의 리터럴 '\t' 두 글자이지 실제 탭 바이트가 아니다 — 실제 탭이
  # 든 경로는 covered.tsv 자체가 탭 구분이라 별개의, 범위 밖 한계다.)
  printf 'W3\n' > 'tab\there.ts'
  git add 'tab\there.ts'
  stamp
  run commit_as_human -m x
  [ "$status" -ne 0 ]
  [[ "$output" == *'tab\there.ts'* ]]
  stub_covered_line 'tab\there.ts'
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

  # 대조군을 먼저 본다: 통과시킨 것이 MERGE_HEAD 때문임을 못 박는다. 마커를
  # 잠깐 치우면 똑같은 스테이징·똑같은 핸드셰이크로 막혀야 한다. 이게 없으면
  # "아무것도 안 하는 훅"도 이 테스트를 통과한다. (커밋을 먼저 성공시켜 버리면
  # 스테이징이 비어 대조군이 "커밋할 것 없음"으로 무력해진다.)
  merge_head="$(git rev-parse --git-path MERGE_HEAD)"
  mv "$merge_head" "$merge_head.stash"
  run commit_as_human -m resolved
  [ "$status" -ne 0 ]
  [[ "$output" == *"a.ts"* ]]

  mv "$merge_head.stash" "$merge_head"
  run commit_as_human -m resolved
  [ "$status" -eq 0 ]                       # 커버 여부와 무관하게 통과해야 한다
}

@test "MERGE_HEAD 말고 다른 진행중 마커도 전부 통과시킨다" {
  # 탈출 목록이 MERGE_HEAD 하나로 줄어드는 돌연변이를 잡는다. cherry-pick·
  # revert·rebase 는 이번 세션에 새로 쓴 코드가 아니라 다른 커밋의 내용을
  # 그대로 올리는 것이므로 퀴즈 대상이 아니다.
  #
  # 마커마다 새 파일을 쓴다 — 통과한 커밋이 스테이징을 비워 다음 회차의
  # 대조군이 "커밋할 것 없음"으로 무력해지는 것을 피하기 위해서다.
  for marker in CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply; do
    f="m_$marker.ts"
    printf '%s\n' "$marker" > "$f"; git add "$f"
    stamp

    # 대조군: 마커가 없으면 막힌다
    run commit_as_human -m "x-$marker"
    [ "$status" -ne 0 ] || { echo "대조군 실패: $marker 없이도 통과했다"; return 1; }
    [[ "$output" == *"$f"* ]]

    path="$(git rev-parse --git-path "$marker")"
    case "$marker" in
      rebase-*) mkdir -p "$path" ;;
      *) git rev-parse HEAD > "$path" ;;
    esac
    run commit_as_human -m "x-$marker"
    [ "$status" -eq 0 ] || { echo "marker=$marker 에서 통과하지 않았다: $output"; return 1; }
    rm -rf "$path"
  done
}

@test "스테이징된 삭제도 게이트 대상이다 (null SHA 를 건너뛰지 않는다)" {
  # --raw 는 삭제된 파일에 40개의 0 SHA 를 준다. 훅이 그 SHA 를 "빈 값"으로
  # 오해하고 건너뛰면, 스테이징된 삭제는 어떤 검증도 없이 커밋된다.
  git rm -q old.ts
  stamp
  run commit_as_human -m x
  [ "$status" -ne 0 ]
  [[ "$output" == *"old.ts"* ]]

  # 그리고 진짜 record-pass.sh 왕복으로 풀려야 한다 (스텁이 아니라).
  run record_pass
  [ "$status" -eq 0 ]
  grep -q "^${NULL_SHA}"$'\t'"old.ts"$'\t' "$(qdir)/covered.tsv"
  run commit_as_human -m x
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

@test "체이닝 파일이 우리 자신의 훅 사본이면 재귀를 막기 위해 실행하지 않는다" {
  # 대조군은 바로 위 "먼저 실행되고 거부하면" 테스트다 — 마커만 없으면
  # 똑같은 exit 7 스크립트가 실제로 실행되어 status 7·CHAINED_RAN 을 낸다.
  # 여기서는 마커를 넣어서 그 실행이 억제되는지만 가른다.
  printf '#!/bin/sh\necho CHAINED_RAN >&2\n# KKOCHIKKOCHI-HOOK-v1\nexit 7\n' \
    > "$(hooksdir)/pre-commit.kkochikkochi-chained"
  chmod +x "$(hooksdir)/pre-commit.kkochikkochi-chained"
  printf 'C1\n' > c.ts; git add c.ts
  stamp
  run "$(hooksdir)/pre-commit"
  [ "$status" -ne 7 ]
  [[ "$output" != *"CHAINED_RAN"* ]]
  # 체이닝을 건너뛴 다음 우리 판정이 실제로 이어져야 한다. 이 두 줄이 없으면
  # "그냥 exit 0 하는 훅"도 위 두 검사를 우연히 통과한다.
  [ "$status" -ne 0 ]
  [[ "$output" == *"c.ts"* ]]
}

@test "훅에 자기 식별 마커가 들어 있다" {
  # 정적 문자열 검사다 — 아무 일도 안 하는 훅이라도 마커만 있으면 통과하는
  # 게 맞다. 판정 로직 검증은 이 테스트의 목적이 아니다.
  grep -q 'KKOCHIKKOCHI-HOOK-v1' "$(hooksdir)/pre-commit"
}

# ── 음성 신호 (TTY) — D41 의 우선순위를 못 박는다 ──

@test "실제 터미널이 있으면 환경변수 신호보다 우선해 통과한다" {
  # git 은 pre-commit 훅의 표준입력만 리다이렉트한다. fd 1/2 에 진짜 pty 가
  # 붙어 있으면 사람이 지금 터미널에 있다는 뜻이고, 남아 있는 CLAUDECODE 같은
  # 환경변수보다 이 신호가 우선해야 한다.
  printf 'C1\n' > c.ts; git add c.ts
  with_tty env CLAUDECODE=1 git commit -m x || {
    echo "pty 를 할당하지 못했다 — 이 테스트는 pty 없이는 아무것도 증명하지 못한다" >&2
    return 1
  }
  [ "$TTY_RC" -eq 0 ]
  # 대조군: 같은 CLAUDECODE 값이라도 진짜 터미널이 없으면 (bats 의 run 이
  # 늘 그렇듯) 여전히 막힌다 — 즉 방금 통과한 건 TTY 신호가 실제로 한 일이다.
  # (c.ts 는 이미 위에서 커밋됐으니 새 파일 d.ts 로 다시 스테이징한다 —
  # 안 그러면 "스테이징된 게 없어서" 라는 무관한 이유로 막혀 대조군이 무력해진다.)
  printf 'C2\n' > d.ts; git add d.ts
  run env CLAUDECODE=1 git commit -m y
  [ "$status" -ne 0 ]
}

@test "실제 터미널은 신선한 핸드셰이크보다도 우선해 통과한다 (D41)" {
  # 이 테스트가 없으면 "TTY 가 핸드셰이크보다 먼저" 와 "핸드셰이크가 먼저"
  # 두 배치가 **똑같이** 초록이었다 (돌연변이 감사: 69/69 생존).
  #
  # 지금 배치가 옳은 이유: stamp-agent.sh 는 매 Bash 호출마다 마커를
  # 갱신하므로, 에이전트 세션이 살아 있는 동안 120초 창은 사실상 닫히지
  # 않는다. 핸드셰이크가 이기면 옆 창에서 사람이 손으로 친 커밋이 막힌다 —
  # D00 이 명시적으로 금지하는 마찰이다.
  printf 'C1\n' > c.ts; git add c.ts
  stamp                                   # 방금 찍힌, 최대한 신선한 마커
  # commit_as_human 은 셸 함수라 서브셸로 넘어가지 않는다 — 여기서는 풀어 쓴다.
  with_tty env -u CLAUDECODE -u CLAUDE_CODE_SESSION_ID git commit -m x || {
    echo "pty 를 할당하지 못했다 — 이 테스트는 pty 없이는 아무것도 증명하지 못한다" >&2
    return 1
  }
  [ "$TTY_RC" -eq 0 ]
  # 대조군: 똑같이 신선한 마커인데 pty 만 없으면 막힌다. 즉 통과시킨 것은
  # 오직 TTY 신호다.
  printf 'C2\n' > d.ts; git add d.ts
  stamp
  run commit_as_human -m y
  [ "$status" -ne 0 ]
  [[ "$output" == *"d.ts"* ]]
}

# ── 신선도 계산의 내구성 ──

@test "mtime 계산이 숫자가 아닌 값을 내도 훅이 죽지 않는다" {
  # GNU coreutils 에서는 stat -f 가 --file-system 으로 해석되어 종료코드
  # 0으로 사람이 읽는 텍스트를 낸다 (실측: Ubuntu 22.04, coreutils 8.32).
  # 그 출력을 산술식에 그대로 넣으면 dash 는 "Illegal number" 로 죽는다
  # (macOS 의 /bin/sh 는 bash 라 "unbound variable" 로, 메시지도 다르다 —
  # 그래서 메시지 문자열이 아니라 종료코드로 판정한다). 여기서는 실제 GNU
  # 환경 없이도 그 실패 모드를 흉내내, 숫자가-아니면-0 가드가 실제로
  # 방어하는지 확인한다.
  #
  # 가드가 없으면 두 플랫폼 다 셸 산술식에서 죽고, git 은 그 어떤 훅의
  # 0이-아닌-종료코드도 자기 코드(1)로 보고한다 — 그래서 "죽지 않는다"의
  # 증거는 메시지 문자열이 아니라 "커밋이 정상적으로 통과했다"(status 0)
  # 이다. 이 커밋엔 다른 에이전트 신호가 전혀 없으니(마커가 못 읽혔다고
  # 보고 낡은 걸로 처리) 가드가 제대로 동작하면 애매함으로 통과해야 한다.
  fakebin="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$fakebin"
  printf '#!/bin/sh\necho "  File: fake filesystem info"\nexit 0\n' > "$fakebin/stat"
  chmod +x "$fakebin/stat"
  printf 'C1\n' > c.ts; git add c.ts
  stamp

  # 대조군을 먼저 본다: 진짜 stat 으로는 같은 마커·같은 스테이징이 막힌다.
  # 이게 없으면 "그냥 exit 0 하는 훅"도 아래 검사를 전부 통과한다 — 통과의
  # 원인이 가드인지 훅이 아무 일도 안 한 것인지 가려지지 않는다. (순서가
  # 중요하다: 아래 커밋이 성공하면 스테이징이 비어 대조군이 무력해진다.)
  run commit_as_human -m x
  [ "$status" -ne 0 ]
  [[ "$output" == *"c.ts"* ]]

  PATH="$fakebin:$PATH" run commit_as_human -m x
  [ "$status" -eq 0 ]
  [[ "$output" != *"Illegal number"* ]]
  [[ "$output" != *"unbound variable"* ]]
}

# ── fail-open: 이해와 무관한 이유로 커밋을 영구히 막지 않는다 ──

@test "경로에 개행이 있어 스트림이 어긋나면 경고와 함께 통과시킨다" {
  # 예전에는 그 경로 하나만 망가지는 것이 아니라, 짝짓기가 한 칸 밀려
  # **뒤따르는 파일이 훅의 시야에서 통째로 사라진 채** 커밋됐다.
  printf 'N\n' > "$(printf 'we\nird.ts')"
  printf 'Z\n' > zzz.ts
  git add -A
  stamp
  run commit_as_human -m x
  [ "$status" -eq 0 ]                       # 어긋난 스트림으로 판정을 이어가지 않는다
  [[ "$output" == *"경고"* ]]               # 조용히 통과시키지도 않는다

  # 대조군: 개행 없는 같은 파일 집합이면 정상적으로 막힌다.
  printf 'Y\n' > yyy.ts; git add yyy.ts
  stamp
  run commit_as_human -m y
  [ "$status" -ne 0 ]
  [[ "$output" == *"yyy.ts"* ]]
}

@test "jq 가 없으면 경고와 함께 통과시킨다 (통과할 방법이 없는 게이트를 만들지 않는다)" {
  # record-pass.sh 는 jq 없이 한 줄도 쓰지 못한다. 그 환경에서 훅이 막으면
  # 이해와 무관한 이유로 커밋이 영구히 막힌다 — 이 프로젝트의 대죄다.
  fakebin="$(mktemp -d)"
  printf '#!/bin/sh\nexit 127\n' > "$fakebin/jq"   # PATH 앞단에서 jq 를 가린다
  chmod +x "$fakebin/jq"
  # command -v 는 실행 가능 파일이 있으면 성공하므로, 아예 없는 상태를
  # 만들려면 jq 가 든 디렉터리를 뺀 PATH 를 써야 한다.
  nojq="$(mktemp -d)"
  for b in git awk sed grep cat date stat mkdir rm mv cp chmod printf tr head wc env dirname uname sort cut touch expr basename gettext; do
    p="$(command -v "$b" 2>/dev/null)" && ln -sf "$p" "$nojq/$b"
  done
  printf 'C1\n' > c.ts; git add c.ts
  stamp
  # 대조군 먼저: jq 가 있으면 막힌다
  run commit_as_human -m x
  [ "$status" -ne 0 ]
  PATH="$nojq" run commit_as_human -m x
  [ "$status" -eq 0 ]
  [[ "$output" == *"jq"* ]]
}
