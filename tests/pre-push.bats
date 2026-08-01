#!/usr/bin/env bats
#
# pre-push 는 최종 경계다. Stop 훅은 사람이 Esc 로 빠져나갈 수 있으므로,
# 미검증 커밋이 남에게 넘어가는 것은 여기서 막는다.
#
# 여기서는 퀴즈를 내지 않는다 — push 는 보통 명령 하나이고 사람에게 묻는
# 채널이 없다. 거부하고 안내만 한다.

load helper

setup() { setup_repo; seed_repo; }
teardown() { teardown_repo; }

install_push_hook() {
  mkdir -p "$(hooksdir)"
  cp "$PLUGIN_ROOT/hooks/pre-push" "$(hooksdir)/pre-push"
  chmod +x "$(hooksdir)/pre-push"
}

# pre-push 훅을 git 없이 직접 태운다 (stdin 계약을 그대로 준다).
run_push_hook() {  # $1 = remote sha, $2 = local sha
  printf 'refs/heads/main %s refs/heads/main %s\n' "$2" "$1" \
    | "$(hooksdir)/pre-push" origin https://example.invalid/r.git
}

@test "미검증 커밋이 없으면 통과한다" {
  install_push_hook
  base="$(git rev-parse HEAD)"
  run run_push_hook "$base" "$base"
  [ "$status" -eq 0 ]
}

@test "미검증 커밋이 섞이면 거부한다" {
  install_push_hook
  base="$(git rev-parse HEAD)"
  printf 'C1\n' > c.ts; git add c.ts
  commit_as_human -qm "unverified"
  run run_push_hook "$base" "$(git rev-parse HEAD)"
  [ "$status" -ne 0 ]
  [[ "$output" == *"c.ts"* ]]
}

@test "검증된 커밋만 있으면 통과한다" {
  install_push_hook
  base="$(git rev-parse HEAD)"
  printf 'C1\n' > c.ts; git add c.ts
  stub_covered_line c.ts
  commit_as_human -qm "verified"
  run run_push_hook "$base" "$(git rev-parse HEAD)"
  [ "$status" -eq 0 ]
}

@test "새 브랜치(remote sha 가 0)에서도 범위를 잡는다" {
  install_push_hook
  printf 'C1\n' > c.ts; git add c.ts
  commit_as_human -qm "unverified"
  run run_push_hook "$NULL_SHA" "$(git rev-parse HEAD)"
  [ "$status" -ne 0 ]
}

@test "브랜치 삭제(local sha 가 0)는 통과한다" {
  install_push_hook
  run run_push_hook "$(git rev-parse HEAD)" "$NULL_SHA"
  [ "$status" -eq 0 ]
}

@test "미검증 판정에 jq 를 쓰지 않는다" {
  # 원안의 grep -c 'jq' 는 주석까지 센다 — 이 훅의 헤더 주석은 "왜 jq 를
  # 쓰지 않는가"를 설명하려고 정확히 그 단어를 두 번 쓰므로, 원안 그대로는
  # 자기 자신의 참조 구현에도 실패한다. 여기서 검증하려는 성질은 "jq 라는
  # 글자가 파일에 없다"가 아니라 "jq 를 명령으로 실행하지 않는다"이므로,
  # 주석 줄(# 로 시작)을 걷어내고 남은 코드에서만 센다.
  install_push_hook
  run bash -c "grep -v '^[[:space:]]*#' '$(hooksdir)/pre-push' | grep -c 'jq'"
  [ "$output" = "0" ]
}

# ── sha 형식 검증: git rev-list 인자 주입 방어 (리뷰 대응) ──
#
# local_sha/remote_sha 는 정상 경로에서는 항상 16진수이지만, 이 훅을 직접
# 태우는 경로(아래 run_push_hook 이 하는 바로 그것)에서는 무엇이든 올 수
# 있다. "-" 로 시작하는 값이 그대로 git rev-list 인자로 새면 옵션으로
# 오인될 수 있다.
#
# 두 경로의 실제 위험도가 다르다는 걸 직접 확인했다: `$remote_sha..$local_sha`
# (기존 브랜치) 형태는 한 토큰(".."으로 붙어 있다)이라, 안에 "--foo" 가
# 섞여도 git 이 "애매한 인자"로 거부하며 128 로 죽는다 — Critical 2 의
# fail-closed 가 이미 그 실패를 막아 주므로, 이 경로만 놓고 보면 sha 형식
# 가드를 지워도 관찰 가능한 차이가 없다(실측). 반면 새 브랜치 경로의
# `range="$local_sha --not --remotes"` 는 공백으로 분리된 여러 토큰이라,
# local_sha 가 "--all" 같은 **진짜 rev-list 옵션**이면 git 이 에러 없이
# 그대로 실행해 버린다 — 이게 진짜 구멍이다. 아래 테스트가 그 시나리오를
# 재현한다: 커버된 것은 현재 HEAD 뿐이고, 실제로 "새로 push 되려는" 내용
# (별 ref 에도 안 달린 커밋)은 미검증인데, local_sha 자리에 "--all" 을
# 넣으면 rev-list 가 "그 커밋"이 아니라 "이 저장소가 아는 모든 ref" 를
# 봐 버려서 진짜 미검증 내용을 건너뛰고 조용히 통과한다 — 가드를 지우면
# 이 테스트가 정확히 그 실패(STATUS=0)로 빨갛게 뜬다(실측 확인).

@test "local sha 자리에 rev-list 옵션을 넣어도 실제로 push 되는 미검증 내용을 건너뛰지 못한다" {
  install_push_hook
  # 현재 HEAD(seed_repo 가 만든 a.ts/b.ts/old.ts)는 전부 커버해 둔다 —
  # "--all" 이 보게 될 바로 그 범위를 깨끗하게 만들어, 통과가 가드
  # 때문인지 원래 내용이 깨끗해서인지 뒤섞이지 않게 한다.
  stub_covered_line a.ts
  stub_covered_line b.ts
  stub_covered_line old.ts
  # 실제로 push 되려는(어느 ref 에도 안 달린) 새 커밋 — 미검증 내용을
  # 담고 있다. 진짜 local_sha 였어야 할 값이다.
  git checkout -q --detach
  printf 'EVIL\n' > evil.ts; git add evil.ts
  commit_as_human -qm "dangling unverified commit"
  git checkout -q -
  run run_push_hook "$NULL_SHA" "--all"
  [ "$status" -ne 0 ]
}

@test "remote sha 형식이 이상하면 거부한다" {
  # 기존 브랜치 경로(`$remote_sha..$local_sha`)는 한 토큰이라 git 자신이
  # "애매한 인자"로 거부하므로(Critical 2 의 fail-closed 가 그 실패를
  # 막아 준다), 이 경로만으로는 sha 형식 가드 유무가 관찰 가능한 차이를
  # 만들지 않는다 — 그래도 방어 계층으로 남겨 둔다: rev-list 앞에서
  # 먼저 걸러 판정 사유를 "형식 오류"로 명확히 알려 준다(그렇게 검증한다).
  install_push_hook
  run run_push_hook "--upload-pack=x" "$(git rev-parse HEAD)"
  [ "$status" -ne 0 ]
}

# ── rev-list 실패는 fail-closed 다 (Critical 2) ──

@test "범위를 계산할 수 없으면(모르는 remote sha) 실제 커버리지와 무관하게 거부한다" {
  install_push_hook
  # c.ts 자체는 커버돼 있다 — 그래도 범위를 못 구하면 막아야 한다는 것이
  # 요점이다. rev-list 실패를 fail-open 하면 이 테스트가 우연히 초록이
  # 되므로, "커버됐지만 그래도 막힌다"를 확인해야 진짜 검증이 된다.
  unknown_sha="ffffffffffffffffffffffffffffffffffffff"
  printf 'C1\n' > c.ts; git add c.ts
  stub_covered_line c.ts
  commit_as_human -qm "verified"
  run run_push_hook "$unknown_sha" "$(git rev-parse HEAD)"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--no-verify"* ]]
}

# ── 경로에 개행이 있으면 fail-closed 하고 탈출구를 안내한다 (Important 3) ──

@test "경로에 개행이 있으면 거부하고 --no-verify 탈출구를 안내한다" {
  install_push_hook
  base="$(git rev-parse HEAD)"
  printf 'N\n' > "$(printf 'we\nird.ts')"
  printf 'Z\n' > zzz.ts
  git add -A
  commit_as_human -qm "weird path"
  run run_push_hook "$base" "$(git rev-parse HEAD)"
  [ "$status" -ne 0 ]
  # 어떤 퀴즈로도 이 상태를 풀 수 없으므로, 반드시 우회 방법을 알려줘야
  # 한다 — pending.sh 는 같은 스트림을 형식 오류로 거부하므로 covered.tsv
  # 를 채울 방법이 없다(D00/D42: 이해와 무관한 이유로 영구히 막히면 안 된다).
  [[ "$output" == *"--no-verify"* ]]
}

# ── 병합 커밋 (Critical 1) ──

@test "병합 커밋의 충돌 해소 내용이 미검증이면 거부한다" {
  # 두 가지(branchA·main) 원래 커밋의 내용은 미리 검증해 둔다 — 그래야
  # "여전히 거부됨"의 원인이 저 둘이 아니라 병합 커밋 자신이 새로 만든
  # 충돌 해소 내용(그 어느 parent 에도 없던 "A1\nX\nY")이라고 특정할 수
  # 있다. 그렇게 격리하지 않으면, --cc 를 지워 Critical 1 을 되살려도 이
  # 테스트는 (branchA·main 커밋 자체가 미검증이라는 무관한 이유로) 여전히
  # 초록으로 남아 회귀를 못 잡는다.
  install_push_hook
  base="$(git rev-parse HEAD)"
  main_branch="$(git symbolic-ref --short HEAD)"
  git checkout -qb branchA
  printf 'A1\nX\n' > a.ts; git add a.ts; stub_covered_line a.ts
  commit_as_human -qm "branchA change"
  git checkout -q "$main_branch"
  printf 'A1\nY\n' > a.ts; git add a.ts; stub_covered_line a.ts
  commit_as_human -qm "main change"
  # 충돌하는 병합이라 git merge 가 실패 종료하는 게 정상이다 — 이어서 직접
  # 해소하고 커밋한다. 이 마지막 내용만 커버하지 않는다.
  ! git merge --no-edit branchA -q >/dev/null 2>&1
  printf 'A1\nX\nY\n' > a.ts
  git add a.ts
  commit_as_human -qm "merge resolved"
  run run_push_hook "$base" "$(git rev-parse HEAD)"
  [ "$status" -ne 0 ]
  [[ "$output" == *"a.ts"* ]]
}

@test "병합 커밋도 검증되면 통과한다" {
  install_push_hook
  base="$(git rev-parse HEAD)"
  main_branch="$(git symbolic-ref --short HEAD)"
  git checkout -qb branchA
  printf 'A1\nX\n' > a.ts; git add a.ts; stub_covered_line a.ts
  commit_as_human -qm "branchA change"
  git checkout -q "$main_branch"
  printf 'A1\nY\n' > a.ts; git add a.ts; stub_covered_line a.ts
  commit_as_human -qm "main change"
  ! git merge --no-edit branchA -q >/dev/null 2>&1
  printf 'A1\nX\nY\n' > a.ts
  git add a.ts
  stub_covered_line a.ts
  commit_as_human -qm "merge resolved"
  run run_push_hook "$base" "$(git rev-parse HEAD)"
  [ "$status" -eq 0 ]
}

@test "자동 병합된(충돌 없는) 파일은 각자의 원래 커밋 검증만으로 충분하다" {
  # branchA·main 이 서로 다른 파일만 건드리면 병합은 충돌 없이 자동으로
  # 되고, 병합 결과의 두 파일 모두 어느 한쪽 parent 와 완전히 같다 — git
  # diff-tree --cc 는 그런("어느 parent 로도 설명되는") 파일을 아예 내지
  # 않는다. 두 원래 커밋만 커버해 두면 병합 커밋 자체가 뭔가를 더 요구하지
  # 않고 통과해야 한다. --cc 가 아니라 "병합이면 전부 다시 보자"는 식으로
  # 잘못 구현했다면, 이미 커버된 내용이 병합 시점에 다른 형태로 다시
  # 검사되며 엉뚱하게 막힐 수 있다 — 그 오탐을 잡는 테스트다.
  install_push_hook
  base="$(git rev-parse HEAD)"
  main_branch="$(git symbolic-ref --short HEAD)"
  git checkout -qb branchA
  printf 'B1\nX\n' > b.ts; git add b.ts; stub_covered_line b.ts
  commit_as_human -qm "branchA touches b.ts only"
  git checkout -q "$main_branch"
  printf 'A1\nY\n' > a.ts; git add a.ts; stub_covered_line a.ts
  commit_as_human -qm "main change, covered"
  git merge --no-edit branchA -q
  run run_push_hook "$base" "$(git rev-parse HEAD)"
  [ "$status" -eq 0 ]
}

# ── 체이닝 (Important 4 — 지금까지 테스트가 하나도 없었다) ──

@test "체이닝된 훅이 먼저 실행되고 거부하면 즉시 끝난다" {
  install_push_hook
  printf '#!/bin/sh\necho CHAINED_RAN >&2\nexit 7\n' > "$(hooksdir)/pre-push.kkochikkochi-chained"
  chmod +x "$(hooksdir)/pre-push.kkochikkochi-chained"
  base="$(git rev-parse HEAD)"
  run run_push_hook "$base" "$base"
  [ "$status" -eq 7 ]
  [[ "$output" == *"CHAINED_RAN"* ]]
  [[ "$output" != *"KkochiKkochi"* ]]
}

@test "체이닝된 훅이 통과하면 우리 판정으로 넘어간다" {
  install_push_hook
  printf '#!/bin/sh\nexit 0\n' > "$(hooksdir)/pre-push.kkochikkochi-chained"
  chmod +x "$(hooksdir)/pre-push.kkochikkochi-chained"
  base="$(git rev-parse HEAD)"
  printf 'C1\n' > c.ts; git add c.ts
  commit_as_human -qm "unverified"
  run run_push_hook "$base" "$(git rev-parse HEAD)"
  [ "$status" -ne 0 ]
  [[ "$output" == *"c.ts"* ]]
}

@test "체이닝 파일이 우리 자신의 훅 사본이면 재귀를 막기 위해 실행하지 않는다" {
  install_push_hook
  printf '#!/bin/sh\necho CHAINED_RAN >&2\n# KKOCHIKKOCHI-HOOK-v1\nexit 7\n' \
    > "$(hooksdir)/pre-push.kkochikkochi-chained"
  chmod +x "$(hooksdir)/pre-push.kkochikkochi-chained"
  base="$(git rev-parse HEAD)"
  run run_push_hook "$base" "$base"
  [ "$status" -ne 7 ]
  [[ "$output" != *"CHAINED_RAN"* ]]
  [ "$status" -eq 0 ]
}

# ── SHA-256 저장소 (Critical 2) ──
#
# 표준 setup()/teardown() 은 sha1 저장소 하나(TEST_REPO)를 전제하므로,
# object-format 이 다른 저장소는 이 테스트 안에서 따로 만들고 따로 치운다.
# 이 git 이 --object-format=sha256 을 못 만들면(오래된 빌드) 스스로 건너뛴다.

@test "SHA-256 저장소에서 새 브랜치 첫 push 가 null sha 오판으로 막히지 않는다" {
  # 여기서 검증하려는 건 "새 브랜치(원격 sha 가 전부 0)" 판별이 sha1 의
  # 40자리를 가정하지 않고 sha256 의 64자리 0 에서도 맞게 동작하는가다 —
  # 내용 커버리지 자체는 다른 테스트가 이미 본다. 그래서 a.txt 를 미리
  # 커버해 둔다: 안 그러면 이 push 는(정당하게) 미검증 내용 때문에
  # 막히고, 그 실패가 null sha 오판 때문인지 그냥 미검증 때문인지 가려지지
  # 않는다.
  #
  # stub_covered_line(tests/helper.bash) 은 못 쓴다 — 그건 `git hash-object`
  # 의 원문 길이(sha256 이면 64자리)를 그대로 쓰는데, 실제 파이프라인
  # (hooks/pre-commit → record-pass.sh)이 covered.tsv 에 적는 값은 항상
  # `--abbrev=40` 을 거친 40자리 접두어다(실측: 두 값이 앞 40자리까지는
  # 같지만 그 뒤가 다르다). sha1 저장소에서는 40=원문 길이라 이 차이가
  # 안 보였을 뿐이다. 그래서 여기서는 실제 훅과 같은 방식으로 40자리
  # 접두어를 직접 만들어 covered.tsv 에 적는다.
  s256="$(mktemp -d)"
  if ! git init -q --object-format=sha256 --bare "$s256/remote.git" >/dev/null 2>&1; then
    rm -rf "$s256"
    skip "이 git 은 --object-format=sha256 을 지원하지 않는다"
  fi
  git init -q --object-format=sha256 "$s256/repo" >/dev/null
  cd "$s256/repo" || return 1
  git config user.email t@e.com; git config user.name t; git config commit.gpgsign false
  git remote add origin "$s256/remote.git"
  printf 'A\n' > a.txt; git add a.txt
  abbr_sha="$(git hash-object -- a.txt | cut -c1-40)"
  mkdir -p .git/quiz-gate
  printf '%s\ta.txt\tp-stub\n' "$abbr_sha" > .git/quiz-gate/covered.tsv
  git commit -qm init
  mkdir -p .git/hooks
  cp "$PLUGIN_ROOT/hooks/pre-push" .git/hooks/pre-push
  chmod +x .git/hooks/pre-push
  run git push origin HEAD:refs/heads/main
  [ "$status" -eq 0 ]
  rm -rf "$s256"
}

@test "SHA-256 저장소에서도 미검증 내용은 여전히 막힌다" {
  s256="$(mktemp -d)"
  if ! git init -q --object-format=sha256 --bare "$s256/remote.git" >/dev/null 2>&1; then
    rm -rf "$s256"
    skip "이 git 은 --object-format=sha256 을 지원하지 않는다"
  fi
  git init -q --object-format=sha256 "$s256/repo" >/dev/null
  cd "$s256/repo" || return 1
  git config user.email t@e.com; git config user.name t; git config commit.gpgsign false
  git remote add origin "$s256/remote.git"
  printf 'A\n' > a.txt; git add a.txt
  mkdir -p .git/hooks
  cp "$PLUGIN_ROOT/hooks/pre-push" .git/hooks/pre-push
  chmod +x .git/hooks/pre-push
  env -u CLAUDECODE -u CLAUDE_CODE_SESSION_ID git commit -qm init
  run git push origin HEAD:refs/heads/main
  [ "$status" -ne 0 ]
  [[ "$output" == *"a.txt"* ]]
  rm -rf "$s256"
}
