#!/usr/bin/env bash
# 픽스처 git 레포를 만들고 그 안으로 이동한다.

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PLUGIN_ROOT
export NULL_SHA=0000000000000000000000000000000000000000

setup_repo() {
  TEST_REPO="$(mktemp -d)"
  export TEST_REPO
  cd "$TEST_REPO" || return 1
  git init -q .
  git config user.email "test@example.com"
  git config user.name "test"
  git config commit.gpgsign false
}

# 링크된 워크트리를 만들고 그 경로를 stdout 으로 낸다.
# teardown_repo 가 지울 수 있도록 TEST_WORKTREES 에 모아 둔다.
add_worktree() {  # $1 = 새 브랜치 이름
  local wt
  wt="$(mktemp -d)"
  rm -rf "$wt"   # git worktree add 는 존재하지 않는 경로를 요구한다
  git worktree add -q "$wt" -b "$1" >/dev/null 2>&1 || return 1
  TEST_WORKTREES="${TEST_WORKTREES:-} $wt"
  export TEST_WORKTREES
  echo "$wt"
}

teardown_repo() {
  cd / || return 0
  for wt in ${TEST_WORKTREES:-}; do
    [ -d "$wt" ] && rm -rf "$wt"
  done
  TEST_WORKTREES=""
  [ -n "${TEST_REPO:-}" ] && [ -d "$TEST_REPO" ] && rm -rf "$TEST_REPO"
  return 0
}

# 초기 커밋 하나를 만든다: a.ts, b.ts, old.ts
seed_repo() {
  printf 'A1\n' > a.ts
  printf 'B1\n' > b.ts
  printf 'OLD\n' > old.ts
  git add .
  git commit -qm init
}

qdir() { echo "$(git rev-parse --git-common-dir)/quiz-gate"; }
hooksdir() { git rev-parse --git-path hooks; }

install_hook() {
  mkdir -p "$(hooksdir)"
  cp "$PLUGIN_ROOT/hooks/pre-commit" "$(hooksdir)/pre-commit"
  chmod +x "$(hooksdir)/pre-commit"
}

# 핸드셰이크 마커를 신선하게 남긴다.
# 인자 없이 부르면 메인 스레드 마커, agent_id 를 주면 서브에이전트 마커다.
stamp() {  # $1 = agent, $2 = agent_id, $3 = agent_type
  local name="main"
  [ -n "${2:-}" ] && name="$2"
  mkdir -p "$(qdir)/marker"
  printf '%s\t%s\t%s\t%s\n' \
    "${1:-test-agent}" "${2:-}" "${3:-}" "sess-1" > "$(qdir)/marker/$name"
}

# ⚠ 이것은 record-pass.sh 가 아니다. 훅 단독 테스트용으로 covered.tsv 에 한 줄을
# 손으로 박아 넣는 스텁일 뿐이며, SHA 를 **워크트리 파일**에서 계산한다.
#
# 예전 이름은 mark_covered 였는데, 그 이름이 "통과를 기록한다"는 진짜 쓰기
# 경로처럼 읽혀서 C1(`git commit -am` 영구 교착)을 통째로 가렸다: 이 스텁은
# *올바른* record-pass.sh 가 낼 법한 줄을 내주므로, 왕복 테스트가 초록인 채로
# 실제 배포된 writer 는 그 줄을 애초에 만들어낼 수 없는 상태였다.
#
# 규칙: **왕복(기록→커밋 통과) 주장에는 절대 쓰지 않는다.** 그 주장은 반드시
# 진짜 record-pass.sh 를 태워야 한다. 여기 쓰는 곳은 "훅이 covered.tsv 를
# 어떻게 읽는가"만 보는 훅 단독 테스트뿐이다.
stub_covered_line() {  # $1 = 경로
  mkdir -p "$(qdir)"
  printf '%s\t%s\t%s\n' "$(git hash-object -- "$1")" "$1" "p-stub" >> "$(qdir)/covered.tsv"
}

# 진짜 record-pass.sh 를 통과 기록으로 태운다 (왕복 주장은 이것만 쓴다).
record_pass() {
  printf '%s' '{"questions":[{"axis":"facts","q":"무엇이 바뀌었나?","evidence":"x:1","format":"choice","answer":"A","correct":"A","attempts":1,"gave_up":false}]}' \
    | bash "$PLUGIN_ROOT/scripts/record-pass.sh"
}

# 에이전트 환경변수를 지운 상태로 커밋한다 (사람 커밋 근사)
commit_as_human() { env -u CLAUDECODE -u CLAUDE_CODE_SESSION_ID git commit "$@"; }

# 의사 터미널(pty)에 명령의 fd 1/2 를 붙여서 실행한다. bats 자체는 tty 를
# 주지 않으므로, 훅의 "실제 터미널이면 사람" 신호를 테스트하려면 이렇게
# script(1)로 pty 를 만들어 줘야 한다. BSD 와 util-linux 의 script 인자
# 문법이 달라 OS 별로 분기한다.
#
# 이 헬퍼는 두 가지를 의도적으로 script(1) 에 맡기지 않는다. 예전 구현은
# 둘 다 맡겼고, 그 탓에 이 메커니즘 하나에 걸린 테스트가 산발적으로 붉게
# 떴다 (18회 정상 / 5회 오탐, 손대지 않은 트리에서도) — D35 가 딛고 선
# 티어를 지키는 테스트가 흔들리면 사람들은 그냥 재실행하는 법을 배운다.
#
#   1) 종료 코드. script 의 -e 전파에 기대지 않고 명령이 스스로 파일에
#      적는다. 결과는 $TTY_RC 로 돌려준다.
#   2) pty 가 정말 붙었는가. 안에서 [ -t 1 ] 을 직접 찍어 확인한다.
#      pty 할당 자체가 실패하면(부하가 높을 때 일어난다) 판정을 신뢰할 수
#      없으므로 조용히 통과시키지 않고 재시도하고, 끝내 못 잡으면
#      0 이 아닌 값으로 실패를 알린다 — 호출자가 그것을 테스트 실패로
#      드러내야 한다.
#
# 사용법:  with_tty <cmd> [args...]  || { echo "no pty" >&2; return 1; }
#          [ "$TTY_RC" -eq 0 ]
# 실행할 것은 **파일**에 적어서 넘긴다. util-linux 의 `script -c <문자열>` 은
# 그 문자열을 $SHELL(대개 dash)에게 넘기는데, printf %q 가 여러 줄 문자열에
# 대해 내는 bash 문법 $'...' 를 dash 는 모른다 — 그러면 pty 는 정상인데 안에서
# 아무것도 실행되지 않아, 겉보기에 "pty 할당 실패"로만 보인다(우분투 22.04 로
# 실측). 파일로 넘기면 어느 /bin/sh 를 거치든 문제가 없다.
with_tty() {
  local rc_file probe_file script_file attempt
  rc_file="$(mktemp)"; probe_file="$(mktemp)"; script_file="$(mktemp)"
  TTY_RC=""
  {
    printf 'if [ -t 1 ]; then echo yes > %q; else echo no > %q; fi\n' "$probe_file" "$probe_file"
    printf '%q ' "$@"; printf '\n'
    printf 'echo $? > %q\n' "$rc_file"
  } > "$script_file"

  # 재시도를 넉넉히 준다. 부하가 높을 때(예: 돌연변이 감사가 전체 스위트를
  # 연달아 돌릴 때) pty 할당이 실패하는 것을 실측했다 — 그때 한두 번 만에
  # 포기하면 제품 결함이 아닌데 붉게 뜨고, 그것이 바로 이 헬퍼를 다시 쓰게
  # 만든 원래 문제다. 시도 사이에 잠깐 쉬어 커널이 pty 를 회수할 틈을 준다.
  for attempt in 1 2 3 4 5 6; do
    [ "$attempt" -gt 1 ] && sleep 0.3
    : > "$probe_file"; : > "$rc_file"
    if [ "$(uname)" = "Darwin" ]; then
      script -q /dev/null /bin/bash "$script_file" >/dev/null 2>&1
    else
      script -qc "/bin/bash $(printf '%q' "$script_file")" /dev/null >/dev/null 2>&1
    fi
    if [ "$(cat "$probe_file" 2>/dev/null)" = "yes" ] && [ -s "$rc_file" ]; then
      # shellcheck disable=SC2034  # 호출자(.bats)가 읽는 반환 채널이다
      TTY_RC="$(cat "$rc_file")"
      rm -f "$rc_file" "$probe_file" "$script_file"
      return 0
    fi
  done
  rm -f "$rc_file" "$probe_file" "$script_file"
  return 1
}
