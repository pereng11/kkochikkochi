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
# 사라진다(review critical finding, 재현: raw id `sess.1/agent:9` →
# `--bundle 'sess.1/agent:9'` 는 rc=0, `--bundle sess_1_agent_9` 는 rc=1).
#
# **"아직 도는 중인가"는 3번째 필드(sealed_at)만으로 판단하고, 그 판단을
# 이 루프의 다른 어떤 continue 보다 먼저 한다.** 그 필드는 이 스크립트가
# 처음부터 평문 ISO-8601 로 써 왔고, seal-bundle.sh 가 4번째 필드(원문
# agent_id)를 추가하기 전(66f9a25 이전, 3필드 포맷)에도 항상 같은 자리에
# 있었다 — 그래서 4번째 필드를 디코드할 수 있는지와 완전히 무관하게 항상
# 읽을 수 있다. 예전 버전은 순서가 반대였다: 4번째 필드 디코드가
# 실패하면(구버전 3필드 포맷이 그 예다) sealed 여부를 보기도 전에
# continue 해서 "아직 도는 중"이라는 사실 자체를 기록하지 못했고, 그 결과
# 아래 폴백이 그 번들을 "봉인 기록이 아예 없는 것"과 구별하지 못해 도는
# 중인 서브에이전트에게 검증을 요구해 버렸다(review, 재현: 구버전 3필드
# 미봉인 `agents/aaa11` + 원장의 aaa11 행). 이 저장소는 스스로를 dogfood
# 하고, 문서화된 갱신 흐름이 `plugin uninstall && plugin install` +
# 재로드라 `quiz-gate/agents/` 의 구버전 파일이 디스크에 남는 창이 실제로
# 있다 — 가상의 시나리오가 아니다.
lines=""
if [ -d "$qdir/agents" ]; then
  for f in "$qdir/agents"/*; do
    [ -f "$f" ] || continue
    sealed="$(cut -sf3 "$f" 2>/dev/null | head -n 1)"
    [ -n "$sealed" ] || continue   # 아직 도는 중이다 — 상세 메시지를 만들지 않는다

    enc_type="$(cut -sf1 "$f" 2>/dev/null | head -n 1)"
    enc_id="$(cut -sf4 "$f" 2>/dev/null | head -n 1)"
    raw_id="$(decode "$enc_id")"
    # 봉인은 됐지만 원문 agent_id 를 복원할 수 없으면(구버전 3필드 포맷,
    # 또는 디코드가 깨진 경우) 상세 메시지는 포기한다. 조용히 사라지지는
    # 않는다 — 아래 폴백이 원장의 agent_id 열을 직접 훑으므로, 이 번들이
    # 실제로 미검증을 남겼다면 일반적인(파일명 기반) 메시지로 여전히
    # 잡는다.
    [ -n "$raw_id" ] || continue

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

# 폴백 — 원장에 등장하는 agent_id 를 모두 훑어, 아직 도는 중이 아닌 것만
# 요구한다.
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
# 모두 훑는다(all_rc==0 을 이미 확인했으므로 pending.sh 가 이미 전체 형식을
# 검증했다는 뜻이고, 그래서 이 열을 직접 읽어도 D45 가 금지하는 "판정을
# 다시 구현하는 것"이 아니다 — 판정은 여전히 매 agent_id 마다
# `pending.sh --bundle` 호출이 낸다, 여기서는 "누가 있는가"만 본다).
#
# 각 agent_id 의 "아직 도는 중인가"는 위 상세 루프와 똑같은 원칙을 쓴다 —
# 파일명으로 다시 찾은 agents/<name> 파일의 **3번째 필드만** 본다(4번째
# 필드 디코드는 필요 없다 — 그래서 그 디코드가 실패하는 구버전 3필드
# 포맷이라도 "도는 중"이라는 판정 자체는 절대 놓치지 않는다).
#
# 이름은 **두 후보를 순서대로** 시도한다 (round 4 review 의 root cause 수정):
#
#   1) 해시 이름 — seal-bundle.sh 가 지금 쓰는, raw agent_id 에서 주입적으로
#      (사실상 충돌 없이) 유도한 이름. 이 agent_id 가 새 코드 아래에서 한
#      번이라도 seal-bundle.sh 를 거쳤다면 반드시 여기서 찾는다.
#   2) 예전 `tr -c 'A-Za-z0-9_-' '_' | cut -c1-64` 이름 — round 4 이전
#      seal-bundle.sh 가 쓰던, **충돌하도록 설계된** 이름. 이 저장소는
#      스스로를 dogfood 하고, 문서화된 갱신 흐름(plugin uninstall→install
#      +재로드)이 quiz-gate/agents/ 를 청소하지 않으므로, 업그레이드 이후
#      아직 한 번도 seal-bundle.sh 를 거치지 않은 번들의 파일이 옛 이름
#      그대로 남아 있을 수 있다. 그 파일을 놓치면 round 3 가 고친 "구버전
#      포맷이 아직 도는 중인데 요구해 버리는" 사고가 이번엔 "구버전 이름
#      이라 아예 못 찾는" 모양으로 되살아난다.
#
#   둘 다 없으면 봉인 기록이 없는 것으로 보고 안전한 쪽(요구한다)으로
#   간다 — 이 경로는 명시적이고(이 주석과 아래 분기), 관찰 가능하다(테스트로
#   고정돼 있다): "찾지 못했다 → 요구한다"는 이 폴백 전체의 기존 규칙을
#   그대로 따를 뿐 조용히 사라지는 새 경로가 아니다.
#
#   두 후보 다 내용을 디코드해 재확인하지 않는다 — 해시 이름은 주입적이라
#   재확인이 필요 없고, tr 이름은 여전히 충돌 가능하지만 그 위험은 "새
#   코드로 아직 한 번도 안 건드려진 두 legacy id 가 동시에 이 이름을
#   공유하는" 좁은 과거-전환기 창에만 남는다 — 원래 결함(모든 id 가 영원히
#   충돌)보다 훨씬 좁고, 둘 중 하나라도 다시 seal-bundle.sh 를 거치면 그
#   즉시 자기 몫의 해시 이름 파일이 생겨 이 창에서 빠져나간다(자기 치유).
#   이미 서로 덮어써 사라진 과거 데이터까지 지금 복구할 방법은 없다 —
#   round 4 report 에 이 잔여 위험을 남겼다.
fallback_out=""
if [ -r "$ledger" ]; then
  while IFS= read -r raw; do
    [ -n "$raw" ] || continue

    hash_name="$(printf '%s' "$raw" | git hash-object --stdin 2>/dev/null)"
    legacy_name="$(printf '%s' "$raw" | tr -c 'A-Za-z0-9_-' '_' | cut -c1-64)"

    agent_file=""
    if [ -n "$hash_name" ] && [ -f "$qdir/agents/$hash_name" ]; then
      agent_file="$qdir/agents/$hash_name"
    elif [ -n "$legacy_name" ] && [ -f "$qdir/agents/$legacy_name" ]; then
      agent_file="$qdir/agents/$legacy_name"
    fi

    if [ -n "$agent_file" ]; then
      sealed="$(cut -sf3 "$agent_file" 2>/dev/null | head -n 1)"
      [ -n "$sealed" ] || continue   # 아직 도는 중이다 — 조용히 둔다
    fi

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
