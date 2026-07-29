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

# --- 이 커맨드가 git commit 인가 -------------------------------------
# 접두 매칭(`Bash(git commit:*)`)은 `cd x && git commit` 을 놓치므로 쓰지 않는다.
# 게이트에서는 누락이 곧 실패다. 직접 토큰 단위로 판정한다.
is_git_commit() {
  local segment tok found_git stripped
  # 따옴표 안의 내용은 실행되는 커맨드가 아니므로 지운다.
  # 이걸 하지 않으면 `echo "run git commit later"` 가 오탐된다.
  stripped="$(printf '%s' "$cmd" | sed "s/'[^']*'/''/g; s/\"[^\"]*\"/\"\"/g")"
  # 구분자(; && || |)로 쪼갠다.
  # BSD sed 는 치환문에서 \n 을 개행으로 해석하지 않으므로 awk 를 쓴다.
  while IFS= read -r segment; do
    found_git=0
    # shellcheck disable=SC2086
    set -- $segment
    while [ $# -gt 0 ]; do
      tok="$1"
      if [ "$found_git" -eq 0 ]; then
        case "$tok" in
          git|*/git) found_git=1 ;;
        esac
      else
        case "$tok" in
          # git 레벨 옵션은 값까지 건너뛴다
          -C|-c|--git-dir|--work-tree|--namespace) shift ;;
          --*=*|-*) : ;;
          commit) return 0 ;;
          *) found_git=0 ;;   # 다른 서브커맨드 → 이 git 은 아님
        esac
      fi
      shift
    done
  done < <(printf '%s\n' "$stripped" | awk '{gsub(/&&|\|\||[;|]/, "\n"); print}')
  return 1
}

is_git_commit || allow

# --- 판정 -------------------------------------------------------------
[ -d "$cwd" ] && { cd "$cwd" 2>/dev/null || true; }
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
