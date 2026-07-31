#!/usr/bin/env bash
# PostToolUse(Task) — 봉인된 번들의 검증을 부모 에이전트에게 요구한다.
#
# 사용법: <hook json> | bundle-notify.sh
# 출력:   요구할 것이 있으면 hookSpecificOutput.additionalContext / 없으면 없음
# 종료:   항상 0.
#
# 여기가 서브에이전트 작업 마무리에 가장 가까우면서 사람에게 물을 수 있는
# 자리다. 서브에이전트가 끝나 결과가 부모로 돌아오는 순간 부모 문맥에서
# 발동하므로 AskUserQuestion 을 쓸 수 있다.
#
# 훅이 직접 퀴즈를 내지 않는다 — 훅에는 사람에게 묻는 채널이 없고 timeout 이
# 걸려 있어(기본 60초, 넘으면 훅이 죽어 판정이 사라진다) 사람의 답을 기다리는
# 구조는 성립하지 않는다. 요구만 주입하고 퀴즈는 에이전트가 스킬로 낸다.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

payload="$(cat)"

command -v jq >/dev/null 2>&1 || exit 0

cwd="$(jq -r '.cwd // ""' <<<"$payload" 2>/dev/null || echo "")"
# scripts/stop-gate.sh 가 이미 겪은 문제와 같다 — `[ -n "$cwd" ] && cd
# "$cwd" 2>/dev/null` 는 cd 실패를 검사하지 않는다는 lint 지적을 받고,
# `|| exit` 를 그냥 이어붙이면 cwd 가 비어 `[ -n "$cwd" ]` 자체가 실패한
# 흔한 경우에도 우변이 실행돼 "항상 exit 0" 계약이 깨진다. cd 가 실제로
# 실패했을 때만 애매함으로 통과시키도록 if 로 감싼다.
if [ -n "$cwd" ]; then
  cd "$cwd" 2>/dev/null || exit 0
fi

git rev-parse --git-common-dir >/dev/null 2>&1 || exit 0
qdir="$(git rev-parse --git-common-dir)/quiz-gate"

# 유예 모드면 조용히 지나간다. 원장은 계속 쌓이고 Stop 이 턴 끝에 막는다.
[ -e "$qdir/defer" ] && exit 0

emit() {  # $1 = additionalContext 본문
  jq -n --arg c "$1" '{
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: $c
    }
  }'
  exit 0
}

# 판정은 pending.sh 한 곳에만 있다 (D45). 여기서 원장을 직접 읽지 않는다.
# pending.sh 는 세 가지 종료 코드로 답한다 (스크립트 헤더 참고):
#   0 = 목록이 나온다   1 = 미검증 없음   2 = 판정 불가(원장 손상)
#
# 브리핑 원문은 --all-unverified 를 `if unverified="$(...)"; then` 하나로만
# 감쌌다. bash 에서 이 형태의 조건은 명령 치환의 종료 코드를 그대로 쓰므로,
# 실패(0 이 아님)는 전부 같은 가지로 떨어진다 — 즉 "미검증 없음"(1)과
# "판정 불가"(2)를 구별하지 않고 둘 다 조용히 넘긴다. 그런데 2 는 stop-gate.sh
# 가 두 라운드에 걸쳐 막은 바로 그 critical bug 다: 원장이 손상돼 있는데
# "미검증 없음"으로 읽히면, 실제로는 검증되지 않은 변경이 있어도 아무 요구
# 없이 턴이 넘어간다. 여기서도 같은 실수를 반복하지 않도록 rc 를 명시적으로
# 나눈다. PostToolUse 에는 Stop 의 `decision:block` 같은 차단 수단이 없으므로
# (도구는 이미 실행된 뒤다) 여기서 할 수 있는 최선은 침묵하지 않고 알리는
# 것이다 — 실제 차단은 Stop 훅이 턴 끝에서 rc=2 를 그대로 막는다.
all_out="$(bash "$SCRIPT_DIR/pending.sh" --all-unverified 2>/dev/null)"
all_rc=$?

if [ "$all_rc" -eq 2 ]; then
  emit "🦡 KkochiKkochi — 원장이 손상돼 있어 어느 서브에이전트 번들이
아직 검증되지 않았는지 판정할 수 없습니다. 이 훅은 침묵하는 대신 알립니다
— 실제 차단은 턴이 끝날 때 Stop 훅이 합니다.

$qdir/ledger.tsv 의 형식이 깨진 줄을 확인하세요."
fi

if [ "$all_rc" -ne 0 ]; then
  # 1 = 미검증 없음. 정상 상태이고 흔하다 — 매 서브에이전트 종료마다
  # 이 훅이 돈다.
  exit 0
fi

# all_rc == 0: 원장에 미검증이 있다. 봉인된 번들부터 자세히 본다.
#
# 아직 도는(sealed 가 비어 있는) 번들의 몫은 여기서도, 아래 폴백에서도
# 요구하지 않는다 — 브리핑 원문의 폴백은 --all-unverified 결과를 그대로
# 썼는데, 그 목록은 sealed 여부와 무관하게 원장 전체를 본다. 그래서 원문
# 그대로면 "SubagentStart 만 오고 Stop 은 아직 안 온" 번들의 커밋도 폴백이
# 요구해 버린다 — 서브에이전트가 아직 일하는 중인데 검증부터 조르는 순서
# 역전이다(tests/bundle.bats 의 "아직 봉인되지 않은 번들은 요구하지 않는다"
# 가 바로 이 상태를 잡는다). 그래서 sealed 가 비어 있는 번들의 몫은 `exclude`
# 에 모아 뒀다가 폴백에서 뺀다.
lines=""
exclude=""
if [ -d "$qdir/agents" ]; then
  for f in "$qdir/agents"/*; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"
    sealed="$(cut -f3 "$f" 2>/dev/null | head -n 1)"
    atype="$(cut -f1 "$f" 2>/dev/null | head -n 1)"

    bundle_out="$(bash "$SCRIPT_DIR/pending.sh" --bundle "$name" 2>/dev/null)"
    bundle_rc=$?
    # rc != 0 이면(1: 이 번들엔 볼 게 없음, 또는 드문 레이스로 2) 이
    # 번들에서는 더 할 게 없다. 원장 전체의 판정은 위에서 이미 all_rc 로
    # 확인했으므로, 개별 번들 호출이 레이스로 2 를 내더라도 조용히 넘어가는
    # 것이 안전하다(다음 PostToolUse 호출이나 Stop 이 다시 본다).
    [ "$bundle_rc" -eq 0 ] || continue

    if [ -n "$sealed" ]; then
      n="$(printf '%s\n' "$bundle_out" | wc -l | tr -d ' ')"
      [ "${n:-0}" -gt 0 ] || continue
      lines="$lines   $atype ($name) — $n 개 변경
"
    else
      exclude="$exclude$bundle_out
"
    fi
  done
fi

if [ -n "$lines" ]; then
  emit "🦡 KkochiKkochi — 끝난 서브에이전트의 변경이 아직 검증되지 않았습니다.

$lines
kkochikkochi 스킬을 실행해 번들마다 퀴즈를 내세요. 대상은
\`pending.sh --bundle <agent_id>\` 가 냅니다. 완료 순서대로 하나씩 처리하세요."
fi

# 폴백 — 봉인 기록이 없는데(agents/ 에 그 agent_id 파일이 아예 없다) 원장에
# 미검증이 남아 있는 경우. SubagentStop 이 PostToolUse 보다 늦게 돌거나 아예
# 발동하지 않아도 검증이 사라지지 않게 한다. 위에서 모은 `exclude`(아직
# 도는 번들의 몫)는 제외한다.
fallback_out="$all_out"
if [ -n "$exclude" ]; then
  fallback_out="$(printf '%s\n' "$all_out" | grep -Fxv -f <(printf '%s\n' "$exclude") || true)"
fi

[ -n "$fallback_out" ] || exit 0

paths="$(printf '%s\n' "$fallback_out" | cut -f2 | sort -u | sed 's/^/   /')"
emit "🦡 KkochiKkochi — 아직 검증되지 않은 변경이 있습니다.

$paths

kkochikkochi 스킬을 실행해 퀴즈를 통과하세요."
