#!/usr/bin/env bash
# 퀴즈 통과를 기록한다.
#
# 사용법: echo "<transcript json>" | record-pass.sh
# 종료:   0 = 기록됨 / 1 = 거부
#
# 대상(SHA·경로)은 인자로 받지 않고 `git diff --cached` 로 직접 계산한다.
# 에이전트가 건네준 명령 문자열이나 해시를 신뢰하지 않기 위해서다. 이 값은
# 커밋될 내용 그 자체이므로 파싱이 필요 없다 — hooks/pre-commit 과 같은
# 원리다.

set -uo pipefail

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
if jq -e '.questions[] | select(.format == "free")
          | select((.answer // "") | gsub("\\s"; "") == "")' \
     >/dev/null <<<"$transcript"; then
  die "서술형 답변이 비어 있습니다"
fi

# 커밋될 내용 = git diff --cached. hooks/pre-commit 과 정확히 같은 커맨드와
# 같은 -z 파싱을 쓴다 — --name-only 나 -z 없는 형태는 큰따옴표·역슬래시·
# 탭·개행을 담은 경로를 C-quote 해 버려 covered.tsv 의 철자가 게이트가
# 읽는 철자와 달라진다. 그러면 그 경로는 어떤 퀴즈로도 통과시킬 수 없는
# 채로 영영 막힌다. 삭제된 파일은 --raw 가 이미 40개의 0 SHA 를 내어주므로
# git hash-object 로 다시 계산하지 않는다 — 그건 애초에 존재하지 않는
# blob 의 해시라 계산할 수 없다.
pending="$(git -c core.quotePath=false diff --cached --raw -z --abbrev=40 --no-renames \
           | tr '\0' '\n' \
           | awk 'NR % 2 { split($0, f, " "); sha = f[4]; next } { printf "%s\t%s\n", sha, $0 }')"
[ -n "$pending" ] || die "커밋될 내용이 없습니다"

git_dir="$(git rev-parse --git-dir 2>/dev/null)" || die "git 저장소가 아닙니다"
qdir="$git_dir/quiz-gate"
mkdir -p "$qdir/passes" || die "상태 디렉터리를 만들 수 없습니다"

pass_id="p-$(date -u +%Y%m%d-%H%M%S)"

# 문답 전문을 먼저 저장하고, 그것이 안전하게 자리잡은 뒤에만 covered.tsv 에
# 커버리지를 기록한다. 순서를 반대로 하면(커버리지 라인을 먼저 쓰면)
# 전문 저장이 실패했을 때 감사 기록 없는 "유령 커버리지"가 covered.tsv 에
# 영원히 남아 hooks/pre-commit 을 조용히 무력화한다.
#
# 같은 디렉터리에 임시 파일로 먼저 쓰고 mv 로 옮겨, 쓰다 만 JSON 이
# passes/ 아래에 절대 보이지 않게 한다(mv 는 같은 파일시스템에서 원자적).
covered_json="$(
  while IFS=$'\t' read -r sha path; do
    [ -n "$sha" ] || continue
    jq -n --arg p "$path" --arg s "$sha" '{key: $p, value: $s}'
  done <<<"$pending" | jq -s 'from_entries'
)"

tmp_pass="$(mktemp "$qdir/passes/.tmp.XXXXXX" 2>/dev/null)" \
  || die "임시 파일을 만들 수 없습니다"

jq -n \
  --arg id "$pass_id" \
  --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg head "$(git rev-parse --short HEAD 2>/dev/null || echo '')" \
  --argjson covered "$covered_json" \
  --argjson transcript "$transcript" \
  '{v: 1, pass_id: $id, at: $at, head: $head,
    covered: $covered, transcript: $transcript}' \
  > "$tmp_pass" || { rm -f "$tmp_pass"; die "기록 파일을 쓸 수 없습니다"; }

mv "$tmp_pass" "$qdir/passes/$pass_id.json" \
  || { rm -f "$tmp_pass"; die "기록 파일을 옮길 수 없습니다"; }

# 전문이 안전하게 자리잡았으니 이제 covered.tsv 에 추가한다. 이 추가가
# 실패하면 전문은 있는데 커버리지가 없는 상태가 되지만, 그 방향은
# 안전하다 — 사용자는 그저 다시 퀴즈를 통과해야 할 뿐이다.
while IFS=$'\t' read -r sha path; do
  [ -n "$sha" ] || continue
  printf '%s\t%s\t%s\n' "$sha" "$path" "$pass_id" >> "$qdir/covered.tsv"
done <<<"$pending"

echo "$pass_id"
exit 0
