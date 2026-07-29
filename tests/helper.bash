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
