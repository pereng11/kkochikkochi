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

pending() {
  bash "$PLUGIN_ROOT/scripts/pending-set.sh" "$1"
}

# 훅 stdin JSON 을 만들어 gate.sh 에 흘려넣는다.
run_gate() {  # $1 = command 문자열
  local payload
  payload=$(jq -n --arg c "$1" --arg cwd "$PWD" \
    '{tool_name:"Bash", cwd:$cwd, tool_input:{command:$c}}')
  echo "$payload" | bash "$PLUGIN_ROOT/hooks/gate.sh"
}

record_pass() {  # $1 = transcript JSON, $2 = command
  echo "$1" | bash "$PLUGIN_ROOT/scripts/record-pass.sh" "$2"
}

# `git diff --cached --raw` 가 말하는 (SHA, 경로) 집합. pending-set 의 출력은
# 절대 이것의 부분집합이 될 수 없다(never-shrink 불변식).
staged_set() {
  git -c core.quotePath=false diff --cached --raw --abbrev=40 --no-renames |
    awk -F'\t' '{ split($1, f, " "); print f[4] "\t" $2 }'
}
