#!/usr/bin/env bash
# 퀴즈 통과를 기록한다.
#
# 사용법: echo "<transcript json>" | record-pass.sh
# 종료:   0 = 기록됨 / 1 = 거부
#
# 대상(SHA·경로)은 인자로 받지 않는다. 에이전트가 건네준 명령 문자열이나
# 해시를 신뢰하지 않기 위해서다. 두 군데에서 얻는다:
#
#   1) 훅이 남긴 $GIT_DIR/quiz-gate/pending — 훅이 **자기가 계산한 답**을
#      그대로 적어 둔 파일. 이것이 있고 신선하면 이것을 쓴다.
#   2) 없거나 낡았으면 `git diff --cached` 로 직접 계산한다.
#
# 1이 필요한 이유: git 은 `-a` 나 `-- <path>` 커밋에서 훅에게 **임시 인덱스**를
# 물려준다(실측: `git commit -a` 는 GIT_INDEX_FILE=.../index.lock, 평범한
# 스테이징 커밋은 .git/index). 그래서 훅 안의 `git diff --cached` 는 정확하지만,
# 나중에 평범한 셸에서 도는 이 스크립트의 `git diff --cached` 는 진짜 인덱스를
# 본다 — 같은 명령이 다른 답을 낸다. 훅에게 답을 다시 물어보게 하지 않고
# 훅이 답을 발표하게 만든 이유다. (D40)

set -uo pipefail

die() { echo "kkochikkochi: $1" >&2; exit 1; }

# 훅이 남긴 pending 을 몇 초까지 신선하다고 볼 것인가.
#
# 900초(15분)를 고른 근거: 퀴즈의 시간 목표는 오답 재시도 루프까지 포함해
# 3분이다(SKILL.md §2). 그 5배면 코드를 오래 읽는 사람에게도 넉넉하고,
# 그보다 훨씬 길게 잡으면 "예전에 한 번 막혔다가 그만둔" pending 을 나중에
# /kk 로 부른 퀴즈가 집어삼켜 지금 스테이징된 것과 다른 집합을 기록하게 된다.
# 반대로 너무 짧으면 폴백을 타고 C1(영구 교착)이 그대로 되살아난다.
# 훅은 deny 할 때마다 이 파일을 다시 쓰고, 이 스크립트는 성공적으로 기록한
# 뒤 지운다 — 그래서 이 창이 실제로 문제가 되는 구간은 매우 좁다.
PENDING_FRESH_SECS=900

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

git_dir="$(git rev-parse --git-dir 2>/dev/null)" || die "git 저장소가 아닙니다"
qdir="$git_dir/quiz-gate"

# ① 훅이 발표한 답이 있고 신선하면 그것을 쓴다.
pending=""
pending_file="$qdir/pending"
pending_source="git diff --cached"
if [ -s "$pending_file" ]; then
  # GNU 는 -f 를 --file-system 으로 해석해 종료코드 0으로 헛값을 낸다. GNU
  # 형식을 먼저 시도해야 그 헛값이 아니라 진짜 실패로 폴백을 탄다.
  mtime="$(stat -c %Y "$pending_file" 2>/dev/null || stat -f %m "$pending_file" 2>/dev/null || echo 0)"
  case "$mtime" in '' | *[!0-9]*) mtime=0 ;; esac
  age=$(( $(date +%s) - mtime ))
  if [ "$age" -ge 0 ] && [ "$age" -le "$PENDING_FRESH_SECS" ]; then
    pending="$(cat "$pending_file")"
    pending_source="훅이 남긴 pending"
  fi
fi

# ② 폴백 — 커밋될 내용 = git diff --cached. hooks/pre-commit 과 정확히 같은
# 커맨드와 같은 -z 파싱을 쓴다 — --name-only 나 -z 없는 형태는 큰따옴표·
# 역슬래시·탭·개행을 담은 경로를 C-quote 해 버려 covered.tsv 의 철자가
# 게이트가 읽는 철자와 달라진다. 그러면 그 경로는 어떤 퀴즈로도 통과시킬 수
# 없는 채로 영영 막힌다. 삭제된 파일은 --raw 가 이미 40개의 0 SHA 를
# 내어주므로 git hash-object 로 다시 계산하지 않는다 — 그건 애초에 존재하지
# 않는 blob 의 해시라 계산할 수 없다.
#
# meta 줄의 생김새를 매 짝마다 검사한다(hooks/pre-commit 과 같은 검사).
# 경로에 진짜 개행이 있어 스트림이 밀리면, 검사 없이는 --raw meta 줄을
# 그대로 담은 쓰레기 라인이 covered.tsv 에 들어간다 — 그건 감사 기록을
# 오염시키고 그 뒤 파일들의 커버리지를 통째로 날린다. 쓰레기를 쓰느니
# 거부한다(그 커밋은 훅이 이미 fail-open 으로 통과시키므로 막히지 않는다).
if [ -z "$pending" ]; then
  if ! pending="$(git -c core.quotePath=false diff --cached --raw -z --abbrev=40 --no-renames \
             | tr '\0' '\n' \
             | awk '
      function is_meta(s,   n, a) {
        if (substr(s, 1, 1) != ":") return 0
        n = split(s, a, " ")
        if (n != 5) return 0
        if (length(a[1]) != 7) return 0
        if (length(a[3]) != 40 || length(a[4]) != 40) return 0
        if (a[3] ~ /[^0-9a-f]/ || a[4] ~ /[^0-9a-f]/) return 0
        return 1
      }
      NR % 2 { if (!is_meta($0)) exit 1; split($0, f, " "); sha = f[4]; next }
             { printf "%s\t%s\n", sha, $0 }
      END    { if (NR % 2) exit 1 }
    ')"; then
    die "커밋될 경로 목록을 해석할 수 없습니다 (경로에 개행 문자가 있습니까?)"
  fi
fi

[ -n "$pending" ] || die "커밋될 내용이 없습니다 (근거: $pending_source)"

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

# 다 쓴 pending 은 지운다. 남겨두면 나중에 /kk 로 부른 퀴즈가 지금 스테이징된
# 것과 다른 집합을 기록할 수 있다. 커버리지 기록이 끝난 **뒤에** 지워야
# 한다 — 먼저 지우면 위에서 실패했을 때 훅의 답을 잃고 폴백(C1)으로 떨어진다.
rm -f "$pending_file" 2>/dev/null || :

echo "$pass_id"
exit 0
