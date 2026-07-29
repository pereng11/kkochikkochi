#!/usr/bin/env bats

load helper

setup() { setup_repo; seed_repo; }
teardown() { teardown_repo; }

# run_gate 는 helper.bash 에 있다.

covered_dir() { echo "$(git rev-parse --git-dir)/quiz-gate"; }

# "출력이 비었다" 는 통과와 크래시를 구별하지 못한다. 같은 픽스처에서
# 커버리지를 지우면 deny 가 나오는지 확인해, 게이트가 살아 있는 상태에서
# 통과를 선택했다는 것을 증명한다.
assert_denies_without_coverage() {  # $1 = command 문자열
  local out saved
  saved="$(covered_dir)/covered.tsv"
  [ -f "$saved" ] || return 1
  mv "$saved" "$saved.bak"
  out="$(run_gate "$1")"
  mv "$saved.bak" "$saved"
  [[ "$out" == *"deny"* ]]
}

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
  # 대조군: 커버리지만 치우면 같은 입력에서 deny 가 나온다 —
  # 위의 빈 출력이 크래시가 아니라 판정 결과임을 증명한다.
  assert_denies_without_coverage 'git commit -m "x"'
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
  assert_denies_without_coverage 'git commit -m "d"'
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
  # 양성 대조군: 같은 픽스처에서 진짜 커밋은 막힌다.
  run run_gate 'git commit -m "x"'
  [[ "$output" == *"deny"* ]]
}

@test "git revert 는 게이트하지 않는다" {
  printf 'C1\n' > c.ts; git add c.ts
  run run_gate 'git revert HEAD'
  [ -z "$output" ]
  run run_gate 'git commit -m "x"'
  [[ "$output" == *"deny"* ]]
}

@test "commit-tree 는 commit 으로 오인하지 않는다" {
  printf 'C1\n' > c.ts; git add c.ts
  run run_gate 'git commit-tree abc123'
  [ -z "$output" ]
  run run_gate 'git commit -m "x"'
  [[ "$output" == *"deny"* ]]
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
  run run_gate 'git commit -m "x"'
  [[ "$output" == *"deny"* ]]
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
  assert_denies_without_coverage 'git commit -m "x"'
}

@test "fail-open: git 레포가 아니면 통과한다" {
  cd "$(mktemp -d)" || return 1
  run run_gate 'git commit -m "x"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "git -C 다른 레포를 향하면 그 레포 기준으로 판정한다" {
  local other
  other="$(mktemp -d)"
  (
    cd "$other" || exit 1
    git init -q .
    git config user.email "test@example.com"
    git config user.name "test"
    git config commit.gpgsign false
    printf 'O1\n' > o.ts
    git add o.ts
  )
  # 세션 레포(현재 $PWD)는 깨끗하다 — 스테이징된 게 없다.
  run run_gate "git -C '$other' commit -m 'x'"
  [[ "$output" == *"deny"* ]]
  [[ "$output" == *"o.ts"* ]]
  rm -rf "$other"
}

@test "git -C 다른 레포가 covered.tsv 에 있으면 통과한다" {
  local other other_git_dir
  other="$(mktemp -d)"
  (
    cd "$other" || exit 1
    git init -q .
    git config user.email "test@example.com"
    git config user.name "test"
    git config commit.gpgsign false
    printf 'O1\n' > o.ts
    git add o.ts
  )
  other_git_dir="$(cd "$other" && git rev-parse --git-dir)"
  case "$other_git_dir" in
    /*) : ;;
    *) other_git_dir="$other/$other_git_dir" ;;
  esac
  mkdir -p "$other_git_dir/quiz-gate"
  printf '%s\t%s\t%s\n' \
    "$(cd "$other" && git hash-object -- o.ts)" "o.ts" "p-test" \
    >> "$other_git_dir/quiz-gate/covered.tsv"
  # 세션 레포에도 검증되지 않은 스테이징을 만들어 둔다. gate.sh 가 -C 를
  # 무시하고 세션 레포를 판정해 버리면 여기서 deny 가 나와야 하므로,
  # 이 파일이 없으면 -C 를 아예 무시해도 통과해 버리는 맹점이 생긴다.
  printf 'C1\n' > c.ts
  git add c.ts
  run run_gate "git -C '$other' commit -m 'x'"
  [ -z "$output" ]
  rm -rf "$other"
}

@test "git -C 존재하지 않는 경로는 통과한다(fail-open)" {
  printf 'C1\n' > c.ts; git add c.ts
  run run_gate "git -C '/no/such/dir/at/all' commit -m 'x'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "-C 앞 옵션 값의 따옴표 안에 && 가 있어도 -C 를 놓치지 않는다" {
  local other
  other="$(mktemp -d)"
  (
    cd "$other" || exit 1
    git init -q .
    git config user.email "test@example.com"
    git config user.name "test"
    git config commit.gpgsign false
    printf 'O1\n' > o.ts
    git add o.ts
  )
  # 세션 레포는 깨끗하다. -c 옵션의 따옴표로 감싼 값 안에 && 가 들어
  # 있다 — 예전 구현은 이걸 분류용(따옴표 지운) 문자열과 원본 문자열을
  # 각각 따로 쪼개면서 세그먼트 개수가 어긋나, -C 값을 잃어버리고
  # 세션 레포를 판정해(즉 조용히 통과해) 버렸다.
  run run_gate "git -c alias.foo=\"a && b\" -C '$other' commit -m x"
  [[ "$output" == *"deny"* ]]
  [[ "$output" == *"o.ts"* ]]
  rm -rf "$other"
}

@test "세그먼트 끝의 -c 뒤에 오는 진짜 git commit(;)을 놓치지 않는다" {
  printf 'C1\n' > c.ts; git add c.ts
  run run_gate 'git -c; git commit -m x'
  [[ "$output" == *"deny"* ]]
  [[ "$output" == *"c.ts"* ]]
}

@test "세그먼트 끝의 -C 뒤에 오는 진짜 git commit(;)을 놓치지 않는다" {
  printf 'C1\n' > c.ts; git add c.ts
  run run_gate 'git -C; git commit -m x'
  [[ "$output" == *"deny"* ]]
  [[ "$output" == *"c.ts"* ]]
}

@test "세그먼트 끝의 -c 뒤에 오는 진짜 git commit(&&)을 놓치지 않는다" {
  printf 'C1\n' > c.ts; git add c.ts
  run run_gate 'git -c && git commit -m x'
  [[ "$output" == *"deny"* ]]
  [[ "$output" == *"c.ts"* ]]
}
