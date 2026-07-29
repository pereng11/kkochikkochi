#!/usr/bin/env bats

load helper

setup() { setup_repo; seed_repo; }
teardown() { teardown_repo; }

# 훅 stdin JSON 을 만들어 gate.sh 에 흘려넣는다.
run_gate() {  # $1 = command 문자열
  local payload
  payload=$(jq -n --arg c "$1" --arg cwd "$PWD" \
    '{tool_name:"Bash", cwd:$cwd, tool_input:{command:$c}}')
  echo "$payload" | bash "$PLUGIN_ROOT/hooks/gate.sh"
}

covered_dir() { echo "$(git rev-parse --git-dir)/quiz-gate"; }

mark_covered() {  # $1 = 경로
  mkdir -p "$(covered_dir)"
  printf '%s\t%s\t%s\n' "$(git hash-object -- "$1")" "$1" "p-test" \
    >> "$(covered_dir)/covered.tsv"
}

@test "미검증 변경이 있으면 deny 한다" {
  printf 'C1\n' > c.ts
  git add c.ts
  run run_gate 'git commit -m "x"'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"permissionDecision": "deny"'* ]] \
    || [[ "$output" == *'"permissionDecision":"deny"'* ]]
}

@test "deny 사유에 미검증 파일명이 들어간다" {
  printf 'C1\n' > c.ts
  git add c.ts
  run run_gate 'git commit -m "x"'
  [[ "$output" == *"c.ts"* ]]
}

@test "covered.tsv 에 있으면 통과(출력 없음)" {
  printf 'C1\n' > c.ts
  mark_covered c.ts
  git add c.ts
  run run_gate 'git commit -m "x"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "커버된 뒤 파일을 고치면 다시 deny 한다" {
  printf 'C1\n' > c.ts
  mark_covered c.ts
  printf 'C2\n' > c.ts        # 내용이 바뀌면 SHA 가 달라진다
  git add c.ts
  run run_gate 'git commit -m "x"'
  [[ "$output" == *"deny"* ]]
}

@test "분할 커밋: 한 번 커버하면 나눠 커밋해도 재퀴즈 없음" {
  printf 'C1\n' > c.ts; printf 'D1\n' > d.ts
  mark_covered c.ts; mark_covered d.ts
  git add c.ts && git commit -qm "c"
  git add d.ts
  run run_gate 'git commit -m "d"'
  [ -z "$output" ]
}

@test "Bash 가 아닌 툴은 무시한다" {
  run bash -c "echo '{\"tool_name\":\"Read\",\"tool_input\":{}}' | bash '$PLUGIN_ROOT/hooks/gate.sh'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "git commit 이 아닌 명령은 무시한다" {
  printf 'C1\n' > c.ts; git add c.ts
  run run_gate 'git status'
  [ -z "$output" ]
}

@test "git revert 는 게이트하지 않는다" {
  printf 'C1\n' > c.ts; git add c.ts
  run run_gate 'git revert HEAD'
  [ -z "$output" ]
}

@test "commit-tree 는 commit 으로 오인하지 않는다" {
  printf 'C1\n' > c.ts; git add c.ts
  run run_gate 'git commit-tree abc123'
  [ -z "$output" ]
}

@test "복합 커맨드(cd x && git commit)도 잡는다" {
  printf 'C1\n' > c.ts; git add c.ts
  run run_gate "cd '$PWD' && git commit -m 'x'"
  [[ "$output" == *"deny"* ]]
}

@test "git -C 형태도 잡는다" {
  printf 'C1\n' > c.ts; git add c.ts
  run run_gate "git -C '$PWD' commit -m 'x'"
  [[ "$output" == *"deny"* ]]
}

@test "문자열 안의 git commit 은 잡지 않는다" {
  printf 'C1\n' > c.ts; git add c.ts
  run run_gate 'echo "run git commit later"'
  [ -z "$output" ]
}

@test "빈 커밋(스테이징 없음)은 통과한다" {
  run run_gate 'git commit -m "x"'
  [ -z "$output" ]
}

@test "fail-open: covered.tsv 가 깨져도 판정을 계속한다" {
  printf 'C1\n' > c.ts
  mkdir -p "$(covered_dir)"
  printf 'garbage line without tabs\n' >> "$(covered_dir)/covered.tsv"
  mark_covered c.ts
  git add c.ts
  run run_gate 'git commit -m "x"'
  [ -z "$output" ]
}

@test "fail-open: git 레포가 아니면 통과한다" {
  cd "$(mktemp -d)" || return 1
  run run_gate 'git commit -m "x"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
