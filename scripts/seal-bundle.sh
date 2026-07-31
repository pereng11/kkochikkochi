#!/usr/bin/env bash
# SubagentStart / SubagentStop — 번들을 열고 봉인한다.
#
# 사용법: <hook json> | seal-bundle.sh --event start|stop
# 출력:   없음. stdout 은 훅의 판정 채널이고 이 스크립트는 판정하지 않는다.
#
# 왜 필요한가: PostToolUse(Task) 는 부모 문맥에서 돌아 agent_id 를 받지 못한다
# (SDK: "Present only when the hook fires from inside a Task-spawned
# sub-agent"). 어느 번들이 끝났는지는 여기서만 알 수 있으므로 디스크에 남긴다.
#
# 여기서 퀴즈를 내지 않는 이유: SubagentStop 은 서브에이전트 문맥에서 돌고,
# 거기서 block 을 내면 그 서브에이전트가 계속 일하게 된다. 사람에게 묻는
# 채널이 없으므로 검증은 불가능하고, 경계를 정하는 데만 쓸 수 있다.

set -uo pipefail

EVENT="stop"
while [ $# -gt 0 ]; do
  case "$1" in
    --event) EVENT="${2:-stop}"; shift ;;
  esac
  shift
done

payload="$(cat)"

command -v jq >/dev/null 2>&1 || exit 0

cwd="$(jq -r '.cwd // ""' <<<"$payload" 2>/dev/null || echo "")"
# stop-gate.sh 가 이미 겪은 것과 같은 문제다: `[ -n "$cwd" ] && cd "$cwd"
# 2>/dev/null` 는 shellcheck 의 "cd 실패 검사 없음"(SC2164) 에 걸리는데,
# `&&` 뒤에 `|| exit` 를 그대로 이어붙이면 cwd 가 애초에 비어 있어
# `[ -n "$cwd" ]` 가 실패했을 때도 우변이 실행돼 스크립트가 죽는다 — "출력
# 없음, 종료 항상 0" 계약을 cwd 가 없는 흔한 경우에 깨버린다. cd 가 진짜로
# 실패했을 때만(cwd 가 더 이상 존재하지 않는 등) 애매함으로 통과시켜야
# 하므로 if 로 감싼다.
if [ -n "$cwd" ]; then
  cd "$cwd" 2>/dev/null || exit 0
fi

git rev-parse --git-common-dir >/dev/null 2>&1 || exit 0
qdir="$(git rev-parse --git-common-dir)/quiz-gate"

agent_id="$(jq -r '.agent_id // ""' <<<"$payload" 2>/dev/null || echo "")"
agent_type="$(jq -r '.agent_type // ""' <<<"$payload" 2>/dev/null || echo "")"
[ -n "$agent_id" ] || exit 0

# 마커(scripts/stamp-agent.sh)와 같은 정규화를 쓴다 — 두 곳의 파일명이
# 어긋나면 번들을 찾지 못한다. 문자 그대로 복사했다: `tr -c 'A-Za-z0-9_-'
# '_' | cut -c1-64`.
name="$(printf '%s' "$agent_id" | tr -c 'A-Za-z0-9_-' '_' | cut -c1-64)"
[ -n "$name" ] || exit 0

mkdir -p "$qdir/agents" 2>/dev/null || exit 0
file="$qdir/agents/$name"
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

started=""
[ -r "$file" ] && started="$(cut -f2 "$file" 2>/dev/null | head -n 1)"
[ -n "$started" ] || started="$now"

if [ "$EVENT" = "start" ]; then
  # 이미 봉인된 같은 이름이 있으면(재개된 에이전트) 봉인을 푼다 — 새 커밋이
  # 이어질 수 있고, 봉인된 채로 두면 그 뒤 커밋이 요구 대상에서 빠진다.
  printf '%s\t%s\t%s\n' "$agent_type" "$started" "" > "$file" 2>/dev/null || :
else
  printf '%s\t%s\t%s\n' "$agent_type" "$started" "$now" > "$file" 2>/dev/null || :
fi
exit 0
