#!/usr/bin/env bats

load helper

setup() { setup_repo; seed_repo; }
teardown() { teardown_repo; }

record() {  # $1 = transcript JSON
  echo "$1" | bash "$PLUGIN_ROOT/scripts/record-pass.sh"
}

qdir() { echo "$(git rev-parse --git-dir)/quiz-gate"; }

VALID='{"questions":[{"axis":"facts","q":"무엇이 바뀌었나?","evidence":"c.ts:1","format":"choice","answer":"A","correct":"A","attempts":1,"gave_up":false}]}'

@test "통과를 기록하면 covered.tsv 에 라인이 생긴다" {
  printf 'C1\n' > c.ts; git add c.ts
  run record "$VALID"
  [ "$status" -eq 0 ]
  grep -q "$(git hash-object c.ts)" "$(qdir)/covered.tsv"
}

@test "covered.tsv 라인은 SHA/경로/pass_id 세 필드다" {
  printf 'C1\n' > c.ts; git add c.ts
  record "$VALID"
  line="$(head -1 "$(qdir)/covered.tsv")"
  [ "$(awk -F'\t' '{print NF}' <<<"$line")" -eq 3 ]
}

@test "문답 전문이 passes/ 에 저장된다" {
  printf 'C1\n' > c.ts; git add c.ts
  record "$VALID"
  [ "$(find "$(qdir)/passes" -name 'p-*.json' | wc -l)" -eq 1 ]
}

@test "저장된 JSON 에 questions 가 보존된다" {
  printf 'C1\n' > c.ts; git add c.ts
  record "$VALID"
  f="$(find "$(qdir)/passes" -name 'p-*.json' | head -1)"
  [ "$(jq -r '.transcript.questions[0].axis' "$f")" = "facts" ]
}

@test "SHA 는 인자가 아니라 스크립트가 직접 계산한다" {
  printf 'C1\n' > c.ts; git add c.ts
  record "$VALID"
  grep -q "$(git hash-object c.ts)"$'\t'"c.ts" "$(qdir)/covered.tsv"
}

@test "문항이 0개면 거부한다" {
  printf 'C1\n' > c.ts; git add c.ts
  run record '{"questions":[]}'
  [ "$status" -eq 1 ]
  [ ! -f "$(qdir)/covered.tsv" ]
}

@test "서술형 답변이 공백이면 거부한다" {
  printf 'C1\n' > c.ts; git add c.ts
  bad='{"questions":[{"axis":"intent","q":"왜?","evidence":"대화","format":"free","answer":"   ","correct":null,"attempts":1,"gave_up":false}]}'
  run record "$bad"
  [ "$status" -eq 1 ]
  [ ! -f "$(qdir)/covered.tsv" ]
  [ ! -d "$(qdir)/passes" ]
}

@test "skipped_reason 이 있으면 문항 0개라도 기록한다" {
  printf 'C1\n' > c.ts; git add c.ts
  run record '{"questions":[],"skipped_reason":"lockfile 재생성만 포함"}'
  [ "$status" -eq 0 ]
  grep -q "c.ts" "$(qdir)/covered.tsv"
}

@test "잘못된 JSON 은 거부한다" {
  printf 'C1\n' > c.ts; git add c.ts
  run record 'not json at all'
  [ "$status" -eq 1 ]
  [ ! -f "$(qdir)/covered.tsv" ]
  [ ! -d "$(qdir)/passes" ]
}

@test "questions 가 문자열이면 거부한다" {
  printf 'C1\n' > c.ts; git add c.ts
  run record '{"questions":"abc"}'
  [ "$status" -eq 1 ]
  [ ! -f "$(qdir)/covered.tsv" ]
  [ ! -d "$(qdir)/passes" ]
}

@test "questions 가 객체면 거부한다" {
  printf 'C1\n' > c.ts; git add c.ts
  run record '{"questions":{}}'
  [ "$status" -eq 1 ]
  [ ! -f "$(qdir)/covered.tsv" ]
  [ ! -d "$(qdir)/passes" ]
}

@test "questions 가 정상 배열이면 여전히 기록된다" {
  printf 'C1\n' > c.ts; git add c.ts
  run record "$VALID"
  [ "$status" -eq 0 ]
  grep -q "c.ts" "$(qdir)/covered.tsv"
}

@test "전문 저장이 실패하면 covered.tsv 에 유령 라인을 남기지 않는다" {
  if [ "$(id -u)" -eq 0 ]; then
    skip "root 로 실행하면 읽기 전용 디렉터리가 쓰기를 막지 못한다"
  fi
  printf 'C1\n' > c.ts; git add c.ts
  mkdir -p "$(qdir)/passes"
  chmod 555 "$(qdir)/passes"
  run record "$VALID"
  chmod 755 "$(qdir)/passes"
  [ "$status" -ne 0 ]
  if [ -f "$(qdir)/covered.tsv" ]; then
    run grep -q "c.ts" "$(qdir)/covered.tsv"
    [ "$status" -ne 0 ]
  fi
}

@test "여러 번 기록하면 covered.tsv 에 누적된다" {
  printf 'C1\n' > c.ts; git add c.ts
  record "$VALID"
  printf 'D1\n' > d.ts; git add d.ts
  record "$VALID"
  [ "$(wc -l < "$(qdir)/covered.tsv")" -ge 2 ]
}

@test "기록 후 gate.sh 가 통과시킨다 (종단 확인)" {
  printf 'C1\n' > c.ts; git add c.ts
  record "$VALID"
  payload=$(jq -n --arg c 'git commit -m x' --arg cwd "$PWD" \
    '{tool_name:"Bash", cwd:$cwd, tool_input:{command:$c}}')
  run bash -c "echo '$payload' | bash '$PLUGIN_ROOT/hooks/pre-commit'"
  [ -z "$output" ]
}

# 아래 세 테스트는 Task 1~3 리뷰에서 넘어온 계약을 record-pass.sh 스스로가
# 지키는지 확인한다 (mark_covered 같은 테스트 전용 헬퍼가 아니라 실제
# record-pass.sh 출력으로). agent-session 핸드셰이크를 직접 남기고 진짜
# `git commit` 을 설치된 훅으로 태워, record-pass.sh 가 쓴 철자가 훅이 읽는
# 철자와 정확히 같은지까지 왕복으로 증명한다.

@test "따옴표가 든 경로도 기록된 철자 그대로 게이트를 통과시킨다" {
  install_hook
  printf 'W1\n' > 'we"ird.ts'; git add 'we"ird.ts'
  run record "$VALID"
  [ "$status" -eq 0 ]
  grep -Fq 'we"ird.ts' "$(qdir)/covered.tsv"
  stamp
  run commit_as_human -m x
  [ "$status" -eq 0 ]
}

@test "역슬래시가 든 경로도 기록된 철자 그대로 게이트를 통과시킨다" {
  install_hook
  printf 'W2\n' > 'back\slash.ts'; git add 'back\slash.ts'
  run record "$VALID"
  [ "$status" -eq 0 ]
  grep -Fq 'back\slash.ts' "$(qdir)/covered.tsv"
  stamp
  run commit_as_human -m x
  [ "$status" -eq 0 ]
}

@test "삭제된 파일은 40개의 0 SHA 로 기록되고 게이트를 통과시킨다" {
  install_hook
  printf 'OLD2\n' > old2.ts; git add old2.ts; commit_as_human -qm add-old2
  git rm -q old2.ts
  run record "$VALID"
  [ "$status" -eq 0 ]
  grep -q "^${NULL_SHA}"$'\t'"old2.ts"$'\t' "$(qdir)/covered.tsv"
  stamp
  run commit_as_human -m x
  [ "$status" -eq 0 ]
}
