#!/usr/bin/env bash
# Stop 훅 — 미검증 번들이 남은 채로 턴이 끝나는 것을 막는다.
#
# 사용법: <hook json> | stop-gate.sh
# 출력:   미검증 있음 → {"decision":"block","reason":...} / 원장을 못 읽음
#         (형식 손상·중간에 끊긴 append·권한 문제) → 마찬가지로 block(판정
#         불가 자체가 안전하지 않다는 뜻이다) / 정말 없거나 전부 검증됨 →
#         아무것도
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
# 다만 pending.sh 가 실패했을 때 그 실패가 "미검증 없음"인지 "원장을 읽지
# 못했다"인지는 이 스크립트가 구분해야 한다 — 둘 다 exit 1 로 나온다
# (scripts/pending.sh 의 주석 참고: 그 계약은 여기서 바꾸지 않는다).
err_file="$(mktemp 2>/dev/null)" || exit 0
unverified="$(bash "$SCRIPT_DIR/pending.sh" --all-unverified 2>"$err_file")"
rc=$?
err="$(cat "$err_file" 2>/dev/null)"
rm -f "$err_file" 2>/dev/null || :

if [ "$rc" -ne 0 ]; then
  # pending.sh 가 exit 1 로 실패하는 사유는 최소 세 갈래다: (a) 원장이
  # 아예 없다(가장 흔함 — 이 저장소에서 서브에이전트가 한 번도 커밋한 적이
  # 없다), (b) 원장이 있고 형식도 멀쩡한데 전부 이미 검증돼 미검증이
  # 0건이다, (c) 원장이 있는데 못 읽는다(형식이 깨졌거나 append 가 중간에
  # 끊겼거나 권한 문제). (a) 와 (b) 는 정상 상태이고 stop-gate.sh 가 매 턴
  # 부르므로 흔한 경로다 — 유예를 지우고 조용히 통과해야 한다. (c) 는
  # "미검증 없음"과는 다른 사고다: 나쁜 줄 하나가 원장 전체를 못 읽게
  # 만들어, 같은 원장에 남아 있는 다른 파일의 미검증 상태까지 그 줄 때문에
  # 통째로 가려질 수 있다(실측 — 리뷰 critical finding 1: 형식이 깨진 줄
  # 하나 때문에 같은 커밋의 good.ts 미검증 상태가 조용히 사라졌다).
  #
  # (b) 와 (c) 를 가르는 게 까다롭다: 둘 다 pending.sh 를 "정상적으로
  # 실행"하지만 하나는 "성공적으로 읽었더니 0건"이고 하나는 "못 읽었다"이며,
  # 종료 코드는 둘 다 1로 같다(계약, 안 바꾼다). 그래서 두 가지 독립 신호로
  # (c) 만 골라낸다 — 어느 한쪽이라도 걸리면 (c) 로 본다:
  #   1) 메시지에 "손상"이 있다 — pending.sh 가 형식 오류를 스스로
  #      검출했을 때만 내는 문구다(형식이 깨진 줄, 중간에 끊긴 append).
  #   2) 원장 파일이 존재하는데 우리가 직접 읽을 수 없다 — 권한 문제
  #      (chmod 000) 는 pending.sh 안에서 "원장 없음"과 같은 문구로
  #      나온다(별도로 기록된, 이번 라운드에서 고치지 않는 결함). 그
  #      문구만으로는 (a) 와 못 가르므로, 메시지에 기대지 않고 원장 파일의
  #      존재/읽기 가능 여부를 여기서 직접 확인한다. `[ -e ]` 로 존재부터
  #      확인해야 (a) 진짜 없는 경우가 이 분기로 잘못 들어오지 않는다
  #      (없는 파일은 `[ ! -r ]` 도 참이기 때문이다).
  loud=0
  case "$err" in *손상*) loud=1 ;; esac
  if [ -e "$ledger" ] && [ ! -r "$ledger" ]; then
    loud=1
  fi

  if [ "$loud" -eq 0 ]; then
    # (a) 또는 (b) — 미검증이 없다. 유예는 턴 끝까지이므로 여기서 해제한다.
    rm -f "$qdir/defer" 2>/dev/null || :
    exit 0
  fi

  # (c) — 유예를 지우지 않는다. 판정을 못 내린 채로 턴을 조용히 끝내게
  # 두지 않는다.
  jq -n --arg e "$err" --arg ledger "$ledger" '{
    decision: "block",
    reason: ("🦡 KkochiKkochi — 원장(" + $ledger + ")을 읽을 수 없어 미검증 여부를 판정하지 못했습니다. 검증되지 않은 변경이 가려져 있을 수 있습니다.\n\n"
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
