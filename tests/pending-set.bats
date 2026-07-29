#!/usr/bin/env bats

load helper

setup() { setup_repo; seed_repo; }
teardown() { teardown_repo; }

@test "기본 커밋: 스테이징된 것만, unstaged 는 제외" {
  printf 'A2\n' > a.ts          # unstaged 수정
  printf 'C1\n' > c.ts
  git add c.ts
  run pending 'git commit -m "x"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"$(git hash-object c.ts)"$'\t'"c.ts"* ]]
  [[ "$output" != *"a.ts"* ]]
}

@test "삭제된 파일은 NULL_SHA 로 나온다" {
  git rm -q old.ts
  run pending 'git commit -m "x"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"$NULL_SHA"$'\t'"old.ts"* ]]
}

@test "-am 은 추적 파일의 워크트리 내용을 포함한다" {
  printf 'A2\n' > a.ts
  run pending 'git commit -am "x"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"$(git hash-object a.ts)"$'\t'"a.ts"* ]]
}

@test "짧은 옵션 묶음(-va)에서도 -a 를 인식한다" {
  printf 'A2\n' > a.ts
  run pending 'git commit -va -m "x"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"a.ts"* ]]
}

@test "pathspec 지정 시 해당 경로만" {
  printf 'A2\n' > a.ts
  printf 'B2\n' > b.ts
  run pending 'git commit -m "x" -- a.ts'
  [ "$status" -eq 0 ]
  [[ "$output" == *"a.ts"* ]]
  [[ "$output" != *"b.ts"* ]]
}

@test "amend 메시지만 수정하면 빈 출력" {
  run pending 'git commit --amend -m "new"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "amend 로 내용을 얹으면 그 델타만" {
  printf 'A2\n' > a.ts
  git add a.ts
  run pending 'git commit --amend --no-edit'
  [ "$status" -eq 0 ]
  [[ "$output" == *"$(git hash-object a.ts)"$'\t'"a.ts"* ]]
}

@test "git 레포가 아니면 종료코드 2" {
  cd "$(mktemp -d)" || return 1
  run pending 'git commit -m "x"'
  [ "$status" -eq 2 ]
}

@test "머지 진행 중이면 종료코드 2" {
  git checkout -qb feat
  printf 'feat\n' > a.ts
  git commit -qam feat
  git checkout -q -
  printf 'main\n' > a.ts
  git commit -qam main
  git merge feat >/dev/null 2>&1 || true
  run pending 'git commit -m merge'
  [ "$status" -eq 2 ]
}

@test "cherry-pick 진행 중이면 종료코드 2" {
  git checkout -qb feat
  printf 'feat\n' > a.ts
  git commit -qam feat
  git checkout -q -
  printf 'main\n' > a.ts
  git commit -qam main
  git cherry-pick feat >/dev/null 2>&1 || true
  run pending 'git commit -m pick'
  [ "$status" -eq 2 ]
}

@test "rebase(merge 백엔드) 충돌 진행 중이면 종료코드 2" {
  git checkout -qb feat
  printf 'feat\n' > a.ts
  git commit -qam feat
  git checkout -q -
  printf 'main\n' > a.ts
  git commit -qam main
  git rebase feat >/dev/null 2>&1 || true
  [ -d "$(git rev-parse --git-dir)/rebase-merge" ]
  run pending 'git commit -m "x"'
  [ "$status" -eq 2 ]
}

@test "rebase(apply 백엔드) 충돌 진행 중이면 종료코드 2" {
  git checkout -qb feat
  printf 'feat\n' > a.ts
  git commit -qam feat
  git checkout -q -
  printf 'main\n' > a.ts
  git commit -qam main
  git rebase --apply feat >/dev/null 2>&1 || true
  [ -d "$(git rev-parse --git-dir)/rebase-apply" ]
  run pending 'git commit -m "x"'
  [ "$status" -eq 2 ]
}

@test "revert --no-commit 진행 중이면 종료코드 2" {
  printf 'A2\n' > a.ts
  git commit -qam second
  git revert --no-commit HEAD >/dev/null 2>&1 || true
  [ -e "$(git rev-parse --git-dir)/REVERT_HEAD" ]
  run pending 'git commit -m "x"'
  [ "$status" -eq 2 ]
}

@test "SHA 는 항상 40자리다" {
  printf 'C1\n' > c.ts
  git add c.ts
  run pending 'git commit -m "x"'
  sha="${output%%$'\t'*}"
  [ "${#sha}" -eq 40 ]
}
