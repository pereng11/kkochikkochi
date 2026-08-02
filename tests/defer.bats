#!/usr/bin/env bats
#
# 유예 모드 — 구현 중에는 묻지 않고 턴 끝에 몰아 받는다.
#
# 훅 기능으로는 만들 수 없다: 훅의 timeout(기본 60초)은 시간이 지나면 훅을
# 죽여 판정을 잃는다. 파일 상태로 만들면 세션이 죽어도 살아남고 pre-push 가
# 마지막에 잡는다.

load helper

setup() { setup_repo; seed_repo; }
teardown() { teardown_repo; }

defer_sh() { bash "$PLUGIN_ROOT/scripts/defer.sh" "$@"; }

@test "on 이 defer 파일을 만든다" {
  run defer_sh on
  [ "$status" -eq 0 ]
  [ -e "$(qdir)/defer" ]
}

@test "off 가 defer 파일을 지운다" {
  defer_sh on
  run defer_sh off
  [ "$status" -eq 0 ]
  [ ! -e "$(qdir)/defer" ]
}

@test "status 가 상태를 낸다" {
  run defer_sh status
  [ "$output" = "off" ]
  defer_sh on
  run defer_sh status
  [ "$output" = "on" ]
}

@test "이미 켜져 있을 때 on 을 또 불러도 0 을 낸다" {
  defer_sh on
  run defer_sh on
  [ "$status" -eq 0 ]
}

@test "꺼져 있을 때 off 를 불러도 0 을 낸다" {
  run defer_sh off
  [ "$status" -eq 0 ]
}

@test "알 수 없는 인자는 거부한다" {
  run defer_sh nonsense
  [ "$status" -ne 0 ]
}

@test "git 저장소가 아니면 거부한다" {
  cd "$(mktemp -d)"
  run defer_sh on
  [ "$status" -ne 0 ]
}
