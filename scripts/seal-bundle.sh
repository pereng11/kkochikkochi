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

# 파일명은 원문 agent_id 의 해시로 정한다.
#
# round 4 review 의 근본 원인: 예전에는 마커(scripts/stamp-agent.sh)와 같은
# `tr -c 'A-Za-z0-9_-' '_' | cut -c1-64` 정규화를 문자 그대로 복사해 썼다.
# 그 정규화는 **처음부터 충돌하도록 만들어져 있다** — "a.b" 와 "a/b" 는 둘
# 다 "a_b" 로 뭉개지고(문자 충돌), 64바이트를 넘는 서로 다른 두 agent_id
# 도 뭉개진다(자름 충돌). 마커(marker/<name>)는 이름을 다시 계산해 찾는
# 곳이 아무 데도 없어(각 훅이 자기 자신의 최신 상태만 쓰고, 읽는 쪽은 항상
# `marker/*` 를 통째로 훑으며 내용의 agent_id 로 판별한다 — hooks/pre-commit
# 참고) 이 정규화로도 괜찮지만, 번들 파일(agents/<name>)은 다르다 —
# `bundle-notify.sh` 가 원장의 agent_id 로부터 파일명을 **다시 계산해서**
# 찾는다. 서로 다른 두 agent_id 가 이름 하나에 부딪히면, 나중에 쓰는 쪽이
# 먼저 쓴 쪽의 파일을 **통째로 덮어써 버린다** — 파일이 하나뿐이므로
# "이름으로 다시 찾지 않는다"는 원칙만으로는 이 WRITE 충돌을 못 막는다
# (review 재현, 양방향: A 는 도는 중인데 B 가 이름을 공유해 끝나면 B 의
# 미검증이 A 의 "도는 중" 상태에 가려 사라지거나, 반대로 B 의
# `SubagentStart` 가 A 의 sealed_at 을 지워 A 의 완료·미검증 기록이
# 사라진다).
#
# 그래서 파일명을 raw agent_id 에서 **주입적으로**(사실상 충돌 없이)
# 유도한다. git 은 이미 이 스크립트의 필수 의존성이므로(위에서
# `git rev-parse --git-common-dir` 로 이미 확인) 새 의존성 없이
# `git hash-object --stdin` 을 쓴다 — 저장소의 객체 포맷에 따라 고정
# 길이(SHA-1 이면 40자, SHA-256 이면 64자)의 순수 16진수를 내므로 경로
# 순회 위험이 없고(`tr` 정규화가 하던 일을 구조적으로 대신한다) 길이 제한
# (`cut -c1-64`)도 필요 없다. `bundle-notify.sh` 는 같은 명령으로 같은
# 이름을 다시 계산해 조회한다 — 두 곳이 정확히 같은 함수를 써야 하는
# 이유는 예전 tr 정규화 때와 같다(Task 2 인터페이스 노트, 이제는 해시
# 함수에 적용된다).
#
# 원문 `agent_id` 는 여전히 파일 **안**(4번째 필드)에도 남긴다 —
# `pending.sh --bundle` 은 원장(ledger.tsv)의 agent_id 열(정규화되지 않은
# 원문)과 비교하므로, 파일명(해시)이 아니라 이 필드를 디코드해 넘겨야 한다
# (round 2 critical finding, 여전히 유효하다 — 해시로 바꿔도 파일명 자체를
# 조회에 쓰면 안 된다는 사실은 그대로다).
name="$(printf '%s' "$agent_id" | git hash-object --stdin 2>/dev/null)"
[ -n "$name" ] || exit 0

mkdir -p "$qdir/agents" 2>/dev/null || exit 0
file="$qdir/agents/$name"
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# agent_type 과 agent_id(원문)는 페이로드에서 온 임의의 문자열이라 탭이나
# 개행을 담을 수 있다. 그대로 탭 구분 줄에 넣으면 필드 수가 늘어나거나
# 줄이 갈라져 파일 구조가 깨진다 — 그러면 `sealed`(3번 필드) 자리가 밀려,
# **아직 도는 번들이 이미 봉인된 것처럼** 읽힐 수 있다(review mandate:
# `cut -f3`가 봉인 안 된 번들에서 non-empty 를 낼 수 있음을 재현했다).
# jq 의 JSON 문자열 인코딩은 제어 문자(탭·개행 포함)를 전부 `\t`·`\n` 같은
# 2문자 이스케이프로 바꿔 항상 한 줄짜리 값을 내므로, 그 값을 필드로 쓰면
# 필드 수·줄 수가 입력 내용과 무관하게 고정된다. jq 는 이 스크립트의 필수
# 의존성이라(맨 위에서 이미 확인) 여기서 실패할 일이 거의 없지만, 혹시
# 실패해도 빈 문자열이 아니라 유효한 JSON 문자열(`""`)로 떨어지게 한다 —
# 필드가 아예 비면(개행 없는 빈 줄) 그 자체로 필드 수가 흔들린다.
encode() {  # $1 = 원문 문자열 -> 한 줄짜리 JSON 문자열 리터럴
  jq -Rn --arg s "$1" '$s' 2>/dev/null || printf '""'
}

agent_type_enc="$(encode "$agent_type")"
agent_id_enc="$(encode "$agent_id")"

# started 는 이 스크립트가 직접 만드는 ISO-8601 시각이라 탭/개행 걱정이
# 없다 — 필드 2는 그대로 둔다.
started=""
[ -r "$file" ] && started="$(cut -sf2 "$file" 2>/dev/null | head -n 1)"
[ -n "$started" ] || started="$now"

# 파일 형식: <agent_type(JSON 문자열)>\t<started_at>\t<sealed_at>\t<agent_id(JSON 문자열)>
if [ "$EVENT" = "start" ]; then
  # 이미 봉인된 같은 이름이 있으면(재개된 에이전트) 봉인을 푼다 — 새 커밋이
  # 이어질 수 있고, 봉인된 채로 두면 그 뒤 커밋이 요구 대상에서 빠진다.
  printf '%s\t%s\t%s\t%s\n' "$agent_type_enc" "$started" "" "$agent_id_enc" > "$file" 2>/dev/null || :
else
  printf '%s\t%s\t%s\t%s\n' "$agent_type_enc" "$started" "$now" "$agent_id_enc" > "$file" 2>/dev/null || :
fi
exit 0
