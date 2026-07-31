#!/usr/bin/env bats
#
# 상태는 워크트리를 넘나들어야 한다.
#
# --git-path quiz-gate 는 링크된 워크트리에서 .git/worktrees/<name>/quiz-gate 로
# 풀린다(실측). 그러면 워크트리로 격리된 서브에이전트가 만든 커밋의 원장을
# 메인 세션의 Stop 훅이 보지 못한다 — 게이트가 조용히 없는 상태가 된다.

load helper

setup() { setup_repo; seed_repo; }
teardown() { teardown_repo; }

@test "링크된 워크트리와 메인 저장소가 같은 quiz-gate 를 가리킨다" {
  main_qdir="$(cd "$TEST_REPO" && qdir)"
  main_real="$(mkdir -p "$main_qdir" && cd "$main_qdir" && pwd -P)"

  wt="$(add_worktree br1)"
  wt_qdir="$(cd "$wt" && qdir)"
  wt_real="$(mkdir -p "$wt_qdir" && cd "$wt_qdir" && pwd -P)"

  [ "$main_real" = "$wt_real" ]
}

@test "워크트리에서 훅이 남긴 pending 을 메인 저장소에서 읽는다" {
  install_hook
  wt="$(add_worktree br2)"

  cd "$wt"
  printf 'W1\n' > w.ts
  git add w.ts
  stamp
  run git commit -qm "from worktree"
  [ "$status" -ne 0 ]

  # 훅이 발표한 답을 메인 저장소 쪽에서 읽을 수 있어야 한다
  cd "$TEST_REPO"
  [ -s "$(qdir)/pending" ]
  run cat "$(qdir)/pending"
  [[ "$output" == *"w.ts"* ]]
}
