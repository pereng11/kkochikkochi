#!/usr/bin/env bash
# 에이전트 훅이 발동했다는 사실을 기록한다 (핸드셰이크).
#
# 이 스크립트가 실행됐다 = 에이전트가 도구를 호출했다. 판별할 필요가 없다. (D34)
# Claude Code 와 Codex 는 훅 stdin JSON 스키마가 같아 같은 스크립트를 쓴다. (D36)
#
# 사용법: <hook json> | stamp-agent.sh --agent <name>
# stdout 에는 절대 쓰지 않는다 — 훅 프로토콜에서 stdout 은 판정 채널이다.

set -uo pipefail

AGENT="unknown"
while [ $# -gt 0 ]; do
  case "$1" in
    --agent) AGENT="${2:-unknown}"; shift ;;
  esac
  shift
done

payload="$(cat)"

git rev-parse --git-dir >/dev/null 2>&1 || exit 0
qdir="$(git rev-parse --git-path quiz-gate)"
mkdir -p "$qdir" 2>/dev/null || exit 0

session="unknown"
if command -v jq >/dev/null 2>&1; then
  session="$(jq -r '.session_id // "unknown"' <<<"$payload" 2>/dev/null || echo unknown)"
fi

printf '%s/%s\n' "$AGENT" "$session" > "$qdir/agent-session" 2>/dev/null || exit 0
exit 0
