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
#
# D47 이후 범위 계산은 stdin 의 remote sha 필드를 보지 않고, 로컬이 이미
# 아는 리모트 추적 ref(--remotes)만 본다. 실제 git 에서는 그 ref 가
# remote_sha 와 보통 일치한다(직전 fetch/push 로 생긴다) — 하지만 이 헬퍼는
# 훅을 stdin 계약으로 직접 태우므로 그런 ref 가 저절로 생기지 않는다. "이미
# 리모트에 있다"는 낡은 테스트들의 의도를 살리려면 여기서 흉내내야 한다.
#
# 진짜 origin 추적 ref(refs/remotes/origin/*)는 건드리지 않는다 —
# setup_origin 을 쓰는 테스트는 실제 fetch 로 그 ref 를 정확히 채워 두므로
# 덮어쓰면 오히려 틀린다. 대신 남는 이름 공간을 하나 새로 만든다 — --remotes
# 는 refs/remotes/ 아래 어떤 이름이든 다 본다.
run_push_hook() {  # $1 = remote sha, $2 = local sha
  # 매 호출마다 지우고 나서(필요하면) 다시 만든다 — 안 지우면 한 테스트
  # 안에서 두 번째 호출이 첫 번째 호출의 제외를 그대로 물려받는다.
  git update-ref -d refs/remotes/_run_push_hook_sim/remote 2>/dev/null
  if commit_sha="$(git rev-parse -q --verify "$1^{commit}" 2>/dev/null)"; then
    git update-ref refs/remotes/_run_push_hook_sim/remote "$commit_sha" 2>/dev/null
  fi
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

# ── rev-list 실패는 fail-closed 다 (Critical 2) ──

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

# ── D47: 게이트가 볼 수 있었던 적 없는 커밋은 검사하지 않는다 ──
#
# 로컬 bare 저장소를 origin 으로 쓴다. 리모트를 건드리는 명령은 origin 이
# 로컬 경로일 때만 허용한다는 격리 규칙을 지킨다.

setup_origin() {   # bare origin 을 만들고 현재 HEAD 를 main 으로 올린다
  # setup() 의 seed_repo 커밋은 install_push_hook(게이트 설치를 흉내낸다)보다
  # 먼저 만들어진다 — 실제 install.sh 라면 이 시점의 HEAD 를 epoch 으로
  # 적었을 것이다(Task 1). 여기서 epoch 을 안 적으면 아래 첫 push 가 seed
  # 커밋(a.ts/b.ts/old.ts, 미검증) 자체를 새 브랜치 범위로 보고 막아 버려서,
  # 이 헬퍼를 쓰는 테스트들이 검증하려는 것(리모트/기준점 도달성)과 무관한
  # 이유로 setup 단계에서부터 실패한다.
  mkdir -p "$(qdir)"
  git rev-parse HEAD > "$(qdir)/epoch"
  ORIGIN="$(mktemp -d)/origin.git"
  git init -q --bare "$ORIGIN"
  git remote add origin "$ORIGIN"
  git push -q origin HEAD:refs/heads/main
  git fetch -q origin
  # epoch 은 이 함수 안의 push 를 성공시키려고만 잠깐 필요했다(주석 참고).
  # 남겨 두면 "리모트 기준으로 만든 새 브랜치의 기준점 커밋은 검사에서
  # 빠진다" 가 --remotes 가 아니라 epoch 만으로도 통과해 --remotes 제외
  # 자체를 검증하지 못하는 채로 초록이 된다(실측 확인) — 그래서 여기서
  # 지운다.
  rm -f "$(qdir)/epoch"
}

@test "pull 로 들어온 남의 커밋은 검사에서 빠진다" {
  install_push_hook
  setup_origin
  # 동료가 origin/main 에 커밋을 올린다
  other="$(mktemp -d)"
  git clone -q "$ORIGIN" "$other"
  git -C "$other" config user.email o@e.com
  git -C "$other" config user.name o
  git -C "$other" config commit.gpgsign false
  printf 'COLLEAGUE\n' > "$other/colleague.ts"
  git -C "$other" add colleague.ts
  git -C "$other" commit -qm "colleague work"
  git -C "$other" push -q origin HEAD:refs/heads/main
  # 나는 feature 를 올려 두고 그 위로 main 을 pull 해 온다
  git checkout -qb feat
  printf 'MINE\n' > mine.ts; git add mine.ts
  stub_covered_line mine.ts
  commit_as_human -qm "my agent work"
  git push -q origin feat
  git fetch -q origin
  base="$(git rev-parse origin/feat)"
  git pull -q --no-rebase origin main
  run run_push_hook "$base" "$(git rev-parse HEAD)"
  [ "$status" -eq 0 ]
  [[ "$output" != *"colleague.ts"* ]]
}

@test "리모트 기준으로 만든 새 브랜치의 기준점 커밋은 검사에서 빠진다" {
  install_push_hook
  setup_origin
  git checkout -qb topic origin/main
  printf 'MINE\n' > mine.ts; git add mine.ts
  stub_covered_line mine.ts
  commit_as_human -qm "my agent work"
  run run_push_hook "$NULL_SHA" "$(git rev-parse HEAD)"
  [ "$status" -eq 0 ]
}

@test "리모트가 없어도 epoch 이 초기 커밋을 빼 준다" {
  install_push_hook
  # 게이트 설치 시점을 흉내낸다 — seed_repo 의 초기 커밋이 epoch 이다
  mkdir -p "$(qdir)"
  git rev-parse HEAD > "$(qdir)/epoch"
  base="$(git rev-parse HEAD)"
  printf 'MINE\n' > mine.ts; git add mine.ts
  stub_covered_line mine.ts
  commit_as_human -qm "my agent work"
  run run_push_hook "$NULL_SHA" "$(git rev-parse HEAD)"
  [ "$status" -eq 0 ]
  [[ "$output" != *"a.ts"* ]]
  # 대조군: epoch 을 치우면 초기 커밋이 다시 검사 대상이 된다
  rm -f "$(qdir)/epoch"
  run run_push_hook "$NULL_SHA" "$(git rev-parse HEAD)"
  [ "$status" -ne 0 ]
  [[ "$output" == *"a.ts"* ]]
}

@test "epoch 의 사라진 객체가 push 를 막지 못한다" {
  install_push_hook
  mkdir -p "$(qdir)"
  {
    git rev-parse HEAD
    printf 'deadbeef\n' | git hash-object --stdin   # 저장소에 없는 객체
  } > "$(qdir)/epoch"
  base="$(git rev-parse HEAD)"
  printf 'MINE\n' > mine.ts; git add mine.ts
  stub_covered_line mine.ts
  commit_as_human -qm "my agent work"
  run run_push_hook "$NULL_SHA" "$(git rev-parse HEAD)"
  # 죽은 줄 하나가 rev-list 를 128 로 죽이면 fail-closed 가 모든 push 를
  # 어떤 퀴즈로도 못 푸는 채로 영구 차단한다 (D00/D42 가 금지하는 모양)
  [ "$status" -eq 0 ]
  # 조용히 버리지 않고 경고했는지 직접 확인한다 — "16진수" 가 아니라
  # "사라진 객체" 로 특정해, 아래 16진수 테스트와 서로의 메시지로
  # 통과하지 못하게 한다.
  [[ "$output" == *"사라진 객체"* ]]
}

@test "epoch 의 모호한(ambiguous) 축약 16진수 줄이 push 를 막지 못한다" {
  # cat-file --batch-check 는 없는 객체만 "missing" 으로 답하지 않는다 —
  # 짧게 줄인 16진수가 객체 두 개 이상과 동시에 맞으면 "ambiguous" 를 낸다
  # (실측). 예전 필터($2 != "missing")는 이 줄을 그대로 통과시켜, 존재하지
  # 않는 객체 이름 대신 입력값(모호한 접두어) 그대로가 epoch_args 에
  # 실렸다 — 그 값이 그대로 `git rev-list --not` 인자로 가면 rev-list 가
  # 128 로 죽고, 이 훅의 fail-closed 경로가 그 순간 이 저장소의 모든 push
  # 를 어떤 퀴즈로도 못 푸는 채로 영구 차단한다(위 "사라진 객체" 테스트와
  # 달리 --no-verify 말고는 빠져나갈 길이 없는 unparseable 범주로 간다).
  # 4-hex 접두어 충돌이 필요하다 — git 은 4자 미만의 접두어는 실제 존재
  # 여부와 무관하게 그냥 "missing" 으로 답해(모호함 판정 자체를 안 한다)
  # ambiguous 를 재현하지 못한다.
  install_push_hook

  # 4-hex 접두어가 겹치는 블롭 두 개를 찾는다. 내용을 "collide-<i>" 로
  # 고정해 두면 실행마다 완전히 같은 시퀀스를 해시하므로 이 충돌은 사실
  # 결정적이다(무작위가 아니다) — 그래도 상한을 두고 못 찾으면 skip 하는
  # 것은, 흔들리는 테스트를 결함으로 보는 이 프로젝트의 원칙(helper.bash
  # 의 with_tty 주석 참고)을 그대로 지키기 위해서다. 블롭 하나마다 git
  # 프로세스를 새로 fork 하면(hash-object --stdin) 수백 번의 프로세스
  # 생성 비용이 쌓이므로, --stdin-paths 로 한 번의 git 호출에 여러 개를
  # 묶어 만든다.
  batch_dir="$(mktemp -d)"
  declare -A seen_prefix
  collide_prefix=""
  i=0
  cap=5000
  batch_size=500
  while [ -z "$collide_prefix" ] && [ "$i" -lt "$cap" ]; do
    filelist="$batch_dir/list.txt"
    : > "$filelist"
    end=$((i + batch_size))
    [ "$end" -gt "$cap" ] && end="$cap"
    j=$i
    while [ "$j" -lt "$end" ]; do
      f="$batch_dir/f$j"
      printf 'collide-%d\n' "$j" > "$f"
      printf '%s\n' "$f" >> "$filelist"
      j=$((j + 1))
    done
    shas="$(git hash-object -w --stdin-paths < "$filelist")"
    for sha in $shas; do
      prefix="${sha:0:4}"
      if [ -n "${seen_prefix[$prefix]:-}" ]; then
        collide_prefix="$prefix"
        break
      fi
      seen_prefix[$prefix]=1
    done
    i="$end"
  done
  rm -rf "$batch_dir"
  [ -n "$collide_prefix" ] || skip "4-hex 접두어 충돌을 $cap 회 안에 못 찾음"

  mkdir -p "$(qdir)"
  {
    git rev-parse HEAD
    printf '%s\n' "$collide_prefix"
  } > "$(qdir)/epoch"

  printf 'MINE\n' > mine.ts; git add mine.ts
  stub_covered_line mine.ts
  commit_as_human -qm "my agent work"
  run run_push_hook "$NULL_SHA" "$(git rev-parse HEAD)"
  # ambiguous 줄이 그대로 rev-list --not 인자로 새면 rev-list 가 128 로
  # 죽어 이 훅의 fail-closed 경로가 이 push 를 영구히 막는다.
  [ "$status" -eq 0 ]
  # 조용히 버리지 않고 경고했는지 확인한다 — 필터가 "사라진 객체" 와 같은
  # 문구를 쓰는 것은 의도한 그대로다(위 테스트와 코드 경로를 공유한다).
  [[ "$output" == *"사라진 객체"* ]]
  [[ "$output" == *"$collide_prefix"* ]]
}

@test "epoch 의 16진수 아닌 줄은 rev-list 인자로 새지 않는다" {
  # "--all" 만으로는 이 테스트가 16진수 검사를 실제로 지키지 못한다(실측,
  # 코디네이터 지적) — `git cat-file -e "--all"` 은 대시로 시작하는 값을 git
  # 자신의 옵션 파서가 먼저 잡아 rc=129 로 실패하므로, 16진수 검사를 지워도
  # 그 줄은 어차피 "사라진 객체" 취급으로 걸러진다(즉 이 값 하나로는 16진수
  # 검사 자체의 회귀를 못 잡는다).
  #
  # `cat-file -e` 가 실제로 못 잡는 건 대시로 시작하지 않는 **ref 이름**이다.
  # `HEAD` 는 16진수는 아니지만 언제나 존재하는 유효한 리비전이라
  # `cat-file -e HEAD` 는 rc=0 으로 통과한다(실측: cat-file -e HEAD/main/
  # refs/heads/main 전부 rc=0). 16진수 검사가 없으면 `HEAD` 가 그대로
  # epoch_args 에 실려 `rev-list local_sha --not --remotes HEAD` 가 되는데,
  # 이 훅이 도는 시점의 HEAD 는 지금 막 만든(미검증) 커밋 자신이므로 `--not
  # HEAD` 가 local_sha 를 통째로 지워 버린다(실측: rev-list HEAD --not
  # --remotes HEAD → 0 커밋). 결과적으로 검사 대상이 하나도 안 남아 훅이
  # 조용히 통과한다 — 이 프로젝트가 계속 막아 온 "게이트가 조용히 꺼지는"
  # 바로 그 모양이다. 16진수 검사가 이 시나리오의 유일한 방어선이다.
  install_push_hook
  mkdir -p "$(qdir)"
  {
    git rev-parse HEAD
    printf -- '--all\n'
    printf 'HEAD\n'
  } > "$(qdir)/epoch"
  printf 'EVIL\n' > evil.ts; git add evil.ts
  commit_as_human -qm "unverified"
  run run_push_hook "$NULL_SHA" "$(git rev-parse HEAD)"
  # HEAD 가 인자로 새면 범위 자체가 사라져 미검증 내용을 건너뛴다
  [ "$status" -ne 0 ]
  [[ "$output" == *"evil.ts"* ]]
  # "--all"·"HEAD" 둘 다 조용히 버리지 않고 경고했는지 확인한다 — "사라진
  # 객체" 가 아니라 "16진수" 로 특정해, 위 사라진 객체 테스트와 서로의
  # 메시지로 통과하지 못하게 한다.
  [[ "$output" == *"16진수"* ]]
}

@test "epoch 을 읽을 수 없으면 막고 --no-verify 를 안내한다" {
  install_push_hook
  mkdir -p "$(qdir)"
  git rev-parse HEAD > "$(qdir)/epoch"
  chmod 000 "$(qdir)/epoch"
  base="$(git rev-parse HEAD)"
  run run_push_hook "$base" "$base"
  chmod 644 "$(qdir)/epoch"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--no-verify"* ]]
}

@test "remote_sha 가 무엇이든 범위 계산에 영향을 주지 않는다" {
  # remote_sha 는 더 이상 쓰이지 않는다. 예전에는 이 값이 이상하면 거부했다.
  install_push_hook
  printf 'MINE\n' > mine.ts; git add mine.ts
  stub_covered_line mine.ts
  mkdir -p "$(qdir)"
  git rev-parse HEAD > "$(qdir)/epoch"
  commit_as_human -qm "covered work"
  head="$(git rev-parse HEAD)"
  run run_push_hook "--upload-pack=x" "$head"
  [ "$status" -eq 0 ]
  run run_push_hook "$NULL_SHA" "$head"
  [ "$status" -eq 0 ]
}

@test "local sha 를 로컬이 모르면 여전히 fail-closed 다" {
  # Critical 2 의 성질은 그대로 지킨다 — 범위를 하나도 못 본 것과 정말
  # 아무것도 없는 것은 다르다. remote_sha 로는 더 이상 재현되지 않으므로
  # local_sha 로 재현한다.
  install_push_hook
  unknown="$(printf 'nope' | git hash-object --stdin)"
  run run_push_hook "$NULL_SHA" "$unknown"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--no-verify"* ]]
}
