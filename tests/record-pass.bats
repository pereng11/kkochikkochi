#!/usr/bin/env bats

load helper

setup() { setup_repo; seed_repo; }
teardown() { teardown_repo; }

record() {  # $1 = transcript JSON, $2 = command
  echo "$1" | bash "$PLUGIN_ROOT/scripts/record-pass.sh" "${2:-git commit -m x}"
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
  run bash -c "echo '$payload' | bash '$PLUGIN_ROOT/hooks/gate.sh'"
  [ -z "$output" ]
}
