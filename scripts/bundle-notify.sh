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
ledger="$qdir/ledger.tsv"

# 유예 모드면 조용히 지나간다. 원장은 계속 쌓이고 Stop 이 턴 끝에 막는다.
[ -e "$qdir/defer" ] && exit 0

# scripts/seal-bundle.sh 와 짝을 이루는 디코더. agent_type·agent_id(원문)는
# jq 의 JSON 문자열 인코딩(`\t`·`\n` 같은 이스케이프)으로 저장돼 있다 — 그
# 이유는 seal-bundle.sh 의 encode() 주석 참고.
decode() {  # $1 = JSON 문자열 리터럴 -> 원문
  printf '%s' "$1" | jq -r '.' 2>/dev/null
}

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
# 여기서는 rc 만 있으면 된다 — 이 값을 실제 목록으로 쓰지는 않는다(폴백은
# agent_id 단위로 다시 조회한다, 아래 이유 참고). 그래서 stdout 은 버린다.
bash "$SCRIPT_DIR/pending.sh" --all-unverified >/dev/null 2>&1
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
# `pending.sh --bundle` 은 원장의 agent_id **원문**과 비교한다(위 파일 형식
# 주석 참고) — 그래서 여기서도 파일명(`basename`, 정규화된 값)이 아니라
# 파일 안의 4번째 필드(원문 agent_id)를 디코드해 넘긴다. 파일명을 그대로
# 넘기면 agent_id 에 `tr -c 'A-Za-z0-9_-' '_'` 가 바꾸는 문자(64자 초과
# 포함)가 하나라도 있을 때 조회가 조용히 실패해 이 번들의 요구가 통째로
# 사라지고, 아래 "아직 도는 번들" 판정도 같이 깨진다(review critical
# finding, 재현: raw id `sess.1/agent:9` → `--bundle 'sess.1/agent:9'` 는
# rc=0, `--bundle sess_1_agent_9` 는 rc=1).
#
# 아직 도는(sealed 가 비어 있는) 번들의 몫은 여기서도, 아래 폴백에서도
# 요구하지 않는다 — 서브에이전트가 아직 일하는 중인데 검증부터 조르는 순서
# 역전이기 때문이다(tests/bundle.bats 의 "아직 봉인되지 않은 번들은
# 요구하지 않는다"가 이 상태를 잡는다. 대신 그 판정을 Stop 훅에 미룬다 —
# `stop-gate.sh` 는 봉인 여부를 보지 않고 원장 전체를 보므로, 이 턴에 더
# 이상 `PostToolUse(Task)` 가 없어도(예: 방금이 이번 턴의 마지막
# 서브에이전트였다) 턴 끝에서 반드시 잡는다. 이 트레이드오프는
# docs/superpowers/specs/2026-07-30-parallel-gate-design.md §3 에 명시했다).
#
# `matched_raw_ids` 에는 이 루프에서 디코드에 성공한 원문 agent_id 를 전부
# 모은다 — sealed 든 아니든. 아래 폴백은 원장의 agent_id 열 전체를 훑으면서
# 이 목록에 없는(= agents/ 에 대응 기록이 없는) agent_id 만 개별 조회한다.
lines=""
matched_raw_ids=""
if [ -d "$qdir/agents" ]; then
  for f in "$qdir/agents"/*; do
    [ -f "$f" ] || continue
    sealed="$(cut -sf3 "$f" 2>/dev/null | head -n 1)"
    enc_type="$(cut -sf1 "$f" 2>/dev/null | head -n 1)"
    enc_id="$(cut -sf4 "$f" 2>/dev/null | head -n 1)"
    raw_id="$(decode "$enc_id")"
    # 이 파일에서 원문 agent_id 를 복원할 수 없으면(구버전 3필드 포맷이
    # 남아 있거나 디코드가 깨진 경우) 이 파일은 건드리지 않는다 —
    # matched_raw_ids 에도 넣지 않으므로, 이 번들의 원장 줄은 아래 폴백이
    # (agents/ 에 대응 기록이 없는 것과 똑같이) 일반적인 방식으로 여전히
    # 잡는다. 틀린 이름으로 조회해 조용히 놓치는 것보다 안전하다.
    [ -n "$raw_id" ] || continue

    matched_raw_ids="$matched_raw_ids$raw_id
"
    [ -n "$sealed" ] || continue   # 아직 도는 중이다 — 조용히 둔다

    bundle_out="$(bash "$SCRIPT_DIR/pending.sh" --bundle "$raw_id" 2>/dev/null)"
    bundle_rc=$?
    # rc != 0 이면(1: 이 번들엔 볼 게 없음, 또는 드문 레이스로 2) 이
    # 번들에서는 더 할 게 없다. 원장 전체의 판정은 위에서 이미 all_rc 로
    # 확인했으므로, 개별 번들 호출이 레이스로 2 를 내더라도 조용히 넘어가는
    # 것이 안전하다(다음 PostToolUse 호출이나 Stop 이 다시 본다).
    [ "$bundle_rc" -eq 0 ] || continue

    n="$(printf '%s\n' "$bundle_out" | wc -l | tr -d ' ')"
    [ "${n:-0}" -gt 0 ] || continue
    atype="$(decode "$enc_type")"
    [ -n "$atype" ] || atype="$enc_type"
    lines="$lines   $atype ($raw_id) — $n 개 변경
"
  done
fi

if [ -n "$lines" ]; then
  emit "🦡 KkochiKkochi — 끝난 서브에이전트의 변경이 아직 검증되지 않았습니다.

$lines
kkochikkochi 스킬을 실행해 번들마다 퀴즈를 내세요. 대상은
\`pending.sh --bundle <agent_id>\` 가 냅니다. 완료 순서대로 하나씩 처리하세요."
fi

# 폴백 — agents/ 에 대응 기록이 전혀 없는 agent_id 의 몫만 요구한다.
#
# 여기서 (sha, path) **쌍** 단위로 `pending.sh --all-unverified` 의 결과에서
# "아직 도는 번들의 몫"을 빼는 방식은(예전 구현) 틀렸다 — 그 명령은
# agent_id 를 버리고 (sha, path) 만 중복 제거해 내므로, 서로 다른 두
# agent_id 가 우연히 같은 (sha, path) 를 갖는 경우(한 에이전트가 되돌렸다가
# 다른 에이전트가 같은 내용을 같은 경로에 다시 커밋, 또는 같은
# common-dir 를 공유하는 두 워크트리가 각각 동일한 내용을 커밋)를 구별할
# 수 없다. 그러면 도는 중인 agent 의 몫을 빼려다가 마침 같은 쌍을 가진
# **다른(대응 기록 없는) agent** 의 몫까지 통째로 사라진다(review important
# finding 2, 재현: (c.ts,AAA) + (c.ts,BBB), AAA 는 도는 중, BBB 는 기록 없음
# → 예전 코드는 알림을 아예 내지 않았다).
#
# 그래서 폴백은 **agent_id 단위**로 판단한다: 원장에 등장하는 agent_id 를
# 모두 훑어(all_rc==0 을 이미 확인했으므로 pending.sh 가 이미 전체 형식을
# 검증했다는 뜻이고, 그래서 이 열을 직접 읽어도 D45 가 금지하는 "판정을
# 다시 구현하는 것"이 아니다 — 판정은 여전히 매 agent_id 마다
# `pending.sh --bundle` 호출이 낸다, 여기서는 "누가 있는가"만 본다)
# matched_raw_ids 에 없는 것만 개별적으로 `pending.sh --bundle` 로 조회한다.
# 그 조회는 agent_id 로 이미 걸러져 있으므로 (sha, path) 가 겹쳐도 다른
# agent 의 몫과 뒤섞이지 않는다.
fallback_out=""
if [ -r "$ledger" ]; then
  while IFS= read -r raw; do
    [ -n "$raw" ] || continue
    printf '%s\n' "$matched_raw_ids" | grep -Fxq "$raw" && continue

    bundle_out="$(bash "$SCRIPT_DIR/pending.sh" --bundle "$raw" 2>/dev/null)"
    bundle_rc=$?
    [ "$bundle_rc" -eq 0 ] || continue
    fallback_out="$fallback_out$bundle_out
"
  done <<EOF
$(cut -sf3 "$ledger" 2>/dev/null | sort -u)
EOF
fi

[ -n "$fallback_out" ] || exit 0

paths="$(printf '%s\n' "$fallback_out" | cut -f2 | sort -u | sed 's/^/   /')"
emit "🦡 KkochiKkochi — 아직 검증되지 않은 변경이 있습니다.

$paths

kkochikkochi 스킬을 실행해 퀴즈를 통과하세요."
