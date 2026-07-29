#!/usr/bin/env bash
# 이 커밋에 담길 (blob SHA, 경로) 집합을 계산한다.
#
# 사용법: pending-set.sh "<원본 커맨드 문자열>"
# 출력:   <40자 SHA>\t<경로>   (0줄 이상)
# 종료:   0 = 정상 / 2 = 게이트 무관
#
# 훅과 스킬이 같은 파일 집합을 보게 하는 단일 진실 공급원이다.
# 이 정의가 갈라지면 영원히 통과하지 못하는 교착이 난다.
#
# **never-shrink 불변식** — 출력은 결코 `git diff --cached --raw` 의 부분집합이
# 될 수 없다. 스테이징된 집합을 항상 먼저 낸 뒤, 커맨드가 더 담는다고 말하는
# 만큼만 더한다. 파서가 확신하지 못하는 토큰이 하나라도 있으면 워크트리
# 수정본까지 합집합으로 낸다. 과잉 포함은 사용자가 문항 몇 개를 더 푸는
# 비용이지만, 누락은 게이트가 조용히 꺼지는 실패다. 이 비대칭이 코드
# 구조로 강제되어야 한다 — "이 오탐은 과잉 방향이라 안전하다" 는 식의
# 사람의 추론에 맡기면 반드시 한쪽이 틀린다(실제로 틀렸다).

set -uo pipefail

NULL_SHA=0000000000000000000000000000000000000000
CMD="${1:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/lib-tokenize.sh"

git rev-parse --git-dir >/dev/null 2>&1 || exit 2
GIT_DIR_PATH="$(git rev-parse --git-dir)"

# rebase / cherry-pick / revert / merge 진행 중에 만들어지는 커밋은
# 사용자가 새로 쓴 코드가 아니므로 게이트 대상이 아니다.
for marker in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply; do
  [ -e "$GIT_DIR_PATH/$marker" ] && exit 2
done

# --- 커맨드 인자 파싱 -------------------------------------------------
# gate.sh 와 **같은** 파서를 쓴다. 여기서 갈라지면 훅이 막은 것을 스킬이
# 볼 수 없는 교착이 난다.
use_all=0
pathspecs=()
unknown=0
seen_ddash=0

if [ -r "$LIB" ]; then
  # shellcheck source=scripts/lib-tokenize.sh
  . "$LIB"
  parse_git_commit "$CMD" || unknown=1
else
  # 파서가 없으면 인자에 대해 아무것도 확신할 수 없다 → 합집합.
  unknown=1
  COMMIT_ARGS=()
fi

n_args=${#COMMIT_ARGS[@]}
i=0
while [ "$i" -lt "$n_args" ]; do
  a="${COMMIT_ARGS[$i]}"

  if [ "$seen_ddash" -eq 1 ]; then
    pathspecs+=("$a")
    i=$((i + 1))
    continue
  fi

  case "$a" in
    --)
      seen_ddash=1
      ;;

    # 값을 별도 토큰으로 받는 긴 옵션 → 값 하나를 건너뛴다.
    --message | --file | --author | --date | --template | --cleanup | --trailer | \
    --reuse-message | --reedit-message | --fixup | --squash | --pathspec-from-file)
      i=$((i + 1))
      ;;

    --all)
      use_all=1
      ;;

    # 값이 없는 긴 옵션 — 아는 것만 나열한다. 목록에 없으면 unknown 이다.
    --amend | --no-edit | --edit | --allow-empty | --allow-empty-message | \
    --no-verify | --verify | --dry-run | --short | --branch | --porcelain | \
    --long | --null | --signoff | --no-signoff | --quiet | --verbose | \
    --status | --no-status | --reset-author | --gpg-sign | --no-gpg-sign | \
    --untracked-files | --no-post-rewrite | --only | --include | \
    --pathspec-file-nul)
      :
      ;;

    # --opt=value 형태는 값이 붙어 있으므로 건너뛸 토큰이 없다.
    --*=*)
      case "${a%%=*}" in
        --message | --file | --author | --date | --template | --cleanup | \
        --trailer | --reuse-message | --reedit-message | --fixup | --squash | \
        --pathspec-from-file | --untracked-files | --gpg-sign) : ;;
        *) unknown=1 ;;
      esac
      ;;

    --*)
      unknown=1
      ;;

    -)
      unknown=1
      ;;

    -*)
      # 짧은 옵션 묶음(-am, -va, -sam ...)을 글자 단위로 훑는다.
      bundle="${a#-}"
      blen=${#bundle}
      j=0
      while [ "$j" -lt "$blen" ]; do
        ch="${bundle:$j:1}"
        case "$ch" in
          a)
            use_all=1
            ;;
          # 값을 받는 짧은 옵션. 묶음에 뒤가 더 있으면 그것이 값(-mfoo),
          # 없으면 다음 토큰이 값(-m foo). 어느 쪽이든 묶음은 여기서 끝난다.
          m | F | c | C | t)
            [ "$((j + 1))" -lt "$blen" ] || i=$((i + 1))
            break
            ;;
          # 값이 "붙어 있을 때만" 값인 옵션(-S<keyid>, -u<mode>).
          # 뒤에 뭐가 오든 그것은 값이므로 묶음은 여기서 끝난다.
          S | u)
            break
            ;;
          # 값 없는 짧은 옵션.
          s | v | q | e | n | z | o | i)
            :
            ;;
          # -p(--patch) 는 대화형으로 커밋 내용을 고른다 — 무엇이 담길지
          # 예측할 수 없다. 모르는 글자와 똑같이 취급한다.
          *)
            unknown=1
            ;;
        esac
        j=$((j + 1))
      done
      ;;

    *)
      # 옵션이 아닌 맨 단어는 pathspec 이다. `git commit -m x a.ts` 는
      # a.ts 의 **워크트리** 내용을 커밋한다 — 예전 구현은 이 단어가 어느
      # case 에도 걸리지 않아 그냥 버려졌고, 스테이징 전용 분기로 떨어져
      # 미검증 워크트리 내용을 통과시켰다.
      pathspecs+=("$a")
      ;;
  esac
  i=$((i + 1))
done

# --- 출력 -------------------------------------------------------------
# 경로를 내는 모든 git 호출에 core.quotePath=false 를 건다. git 기본값
# (true)에서는 비ASCII 경로가 C 이스케이프되어(`"\355\225\234..."`) 파일이
# 존재하지 않는 것처럼 보이고, 그 결과 NULL_SHA 가 나온다. NULL_SHA 는
# 내용과 무관하므로 한 번 커버되면 그 파일은 어떻게 바뀌어도 다시 묻지
# 않는다 — 한국어로 쓰인 도구에서 한글 파일명은 예외가 아니라 기본이다.
gitq() { git -c core.quotePath=false "$@"; }

# 초기 커밋에는 HEAD 가 없다. `git diff HEAD` 는 stderr 에 fatal 을 뱉는데,
# 훅은 그것을 삼키지만 스킬은 스크립트를 직접 실행하므로 그 텍스트가
# 그대로 LLM 입력에 들어간다. 근원에서 막는다. HEAD 가 없을 때의
# `git diff` 는 index 대비 워크트리 차이이며, 이것이 그 시점의
# "추적 파일 중 워크트리가 다른 것" 의 올바른 정의다.
HAVE_HEAD=0
git rev-parse --verify -q HEAD >/dev/null 2>&1 && HAVE_HEAD=1

diff_worktree() {   # $@ = 추가 인자(예: -- <pathspec>...)
  if [ "$HAVE_HEAD" -eq 1 ]; then
    gitq diff HEAD --name-only "$@" 2>/dev/null
  else
    gitq diff --name-only "$@" 2>/dev/null
  fi
}

emit_worktree_paths() {   # stdin: 경로들(줄 단위)
  local p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if [ -e "$p" ]; then
      printf '%s\t%s\n' "$(git hash-object -- "$p")" "$p"
    else
      printf '%s\t%s\n' "$NULL_SHA" "$p"
    fi
  done
}

emit_staged() {
  gitq diff --cached --raw --abbrev=40 --no-renames 2>/dev/null |
    awk -F'\t' '{ split($1, f, " "); print f[4] "\t" $2 }'
}

{
  # 언제나 먼저: 스테이징된 집합. 이것이 never-shrink 의 바닥이다.
  emit_staged

  # -a 이거나, 파서가 모르는 것을 하나라도 봤으면 워크트리 수정본까지.
  if [ "$use_all" -eq 1 ] || [ "$unknown" -eq 1 ]; then
    diff_worktree | emit_worktree_paths
  fi

  # pathspec 이 있으면 그 경로의 워크트리 내용도. (--only 는 스테이징된
  # 다른 파일을 담지 않지만, 그쪽을 빼는 것은 축소 방향이라 하지 않는다.)
  if [ "${#pathspecs[@]}" -gt 0 ]; then
    diff_worktree -- "${pathspecs[@]}" | emit_worktree_paths
  fi
} | sort -u
