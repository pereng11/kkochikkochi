#!/usr/bin/env bash
# 퀴즈 통과를 기록한다.
#
# 사용법: echo "<transcript json>" | record-pass.sh "<원본 커맨드 문자열>"
# 종료:   0 = 기록됨 / 1 = 거부
#
# SHA 는 인자로 받지 않고 스크립트가 직접 계산한다.
# 에이전트가 건네준 해시를 신뢰하지 않기 위해서다.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PENDING_SET="$SCRIPT_DIR/pending-set.sh"
CMD="${1:-git commit}"

die() { echo "kkochikkochi: $1" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || die "jq 가 필요합니다"

transcript="$(cat)"
jq -e . >/dev/null 2>&1 <<<"$transcript" || die "transcript 가 올바른 JSON 이 아닙니다"

# questions 는 반드시 배열이어야 한다. jq 의 length 는 문자열/객체에도
# 다형적으로 동작하므로("abc"의 length 는 3), 타입을 먼저 확인하지 않으면
# "질문 없음" 판정을 우회할 수 있다.
jq -e '.questions | type == "array"' >/dev/null 2>&1 <<<"$transcript" \
  || die "questions 는 배열이어야 합니다"

n_questions="$(jq '.questions | length' <<<"$transcript" 2>/dev/null)" \
  || die "questions 배열을 읽을 수 없습니다"

# skipped_reason 도 같은 구멍이 있다 — 문자열이 아닌 값(0, false, [], {})은
# jq 의 `//` 에서 "존재함"으로 취급되어 사유 없는 스킵을 통과시킬 수 있다.
# 문자열일 때만 사유로 인정한다.
skipped="$(jq -r '.skipped_reason | if type == "string" then . else "" end' <<<"$transcript" 2>/dev/null)"

# 문항 0개는 사유가 명시된 경우에만 허용한다.
if [ "$n_questions" -eq 0 ] && [ -z "$skipped" ]; then
  die "문항이 없습니다. 출제를 건너뛰려면 skipped_reason 을 명시하세요"
fi

# 서술형 답변이 공백이면 거부한다.
if jq -e '.questions[]? | select(.format == "free")
          | select((.answer // "") | gsub("\\s"; "") == "")' \
     >/dev/null <<<"$transcript"; then
  die "서술형 답변이 비어 있습니다"
fi

pending="$(bash "$PENDING_SET" "$CMD" 2>/dev/null)" || die "커밋 대상을 계산할 수 없습니다"
[ -n "$pending" ] || die "커밋될 내용이 없습니다"

git_dir="$(git rev-parse --git-dir 2>/dev/null)" || die "git 저장소가 아닙니다"
qdir="$git_dir/quiz-gate"
mkdir -p "$qdir/passes" || die "상태 디렉터리를 만들 수 없습니다"

pass_id="p-$(date -u +%Y%m%d-%H%M%S)"

# covered.tsv 에 추가
while IFS=$'\t' read -r sha path; do
  [ -n "$sha" ] || continue
  printf '%s\t%s\t%s\n' "$sha" "$path" "$pass_id" >> "$qdir/covered.tsv"
done <<<"$pending"

# 문답 전문 저장
covered_json="$(
  while IFS=$'\t' read -r sha path; do
    [ -n "$sha" ] || continue
    jq -n --arg p "$path" --arg s "$sha" '{key: $p, value: $s}'
  done <<<"$pending" | jq -s 'from_entries'
)"

jq -n \
  --arg id "$pass_id" \
  --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg head "$(git rev-parse --short HEAD 2>/dev/null || echo '')" \
  --argjson covered "$covered_json" \
  --argjson transcript "$transcript" \
  '{v: 1, pass_id: $id, at: $at, head: $head,
    covered: $covered, transcript: $transcript}' \
  > "$qdir/passes/$pass_id.json" || die "기록 파일을 쓸 수 없습니다"

echo "$pass_id"
exit 0
