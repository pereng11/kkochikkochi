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

# ── 건강검진 ─────────────────────────────────────────────────────
# 게이트가 조용히 없는 상태를 막는다. 여기서 부정확해도 안전하다:
# 오탐이면 안내 한 번, 미탐이면 게이트가 없던 v1 과 같을 뿐이다. (D29)
cmd="$(jq -r '.tool_input.command // ""' <<<"$payload" 2>/dev/null || echo "")"
case "$cmd" in
  *commit*) ;;
  *) exit 0 ;;
esac

deny() {  # $1 = 사유
  jq -n --arg r "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
  exit 0
}

case "$cmd" in
  *--no-verify*)
    deny "🦡 KkochiKkochi — --no-verify 는 git 훅을 건너뛰므로 이해 검증도 건너뜁니다.
플래그 없이 다시 커밋하세요. 정말 건너뛰어야 한다면 사용자에게 먼저 확인하세요." ;;
esac

INSTALL_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/install.sh"
if ! bash "$INSTALL_SH" status >/dev/null 2>&1; then
  if [ -n "$(git config --get core.hooksPath || true)" ]; then
    deny "🦡 KkochiKkochi — 이 저장소는 core.hooksPath 를 사용해 자동 설치를 하지 않았습니다.
실효 훅 디렉터리가 저장소에 추적되므로 말없이 파일을 쓰지 않습니다.
사용자에게 다음 중 무엇을 원하는지 물어보세요:
  1) 그 디렉터리에 직접 설치 (추적되는 변경이 생김)
  2) core.hooksPath 해제 후 재설치
  3) 이 저장소에서는 게이트를 사용하지 않음"
  fi
  deny "🦡 KkochiKkochi — 이 저장소에 게이트가 아직 설치되지 않았습니다.
다음 명령을 실행한 뒤 커밋을 다시 시도하세요:

  bash \"$INSTALL_SH\" install

기존 pre-commit 훅이 있으면 자동으로 체이닝되며 먼저 실행됩니다."
fi

exit 0
