#!/usr/bin/env bats

load helper

setup() { setup_repo; seed_repo; }
teardown() { teardown_repo; }

hc() {  # $1 = command string
  jq -n --arg c "$1" --arg cwd "$PWD" --arg s "sess-1" \
    '{tool_name:"Bash", cwd:$cwd, session_id:$s, tool_input:{command:$c}}' \
  | bash "$PLUGIN_ROOT/scripts/stamp-agent.sh" --agent claude-code
}

@test "훅 미설치 + 커밋으로 보이는 명령 → deny 한다" {
  run hc 'git commit -m x'
  [[ "$output" == *"deny"* ]]
}

@test "deny 사유에 실행 가능한 설치 명령이 들어 있다" {
  run hc 'git commit -m x'
  [[ "$output" == *"install.sh"* ]]
}

@test "훅이 설치돼 있으면 deny 하지 않는다" {
  bash "$PLUGIN_ROOT/scripts/install.sh" install 2>/dev/null
  run hc 'git commit -m x'
  [ -z "$output" ]
}

@test "커밋이 아닌 명령은 훅이 없어도 통과시킨다" {
  run hc 'ls -la'
  [ -z "$output" ]
}

@test "--no-verify 는 훅이 설치돼 있어도 deny 한다" {
  bash "$PLUGIN_ROOT/scripts/install.sh" install 2>/dev/null
  run hc 'git commit --no-verify -m x'
  [[ "$output" == *"deny"* ]]
  [[ "$output" == *"no-verify"* ]]
}

@test "core.hooksPath 저장소에서는 설치 대신 상황을 설명한다" {
  mkdir -p .myhooks; git config core.hooksPath .myhooks
  run hc 'git commit -m x'
  [[ "$output" == *"core.hooksPath"* ]]
}

# ── I1: --no-verify 의 짧은 형태 ──

@test "짧은 -n 도 --no-verify 와 같이 deny 한다" {
  bash "$PLUGIN_ROOT/scripts/install.sh" install 2>/dev/null
  # 대조군: 같은 저장소에서 평범한 커밋은 통과한다 — 아래 deny 가 -n 때문임을 못 박는다
  run hc 'git commit -m x'
  [ -z "$output" ]
  for c in 'git commit -n -m x' 'git commit -nm x' 'git commit -qn -m x' 'git commit -nqm x'; do
    run hc "$c"
    [[ "$output" == *"deny"* ]] || { echo "[$c] 를 통과시켰다"; return 1; }
    [[ "$output" == *"no-verify"* ]]
  done
}

@test "n 이 없는 짧은 플래그는 통과시킨다" {
  bash "$PLUGIN_ROOT/scripts/install.sh" install 2>/dev/null
  for c in 'git commit -am x' 'git commit -q -m x' 'git commit -S -m x'; do
    run hc "$c"
    [ -z "$output" ] || { echo "[$c] 를 잘못 거부했다: $output"; return 1; }
  done
}

# ── I5: 낡은 훅 ──

@test "설치된 훅이 낡았으면 재설치를 요구한다" {
  bash "$PLUGIN_ROOT/scripts/install.sh" install 2>/dev/null
  # 대조군: 최신 훅이면 아무 말도 하지 않는다
  run hc 'git commit -m x'
  [ -z "$output" ]
  # 옛 판의 훅을 흉내 낸다 — 마커는 있지만 내용이 다르다
  printf '#!/bin/sh\n# KKOCHIKKOCHI-HOOK-v1 (ancient)\nexit 0\n' > "$(hooksdir)/pre-commit"
  chmod +x "$(hooksdir)/pre-commit"
  run hc 'git commit -m x'
  [[ "$output" == *"deny"* ]]
  [[ "$output" == *"install.sh"* ]]
  [[ "$output" == *"낡"* ]]
}

@test "실행 권한이 없는 훅도 낡은 것으로 보고 재설치를 요구한다" {
  # git 은 실행 권한 없는 훅을 그냥 무시한다 — "설치됨"이라고 답하면
  # 게이트가 조용히 없는 상태가 된다.
  bash "$PLUGIN_ROOT/scripts/install.sh" install 2>/dev/null
  chmod -x "$(hooksdir)/pre-commit"
  run hc 'git commit -m x'
  [[ "$output" == *"deny"* ]]
  [[ "$output" == *"install.sh"* ]]
}
