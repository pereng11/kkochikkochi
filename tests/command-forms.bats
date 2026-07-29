#!/usr/bin/env bats
#
# 커맨드 형태 행렬(command-form matrix).
#
# 훅과 스킬이 *같은 문자열*을 각각 파싱하던 시절의 버그(빈 집합으로 게이트가
# 조용히 꺼지는 것, bare pathspec 누락, 스킬이 "git commit" 을 가정해 생기는
# 영구 교착)는 전부 이 이음매에 있었고, 이 이음매에는 테스트가 하나도 없었다.
#
# 여기서는 두 가지를 본다.
#   1. 성질 테스트 — 어떤 형태든 pending-set 의 출력은 스테이징된 집합을
#      포함한다(never-shrink). 형태 하나가 아니라 부류 전체를 덮는다.
#   2. 왕복 테스트 — deny → 그 커맨드 그대로 record → allow.
#      C3(교착)을 잡았을 유일한 단언이다.

load helper

setup() { setup_repo; seed_repo; }
teardown() { teardown_repo; }

VALID='{"questions":[{"axis":"facts","q":"무엇이 바뀌었나?","evidence":"c.ts:1","format":"choice","answer":"A","correct":"A","attempts":1,"gave_up":false}]}'

# 스테이징된 것 하나(c.ts 신규)와 스테이징되지 않은 수정 하나(a.ts).
# 두 가지가 동시에 있어야 "스테이징 전용 분기로 떨어지는" 누락이 드러난다.
mixed_state() {
  printf 'A2\n' > a.ts        # 추적 파일, 워크트리만 수정
  printf 'C1\n' > c.ts
  git add c.ts                # 신규, 스테이징됨
}

# 검사할 커맨드 형태 전부. 여기에 한 줄 추가하면 아래 두 테스트가 모두
# 그 형태를 검사한다.
command_forms() {
  cat <<'FORMS'
git commit -m "x"
git commit -am "x"
git commit -va -m "x"
git commit -m "x" -- a.ts
git commit -m "x" a.ts
git commit --amend -m "x"
git commit -m "fix: handle -- separator"
git commit -m "fix -a bug"
git commit --only -m "x" a.ts
git commit --include -m "x" a.ts
git commit --author "A <a@e.com>" -m "x"
git commit -m "x" --no-verify
git commit --wat-is-this -m "x"
FORMS
}

@test "성질: 어떤 커맨드 형태든 pending-set ⊇ git diff --cached --raw" {
  mixed_state
  local want got form
  want="$(staged_set)"
  [ -n "$want" ]              # 픽스처가 실제로 스테이징을 갖고 있는지 먼저 확인
  while IFS= read -r form; do
    got="$(pending "$form")"
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      if [[ "$got" != *"$line"* ]]; then
        echo "형태: $form" >&2
        echo "빠진 줄: $line" >&2
        echo "실제 출력: $got" >&2
        return 1
      fi
    done <<<"$want"
  done < <(command_forms)
}

@test "성질: 메시지 안의 -- 가 pathspec 으로 새지 않는다" {
  # 예전에는 `set -- $ARGS` 의 단어 분리 때문에 따옴표 안의 -- 가 독립
  # 토큰이 되어 seen_ddash 를 켜고, 뒤따르는 단어가 전부 pathspec 이 되어
  # 커밋 대상 집합이 통째로 비었다 — 게이트가 아무 신호 없이 꺼졌다.
  mixed_state
  run pending 'git commit -m "fix: handle -- separator"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"c.ts"* ]]
}

@test "성질: -- 줄이 든 여러 줄 메시지에서도 꺼지지 않는다" {
  # Claude Code 가 heredoc 으로 늘 쓰는 서명 구분선 형태.
  mixed_state
  run pending 'git commit -m "fix: thing

--
Co-Authored-By: Someone <s@example.com>"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"c.ts"* ]]
}

@test "bare pathspec 은 워크트리 내용을 포함한다" {
  # `git commit -m x a.ts` 는 a.ts 의 **워크트리** 내용을 커밋한다.
  # 예전 구현은 이 맨 단어가 어느 case 에도 걸리지 않아 버려졌고,
  # 스테이징 전용 분기로 떨어져 a.ts 를 검증 없이 통과시켰다.
  mixed_state
  run pending 'git commit -m x a.ts'
  [ "$status" -eq 0 ]
  [[ "$output" == *"$(git hash-object a.ts)"$'\t'"a.ts"* ]]
}

@test "--only / --include 에 경로가 붙어도 워크트리 내용을 포함한다" {
  mixed_state
  run pending 'git commit --only -m x a.ts'
  [[ "$output" == *"$(git hash-object a.ts)"$'\t'"a.ts"* ]]
  run pending 'git commit --include -m x a.ts'
  [[ "$output" == *"$(git hash-object a.ts)"$'\t'"a.ts"* ]]
}

@test "모르는 옵션은 워크트리 수정본까지 합집합으로 낸다(과잉 방향)" {
  mixed_state
  run pending 'git commit --some-future-flag -m x'
  [ "$status" -eq 0 ]
  [[ "$output" == *"c.ts"* ]]                       # 스테이징된 것
  [[ "$output" == *"$(git hash-object a.ts)"* ]]    # 워크트리 수정본까지
}

@test "-p(--patch)는 대화형이라 예측 불가 → 합집합" {
  mixed_state
  run pending 'git commit -p -m x'
  [[ "$output" == *"$(git hash-object a.ts)"* ]]
}

@test "--pathspec-from-file: 파일 안의 경로도 게이트된다" {
  # 커밋될 경로가 인자가 아니라 파일 안에 있고 이 스크립트는 그 파일을
  # 읽지 않는다. 한때 두 옵션이 "아는 옵션" 으로 등록되어 unknown 이
  # 켜지지 않았고, 그래서 파일에 적힌 경로가 통째로 게이트를 빠져나갔다.
  mixed_state
  printf 'a.ts\n' > list
  local wt; wt="$(git hash-object a.ts)"
  run pending 'git commit --pathspec-from-file=list -m x'
  [ "$status" -eq 0 ]
  [[ "$output" == *"$wt"$'\t'"a.ts"* ]]
  # 값이 별도 토큰인 형태도 같아야 한다.
  run pending 'git commit --pathspec-from-file list -m x'
  [[ "$output" == *"$wt"$'\t'"a.ts"* ]]
  # --pathspec-file-nul 은 단짝이다. 이것만 있어도 합집합이어야 한다.
  run pending 'git commit --pathspec-file-nul -m x'
  [[ "$output" == *"$wt"$'\t'"a.ts"* ]]
}

@test "--pathspec-from-file: 실제 커밋되는 파일이 deny 사유에 뜬다" {
  # 재현의 핵심 — git 은 list 에 적힌 a.ts 만 커밋하는데, 예전 게이트는
  # 그 커밋이 담지도 않는 c.ts 로만 deny 했다. c.ts 가 커버되고 나면
  # a.ts 는 검증 없이 나갔다.
  mixed_state
  printf 'a.ts\n' > list
  run run_gate 'git commit --pathspec-from-file=list -m x'
  [[ "$output" == *"deny"* ]]
  [[ "$output" == *"a.ts"* ]]
}

@test "화이트리스트 감사: 파일 집합을 바꾸는 옵션은 인식 목록에 없다" {
  # 인식 목록은 손으로 관리하는 화이트리스트다. 항목을 추가하는 것은
  # 안전성 판단이므로, "무엇이 커밋되는지 바꾸는" 옵션이 목록에 들어오면
  # 여기서 잡는다. a.ts 는 unstaged 라서 unknown 이 켜져야만 나타난다.
  mixed_state
  local wt opt; wt="$(git hash-object a.ts)"
  for opt in --pathspec-from-file --pathspec-file-nul --interactive --patch; do
    run pending "git commit $opt zzz -m x"
    if [[ "$output" != *"$wt"* ]]; then
      echo "$opt 가 인식 목록에 있어 unknown 이 켜지지 않는다 — 게이트 구멍" >&2
      return 1
    fi
  done
}

@test "왕복: 모든 커맨드 형태에서 deny → 같은 커맨드로 record → allow" {
  local form out
  while IFS= read -r form; do
    setup_repo; seed_repo
    mixed_state

    out="$(run_gate "$form")"
    if [[ "$out" != *"deny"* ]]; then
      echo "형태: $form — deny 가 나와야 하는데 안 나왔다: [$out]" >&2
      return 1
    fi

    # 스킬은 훅이 사유에 실어 보낸 커맨드를 **그대로** 넘긴다.
    if ! record_pass "$VALID" "$form" >/dev/null 2>&1; then
      echo "형태: $form — record-pass.sh 가 실패했다(교착)" >&2
      return 1
    fi

    out="$(run_gate "$form")"
    if [ -n "$out" ]; then
      echo "형태: $form — 기록 후에도 여전히 막힌다(교착): $out" >&2
      return 1
    fi
    teardown_repo
  done < <(command_forms)
}

@test "deny 사유에 차단된 커맨드 원문이 실려 온다" {
  # 스킬이 "git commit" 을 임의로 가정하지 않으려면 원문이 있어야 한다.
  mixed_state
  run run_gate 'git commit -am "x"'
  [[ "$output" == *'git commit -am '* ]]
}

@test "작은따옴표가 든 커밋 메시지도 왕복한다" {
  # 훅이 준 커맨드를 스킬이 작은따옴표로 감싸 넘기는데, 메시지 안의 '
  # 가 그 자리에서 따옴표를 닫아 셸 문법 오류가 났다. 스크립트가 실행조차
  # 되지 않으니 퀴즈도 기록도 불가능 — 커밋이 영구히 막혔다.
  # SKILL.md §0 이 지시하는 '\'' 이스케이프가 적용된 형태로 검증한다.
  local cmd
  cmd='git commit -m "don'\''t fix -- a.ts"'
  printf 'A2\n' > a.ts
  git add a.ts

  run run_gate "$cmd"
  [[ "$output" == *"deny"* ]]
  [[ "$output" == *"a.ts"* ]]

  # 스킬이 SKILL.md 규칙대로 감싼 그대로 실행한다.
  run bash -c "bash '$PLUGIN_ROOT/scripts/pending-set.sh' 'git commit -m \"don'\\''t fix -- a.ts\"'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$(git hash-object a.ts)"* ]]

  run bash -c "echo '$VALID' | bash '$PLUGIN_ROOT/scripts/record-pass.sh' 'git commit -m \"don'\\''t fix -- a.ts\"'"
  [ "$status" -eq 0 ]

  run run_gate "$cmd"
  [ -z "$output" ]
}

@test "계약: SKILL.md 는 작은따옴표 이스케이프를 지시한다" {
  local skill="$PLUGIN_ROOT/skills/kkochikkochi/SKILL.md"
  grep -qF "'\\''" "$skill"
}

@test "계약: SKILL.md 에 중첩된 삼중 백틱 블록이 없다" {
  # 삼중 백틱 안에 삼중 백틱을 넣으면 바깥 펜스가 먼저 닫혀 예시가
  # 깨진 채로 렌더링된다. 펜스 개수는 짝수여야 한다.
  local skill="$PLUGIN_ROOT/skills/kkochikkochi/SKILL.md"
  local n
  n="$(grep -c '^```' "$skill")"
  [ $((n % 2)) -eq 0 ]
}

@test "deny 사유의 구분선은 커맨드 내용과 충돌하지 않는다" {
  # 예전에는 삼중 백틱 펜스였다. 커맨드가 삼중 백틱을 담고 있으면
  # (마크다운을 heredoc 으로 쓰고 && git commit 하는 흔한 형태) 펜스가
  # 일찍 닫혀 스킬이 잘린 문자열을 받는다.
  printf 'C1\n' > c.ts; git add c.ts
  local cmd
  cmd='printf "```
KKOCHI_CMD
" > d.md && git commit -m x'
  run run_gate "$cmd"
  [[ "$output" == *"deny"* ]]
  # 커맨드가 기본 마커를 이미 담고 있으므로 훅은 다른 마커를 골라야 한다.
  [[ "$output" == *"KKOCHI_CMD_1"* ]]
}

@test "계약: SKILL.md 는 커맨드를 하드코딩하지 않는다" {
  # C3 의 실제 발생 지점은 셸이 아니라 SKILL.md 였다 — 훅이 사용자의 진짜
  # 커맨드로 판정하는데 스킬은 "git commit" 을 하드코딩해, `git commit -am x`
  # 에서 훅은 막고 스킬은 볼 게 없는 영구 교착이 났다. 마크다운은 실행할 수
  # 없으니 계약을 텍스트로 못박아 회귀를 막는다.
  local skill="$PLUGIN_ROOT/skills/kkochikkochi/SKILL.md"
  [ -f "$skill" ]
  ! grep -q 'pending-set\.sh" *"git commit"' "$skill"
  ! grep -q 'record-pass\.sh" *"git commit"' "$skill"
  # 두 스크립트 모두 같은 자리표시자를 받아야 한다.
  grep -q 'pending-set\.sh".*BLOCKED_COMMAND' "$skill"
  grep -q 'record-pass\.sh".*BLOCKED_COMMAND' "$skill"
}

@test "교착 재현: -am 은 훅과 스킬이 같은 집합을 본다" {
  # C3 의 정확한 재현 경로. a.ts 만 수정, 스테이징 없음.
  printf 'A2\n' > a.ts
  run run_gate 'git commit -am "x"'
  [[ "$output" == *"deny"* ]]
  [[ "$output" == *"a.ts"* ]]

  run pending 'git commit -am "x"'
  [ -n "$output" ]                               # 예전에는 여기가 비어서 스킬이 멈췄다
  [[ "$output" == *"$(git hash-object a.ts)"* ]]

  run record_pass "$VALID" 'git commit -am "x"'
  [ "$status" -eq 0 ]

  run run_gate 'git commit -am "x"'
  [ -z "$output" ]
}

@test "비ASCII 경로도 실제 blob SHA 로 나온다(core.quotePath 기본값)" {
  # git 기본값 core.quotePath=true 에서는 비ASCII 경로가 C 이스케이프되어
  # (`"\355\225\234..."`) 파일이 없는 것처럼 보이고 NULL_SHA 가 나온다.
  # NULL_SHA 는 내용과 무관하므로 한 번 커버되면 그 파일은 어떻게 바뀌어도
  # 다시 묻지 않는다 — 한국어 도구에서 한글 파일명은 기본 사례다.
  git config core.quotePath true
  printf 'K1\n' > 한글.ts
  git add 한글.ts
  git commit -qm korean
  printf 'K2\n' > 한글.ts

  run pending 'git commit -am "x"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"$(git hash-object 한글.ts)"$'\t'"한글.ts"* ]]
  [[ "$output" != *"$NULL_SHA"* ]]
  [[ "$output" != *'\355'* ]]

  git add 한글.ts
  run pending 'git commit -m "x"'
  [[ "$output" == *"$(git hash-object 한글.ts)"$'\t'"한글.ts"* ]]
}

@test "비ASCII 경로는 커버 후 내용이 바뀌면 다시 deny 한다" {
  git config core.quotePath true
  printf 'K1\n' > 한글.ts
  git add 한글.ts
  git commit -qm korean
  printf 'K2\n' > 한글.ts

  run record_pass "$VALID" 'git commit -am "x"'
  [ "$status" -eq 0 ]
  run run_gate 'git commit -am "x"'
  [ -z "$output" ]                    # 커버됨

  printf 'K3\n' > 한글.ts             # 내용이 바뀌었다
  run run_gate 'git commit -am "x"'
  [[ "$output" == *"deny"* ]]         # NULL_SHA 였다면 여기서 조용히 통과했다
}

@test "초기 커밋 + -a 는 stderr 에 아무것도 쓰지 않는다" {
  # 스킬은 스크립트를 직접 실행하므로 `fatal: ambiguous argument 'HEAD'`
  # 가 그대로 LLM 입력에 들어간다. 근원에서 막혀 있어야 한다.
  local fresh err
  fresh="$(mktemp -d)"
  err="$(mktemp)"
  (
    cd "$fresh" || exit 1
    git init -q .
    printf 'A1\n' > a.ts
    git add a.ts
    bash "$PLUGIN_ROOT/scripts/pending-set.sh" 'git commit -am "x"' >/dev/null 2>"$err"
  )
  [ ! -s "$err" ]
  rm -rf "$fresh" "$err"
}

@test "긴 커맨드도 훅 타임아웃(10s) 안에 판정된다" {
  local big payload start elapsed
  big="$(head -c 40000 /dev/zero | tr '\0' 'x')"
  printf 'C1\n' > c.ts; git add c.ts
  start=$SECONDS
  payload=$(jq -n --arg c "git commit -m \"$big\"" --arg cwd "$PWD" \
    '{tool_name:"Bash", cwd:$cwd, tool_input:{command:$c}}')
  echo "$payload" | bash "$PLUGIN_ROOT/hooks/gate.sh" >/dev/null
  elapsed=$((SECONDS - start))
  # 실측 1.5s. O(n^2) 로 되돌아가면 이 크기에서 ~16s 가 되므로 4s 면
  # 넉넉히 잡히고, CI 러너가 느려도 2배 이상 여유가 있다.
  [ "$elapsed" -lt 4 ]
}

@test "commit 이 없는 긴 커맨드는 토큰화 없이 즉시 통과한다" {
  local big payload start elapsed
  big="$(head -c 200000 /dev/zero | tr '\0' 'x')"
  printf 'C1\n' > c.ts; git add c.ts
  start=$SECONDS
  payload=$(jq -n --arg c "echo $big" --arg cwd "$PWD" \
    '{tool_name:"Bash", cwd:$cwd, tool_input:{command:$c}}')
  run bash -c "echo '$payload' | bash '$PLUGIN_ROOT/hooks/gate.sh'"
  elapsed=$((SECONDS - start))
  [ -z "$output" ]
  [ "$elapsed" -lt 2 ]   # 실측 0.03s — 사전 필터가 빠지면 즉시 잡힌다
}

@test "토크나이저: 조각 경계에 정확히 걸친 && 도 세그먼트를 나눈다" {
  # 조각 크기는 1024. 경계에 걸친 &/| 를 하나만 넘기면 `...&&` 로 끝나는
  # 조각에서 두 글자가 각각 평범한 글자로 처리되어 세그먼트 구분자가
  # 사라진다. 오프셋을 하나 찍기보다 경계 주변을 훑어 전부 확인한다.
  # (기존 1024 경계 테스트는 && 를 따옴표 안에 넣어 이 경로를 안 탔다.)
  # shellcheck source=scripts/lib-tokenize.sh
  . "$PLUGIN_ROOT/scripts/lib-tokenize.sh"
  local n pad last
  for n in 1014 1015 1016 1017 1018 1019 1020 1021 1022 1023 1024; do
    pad="$(head -c "$n" /dev/zero | tr '\0' 'x')"
    tokenize_cmd "echo $pad && git commit"
    last=$(( ${#TOKENS[@]} - 1 ))
    if [ "${TOKENS[$last]}" != "commit" ] || [ "${TOK_SEG[$last]}" != "1" ]; then
      echo "pad=$n: 마지막 토큰 [${TOKENS[$last]}] seg=${TOK_SEG[$last]} (기대: commit seg=1)" >&2
      return 1
    fi
  done
}

@test "토크나이저 조각 경계(1024)를 넘어도 결과가 같다" {
  # 긴 커맨드는 1024 바이트 조각으로 나눠 처리한다. 경계에 걸친 && 나
  # 따옴표 때문에 세그먼트가 어긋나면 -C 나 commit 을 놓친다.
  local pad other
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
  # -C 앞에 1024 경계를 여러 번 넘기는 긴 값을 끼워 넣는다.
  pad="$(head -c 3000 /dev/zero | tr '\0' 'y')"
  run run_gate "git -c alias.pad=\"$pad && z\" -C '$other' commit -m x"
  [[ "$output" == *"deny"* ]]
  [[ "$output" == *"o.ts"* ]]
  rm -rf "$other"
}

@test "record-pass 는 git -C 가 가리키는 저장소에 기록한다" {
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
  run run_gate "git -C '$other' commit -m x"
  [[ "$output" == *"deny"* ]]

  # 세션 레포(현재 $PWD)에서 실행하지만 기록은 저쪽으로 가야 한다.
  run record_pass "$VALID" "git -C '$other' commit -m x"
  [ "$status" -eq 0 ]

  other_git_dir="$(cd "$other" && git rev-parse --git-dir)"
  case "$other_git_dir" in
    /*) : ;;
    *) other_git_dir="$other/$other_git_dir" ;;
  esac
  [ -f "$other_git_dir/quiz-gate/covered.tsv" ]
  [ ! -e "$(git rev-parse --git-dir)/quiz-gate/covered.tsv" ]

  run run_gate "git -C '$other' commit -m x"
  [ -z "$output" ]
  rm -rf "$other"
}
