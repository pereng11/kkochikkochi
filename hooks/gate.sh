#!/usr/bin/env bash
# PreToolUse 훅. git commit 을 가로채 이해 검증 여부를 판정한다.
#
# 판정만 한다. LLM 을 부르지 않고, 파일을 고치지 않고, git 상태를 바꾸지 않는다.
# 실패하면 통과시킨다(fail-open) — 게이트 버그가 커밋을 영구 차단해서는 안 된다.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PENDING_SET="$SCRIPT_DIR/../scripts/pending-set.sh"

allow() { exit 0; }   # 출력 없이 종료 = 판정 없음 = 정상 권한 흐름

command -v jq >/dev/null 2>&1 || allow

payload="$(cat)"
tool_name="$(jq -r '.tool_name // ""' <<<"$payload" 2>/dev/null)" || allow
[ "$tool_name" = "Bash" ] || allow

cmd="$(jq -r '.tool_input.command // ""' <<<"$payload" 2>/dev/null)" || allow
cwd="$(jq -r '.cwd // ""' <<<"$payload" 2>/dev/null)" || allow

# 원본 커맨드를 통째로, 따옴표를 이해하는 상태 기계로 단 한 번에
# 토큰화한다. 세그먼트(; && || | 로 나뉘는 단위) 경계와 단어 분리를
# 같은 패스에서 처리하므로, 따옴표 안에 숨은 구분자 때문에 두 번 쪼갠
# 결과가 서로 다른 개수로 갈라지는 일이 구조적으로 있을 수 없다
# (예전에는 분류용으로 따옴표를 지운 문자열과, 원본 문자열을 각각
# awk 로 따로 쪼갰는데, `-c foo="a && b"` 처럼 따옴표 안에 구분자가
# 들어있으면 두 결과의 세그먼트 개수가 어긋나 -C 값을 엉뚱한 데서
# 읽어오는 버그가 있었다). eval 을 쓰지 않으므로 값 안에 $(...) 같은
# 게 있어도 실행하지 않는다.
#
# 결과: 전역 배열 TOKENS(모든 세그먼트를 통틀어 순서대로 나열한, 따옴표가
# 제거된 실제 토큰들)와 TOK_SEG(TOKENS 와 길이가 같고, 각 토큰이 속한
# 세그먼트 번호를 담는다. 0부터 시작).
tokenize_cmd() {
  TOKENS=()
  TOK_SEG=()
  local s="$1" word="" c c2 i=0 len in_sq=0 in_dq=0 have_word=0 seg=0 tab
  tab="$(printf '\t')"
  len=${#s}
  while [ "$i" -lt "$len" ]; do
    c="${s:$i:1}"
    if [ "$in_sq" -eq 1 ]; then
      if [ "$c" = "'" ]; then
        in_sq=0
      else
        word+="$c"
      fi
      i=$((i + 1))
      continue
    fi
    if [ "$in_dq" -eq 1 ]; then
      if [ "$c" = '"' ]; then
        in_dq=0
      else
        word+="$c"
      fi
      i=$((i + 1))
      continue
    fi
    # 따옴표 밖에 있을 때만 구분자/공백/따옴표 시작을 인식한다.
    c2="${s:$i:2}"
    if [ "$c2" = "&&" ] || [ "$c2" = "||" ]; then
      if [ "$have_word" -eq 1 ]; then
        TOKENS+=("$word"); TOK_SEG+=("$seg"); word=""; have_word=0
      fi
      seg=$((seg + 1))
      i=$((i + 2))
      continue
    fi
    case "$c" in
      ";" | "|")
        if [ "$have_word" -eq 1 ]; then
          TOKENS+=("$word"); TOK_SEG+=("$seg"); word=""; have_word=0
        fi
        seg=$((seg + 1))
        ;;
      "'")
        in_sq=1
        have_word=1
        ;;
      '"')
        in_dq=1
        have_word=1
        ;;
      " " | "$tab")
        if [ "$have_word" -eq 1 ]; then
          TOKENS+=("$word"); TOK_SEG+=("$seg"); word=""; have_word=0
        fi
        ;;
      *)
        word+="$c"
        have_word=1
        ;;
    esac
    i=$((i + 1))
  done
  if [ "$have_word" -eq 1 ]; then
    TOKENS+=("$word"); TOK_SEG+=("$seg")
  fi
}

# --- 이 커맨드가 git commit 인가 -------------------------------------
# 접두 매칭(`Bash(git commit:*)`)은 `cd x && git commit` 을 놓치므로 쓰지 않는다.
# 게이트에서는 누락이 곧 실패다. 직접 토큰 단위로 판정한다.
#
# `git -C <dir> commit` 은 실제로 다른 저장소를 향한다. 이 함수는 그 값을
# 전역 변수 git_c_dir 에 채운다(없으면 빈 문자열). 여러 -C 는 합성하지
# 않는다 — 마지막 값만 쓰고, cwd 기준으로 바로 해석한다(git 처럼 이전
# -C 에 상대적으로 누적하지 않는다).
is_git_commit() {
  local i n tok seg cur_seg found_git c_seg c_tok_idx
  git_c_dir=""
  tokenize_cmd "$cmd"
  n=${#TOKENS[@]}
  cur_seg=-1
  found_git=0
  c_seg=-1
  c_tok_idx=-1
  i=0
  while [ "$i" -lt "$n" ]; do
    tok="${TOKENS[$i]}"
    seg="${TOK_SEG[$i]}"
    if [ "$seg" != "$cur_seg" ]; then
      cur_seg="$seg"
      found_git=0
    fi
    if [ "$found_git" -eq 0 ]; then
      case "$tok" in
        git|*/git) found_git=1 ;;
      esac
    else
      case "$tok" in
        -C)
          # 값은 바로 다음 토큰이다. TOKENS 는 이미 따옴표가 제거된
          # 실제 값이므로, 나중에 다시 원본을 뒤질 필요가 없다.
          # 단, -C 가 자기 세그먼트의 마지막 토큰이면(예: `git -C;
          # git commit`) 다음 토큰은 완전히 다른 세그먼트의 것이다 —
          # 그걸 값으로 건너뛰면 그 세그먼트의 진짜 git 호출을 통째로
          # 건너뛰게 된다. 그래서 여기서도 아래 commit 판정과 똑같이
          # "같은 세그먼트인가" 를 확인한다.
          if [ "$((i + 1))" -lt "$n" ] && [ "${TOK_SEG[$((i + 1))]}" = "$cur_seg" ]; then
            c_seg="$cur_seg"
            c_tok_idx=$((i + 1))
            i=$((i + 1))   # -C 의 값 토큰은 분류 대상에서 건너뛴다
          fi
          ;;
        # git 레벨 옵션은 값까지 건너뛴다 — 단, 그 값이 같은
        # 세그먼트 안에 있을 때만. 세그먼트 경계 너머는 다른 명령이다.
        -c|--git-dir|--work-tree|--namespace)
          if [ "$((i + 1))" -lt "$n" ] && [ "${TOK_SEG[$((i + 1))]}" = "$cur_seg" ]; then
            i=$((i + 1))
          fi
          ;;
        --*=*|-*) : ;;
        commit)
          if [ "$c_seg" = "$cur_seg" ] && [ "$c_tok_idx" -ge 0 ] &&
             [ "$c_tok_idx" -lt "$n" ] && [ "${TOK_SEG[$c_tok_idx]}" = "$cur_seg" ]; then
            git_c_dir="${TOKENS[$c_tok_idx]}"
          fi
          return 0
          ;;
        *)
          found_git=0   # 다른 서브커맨드 → 이 git 은 아님
          c_seg=-1
          c_tok_idx=-1
          ;;
      esac
    fi
    i=$((i + 1))
  done
  return 1
}

is_git_commit || allow

# --- 판정 -------------------------------------------------------------
if [ -n "$git_c_dir" ]; then
  # -C 가 있으면 그 저장소를 기준으로 판정한다. cwd 를 그대로 쓰면 세션
  # 레포와 실제 커밋 대상 레포가 갈라져 오판(과잉 차단 또는 누락 통과)이
  # 난다. 상대경로면 훅이 알려준 cwd 기준으로 해석한다.
  case "$git_c_dir" in
    /*) target_dir="$git_c_dir" ;;
    *) target_dir="$cwd/$git_c_dir" ;;
  esac
  # 여기서는 대상이 명확히 지정됐으므로, 들어갈 수 없으면 그냥
  # 넘어가지 않고 바로 통과시킨다 — 엉뚱한 디렉터리 기준으로
  # 판정하는 것보다 판정을 안 하는 게 낫다.
  [ -d "$target_dir" ] || allow
  cd "$target_dir" 2>/dev/null || allow
else
  [ -d "$cwd" ] && { cd "$cwd" 2>/dev/null || true; }
fi
[ -r "$PENDING_SET" ] || allow

pending="$(bash "$PENDING_SET" "$cmd" 2>/dev/null)"
rc=$?
[ "$rc" -eq 0 ] || allow          # 2 = 게이트 무관, 그 외 = 오류 → fail-open
[ -n "$pending" ] || allow        # 커밋될 내용 없음

git_dir="$(git rev-parse --git-dir 2>/dev/null)" || allow
covered="$git_dir/quiz-gate/covered.tsv"

missing=""
while IFS=$'\t' read -r sha path; do
  [ -n "$sha" ] || continue
  if [ -r "$covered" ] &&
     awk -F'\t' -v s="$sha" -v p="$path" \
       '$1 == s && $2 == p { found = 1; exit } END { exit !found }' "$covered"; then
    continue
  fi
  missing+="   $path"$'\n'
done <<<"$pending"

[ -n "$missing" ] || allow

reason="🦡 KkochiKkochi — 미검증 변경이 있습니다.

$missing
이 변경을 이해했는지 먼저 확인해야 합니다.
kkochikkochi 스킬을 실행해 퀴즈를 통과한 뒤 다시 커밋하세요."

jq -n --arg r "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $r
  }
}'
exit 0
