#!/usr/bin/env bats
#
# pre-push 는 최종 경계다. Stop 훅은 사람이 Esc 로 빠져나갈 수 있으므로,
# 미검증 커밋이 남에게 넘어가는 것은 여기서 막는다.
#
# 여기서는 퀴즈를 내지 않는다 — push 는 보통 명령 하나이고 사람에게 묻는
# 채널이 없다. 거부하고 안내만 한다.

load helper

setup() { setup_repo; seed_repo; }
teardown() { teardown_repo; }

install_push_hook() {
  mkdir -p "$(hooksdir)"
  cp "$PLUGIN_ROOT/hooks/pre-push" "$(hooksdir)/pre-push"
  chmod +x "$(hooksdir)/pre-push"
}

# pre-push 훅을 git 없이 직접 태운다 (stdin 계약을 그대로 준다).
run_push_hook() {  # $1 = remote sha, $2 = local sha
  printf 'refs/heads/main %s refs/heads/main %s\n' "$2" "$1" \
    | "$(hooksdir)/pre-push" origin https://example.invalid/r.git
}

@test "미검증 커밋이 없으면 통과한다" {
  install_push_hook
  base="$(git rev-parse HEAD)"
  run run_push_hook "$base" "$base"
  [ "$status" -eq 0 ]
}

@test "미검증 커밋이 섞이면 거부한다" {
  install_push_hook
  base="$(git rev-parse HEAD)"
  printf 'C1\n' > c.ts; git add c.ts
  commit_as_human -qm "unverified"
  run run_push_hook "$base" "$(git rev-parse HEAD)"
  [ "$status" -ne 0 ]
  [[ "$output" == *"c.ts"* ]]
}

@test "검증된 커밋만 있으면 통과한다" {
  install_push_hook
  base="$(git rev-parse HEAD)"
  printf 'C1\n' > c.ts; git add c.ts
  stub_covered_line c.ts
  commit_as_human -qm "verified"
  run run_push_hook "$base" "$(git rev-parse HEAD)"
  [ "$status" -eq 0 ]
}

@test "새 브랜치(remote sha 가 0)에서도 범위를 잡는다" {
  install_push_hook
  printf 'C1\n' > c.ts; git add c.ts
  commit_as_human -qm "unverified"
  run run_push_hook "$NULL_SHA" "$(git rev-parse HEAD)"
  [ "$status" -ne 0 ]
}

@test "브랜치 삭제(local sha 가 0)는 통과한다" {
  install_push_hook
  run run_push_hook "$(git rev-parse HEAD)" "$NULL_SHA"
  [ "$status" -eq 0 ]
}

@test "미검증 판정에 jq 를 쓰지 않는다" {
  # 원안의 grep -c 'jq' 는 주석까지 센다 — 이 훅의 헤더 주석은 "왜 jq 를
  # 쓰지 않는가"를 설명하려고 정확히 그 단어를 두 번 쓰므로, 원안 그대로는
  # 자기 자신의 참조 구현에도 실패한다. 여기서 검증하려는 성질은 "jq 라는
  # 글자가 파일에 없다"가 아니라 "jq 를 명령으로 실행하지 않는다"이므로,
  # 주석 줄(# 로 시작)을 걷어내고 남은 코드에서만 센다.
  install_push_hook
  run bash -c "grep -v '^[[:space:]]*#' '$(hooksdir)/pre-push' | grep -c 'jq'"
  [ "$output" = "0" ]
}
