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

teardown_repo() {
  cd / || return 0
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

qdir() { git rev-parse --git-path quiz-gate; }
hooksdir() { git rev-parse --git-path hooks; }

install_hook() {
  mkdir -p "$(hooksdir)"
  cp "$PLUGIN_ROOT/hooks/pre-commit" "$(hooksdir)/pre-commit"
  chmod +x "$(hooksdir)/pre-commit"
}

stamp() {  # 핸드셰이크 마커를 신선하게 남긴다
  mkdir -p "$(qdir)"
  echo "${1:-test-agent}/sess-1" > "$(qdir)/agent-session"
}

mark_covered() {  # $1 = 경로
  mkdir -p "$(qdir)"
  printf '%s\t%s\t%s\n' "$(git hash-object -- "$1")" "$1" "p-test" >> "$(qdir)/covered.tsv"
}

# 에이전트 환경변수를 지운 상태로 커밋한다 (사람 커밋 근사)
commit_as_human() { env -u CLAUDECODE -u CLAUDE_CODE_SESSION_ID git commit "$@"; }

# 의사 터미널(pty)에 명령의 fd 1/2 를 붙여서 실행한다. bats 자체는 tty 를
# 주지 않으므로, 훅의 "실제 터미널이면 사람" 신호를 테스트하려면 이렇게
# script(1)로 pty 를 만들어 줘야 한다. BSD 와 util-linux 의 script 인자
# 문법이 달라 OS 별로 분기한다. -e 는 자식의 종료코드를 script 자신의
# 종료코드로 돌려달라는 뜻이다 — util-linux 는 이 플래그 없이는 항상 0을
# 반환하므로 (v2.37.2 로 실측) 빠지면 이 헬퍼로 하는 종료코드 검증이 전부
# 무의미해진다. BSD script 는 -e 없이도 이미 전파하지만, 이 플래그를
# "호환성을 위해 받아만 준다" (macOS man script(1)) 고 명시하므로 양쪽에
# 그냥 같이 넣어도 안전하다.
with_tty() {
  if [ "$(uname)" = "Darwin" ]; then
    script -qe /dev/null "$@"
  else
    script -qec "$*" /dev/null
  fi
}
