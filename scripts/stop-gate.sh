#!/usr/bin/env bash
# Stop 훅 — 미검증 번들이 남은 채로 턴이 끝나는 것을 막는다.
#
# 사용법: <hook json> | stop-gate.sh
# 출력:   pending.sh --all-unverified 의 종료 코드로 갈린다(그 스크립트
#         헤더의 0/1/2 계약을 그대로 따른다) —
#           0 (목록 있음)   → {"decision":"block","reason":...}
#           2 (판정 불가)   → 마찬가지로 block(판정 불가 자체가 안전하지
#                             않다는 뜻이다) — defer 를 지우지 않는다
#           1 (미검증 없음) → 아무것도, defer 를 지운다
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
ledger="$qdir/ledger.tsv"

# 판정은 pending.sh 한 곳에만 있다 (D45). 여기서 원장을 직접 읽지 않는다.
# pending.sh 는 세 가지 종료 코드로 답한다(스크립트 자체 헤더 주석 참고):
#   0 = 목록이 나온다        1 = 미검증 없음(정상)       2 = 판정 불가(사고)
# 예전 라운드에서는 1 이 "미검증 없음"과 "원장을 못 읽음"을 함께 지고 있어서,
# 이 스크립트가 stderr 의 "손상" 문자열을 읽어 그 둘을 갈랐다. 그런데
# 리뷰에서 pending.sh 의 그 문구만(내용은 그대로) 바꿔서 재현한 결과 —
# 아무 것도 안 고쳤는데 — 같은 사고가 조용히 되살아났다: 판정을 stderr
# 프로즈에 걸어두면 그 프로즈가 바뀌는 순간(재문구화든 번역이든) 조용히
# 무너진다. 그래서 이제는 종료 코드 자체가 신호다 — 아래서는 `$rc` 값만
# 보고 분기하고, stderr 메시지(`$err`)는 block 사유에 사람이 읽을 참고
# 정보로만 넣는다.
err_file="$(mktemp 2>/dev/null)" || exit 0
unverified="$(bash "$SCRIPT_DIR/pending.sh" --all-unverified 2>"$err_file")"
rc=$?
err="$(cat "$err_file" 2>/dev/null)"
rm -f "$err_file" 2>/dev/null || :

if [ "$rc" -ne 0 ]; then
  loud=0
  case "$rc" in
    1)
      # pending.sh 가 명시적으로 "미검증 없음"이라고 답했다(원장 없음·
      # 비어 있음·전부 커버됨 — 정상 상태이고, stop-gate.sh 가 매 턴 이
      # 경로를 타므로 흔하다). 다만 알려진 예외가 하나 있다: 원장이 있는데
      # 권한 때문에 못 읽는 경우(chmod 000)도 pending.sh 는 exit 1 로
      # "원장 없음"과 같은 코드를 낸다 — pending.sh 의 메시지 문구가
      # 그 둘을 안 가르는 것은 별도로 기록된, 이번 라운드에서 고치지 않는
      # 결함이다(deferred). 그 경우까지 여기서 조용히 넘기면 critical
      # finding 1 이 권한 문제로 다시 살아나므로, **문자열이 아니라 파일
      # 상태**로 그 한 가지 예외만 독립적으로 확인한다 — 이건 프로즈에
      # 기대는 게 아니라 파일시스템 사실을 직접 보는 것이라 리뷰가 지적한
      # "문구가 바뀌면 무너지는 신호" 문제에 해당하지 않는다. `[ -e ]` 로
      # 존재부터 확인해야 원장이 진짜 없는 경우가 이 분기로 잘못 들어오지
      # 않는다(없는 파일은 `[ ! -r ]` 도 참이기 때문).
      if [ -e "$ledger" ] && [ ! -r "$ledger" ]; then
        loud=1
      fi
      ;;
    2)
      # pending.sh 가 명시적으로 "판정 불가"라고 답했다 — 종료 코드 자체가
      # 신호이므로 메시지 문자열은 보지 않는다.
      loud=1
      ;;
    *)
      # pending.sh 의 계약은 0/1/2 셋뿐이다. 그 밖의 값은 그 자체로 이상
      # 신호이고, 이 스크립트가 있는 이유가 정확히 "판정 불가를 조용히
      # 넘기지 않는 것"이므로 애매하면 크게 알리는 쪽을 택한다.
      loud=1
      ;;
  esac

  if [ "$loud" -eq 0 ]; then
    # 미검증이 없다. 유예는 턴 끝까지이므로 여기서 해제한다.
    rm -f "$qdir/defer" 2>/dev/null || :
    exit 0
  fi

  # 판정 불가 — 유예를 지우지 않는다. 판정을 못 내린 채로 턴을 조용히
  # 끝내게 두지 않는다.
  jq -n --arg e "$err" --arg ledger "$ledger" --arg rc "$rc" '{
    decision: "block",
    reason: ("🦡 KkochiKkochi — 원장(" + $ledger + ")을 읽을 수 없어 미검증 여부를 판정하지 못했습니다 (pending.sh exit " + $rc + "). 검증되지 않은 변경이 가려져 있을 수 있습니다.\n\n"
             + $e
             + "\n\n원장 파일을 확인해 손상된 줄을 고치거나 권한을 확인한 뒤 다시 시도하세요.")
  }'
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
