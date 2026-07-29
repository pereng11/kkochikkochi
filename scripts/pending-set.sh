#!/usr/bin/env bash
# 이 커밋에 담길 (blob SHA, 경로) 집합을 계산한다.
#
# 사용법: pending-set.sh "<원본 커맨드 문자열>"
# 출력:   <40자 SHA>\t<경로>   (0줄 이상)
# 종료:   0 = 정상 / 2 = 게이트 무관
#
# 훅과 스킬이 같은 파일 집합을 보게 하는 단일 진실 공급원이다.
# 이 정의가 갈라지면 영원히 통과하지 못하는 교착이 난다.

set -uo pipefail

NULL_SHA=0000000000000000000000000000000000000000
CMD="${1:-}"

git rev-parse --git-dir >/dev/null 2>&1 || exit 2
GIT_DIR_PATH="$(git rev-parse --git-dir)"

# rebase / cherry-pick / revert / merge 진행 중에 만들어지는 커밋은
# 사용자가 새로 쓴 코드가 아니므로 게이트 대상이 아니다.
for marker in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply; do
  [ -e "$GIT_DIR_PATH/$marker" ] && exit 2
done

# --- 커맨드 인자 파싱 -------------------------------------------------
# `git commit` 이후의 인자만 본다.
ARGS="${CMD#*git }"
ARGS="${ARGS#*commit}"

use_all=0
pathspecs=()
seen_ddash=0

# shellcheck disable=SC2086
set -- $ARGS
while [ $# -gt 0 ]; do
  if [ "$seen_ddash" -eq 1 ]; then
    pathspecs+=("$1"); shift; continue
  fi
  case "$1" in
    --) seen_ddash=1 ;;
    --all) use_all=1 ;;
    --*) case "$1" in
           --message|--file|--reuse-message|--author|--date) shift ;;
         esac ;;
    -*)
      # 짧은 옵션 묶음(-am, -va 등) 안의 a 를 인식한다.
      case "$1" in *a*) use_all=1 ;; esac
      # 값이 따라오는 옵션은 값을 건너뛴다.
      case "$1" in -m|-F|-C|-c) shift ;; esac
      ;;
  esac
  shift
done

# --- 출력 -------------------------------------------------------------
emit_worktree() {  # $1 = 경로
  if [ -e "$1" ]; then
    printf '%s\t%s\n' "$(git hash-object -- "$1")" "$1"
  else
    printf '%s\t%s\n' "$NULL_SHA" "$1"
  fi
}

if [ "${#pathspecs[@]}" -gt 0 ]; then
  # pathspec 지정: 해당 경로의 워크트리 내용이 커밋된다.
  git diff HEAD --name-only -- "${pathspecs[@]}" | while IFS= read -r p; do
    emit_worktree "$p"
  done
elif [ "$use_all" -eq 1 ]; then
  # -a: 추적 파일의 워크트리 내용 + 이미 스테이징된 신규 파일
  { git diff HEAD --name-only; git diff --cached --name-only; } | sort -u |
    while IFS= read -r p; do emit_worktree "$p"; done
else
  # 기본: index 내용. git 이 이미 완성된 형태로 준다.
  git diff --cached --raw --abbrev=40 --no-renames |
    awk -F'\t' '{ split($1, f, " "); print f[4] "\t" $2 }'
fi
