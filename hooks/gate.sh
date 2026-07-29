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

# 따옴표를 이해하는 안전한 단어 분리기. -C 의 실제 값(따옴표가 보존된
# 원본 커맨드 안의 값)을 뽑아내는 데 쓴다. eval 을 쓰지 않으므로 값 안에
# $(...) 같은 게 있어도 실행하지 않는다. 결과는 전역 배열 sw 에 담는다.
safe_split() {
  sw=()
  local s="$1" word="" c i=0 len in_sq=0 in_dq=0 have_word=0 tab
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
    elif [ "$in_dq" -eq 1 ]; then
      if [ "$c" = '"' ]; then
        in_dq=0
      else
        word+="$c"
      fi
    else
      case "$c" in
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
            sw+=("$word")
            word=""
            have_word=0
          fi
          ;;
        *)
          word+="$c"
          have_word=1
          ;;
      esac
    fi
    i=$((i + 1))
  done
  if [ "$have_word" -eq 1 ]; then
    sw+=("$word")
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
  local segment tok found_git stripped pos idx c_seg_idx c_tok_pos
  local -a raw_segs
  git_c_dir=""
  raw_segs=()
  while IFS= read -r segment; do
    raw_segs+=("$segment")
  done < <(printf '%s\n' "$cmd" | awk '{gsub(/&&|\|\||[;|]/, "\n"); print}')
  c_seg_idx=-1
  c_tok_pos=0
  idx=0
  # 따옴표 안의 내용은 실행되는 커맨드가 아니므로 지운다.
  # 이걸 하지 않으면 `echo "run git commit later"` 가 오탐된다.
  stripped="$(printf '%s' "$cmd" | sed "s/'[^']*'/''/g; s/\"[^\"]*\"/\"\"/g")"
  # 구분자(; && || |)로 쪼갠다.
  # BSD sed 는 치환문에서 \n 을 개행으로 해석하지 않으므로 awk 를 쓴다.
  while IFS= read -r segment; do
    found_git=0
    pos=0
    # shellcheck disable=SC2086
    set -- $segment
    while [ $# -gt 0 ]; do
      tok="$1"
      pos=$((pos + 1))
      if [ "$found_git" -eq 0 ]; then
        case "$tok" in
          git|*/git) found_git=1 ;;
        esac
      else
        case "$tok" in
          -C)
            # 값의 위치를 기억해 두고, 원본(따옴표 보존) 세그먼트에서
            # 나중에 진짜 값을 뽑는다 — $tok 은 따옴표가 지워진 버전이라
            # 여기서 바로 쓸 수 없다.
            c_seg_idx=$idx
            c_tok_pos=$((pos + 1))
            shift
            pos=$((pos + 1))
            ;;
          # git 레벨 옵션은 값까지 건너뛴다
          -c|--git-dir|--work-tree|--namespace)
            shift
            pos=$((pos + 1))
            ;;
          --*=*|-*) : ;;
          commit)
            if [ "$c_seg_idx" -eq "$idx" ] && [ "$c_tok_pos" -gt 0 ] &&
               [ -n "${raw_segs[$idx]:-}" ]; then
              safe_split "${raw_segs[$idx]}"
              git_c_dir="${sw[$((c_tok_pos - 1))]:-}"
            fi
            return 0
            ;;
          *)
            found_git=0   # 다른 서브커맨드 → 이 git 은 아님
            c_seg_idx=-1
            c_tok_pos=0
            ;;
        esac
      fi
      shift
    done
    idx=$((idx + 1))
  done < <(printf '%s\n' "$stripped" | awk '{gsub(/&&|\|\||[;|]/, "\n"); print}')
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
