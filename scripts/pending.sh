#!/usr/bin/env bash
# 이번에 검증해야 할 대상 (blob SHA, 경로) 집합을 결정해 TSV 로 출력한다.
#
# **이 파일이 그 규칙의 유일한 구현이다.** 훅이 남긴 pending 을 쓸지
# `git diff --cached` 로 폴백할지, 그리고 pending 을 언제까지 신선하다고 볼지를
# 여기서만 정한다. 스킬(SKILL.md §1)과 record-pass.sh 가 **둘 다 이 스크립트를
# 부른다.**
#
# 왜 규칙을 한 곳에 두는가: 같은 규칙이 두 벌 있으면 반드시 한쪽이 낡는다.
# 이 브랜치에서만 세 번 겪었고, 마지막이 바로 이 규칙이었다 — SKILL.md 는
# pending 을 신선도 검사 없이 읽고 record-pass.sh 는 900초를 요구해서, 창이
# 지나면 스킬이 낸 문항과 기록되는 파일 집합이 서로 달라졌다. 그 상태에서
# 사용자는 A 를 풀고 B 가 검증된 것으로 기록됐다.
#
# 사용법: pending.sh
# 출력:   <40자리 blob SHA>\t<경로>   한 줄에 하나 (stdout)
# 종료:   0 = 목록 출력 / 1 = 대상 없음 또는 해석 불가 (사유는 stderr)

set -uo pipefail

die() { echo "kkochikkochi: $1" >&2; exit 1; }

# 훅이 남긴 pending 을 몇 초까지 신선하다고 볼 것인가.
#
# 900초(15분)를 고른 근거: 퀴즈의 시간 목표는 오답 재시도 루프까지 포함해
# 3분이다(SKILL.md §2). 그 5배면 코드를 오래 읽는 사람에게도 넉넉하고,
# 그보다 훨씬 길게 잡으면 "예전에 한 번 막혔다가 그만둔" pending 을 나중에
# /kk 로 부른 퀴즈가 집어삼켜 지금 스테이징된 것과 다른 집합을 기록하게 된다.
# 반대로 너무 짧으면 폴백을 타고 C1(영구 교착)이 그대로 되살아난다.
# 훅은 deny 할 때마다 이 파일을 다시 쓰고, record-pass.sh 는 성공적으로
# 기록한 뒤 지운다 — 그래서 이 창이 실제로 문제가 되는 구간은 매우 좁다.
PENDING_FRESH_SECS=900

git_common_dir="$(git rev-parse --git-common-dir 2>/dev/null)" || die "git 저장소가 아닙니다"
pending_file="$git_common_dir/quiz-gate/pending"

qdir="$git_common_dir/quiz-gate"
covered="$qdir/covered.tsv"
ledger="$qdir/ledger.tsv"

MODE="current"
BUNDLE_ID=""
while [ $# -gt 0 ]; do
  case "$1" in
    --bundle)         MODE="bundle"; BUNDLE_ID="${2:-}"; shift ;;
    --all-unverified) MODE="all" ;;
    *) die "알 수 없는 인자: $1 (사용법: pending.sh [--bundle <agent_id> | --all-unverified])" ;;
  esac
  shift
done

[ "$MODE" != "bundle" ] || [ -n "$BUNDLE_ID" ] || die "--bundle 에 agent_id 가 필요합니다"

# 원장에서 미검증 (blob_sha, path) 를 뽑는다. covered.tsv 와의 차집합이며,
# 같은 (sha, path) 가 여러 줄에 있어도 한 번만 낸다.
#
# -v 는 값에 이스케이프 처리를 한다 (back\slash.ts 의 \s 가 사라진다).
# agent_id 는 정규화된 문자열이라 안전하지만, 경로는 ENVIRON 을 거치는
# covered 쪽 비교와 철자가 어긋나지 않도록 원문 그대로 다룬다.
#
# 두 파일을 가르는 데 흔한 `FNR == NR` 트릭을 쓰지 않는다: covered.tsv 가
# 아직 없어 0바이트로 부트스트랩된 첫 실행에서는 NR 이 첫 파일 동안 전혀
# 늘지 않아, 두 번째 파일(ledger)의 첫 줄에서도 FNR==NR(둘 다 1)이 되어
# ledger 전체가 covered 로 오분류된다(실측). 대신 covered 경로를
# ENVIRON 으로 넘겨 FILENAME 과 비교한다 — 몇 줄짜리인지와 무관하다.
ledger_unverified() {  # $1 = agent_id 또는 빈 문자열(전체)
  [ -r "$ledger" ] || return 1
  KK_FILTER="$1" KK_COVERED="$covered" awk -F'\t' '
    FILENAME == ENVIRON["KK_COVERED"] { if (NF >= 2) covered[$1 FS $2] = 1; next }
    {
      if (NF != 5) { bad = 1; exit }
      if (length($1) != 40 || $1 ~ /[^0-9a-f]/ || $2 == "") { bad = 1; exit }
      want = ENVIRON["KK_FILTER"]
      if (want != "" && $3 != want) next
      key = $1 FS $2
      if (key in covered) next
      if (key in seen) next
      seen[key] = 1
      print $1 "\t" $2
    }
    END { if (bad) exit 1 }
  ' "${covered:-/dev/null}" "$ledger" 2>/dev/null
}

if [ "$MODE" != "current" ]; then
  filter=""
  [ "$MODE" = "bundle" ] && filter="$BUNDLE_ID"

  # 원장이 아직 없는 것과 원장이 손상된 것은 서로 다른 사유다. 원장이 없는
  # 것은 서브에이전트가 한 번도 커밋하지 않은 정상 상태이고, stop-gate.sh
  # 가 매 턴 --all-unverified 를 부르므로(D45) 이 경로가 드문 사고가 아니라
  # 흔한 경우다 — 둘을 같은 "손상" 메시지로 뭉치면 그 흔한 경우가 사고처럼
  # 보인다.
  #
  # 종료 코드는 두 경우 다 1로 그대로 둔다 — 이건 기존 호출자와의 호환성
  # 계약이고 여기서 바꾸지 않는다. 하지만 "모든 호출자가 둘을 똑같이
  # 취급해도 된다"는 뜻은 아니다: stop-gate.sh 는 원장이 존재하는데 못
  # 읽는 경우(형식이 깨졌거나 append 가 중간에 끊겼거나 권한 문제)를
  # "미검증 없음"과 다르게 취급해 유예(defer)를 지우지 않고 크게
  # 알린다 — 나쁜 줄 하나가 원장 전체를 못 읽게 만들어 같은 원장에 있던
  # 다른 파일의 미검증 상태까지 가릴 수 있어서다(실측, review critical
  # finding 1). 그 판단은 이 메시지 문자열을 파싱해서 내리지 않는다 —
  # 원장 파일 자체의 존재/크기를 stop-gate.sh 가 독자적으로 확인한다.
  # (빈 원장은 이 검사를 통과해 아래 ledger_unverified 로 가고, out="" 이
  # 되어 그다음 줄의 "검증할 것이 없습니다"로 자연히 떨어진다 — 손상이
  # 아니다.)
  #
  # 이 검사는 covered.tsv 부트스트랩(바로 아래)보다 **먼저** 와야 한다.
  # Task 4 가 그 부트스트랩을 여기로 옮긴 이유가 바로 "아직 아무도 커밋하지
  # 않은 새 레포에서 pending.sh 를 부르기만 해도 covered.tsv 가 생기는
  # 부작용을 막는 것"이었다(review important 3, 아래 부트스트랩 주석의
  # 실측 참고). 원장이 없으면 stop-gate.sh 가 매 턴 이 분기를 타므로,
  # 순서를 반대로 두면 그 부작용이 "드문 사고"에서 "항상 일어나는 일"로
  # 바뀐다.
  if [ ! -r "$ledger" ]; then
    die "검증할 것이 없습니다 (근거: 원장 없음)"
  fi

  # covered 가 없을 때 awk 가 죽지 않게 먼저 만든다. current 모드는 절대
  # 여기를 지나지 않으므로 인자 없는 pending.sh 는 covered.tsv 에 손대지
  # 않는다(실측: qdir 가 아직 없는 새 레포에서 무조건 실행하면 "No such
  # file or directory" 가 새어나가고, 아무 통과도 기록하지 않았는데
  # covered.tsv 가 빈 파일로 생겨버린다). `{ } 2>/dev/null` 로 그룹째
  # 감싸야 한다 — `: > "$covered" 2>/dev/null` 처럼 fd1 리다이렉트만 따로
  # 실패하면 bash 는 그 실패를 fd2 리다이렉트가 걸리기 **전에** 보고해
  # 억제되지 않는다.
  [ -e "$covered" ] || { : > "$covered"; } 2>/dev/null || covered=/dev/null

  if ! out="$(ledger_unverified "$filter")"; then
    die "원장이 손상됐습니다 ($ledger)"
  fi
  [ -n "$out" ] || die "검증할 것이 없습니다 (근거: 원장)"
  printf '%s\n' "$out"
  exit 0
fi

# ① 훅이 발표한 답이 있고 신선하면 그것을 쓴다.
#
# 이것이 필요한 이유: git 은 `-a` 나 `-- <path>` 커밋에서 훅에게 **임시
# 인덱스**를 물려준다(실측: `git commit -a` 는 GIT_INDEX_FILE=.../index.lock,
# 평범한 스테이징 커밋은 .git/index). 그래서 훅 안의 `git diff --cached` 는
# 정확하지만, 나중에 평범한 셸에서 도는 같은 명령은 진짜 인덱스를 본다 —
# 같은 명령이 다른 답을 낸다. 훅에게 답을 다시 물어보게 하지 않고 훅이
# 답을 발표하게 만든 이유다. (D40)
pending=""
source_desc="git diff --cached"
if [ -s "$pending_file" ]; then
  # GNU 는 -f 를 --file-system 으로 해석해 종료코드 0으로 헛값을 낸다. GNU
  # 형식을 먼저 시도해야 그 헛값이 아니라 진짜 실패로 폴백을 탄다.
  mtime="$(stat -c %Y "$pending_file" 2>/dev/null || stat -f %m "$pending_file" 2>/dev/null || echo 0)"
  case "$mtime" in '' | *[!0-9]*) mtime=0 ;; esac
  age=$(( $(date +%s) - mtime ))
  if [ "$age" -ge 0 ] && [ "$age" -le "$PENDING_FRESH_SECS" ]; then
    pending="$(cat "$pending_file")"
    source_desc="훅이 남긴 pending"
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

[ -n "$pending" ] || die "커밋될 내용이 없습니다 (근거: $source_desc)"

# ③ 형식 검증. 두 경로가 합류하는 유일한 지점이므로 검사도 여기 한 번만 둔다.
#
# 잘린 줄(SHA 만 있고 경로가 없는)을 그냥 넘기면 record-pass.sh 가
# `sha<TAB><TAB>pass_id` 를 covered.tsv 에 쓰고 **성공을 보고한다** — 사용자는
# 통과했다는 말을 듣지만 게이트는 그대로 막혀 있다. 조용한 성공보다 시끄러운
# 실패가 낫다. 경로에 진짜 탭이 든 경우(NF > 2)도 여기서 걸린다: covered.tsv
# 가 탭 구분이라 애초에 기록할 수 없는 경로이며, README 한계 표에 회복
# 방법을 적어두었다.
printf '%s\n' "$pending" | awk -F'\t' '
  NF != 2 || length($1) != 40 || $1 ~ /[^0-9a-f]/ || $2 == "" { exit 1 }
  END { if (NR == 0) exit 1 }
' || die "검증 대상 목록이 손상됐습니다 (근거: $source_desc). 경로에 탭 문자가 있거나 pending 파일이 잘렸습니다"

printf '%s\n' "$pending"
