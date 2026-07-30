#!/usr/bin/env bats

load helper

setup() { setup_repo; seed_repo; }
teardown() { teardown_repo; }

inst() { bash "$PLUGIN_ROOT/scripts/install.sh" "$@"; }

@test "install 이 훅을 놓는다" {
  run inst install
  [ "$status" -eq 0 ]
  [ -x "$(hooksdir)/pre-commit" ]
  grep -q 'KKOCHIKKOCHI-HOOK-v1' "$(hooksdir)/pre-commit"
}

@test "status 는 설치 전 1, 설치 후 0" {
  run inst status
  [ "$status" -eq 1 ]
  inst install
  run inst status
  [ "$status" -eq 0 ]
}

@test "기존 훅을 체이닝 파일로 옮긴다" {
  printf '#!/bin/sh\nexit 0\n' > "$(hooksdir)/pre-commit"; chmod +x "$(hooksdir)/pre-commit"
  inst install
  [ -f "$(hooksdir)/pre-commit.kkochikkochi-chained" ]
  grep -q 'KKOCHIKKOCHI-HOOK-v1' "$(hooksdir)/pre-commit"
}

@test "재설치는 멱등이며 체이닝 파일을 덮어쓰지 않는다" {
  printf '#!/bin/sh\necho ORIGINAL\nexit 0\n' > "$(hooksdir)/pre-commit"; chmod +x "$(hooksdir)/pre-commit"
  inst install
  inst install
  run cat "$(hooksdir)/pre-commit.kkochikkochi-chained"
  [[ "$output" == *"ORIGINAL"* ]]
}

@test "uninstall 이 기존 훅을 원상복구한다" {
  printf '#!/bin/sh\necho ORIGINAL\nexit 0\n' > "$(hooksdir)/pre-commit"; chmod +x "$(hooksdir)/pre-commit"
  inst install
  # 대조군: install 이 실제로 우리 훅을 놓았는지 먼저 확인한다. 이게 없으면
  # install 이 아무 일도 안 하는 스텁이어도 ORIGINAL 이 애초에 안 건드려져
  # 아래 검사를 우연히 통과한다.
  grep -q 'KKOCHIKKOCHI-HOOK-v1' "$(hooksdir)/pre-commit"
  inst uninstall
  run cat "$(hooksdir)/pre-commit"
  [[ "$output" == *"ORIGINAL"* ]]
  [ ! -f "$(hooksdir)/pre-commit.kkochikkochi-chained" ]
}

@test "체이닝할 것이 없으면 uninstall 이 훅만 지운다" {
  inst install
  # 대조군: install 이 실제로 훅을 놓았는지 먼저 확인한다. 이게 없으면
  # install 이 아무 일도 안 하는 스텁이어도 애초에 파일이 없어 아래 검사를
  # 우연히 통과한다.
  [ -x "$(hooksdir)/pre-commit" ]
  inst uninstall
  [ ! -f "$(hooksdir)/pre-commit" ]
}

@test "core.hooksPath 가 설정돼 있으면 설치를 거부하고 exit 2" {
  mkdir -p .myhooks
  git config core.hooksPath .myhooks
  run inst install
  [ "$status" -eq 2 ]
  [ ! -f ".myhooks/pre-commit" ]
  [[ "$output" == *"core.hooksPath"* ]]
}

@test "설치 후 게이트가 실제로 동작한다 (종단 확인)" {
  inst install
  printf 'C1\n' > c.ts; git add c.ts
  stamp
  run commit_as_human -m x
  [ "$status" -ne 0 ]
}
