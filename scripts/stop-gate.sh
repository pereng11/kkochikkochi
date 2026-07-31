#!/usr/bin/env bash
# Stop 훅 — 미검증 번들이 남은 채로 턴이 끝나는 것을 막는다.
#
# 사용법: <hook json> | stop-gate.sh
# 출력:   미검증 있음 → {"decision":"block","reason":...} / 없음 → 아무것도
# 종료:   항상 0. 판정은 stdout 의 JSON 으로만 말한다.
#
# 왜 여기인가: 서브에이전트는 사람에게 물을 수 없다(AskUserQuestion 은 메인
# 에이전트만 쓴다). PostToolUse(Task) 가 이미 검증을 요구했더라도 에이전트가
# 그것을 건너뛸 수 있으므로, 턴 종료 지점이 마지막 그물이다.
#
# 왜 command 훅인가: prompt 타입(LLM 판정)도 지원되지만, 이 프로젝트가 내내
# 싸워온 실패 모드가 "게이트가 조용히 꺼지는 것"이다. 판정을 LLM 에 맡기면
# 그 실패 모드를 설계에 초대한다.
#
# stop_hook_active 가 true 여도 계속 막는다. 미검증이 남은 한 막는 것이 이
# 게이트의 존재 이유이고, 원장이 비면 자연히 통과하므로 종료 조건은 있다.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

payload="$(cat)"

# jq 가 없으면 판정 JSON 을 만들 수 없다. 애매하면 통과시킨다 (D35, D42).
command -v jq >/dev/null 2>&1 || exit 0

cwd="$(jq -r '.cwd // ""' <<<"$payload" 2>/dev/null || echo "")"
# lint 도구가 "cd 실패 검사 없음"을 지적한다. 브리핑 원문의
# `[ -n "$cwd" ] && cd "$cwd" 2>/dev/null` 는 그 지적을 받는다. 그렇다고
# `&&` 뒤에 `|| exit` 를 그대로 이어붙이면 cwd 가 비어 있을 때도(즉
# [ -n "$cwd" ] 가 실패해 cd 를 아예 안 돌렸을 때도) 우변이 실행돼
# 스크립트가 죽는다 — 이 스크립트의 "종료: 항상 0" 계약을 cwd 가 없는 흔한
# 경우에 깨버린다. cd 가 진짜로 실패했을 때만(cwd 가 더 이상 존재하지 않는
# 등) 애매함으로 통과시켜야 하므로 if 로 감싼다.
if [ -n "$cwd" ]; then
  cd "$cwd" 2>/dev/null || exit 0
fi

git rev-parse --git-common-dir >/dev/null 2>&1 || exit 0

qdir="$(git rev-parse --git-common-dir)/quiz-gate"

# 판정은 pending.sh 한 곳에만 있다 (D45). 여기서 원장을 직접 읽지 않는다.
if ! unverified="$(bash "$SCRIPT_DIR/pending.sh" --all-unverified 2>/dev/null)"; then
  # 미검증이 없다(또는 원장이 없다). 유예는 턴 끝까지이므로 여기서 해제한다.
  rm -f "$qdir/defer" 2>/dev/null || :
  exit 0
fi

paths="$(printf '%s\n' "$unverified" | cut -f2 | sort -u | sed 's/^/   /')"

jq -n --arg p "$paths" '{
  decision: "block",
  reason: ("🦡 KkochiKkochi — 서브에이전트가 만든 커밋 중 아직 검증되지 않은 변경이 있습니다.\n\n"
           + $p
           + "\n\nkkochikkochi 스킬을 실행해 퀴즈를 통과한 뒤 마치세요.\n"
           + "대상 목록은 `pending.sh --all-unverified` 가 냅니다.")
}'
exit 0
