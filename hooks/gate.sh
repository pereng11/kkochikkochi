#!/usr/bin/env bash
# PreToolUse 훅. git commit 을 가로채 이해 검증 여부를 판정한다.
#
# 판정만 한다. LLM 을 부르지 않고, 파일을 고치지 않고, git 상태를 바꾸지 않는다.
# 실패하면 통과시킨다(fail-open) — 게이트 버그가 커밋을 영구 차단해서는 안 된다.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PENDING_SET="$SCRIPT_DIR/../scripts/pending-set.sh"
LIB_TOKENIZE="$SCRIPT_DIR/../scripts/lib-tokenize.sh"

allow() { exit 0; }   # 출력 없이 종료 = 판정 없음 = 정상 권한 흐름

command -v jq >/dev/null 2>&1 || allow

payload="$(cat)"
tool_name="$(jq -r '.tool_name // ""' <<<"$payload" 2>/dev/null)" || allow
[ "$tool_name" = "Bash" ] || allow

cmd="$(jq -r '.tool_input.command // ""' <<<"$payload" 2>/dev/null)" || allow
cwd="$(jq -r '.cwd // ""' <<<"$payload" 2>/dev/null)" || allow

# --- 값싼 사전 필터 ---------------------------------------------------
# 이 훅은 **모든** Bash 호출에 붙는다(hooks.json 의 matcher 는 "Bash").
# 아래 토크나이저는 커맨드 길이에 민감한데, Claude Code 는 heredoc,
# `python -c`, 큰 sed/awk 같은 긴 커맨드를 수시로 낸다. `commit` 이라는
# 글자가 아예 없으면 토큰화할 이유가 없다 — parse_git_commit 은 리터럴
# `commit` 토큰을 요구하므로 이 필터로 놓치는 커밋은 존재할 수 없다.
case "$cmd" in
  *commit*) ;;
  *) allow ;;
esac

[ -r "$LIB_TOKENIZE" ] || allow
# shellcheck source=scripts/lib-tokenize.sh
. "$LIB_TOKENIZE"

# 파싱은 scripts/lib-tokenize.sh 한 곳에서만 한다. pending-set.sh 도
# 같은 함수를 쓴다 — 훅과 스킬이 같은 문자열에서 다른 답을 얻으면
# "훅은 막는데 스킬은 볼 게 없다" 는 영구 교착이 난다.
parse_git_commit "$cmd" || allow
git_c_dir="$GIT_C_DIR"

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

# 차단된 커맨드 원문을 사유에 실어 보낸다. 스킬은 이것을 그대로
# pending-set.sh / record-pass.sh 에 넘겨야 한다 — 스킬이 "git commit" 을
# 임의로 가정하면(예전 동작) `git commit -am x` 처럼 훅과 답이 갈리는
# 커맨드에서 훅은 막는데 스킬은 볼 게 없는 영구 교착이 난다.
reason="🦡 KkochiKkochi — 미검증 변경이 있습니다.

$missing
이 변경을 이해했는지 먼저 확인해야 합니다.
kkochikkochi 스킬을 실행해 퀴즈를 통과한 뒤 다시 커밋하세요.

차단된 커맨드 — 스킬은 이 문자열을 **그대로** pending-set.sh 와
record-pass.sh 의 인자로 넘길 것:
\`\`\`
$cmd
\`\`\`"

jq -n --arg r "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $r
  }
}'
exit 0
