#!/usr/bin/env bash
# 에이전트 훅이 발동했다는 사실을 기록한다 (핸드셰이크).
#
# 이 스크립트가 실행됐다 = 에이전트가 도구를 호출했다. 판별할 필요가 없다. (D34)
# Claude Code 와 Codex 는 훅 stdin JSON 스키마가 같아 같은 스크립트를 쓴다. (D36)
#
# 사용법: <hook json> | stamp-agent.sh --agent <name>
#
# stdout 은 훅 프로토콜의 판정 채널이다. 핸드셰이크 경로는 여기에 아무것도
# 쓰지 않고, 아래 deny() 만이 의도적으로 판정 JSON 한 덩어리를 쓴다.
#
# 주의: 핸드셰이크는 **이 프로세스의 cwd 저장소**에 남는다. 에이전트가
# `git -C ../other commit` 처럼 다른 저장소를 커밋하면 그쪽에는 마커가
# 없으므로 게이트는 환경변수 신호에만 기댄다 — Claude Code 는 CLAUDECODE
# 덕에 우연히 걸리지만 Codex 는 아무 변수도 내보내지 않아 전혀 걸리지
# 않는다. README 의 한계 표에 적어둔 알려진 구멍이다.

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

# ── 프리필터 — 커밋·push 처럼 보이는 명령에서만 무언가를 한다 ──────
# 단순 문자열 포함 검사이므로 `git log --grep=commit` 처럼 커밋을 만들지 않는
# 명령도 여기를 통과해, 미설치 저장소에서는 설치 안내로 한 번 거부당한다.
# D29 가 명시적으로 감수하는 오탐이다 — 오탐은 안내 한 번, 미탐은 게이트가
# 조용히 없는 것이다.
#
# jq 가 없으면 cmd 가 비어 여기서 조용히 빠져나간다. 그래도 괜찮다 — deny()
# 자체가 jq 로 판정 JSON 을 만들므로 jq 없이는 애초에 거부할 방법이 없고,
# 그 환경은 설치기가 설치를 거부해서 게이트 자체가 없다 (D42).
cmd="$(jq -r '.tool_input.command // ""' <<<"$payload" 2>/dev/null || echo "")"

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

deny_no_verify() {
  deny "🦡 KkochiKkochi — --no-verify (짧게 -n) 는 git 훅을 건너뛰므로 이해 검증도 건너뜁니다.
플래그 없이 다시 시도하세요. 정말 건너뛰어야 한다면 사용자에게 먼저 확인하세요."
}

# ── commit 과 push 를 여기서 갈라 둔다 (F2) ─────────────────────────
# `hooks/pre-push` 는 Stop 을 Esc 로 빠져나간 에이전트를 잡는 최종 경계다
# (README "동작 원리"). 그런데 아래 --no-verify/-n 검사는 예전에 *commit*
# 프리필터 뒤에 있었다 — `git push --no-verify` 는 "commit" 이라는 글자를
# 담지 않으므로 애초에 이 스크립트에 들어오지도 못했고(실측: deny() 가
# 전혀 안 불림), pre-push 를 잡으려고 만든 에이전트 훅이 정작 pre-push 를
# 우회하는 그 명령 앞에서는 아무것도 하지 않았다.
#
# 그렇다고 프리필터 자체를 `*commit*|*push*` 로 넓히면 안 된다 — 그러면
# 아래 마커 쓰기가 매 `git push` 마다 실행돼, D44 가 고친 문제(마커가 항상
# 신선해 그 창에 들어온 모든 커밋이 출처와 무관하게 에이전트 커밋으로
# 보이던 것)가 그대로 되살아난다. push 는 커밋보다 훨씬 잦고(동기화 목적의
# 빈 push 포함), IDE·GUI 클라이언트는 git 을 파이프로 띄워 TTY 구제(D41)도
# 닿지 않으므로 실제 피해가 D44 때보다 크면 컸지 작지 않다.
#
# 그래서 --no-verify/-n 판정만 *push* 도 함께 보게 넓히고, 마커 쓰기와 설치
# 건강검진은 여전히 *commit* 프리필터(아래) 하나로만 게이트한다. 다음
# 사람이 이 둘을 하나로 합치고 싶어질 것이다 — 합치면 이 문단이 설명한
# D44 재발이 정확히 그 방식으로(이번엔 push 경유로) 돌아온다.
case "$cmd" in
  *commit*|*push*)
    case "$cmd" in
      *--no-verify*) deny_no_verify ;;
    esac
    # 짧은 형태 -n 도 같은 일을 한다. 토크나이저는 들이지 않는다 (D30) —
    # 공백으로 구분된 낱말 중 `-`(하이픈 하나)로 시작하고 그 묶음 안에 n 이
    # 들어 있는 것을 찾는 유계 검사면 충분하다. `-n`, `-nm`, `-qn`, `-nqm`
    # 이 전부 걸린다.
    #
    # 오탐 방향으로 헐겁게 잡는다: 커밋 메시지 안에 " -n " 이 들어 있거나
    # `git log -n 5 --grep=commit` 같은 명령도 걸린다. D29 대로 오탐은
    # 왕복 한 번의 비용이고, 미탐은 게이트가 아무 흔적 없이 사라지는 것이다.
    short_n_re='(^|[[:space:]])-[A-Za-z]*n[A-Za-z]*([[:space:]]|$)'
    if [[ "$cmd" =~ $short_n_re ]]; then
      deny_no_verify
    fi
    ;;
esac

# ── 아래(마커 쓰기 + 건강검진)는 *commit* 에서만 한다 ────────────────
case "$cmd" in
  *commit*) ;;
  *) exit 0 ;;
esac

# ── 핸드셰이크 ───────────────────────────────────────────────────
# **커밋처럼 보이는 명령에서만 마커를 남긴다.** (D44)
#
# 예전에는 매 Bash 호출마다 남겼다. 그러면 에이전트가 이 저장소에서 무엇이든
# 하고 있는 동안 마커가 늘 신선해서, 그 창 안에 들어온 **모든** 커밋이 출처와
# 무관하게 에이전트 커밋으로 보였다. IDE·GUI git 클라이언트는 git 을 pty 가
# 아니라 파이프로 띄우므로 TTY 구제(D41)도 닿지 않아, 실제로 IDE 커밋이
# 막혔다 — README 가 막지 않는다고 약속한, 그리고 D00 이 명시적으로 금지하는
# 바로 그것이다.
#
# 이제 마커는 에이전트가 실제로 커밋하기 직전 몇 초 동안만 존재한다.
qdir="$(git rev-parse --git-common-dir)/quiz-gate"
mkdir -p "$qdir" 2>/dev/null || exit 0

session="unknown"
agent_id=""
agent_type=""
if command -v jq >/dev/null 2>&1; then
  session="$(jq -r '.session_id // "unknown"' <<<"$payload" 2>/dev/null || echo unknown)"
  agent_id="$(jq -r '.agent_id // ""' <<<"$payload" 2>/dev/null || echo "")"
  agent_type="$(jq -r '.agent_type // ""' <<<"$payload" 2>/dev/null || echo "")"
fi

# 마커 파일명은 agent_id 다. 페이로드에서 온 문자열이므로 경로로 쓰기 전에
# 정규화한다 — `../` 가 들어오면 quiz-gate 밖에 파일을 쓰게 된다.
# agent_id 가 없으면(메인 스레드) 이름은 main 이다.
marker_name="main"
if [ -n "$agent_id" ]; then
  marker_name="$(printf '%s' "$agent_id" | tr -c 'A-Za-z0-9_-' '_' | cut -c1-64)"
  [ -n "$marker_name" ] || marker_name="unknown-agent"
fi

mkdir -p "$qdir/marker" 2>/dev/null || exit 0
printf '%s\t%s\t%s\t%s\n' "$AGENT" "$agent_id" "$agent_type" "$session" \
  > "$qdir/marker/$marker_name" 2>/dev/null || exit 0

# ── 건강검진 ─────────────────────────────────────────────────────
# 게이트가 조용히 없는 상태를 막는다. 여기서 부정확해도 안전하다:
# 오탐이면 안내 한 번, 미탐이면 게이트가 없던 v1 과 같을 뿐이다. (D29)
#
# --no-verify/-n 판정은 이제 위에서(commit 과 push 모두에 대해) 이미
# 끝났다 — 여기서 다시 하지 않는다. deny()/deny_no_verify() 는 위에서 한
# 번만 정의한다(재정의하면 함수 본문을 두 곳에서 맞춰야 하고, 이 리뷰가
# 고친 바로 그 이유로 한쪽만 고치고 잊기 쉽다).

INSTALL_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/install.sh"
bash "$INSTALL_SH" status >/dev/null 2>&1
install_status=$?

# 3 = 우리 훅이긴 한데 낡았다. 예전에는 낡은 훅도 0("설치됨")으로 보고돼
# 어떤 수정도 이미 설치된 저장소에 도달하지 못했다. (D39)
if [ "$install_status" -eq 3 ]; then
  deny "🦡 KkochiKkochi — 이 저장소에 설치된 게이트 훅이 낡았습니다 (플러그인 사본과 내용이 다릅니다).
다음 명령으로 다시 설치한 뒤 커밋을 다시 시도하세요:

  bash \"$INSTALL_SH\" install"
fi

if [ "$install_status" -ne 0 ]; then
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
