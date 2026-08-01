# push 검사 범위 축소 + Codex 트리거 매핑 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `pre-push` 가 사용자가 에이전트로 작업한 코드만 검사하도록 범위를 좁히고, Codex 서브에이전트 층을 사실에 맞는 이벤트에 배선한다.

**Architecture:** `pre-push` 의 범위 계산에서 `remote_sha` 를 버리고 `$local_sha --not --remotes $epoch_args` 한 규칙으로 통일한다. `epoch` 은 게이트 설치 시점의 ref 팁 목록으로, `scripts/install.sh` 만 쓰고 `hooks/pre-push` 만 읽는 단방향 파일이다. Codex 쪽은 매니페스트에 훅 4종을 추가하되 서브에이전트 생성 도구 이름이 `Task` 가 아니라 `spawn_agent` 임을 반영한다.

**Tech Stack:** POSIX `sh`(`hooks/` 아래), `bash`(`scripts/` 아래), `git`, `jq`, `bats`

**설계 문서:** `docs/superpowers/specs/2026-08-01-push-scope-and-codex-design.md`

## Global Constraints

- **이 저장소의 게이트는 현재 꺼져 있다(사용자 의도). 되살리지 않는다.** `scripts/install.sh install` 을 이 저장소에서 실행하지 말 것
- **git 을 변형하는 명령은 scratchpad 아래에서만 실행한다.** 모든 git 명령에 `-C <절대경로>` 를 붙이고 `cd` 에 의존하지 않는다 (`progress.md:181` 의 2026-08-01 사고 — `cd` 실패가 감지되지 않아 실제 `main` 이 오염됐다)
- **이 저장소에서 `push`·`checkout`·`reset`·`branch` 를 절대 실행하지 않는다.** 각 태스크 끝의 `git commit` 만 허용한다
- **리모트를 건드리는 명령은 `origin` 이 로컬 경로일 때만 허용한다**
- 현재 `bats tests/` 는 **203개 전부 초록**이다. 회귀를 만들지 않는다
- `hooks/` 아래는 POSIX `sh` 다. `[[ ]]`·배열·`local` 을 쓰지 않는다. `scripts/` 아래는 `bash` 다
- **`hooks/pre-push` 는 `jq` 를 실행하지 않는다.** `tests/pre-push.bats:67` 이 주석을 걷어낸 코드에서 `jq` 를 세어 0인지 확인한다
- 한글은 리터럴 문자로 쓴다. `\uXXXX` 이스케이프 금지
- 훅 파일을 고치면 `KKOCHIKKOCHI-HOOK-v1` 마커 줄을 지우지 않는다. 설치기가 그 문자열로 소유권을 판별한다
- 되돌려도 통과하는 테스트를 만들지 않는다. 각 새 테스트는 해당 코드를 지웠을 때 실제로 빨개지는지 확인한 뒤 넣는다 (`progress.md:131`)

---

## 파일 구조

| 파일 | 책임 | 이번에 |
|---|---|---|
| `scripts/install.sh` | 훅 설치/제거/상태 + **epoch 쓰기** | 수정 |
| `hooks/pre-push` | push 범위 판정 + **epoch 읽기** | 수정 |
| `hooks.json` (루트) | Codex 매니페스트 | 수정 |
| `tests/install.bats` | 설치기 계약 | 수정 |
| `tests/pre-push.bats` | push 경계 계약 | 수정 |
| `tests/manifests.bats` | 매니페스트 `command` 실행 계약 | 수정 |
| `README.md` / `docs/DECISIONS.md` / `CHANGELOG.md` | 사용자용 문서 | 수정 |

`epoch` 은 새 스크립트를 만들지 않는다 — 쓰는 곳과 읽는 곳이 하나씩뿐이라 중간 계층이 값을 더하지 못한다.

---

### Task 1: `install.sh` 가 epoch 을 쓰고, `uninstall` 이 상태를 지운다

**Files:**
- Modify: `scripts/install.sh` (상단 상수, `cmd_install`, `cmd_uninstall`)
- Test: `tests/install.bats`

**Interfaces:**
- Consumes: 없음 (첫 태스크)
- Produces:
  - `$(git rev-parse --git-common-dir)/quiz-gate/epoch` — 한 줄에 sha 하나, 정렬·중복 제거됨. **파일이 없을 때만** 쓰인다. 빈 파일일 수 있다(ref 가 없는 저장소)
  - `install.sh uninstall` 이 `quiz-gate` 디렉터리를 통째로 지우고 stderr 에 한 줄 알린다
  - Task 2 의 `hooks/pre-push` 가 이 파일을 읽는다

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`tests/install.bats` 맨 끝에 추가한다.

```bash
# ── epoch — 게이트가 볼 수 있었던 적 없는 이력의 경계 (D47) ──

@test "install 이 epoch 에 그 시점의 ref 팁을 적는다" {
  inst install
  [ -f "$(qdir)/epoch" ]
  run cat "$(qdir)/epoch"
  [[ "$output" == *"$(git rev-parse HEAD)"* ]]
}

@test "재설치는 epoch 을 덮어쓰지 않는다" {
  inst install
  first="$(cat "$(qdir)/epoch")"
  printf 'C1\n' > c.ts; git add c.ts; commit_as_human -qm "after install"
  # 대조군: HEAD 가 실제로 움직였다 — 안 그러면 아래 비교가 공허하다
  [ "$(git rev-parse HEAD)" != "$first" ]
  inst install
  [ "$(cat "$(qdir)/epoch")" = "$first" ]
}

@test "uninstall 후 install 은 epoch 을 새로 쓴다" {
  inst install
  first="$(cat "$(qdir)/epoch")"
  printf 'C1\n' > c.ts; git add c.ts; commit_as_human -qm "after install"
  inst uninstall
  inst install
  [ "$(cat "$(qdir)/epoch")" != "$first" ]
  run cat "$(qdir)/epoch"
  [[ "$output" == *"$(git rev-parse HEAD)"* ]]
}

@test "uninstall 이 quiz-gate 를 통째로 지우고 알린다" {
  inst install
  mkdir -p "$(qdir)/passes"
  printf '{}\n' > "$(qdir)/passes/p-stub.json"
  stub_covered_line a.ts
  # 대조군: 지우기 전에 실제로 있었다
  [ -f "$(qdir)/covered.tsv" ]
  run inst uninstall
  [ "$status" -eq 0 ]
  [ ! -d "$(qdir)" ]
  [[ "$output" == *"quiz-gate"* ]]
}

@test "ref 가 하나도 없는 저장소에서도 install 이 죽지 않는다" {
  empty="$(mktemp -d)"
  git -C "$empty" init -q .
  git -C "$empty" config user.email t@e.com
  git -C "$empty" config user.name t
  run env -C "$empty" bash "$PLUGIN_ROOT/scripts/install.sh" install
  [ "$status" -eq 0 ]
  [ -f "$empty/.git/quiz-gate/epoch" ]
  [ ! -s "$empty/.git/quiz-gate/epoch" ]
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `bats tests/install.bats`
Expected: 위 5개가 FAIL. `epoch` 파일이 없어서 `[ -f ... ]` 가 깨지고, `uninstall` 테스트는 `[ ! -d "$(qdir)" ]` 에서 깨진다.

> `env -C` 를 지원하지 않는 오래된 coreutils 라면 마지막 테스트가 다른 이유로 실패한다. 그때는 `run bash -c 'cd "$1" && bash "$2" install' _ "$empty" "$PLUGIN_ROOT/scripts/install.sh"` 로 바꾼다.

- [ ] **Step 3: `install.sh` 상단에 경로 상수와 epoch writer 를 더한다**

`HOOKS_DIR` 정의(현재 `:30`) 바로 아래에 넣는다.

```bash
HOOKS_DIR="$(git rev-parse --git-path hooks)"
QDIR="$(git rev-parse --git-common-dir)/quiz-gate"
EPOCH="$QDIR/epoch"

# epoch — 게이트가 이 저장소에 설치될 때 **이미 존재하던 모든 ref 팁**.
# hooks/pre-push 가 이것을 읽어, 그보다 앞선 이력을 검사 대상에서 뺀다 (D47).
#
# **파일이 없을 때만 쓴다.** install 은 "처음 설치"만 뜻하지 않는다 — 훅이
# 낡으면 scripts/stamp-agent.sh 의 건강검진이 커밋을 거부하며 에이전트에게
# 이 명령을 시키므로, 플러그인이 업데이트될 때마다 모든 사용자의 저장소에서
# install 이 다시 돈다. 거기서 epoch 을 갱신하면 사용자는 "업데이트했을
# 뿐"인데 그때까지 쌓인 미검증 커밋이 전부 면제된다 — 이 프로젝트가 내내
# 싸워온 "게이트가 조용히 꺼지는 것"의 새로운 모양이다.
#
# uninstall 이 quiz-gate 를 통째로 지우므로, "다시 시작"은 그 경로로만
# 일어난다. 규칙이 하나라서 최초 설치·갱신·구버전 업그레이드가 전부 맞는다.
#
# 실패해도 설치를 막지 않는다. epoch 이 없으면 pre-push 는 예전처럼(제외
# 없이) 동작할 뿐이고, 그것은 회귀가 아니라 현상 유지다.
write_epoch_if_absent() {
  [ -e "$EPOCH" ] && return 0
  mkdir -p "$QDIR" 2>/dev/null || return 0
  tmp="$EPOCH.tmp.$$"
  # 빈 저장소(커밋 전)에서는 두 명령이 다 아무것도 내지 않고 0 이 아닌 값으로
  # 끝난다. set -o pipefail 아래서 그것이 파이프라인 실패로 번지지 않도록
  # 각각 || true 로 받는다 — 빈 epoch 은 오류가 아니라 정답이다.
  {
    git for-each-ref --format='%(objectname)' refs/heads refs/tags refs/remotes 2>/dev/null || true
    git rev-parse --verify --quiet HEAD 2>/dev/null || true
  } | sort -u > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 0; }
  mv "$tmp" "$EPOCH" 2>/dev/null || rm -f "$tmp"
  return 0
}
```

- [ ] **Step 4: `cmd_install` 이 훅을 놓기 전에 epoch 을 쓰게 한다**

현재 `cmd_install` 의 `mkdir -p "$HOOKS_DIR"` (`:95`) **바로 앞**에 한 줄 넣는다.

```bash
  # 훅을 놓기 전에 찍는다. 순서가 반대면 설치와 첫 커밋 사이의 커밋이
  # epoch 에 들어가 검사 대상에서 빠질 수 있다.
  write_epoch_if_absent

  mkdir -p "$HOOKS_DIR" || die "훅 디렉터리를 만들 수 없습니다"
```

- [ ] **Step 5: `cmd_uninstall` 이 상태를 지우게 한다**

`cmd_uninstall` 의 마지막 `echo "kkochikkochi: 제거 완료" >&2` (`:178`) **앞**에 넣는다.

```bash
  # 게이트를 걷어내면 상태도 함께 걷어낸다. epoch 과 covered.tsv 가 따로
  # 놀면 "이력은 지워졌는데 검사는 계속되는" 어긋난 상태가 난다.
  # 조용히 지우지 않는다 — passes/*.json 은 /kk-log 가 읽는 감사 기록이고
  # 복구되지 않는다.
  if [ -d "$QDIR" ]; then
    n_passes="$(find "$QDIR/passes" -name 'p-*.json' 2>/dev/null | wc -l | tr -d ' ')"
    if rm -rf "$QDIR" 2>/dev/null; then
      echo "kkochikkochi: 상태를 지웠습니다 — $QDIR (검증 기록 ${n_passes:-0}건 포함)" >&2
    else
      echo "kkochikkochi: 경고 — 상태를 지우지 못했습니다: $QDIR" >&2
    fi
  fi

  echo "kkochikkochi: 제거 완료" >&2
```

- [ ] **Step 6: 테스트가 통과하는지 확인한다**

Run: `bats tests/install.bats`
Expected: 전부 PASS.

- [ ] **Step 7: 회귀가 없는지 전체를 돌린다**

Run: `bats tests/`
Expected: 208 PASS (기존 203 + 신규 5), 0 FAIL.

- [ ] **Step 8: 새 테스트가 진짜 회귀 가드인지 확인한다**

`write_epoch_if_absent` 호출 한 줄을 임시로 주석 처리하고 `bats tests/install.bats` 를 돌린다.
Expected: epoch 테스트 4개가 FAIL. 확인했으면 주석을 되돌린다.
`cmd_uninstall` 의 `rm -rf "$QDIR"` 블록도 같은 방법으로 확인한다 — "uninstall 이 quiz-gate 를 통째로 지우고 알린다"가 FAIL 해야 한다.

- [ ] **Step 9: 커밋한다**

```bash
git add scripts/install.sh tests/install.bats
git commit -m "feat: record an install epoch and clear state on uninstall"
```

---

### Task 2: `pre-push` 가 도달성과 epoch 으로 범위를 좁힌다

**Files:**
- Modify: `hooks/pre-push` (`:61-133` 부근 — 상수 블록, sha 가드, 범위 계산)
- Test: `tests/pre-push.bats`

**Interfaces:**
- Consumes: Task 1 이 만든 `$(git rev-parse --git-common-dir)/quiz-gate/epoch`
- Produces:
  - 범위 규칙이 `range="$local_sha --not --remotes$epoch_args"` 하나로 통일된다. `remote_sha` 는 더 이상 범위에 쓰이지 않는다
  - `epoch_args` 는 살아 있고 16진수인 epoch 줄을 앞에 공백을 붙여 이은 문자열이며, 비어 있을 수 있다
  - epoch 파일을 읽을 수 없으면 기존 `unparseable` 범주에 쌓여 `--no-verify` 안내가 나간다

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`tests/pre-push.bats` 맨 끝에 추가한다. `run_push_hook` 은 파일 상단에 이미 정의돼 있다(`:21-24`).

```bash
# ── D47: 게이트가 볼 수 있었던 적 없는 커밋은 검사하지 않는다 ──
#
# 로컬 bare 저장소를 origin 으로 쓴다. 리모트를 건드리는 명령은 origin 이
# 로컬 경로일 때만 허용한다는 격리 규칙을 지킨다.

setup_origin() {   # bare origin 을 만들고 현재 HEAD 를 main 으로 올린다
  ORIGIN="$(mktemp -d)/origin.git"
  git init -q --bare "$ORIGIN"
  git remote add origin "$ORIGIN"
  git push -q origin HEAD:refs/heads/main
  git fetch -q origin
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
}

@test "epoch 의 16진수 아닌 줄은 rev-list 인자로 새지 않는다" {
  install_push_hook
  mkdir -p "$(qdir)"
  {
    git rev-parse HEAD
    printf -- '--all\n'
  } > "$(qdir)/epoch"
  printf 'EVIL\n' > evil.ts; git add evil.ts
  commit_as_human -qm "unverified"
  run run_push_hook "$NULL_SHA" "$(git rev-parse HEAD)"
  # --all 이 인자로 새면 범위가 통째로 바뀌어 미검증 내용을 건너뛴다
  [ "$status" -ne 0 ]
  [[ "$output" == *"evil.ts"* ]]
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
```

기존 테스트 하나를 지운다 — `remote_sha` 를 쓰지 않으므로 재현되지 않는다.

```bash
# 삭제: @test "remote sha 형식이 이상하면 거부한다"          (:117-126)
# 삭제: @test "범위를 계산할 수 없으면(모르는 remote sha) ..." (:130-142)
```

두 테스트가 지키던 성질은 위 신규 테스트 두 개(`remote_sha 가 무엇이든...`, `local sha 를 로컬이 모르면...`)가 이어받는다.

- [ ] **Step 2: 실패를 확인한다**

Run: `bats tests/pre-push.bats`
Expected: 신규 8개 중 최소 6개 FAIL. `pull 로 들어온 남의 커밋...` 은 현행 `remote..local` 이 동료 커밋을 잡아 `status != 0` 으로 깨지고, epoch 관련 4개는 epoch 을 아예 안 읽어서 깨진다.

- [ ] **Step 3: `hooks/pre-push` 에 epoch 파싱을 더한다**

현재 `blocked=""` / `unparseable=""` 선언(`:79-83`) **바로 아래**에 넣는다. 순서가 중요하다 — `unparseable` 이 이미 선언돼 있어야 한다.

```sh
EPOCH="$QDIR/epoch"

# epoch — 게이트가 이 저장소에 설치될 때 이미 존재하던 ref 팁 (D47).
# 그보다 앞선 이력은 이 게이트가 볼 수 있었던 적이 없으므로 검사하지 않는다.
#
# **살아 있고 16진수인 줄만 쓴다.** 실측: 없는 객체 하나를 --not 에 주면
# rev-list 가 128 로 죽고(cat-file -e 는 1), 이 훅은 fail-closed 라 그
# 순간 저장소의 모든 push 가 어떤 퀴즈로도 못 푸는 채로 영구 차단된다 —
# D00/D42 가 금지하는 바로 그 모양이다. 브랜치 삭제·GC 로 실제로 일어난다.
# 줄을 버리는 것은 안전 방향으로만 틀린다: 덜 빼면 더 많이 검사한다.
#
# 16진수 검사는 인자 주입 방어를 겸한다. epoch 은 파일에서 온 값이고
# 아래에서 $range 가 단어 분리를 거치므로, "--all" 같은 진짜 rev-list
# 옵션이 섞이면 범위가 통째로 바뀐다.
epoch_args=""
if [ -e "$EPOCH" ]; then
  if [ -r "$EPOCH" ]; then
    while IFS= read -r epoch_line; do
      [ -n "$epoch_line" ] || continue
      case "$epoch_line" in
        *[!0-9a-fA-F]*)
          echo "kkochikkochi: 경고 — epoch 의 16진수 아닌 줄을 무시합니다: $epoch_line" >&2
          continue
          ;;
      esac
      if ! git cat-file -e "$epoch_line" 2>/dev/null; then
        echo "kkochikkochi: 경고 — epoch 의 사라진 객체를 무시합니다: $epoch_line" >&2
        continue
      fi
      epoch_args="$epoch_args $epoch_line"
    done < "$EPOCH"
  else
    # 있는데 못 읽는다. 이 층은 fail-closed 지만, 못 뺀 이력은 어떤 퀴즈로도
    # covered.tsv 에 넣을 수 없으므로(pending.sh 는 staged 만 본다) 반드시
    # --no-verify 탈출구가 있는 unparseable 범주로 보낸다.
    unparseable="$unparseable   (epoch 파일을 읽을 수 없습니다: $EPOCH)
"
  fi
fi
```

- [ ] **Step 4: 범위 계산에서 분기를 없앤다**

`while read -r` 루프 안의 `remote_sha` 형식 검사(`:103-109`)와 범위 분기(`:111-119`)를 통째로 교체한다.

바꾸기 전:

```sh
  case "$remote_sha" in
    ''|*[!0-9a-fA-F]*)
      unparseable="$unparseable   (알 수 없는 remote sha 형식: $remote_sha)
"
      continue
      ;;
  esac

  # 브랜치 삭제 — 넘어가는 내용이 없다.
  is_null_sha "$local_sha" && continue

  if is_null_sha "$remote_sha"; then
    # 새 브랜치다. 이미 리모트에 있는 것을 빼고 이 브랜치에만 있는 것을 본다.
    range="$local_sha --not --remotes"
  else
    range="$remote_sha..$local_sha"
  fi
```

바꾼 뒤:

```sh
  # 브랜치 삭제 — 넘어가는 내용이 없다.
  is_null_sha "$local_sha" && continue

  # remote_sha 는 범위 계산에 쓰지 않는다 (D47).
  #
  # 예전에는 새 브랜치면 `--not --remotes`, 아니면 `$remote_sha..$local_sha`
  # 로 갈렸다. 후자가 구멍이었다: feature 브랜치를 올려 둔 뒤 git pull 로
  # 들어온 남의 커밋이 전부 그 범위에 들어와 검사 대상이 됐다(실측 재현).
  #
  # 로컬의 리모트 추적 ref 로 갈아타는 것은 안전 방향으로만 틀린다 —
  # 추적 ref 가 stale 하면 덜 빼서 더 많이 검사하고, 앞서 있으면 그 부분은
  # 애초에 이 push 범위 밖이다. 새 브랜치 경로가 이미 쓰던 방식이라
  # 두 경로의 규칙이 같아지는 것이 덤이다.
  #
  # --not 하나가 --remotes 와 뒤따르는 epoch sha 전부에 적용된다(실측).
  range="$local_sha --not --remotes$epoch_args"
```

`while read -r` 의 변수 목록에서 `remote_sha` 를 안 쓰는 이름으로 바꾼다.

```sh
while read -r _local_ref local_sha _remote_ref _remote_sha; do
```

- [ ] **Step 5: 헤더 주석에 D47 을 적는다**

파일 상단 `── D45 과의 긴장 ──` 블록 뒤에 붙인다.

```sh
# ── 검사 범위 (D47) ────────────────────────────────────────────
# 이 훅은 "사용자가 에이전트로 작업한 코드"만 본다. push 범위에서 두 가지를
# 뺀다: 어느 리모트 추적 ref 에서든 도달 가능한 커밋(git pull 로 들어온 남의
# 커밋, 브랜치 분기점, clone 해 온 이력)과, 게이트 설치 시점(epoch)의 ref
# 팁에서 도달 가능한 커밋(git init 직후의 이력).
#
# 빠지지 않는 것: cherry-pick·squash 로 가져온 남의 커밋. 새 SHA 라 도달성
# 판정에 안 걸린다. 교착은 아니다 — 막히면 퀴즈로 풀린다.
```

- [ ] **Step 6: 테스트가 통과하는지 확인한다**

Run: `bats tests/pre-push.bats`
Expected: 전부 PASS.

- [ ] **Step 7: `jq` 를 쓰지 않는다는 계약이 유지되는지 확인한다**

Run: `bats tests/pre-push.bats -f "jq"`
Expected: PASS. (새로 넣은 코드에 `jq` 가 없어야 한다)

- [ ] **Step 8: 회귀가 없는지 전체를 돌린다**

Run: `bats tests/`
Expected: 214 PASS (Task 1 이후 208 + 신규 8 − 삭제 2), 0 FAIL.

- [ ] **Step 9: 새 테스트가 진짜 회귀 가드인지 확인한다**

`range` 를 예전 분기로 임시로 되돌리고 `bats tests/pre-push.bats` 를 돌린다.
Expected: `pull 로 들어온 남의 커밋은 검사에서 빠진다` 가 FAIL.

`git cat-file -e` 검사 줄을 임시로 지우고 돌린다.
Expected: `epoch 의 사라진 객체가 push 를 막지 못한다` 가 FAIL.

16진수 `case` 검사를 임시로 지우고 돌린다.
Expected: `epoch 의 16진수 아닌 줄은 rev-list 인자로 새지 않는다` 가 FAIL.

셋 다 확인했으면 되돌린다.

- [ ] **Step 10: 커밋한다**

```bash
git add hooks/pre-push tests/pre-push.bats
git commit -m "feat: scope pre-push to commits the gate could have seen"
```

---

### Task 3: Codex 매니페스트에 서브에이전트 층을 배선한다

**Files:**
- Modify: `hooks.json` (루트 — Codex 매니페스트)
- Test: `tests/manifests.bats`

**Interfaces:**
- Consumes: 없음 (Task 1·2 와 독립)
- Produces: Codex 매니페스트가 `PreToolUse`·`Stop`·`PostToolUse`·`SubagentStart`·`SubagentStop` 5개 이벤트를 등록한다. `PostToolUse` 의 matcher 는 **`spawn_agent`** 다

**사실 근거** (`openai/codex` 원본에서 확인):
- `codex-rs/core/src/tools/hook_names.rs` — 셸 도구는 `"Bash"`, 서브에이전트 생성 도구는 `"spawn_agent"`(matcher alias `"Agent"`). **`Task` 는 아무것도 매칭하지 않는다**
- `codex-rs/hooks/schema/generated/*.schema.json` — `agent_id`·`agent_type` 이 `PreToolUse`·`PostToolUse` 에 optional, `SubagentStart`·`SubagentStop` 에 required. `cwd` 는 전부 required

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`tests/manifests.bats` 의 `@test "Codex 매니페스트에는 서브에이전트 훅이 없다"` (`:97-104`)를 통째로 지우고 그 자리에 넣는다.

```bash
@test "Codex 매니페스트도 서브에이전트 훅을 등록한다" {
  # 계획이 서 있던 "Codex 페이로드에는 agent_id 가 없다"는 전제는 거짓이다.
  # openai/codex 의 생성된 스키마가 agent_id·agent_type 을 PreToolUse·
  # PostToolUse 에 optional, SubagentStart·SubagentStop 에 required 로
  # 정의한다. 잡는 층이 하나도 없던 상태를 닫는다.
  for key in Stop PostToolUse SubagentStart SubagentStop; do
    run jq -e --arg k "$key" '.hooks | has($k)' "$PLUGIN_ROOT/hooks.json"
    [ "$status" -eq 0 ] || { echo "$key 가 없다"; return 1; }
  done
}

@test "Codex 의 PostToolUse matcher 는 Task 가 아니라 spawn_agent 다" {
  # codex-rs/core/src/tools/hook_names.rs — 서브에이전트 생성 도구의
  # 직렬화 이름은 spawn_agent 이고 matcher alias 는 Agent 다. Task 를
  # 쓰면 등록은 되지만 아무것도 매칭하지 않아 조용히 돌지 않는다.
  run jq -r '.hooks.PostToolUse[0].matcher' "$PLUGIN_ROOT/hooks.json"
  [ "$output" = "spawn_agent" ]
}

@test "Codex 매니페스트의 새 훅 command 가 전부 실제로 실행된다" {
  for path in '.hooks.Stop[0].hooks[0].command' \
              '.hooks.PostToolUse[0].hooks[0].command' \
              '.hooks.SubagentStart[0].hooks[0].command' \
              '.hooks.SubagentStop[0].hooks[0].command'; do
    cmd="$(jq -r "$path" "$PLUGIN_ROOT/hooks.json")"
    [ -n "$cmd" ] && [ "$cmd" != "null" ]
    jq -n --arg cwd "$PWD" \
      '{session_id:"sess-m", cwd:$cwd, agent_id:"aaa11", agent_type:"general-purpose"}' \
      | env -u CLAUDE_PLUGIN_ROOT PLUGIN_ROOT="$PLUGIN_ROOT" bash -c "$cmd"
    [ "$?" -eq 0 ] || return 1
  done
}

@test "Codex 매니페스트의 모든 command 가 PLUGIN_ROOT 를 쓴다" {
  # 변수 이름이 뒤바뀌면 경로가 빈 문자열로 펼쳐져 스크립트가 아예 실행되지
  # 않는다 — 이 시스템에서 가장 조용한 실패다.
  run jq -r '[.hooks[][].hooks[].command] | .[]' "$PLUGIN_ROOT/hooks.json"
  [[ "$output" == *'${PLUGIN_ROOT}'* ]]
  [[ "$output" != *'${CLAUDE_PLUGIN_ROOT}'* ]]
}

@test "매니페스트가 없는 하네스는 마커가 없어 통과한다" {
  # 지원 목록에 없는 에이전트는 stamp-agent.sh 가 돌지 않아 marker/ 가
  # 비고, pre-commit 이 D35(애매하면 통과)로 흘려보낸다. 의도된 fallback
  # 인데 지금까지 못이 박혀 있지 않았다.
  install_hook
  printf 'C1\n' > c.ts; git add c.ts
  [ ! -d "$(qdir)/marker" ]
  run commit_as_human -m x
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `bats tests/manifests.bats`
Expected: 새 테스트 중 4개 FAIL (`Stop`·`PostToolUse` 등이 없다). `매니페스트가 없는 하네스는...` 은 이미 참이라 PASS 할 수 있다 — 그건 Step 6 에서 회귀 가드인지 따로 확인한다.

- [ ] **Step 3: 루트 `hooks.json` 을 다시 쓴다**

```json
{
  "description": "KkochiKkochi — records an agent handshake so the git pre-commit gate knows this commit came from an agent, and blocks the turn from ending while subagent commits remain unverified.",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${PLUGIN_ROOT}/scripts/stamp-agent.sh\" --agent codex",
            "timeout": 5
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${PLUGIN_ROOT}/scripts/stop-gate.sh\"",
            "timeout": 10
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "spawn_agent",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${PLUGIN_ROOT}/scripts/bundle-notify.sh\"",
            "timeout": 10
          }
        ]
      }
    ],
    "SubagentStart": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${PLUGIN_ROOT}/scripts/seal-bundle.sh\" --event start",
            "timeout": 5
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${PLUGIN_ROOT}/scripts/seal-bundle.sh\" --event stop",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 4: 테스트가 통과하는지 확인한다**

Run: `bats tests/manifests.bats`
Expected: 전부 PASS.

- [ ] **Step 5: 회귀가 없는지 전체를 돌린다**

Run: `bats tests/`
Expected: 217 PASS (Task 2 이후 214 + 신규 5 − 삭제 1 − 기존 1개 이름 변경), 0 FAIL.

> 개수가 어긋나면 삭제·추가를 다시 세어 본다. 중요한 것은 **FAIL 0** 이다.

- [ ] **Step 6: 새 테스트가 진짜 회귀 가드인지 확인한다**

`hooks.json` 의 `PostToolUse` matcher 를 `"Task"` 로 임시로 바꾸고 돌린다.
Expected: `Codex 의 PostToolUse matcher 는 Task 가 아니라 spawn_agent 다` 가 FAIL. 되돌린다.

`매니페스트가 없는 하네스는 마커가 없어 통과한다` 는 `hooks/pre-commit` 의 D35 통과 줄(`:120` 의 `[ -n "$agent_signal" ] || exit 0`)을 임시로 지워서 확인한다.
Expected: FAIL. 확인했으면 되돌린다. **되돌려도 통과한다면 그 사실을 보고서에 적는다** — 이 저장소는 그런 테스트를 품질 메모로 남긴다.

- [ ] **Step 7: 커밋한다**

```bash
git add hooks.json tests/manifests.bats
git commit -m "feat: wire the Codex subagent layer to spawn_agent, not Task"
```

---

### Task 4: 틀린 Codex 전제를 계획·스펙에서 지운다

**Files:**
- Modify: `docs/superpowers/plans/2026-07-30-parallel-gate.md`
- Modify: `docs/superpowers/specs/2026-07-30-parallel-gate-design.md`
- Test: 없음 (문서만)

**Interfaces:**
- Consumes: Task 3 이 확정한 이벤트 매핑
- Produces: 두 문서에 "Codex 페이로드에는 agent_id 가 없다"가 남아 있지 않다

- [ ] **Step 1: 전제가 어디에 있는지 찾는다**

```bash
grep -rn "agent_id" docs/superpowers/plans/2026-07-30-parallel-gate.md \
                    docs/superpowers/specs/2026-07-30-parallel-gate-design.md \
  | grep -i codex
grep -rn "Codex" docs/superpowers/plans/2026-07-30-parallel-gate.md | head -30
```

- [ ] **Step 2: 찾은 문장을 사실로 교체한다**

각 지점에서 "Codex 페이로드에는 agent_id 가 없으니 서브에이전트 훅을 추가하지 않는다"는 취지의 문장을 지우고 다음으로 바꾼다.

```markdown
Codex 페이로드에도 `agent_id`·`agent_type` 이 있다 (`codex-rs/hooks/schema/generated/*.schema.json`:
`PreToolUse`·`PostToolUse` 에 optional, `SubagentStart`·`SubagentStop` 에 required).
서브에이전트 생성 도구의 직렬화 이름은 `spawn_agent` 이고 matcher alias 는 `Agent` 다
(`codex-rs/core/src/tools/hook_names.rs`) — Claude Code 의 `Task` 는 Codex 에서 아무것도
매칭하지 않는다. 두 에이전트의 층 구조는 같고 이벤트 이름만 다르다. 상세는
`docs/superpowers/specs/2026-08-01-push-scope-and-codex-design.md` §5.
```

- [ ] **Step 3: 계획의 Task 9·10 항목을 현행화한다**

`.superpowers/sdd/2026-07-30-parallel-gate/progress.md:169-177` 이 Task 9 의 범위를 "Codex 매니페스트에 훅 3종 등록"으로 적어 두었다. 이번 Task 3 이 그것을 **훅 4종 + `spawn_agent` 매처**로 수행했으므로, 계획 문서의 Task 9 항목에 완료 표시와 함께 실제 범위를 적는다.

- [ ] **Step 4: 전제가 남아 있지 않은지 확인한다**

```bash
grep -rn "agent_id 가 없" docs/superpowers/ || echo "남은 전제 없음"
grep -rn "PostToolUse(Task)" docs/superpowers/plans/2026-07-30-parallel-gate.md || echo "Task 매처 참조 없음"
```
Expected: 두 명령 모두 "없음" 을 출력한다. Claude Code 를 설명하는 문맥의 `Task` 는 정당하므로 남겨도 된다 — Codex 설명에만 없으면 된다.

- [ ] **Step 5: 커밋한다**

```bash
git add docs/superpowers/
git commit -m "docs(plan): replace the false Codex agent_id premise with the schema"
```

---

### Task 5: README·DECISIONS·CHANGELOG 를 현행화한다

**Files:**
- Modify: `README.md`
- Modify: `docs/DECISIONS.md`
- Modify: `CHANGELOG.md`
- Test: 없음 (문서만)

**Interfaces:**
- Consumes: Task 1~4 의 최종 동작
- Produces: 문서가 실제 동작과 일치한다

이 태스크는 이 브랜치가 계속 미뤄 온 부채를 함께 갚는다 — `progress.md:44` 가 "README·CHANGELOG 갱신이 Task 1~8 어디에도 없다"고 기록해 둔 그 구멍이다.

- [ ] **Step 1: 이미 거짓인 문장을 지운다**

`README.md:156` 의 한계 표 항목을 **삭제한다.**

```markdown
| **`record-pass.sh` 의 `pass_id` 는 초 단위 해상도다** | ... |
```

근거: `scripts/record-pass.sh:81` 이 `pass_id="p-$(date -u +%Y%m%d-%H%M%S)-$$"` 로 PID 를 붙여 이미 고쳤다. 커밋 `96e801c`.

- [ ] **Step 2: "동작 원리 (요약)" 절에 v3 의 층을 더한다**

현재 `README.md:59-66` 은 훅 2개(에이전트 훅 + `pre-commit`)만 설명한다. 실제로는 7개 트리거가 있다. 그 절 뒤에 표를 넣는다.

```markdown
서브에이전트가 커밋할 때는 층이 하나 더 붙는다. 서브에이전트는 사람에게 물을 수 없어서
`pre-commit` 에서 막으면 통과할 방법이 없다. 그래서 막지 않고 **원장(`ledger.tsv`)에 적어
두고** 뒤에서 강제한다.

| 트리거 | 하는 일 |
|---|---|
| `SubagentStart` / `SubagentStop` | 번들을 열고 봉인한다 (`agents/<hash>`) |
| `PostToolUse` (Claude Code `Task` / Codex `spawn_agent`) | 봉인된 번들의 검증을 부모 에이전트에게 요구한다 |
| `Stop` | 미검증이 남은 채로 턴이 끝나는 것을 막는다 |
| git `pre-push` | 최종 경계. Stop 은 Esc 로 빠져나갈 수 있다 |
```

- [ ] **Step 3: "게이트가 통과시키는 git 커맨드" 절에 D47 을 더한다**

`README.md:117-122` 목록에 항목 둘을 더한다.

```markdown
- `git pull` 로 들어온 남의 커밋, 원격 브랜치에서 분기할 때 딸려온 기준점, `git clone` 해 온 이력 — 어느 리모트 추적 ref 에서든 도달 가능하면 `pre-push` 가 보지 않는다 ([D47](docs/DECISIONS.md))
- 게이트를 설치하기 전의 로컬 이력 — 설치 시점의 ref 팁을 `.git/quiz-gate/epoch` 에 적어 두고 그보다 앞선 것은 보지 않는다. 게이트가 볼 수 있었던 적이 없는 커밋이다
```

- [ ] **Step 4: 한계 표에 6개를 더한다**

`README.md` 의 한계 표에 넣는다.

```markdown
| **`pre-push` 는 사람이 손으로 만든 커밋도 막는다** | 이 층은 출처를 보지 않는다 — 커밋 시점의 TTY·핸드셰이크 신호를 사후에 복원할 방법이 없기 때문이다. `pre-commit` 이 통과시킨 사람 커밋도 push 때는 퀴즈를 요구한다. 게이트 설치 이전의 이력과 리모트에서 온 것은 [D47](docs/DECISIONS.md) 로 빠진다 |
| **`cherry-pick`·squash 로 가져온 남의 커밋은 제외되지 않는다** | 새 SHA 라 도달성 판정에 안 걸린다. 제대로 하려면 patch-id 를 리모트 전체에 돌려야 하는데 push 마다 비용이 크다. **갇히지는 않는다** — 막히면 퀴즈로 풀린다. `pre-commit` 은 `CHERRY_PICK_HEAD` 를 보고 이미 통과시키므로 두 층의 판단이 갈리는 지점이다 |
| **epoch 없는 버전에서 업그레이드하면 미검증 커밋이 1회 면제된다** | `epoch` 은 파일이 없을 때만 쓰이므로, 이 기능 이전 버전을 쓰던 저장소는 업그레이드 시점의 ref 팁이 epoch 이 된다. 그때까지 쌓인 미검증 커밋은 한 번 면제된다. 1회성이며 그 뒤로는 안정 상태다 |
| **리모트 추적 ref 가 stale 하면 이미 리모트에 있는 커밋도 검사한다** | `git fetch` 하면 풀린다. 안전 방향이라 그대로 둔다 |
| **`install.sh uninstall` 은 검증 이력을 함께 지운다** | `.git/quiz-gate/` 를 통째로 지운다. `passes/*.json`(`/kk-log` 가 읽는 감사 기록)은 복구되지 않는다. 무엇을 지웠는지 stderr 에 알린다 |
| **워크트리는 `quiz-gate` 를 공유한다** | 상태가 `--git-common-dir` 아래 있어 한 워크트리에서 `uninstall` 하면 전부 사라진다. 훅(`.git/hooks/`)도 공유되므로 동작 자체는 일관된다 |
```

- [ ] **Step 5: "어떻게 기억하는가" 절에 epoch 과 원장을 더한다**

`README.md:124-130` 에 두 줄을 더한다.

```markdown
서브에이전트가 만든 미검증 변경은 `.git/quiz-gate/ledger.tsv` 에, 번들의 시작·봉인 시각은
`.git/quiz-gate/agents/` 에 남는다. 게이트가 이 저장소에 설치된 시점의 ref 팁은
`.git/quiz-gate/epoch` 에 남고, `pre-push` 가 그보다 앞선 이력을 검사에서 뺄 때 쓴다.
```

- [ ] **Step 6: `docs/DECISIONS.md` 에 D47 을 더한다**

파일 맨 끝(D46 뒤)에 붙인다. 기존 항목들의 형식(제목 + 상태 이모지, "왜", "대가", "되돌리는 조건")을 그대로 따른다.

```markdown
### D47. 게이트는 자기가 볼 수 있었던 적 없는 커밋에 의견을 갖지 않는다 ✅

`hooks/pre-push` 의 검사 범위에서 두 가지를 뺀다.

1. **어느 리모트 추적 ref 에서든 도달 가능한 커밋** — `git pull` 로 들어온 남의 커밋, 원격 브랜치에서 분기할 때의 기준점, `clone` 해 온 이력
2. **게이트 설치 시점(`epoch`)의 ref 팁에서 도달 가능한 커밋** — `git init` 직후의 로컬 이력

범위 계산이 `range="$local_sha --not --remotes$epoch_args"` 한 줄로 통일된다. `remote_sha` 는 더 이상 쓰지 않는다.

**왜.** D00 은 "AI 가 사람이 흡수하는 속도보다 빠르게 코드를 만든다"를 문제로 놓는다. 남이 만들어 리모트에 올린 코드와 게이트가 존재하지도 않던 시절의 이력은 그 문제가 아니다. 그것들을 막는 것은 D00 이 말하는 "막아야 할 커밋을 정확히 막는 것"이 아니라 "더 많이 막는 것"이고, D44 가 핸드셰이크를 좁힐 때 쓴 논거와 같다.

실측으로 확인한 구멍: feature 브랜치를 push 해 둔 뒤 `git pull origin main` 을 하면, 들어온 동료 커밋이 전부 `$remote_sha..$local_sha` 범위에 들어와 검사 대상이 됐다.

**epoch 의 수명.** `install.sh` 가 **파일이 없을 때만** 쓰고, `uninstall` 이 `quiz-gate` 를 통째로 지운다. 규칙이 하나여서 최초 설치·갱신·구버전 업그레이드가 전부 맞는다. 갱신 때 다시 쓰면 안 되는 이유: `install` 은 "처음 설치"만 뜻하지 않는다. 훅이 낡으면 건강검진이 에이전트에게 `install` 을 시키므로 플러그인이 업데이트될 때마다 모든 사용자의 저장소에서 다시 돈다. 거기서 epoch 을 갱신하면 사용자는 "업데이트했을 뿐"인데 그때까지의 미검증 커밋이 전부 면제된다.

**죽은 sha 는 버린다.** 없는 객체 하나를 `--not` 에 주면 `rev-list` 가 128 로 죽고, 이 훅은 fail-closed 라 그 순간 저장소의 모든 push 가 어떤 퀴즈로도 못 푸는 채로 영구 차단된다(실측). `git cat-file -e` 로 미리 걸러 그 줄만 버린다 — 덜 빼면 더 많이 검사하므로 안전 방향으로만 틀린다.

**대가.** `cherry-pick`·squash 로 가져온 남의 커밋은 새 SHA 라 여전히 걸린다. epoch 없는 버전에서 업그레이드하면 1회 면제가 생긴다. 둘 다 README 한계 표에 적었다.

**되돌리는 조건.** 도달성 제외 때문에 실제로 검증되어야 할 코드가 새어나간 사례가 관찰되면.
```

- [ ] **Step 7: `CHANGELOG.md` 에 항목을 더한다**

기존 형식을 따라 맨 위에 넣는다.

```markdown
### 바뀐 것

- `pre-push` 가 "사용자가 에이전트로 작업한 코드"만 검사한다. `git pull` 로 들어온 남의 커밋, 원격 브랜치 분기점, `clone` 해 온 이력, 게이트 설치 이전의 로컬 이력이 전부 빠진다 (D47)
- `install.sh install` 이 설치 시점의 ref 팁을 `.git/quiz-gate/epoch` 에 남긴다. 파일이 없을 때만 쓰므로 플러그인 업데이트가 게이트를 리셋하지 않는다
- `install.sh uninstall` 이 `.git/quiz-gate/` 를 통째로 지운다. 무엇을 지웠는지 알린다
- Codex 매니페스트가 `Stop`·`PostToolUse`·`SubagentStart`·`SubagentStop` 을 등록한다. 서브에이전트 생성 도구 이름은 `Task` 가 아니라 `spawn_agent` 다

### 고친 것

- `pre-push` 가 `git pull` 로 들어온 남의 커밋을 검사 대상으로 잡던 문제. 새 브랜치 경로는 이미 옳았고 기존 브랜치 경로만 틀렸다
- README 한계 표의 `pass_id` 초 해상도 항목이 이미 고쳐진 문제를 계속 적고 있던 것
```

- [ ] **Step 8: 문서가 실제 동작과 맞는지 확인한다**

```bash
grep -n "pass_id 는 초 단위" README.md || echo "거짓 항목 삭제됨"
grep -n "D47" README.md docs/DECISIONS.md | head
bats tests/
```
Expected: 첫 줄이 "거짓 항목 삭제됨", `D47` 이 두 파일에 있고, 테스트는 여전히 전부 PASS.

- [ ] **Step 9: 커밋한다**

```bash
git add README.md docs/DECISIONS.md CHANGELOG.md
git commit -m "docs: document the push scope rule, the epoch, and the v3 layers"
```

---

## 자체 리뷰 결과

**스펙 커버리지.** 설계 문서의 각 절이 어느 태스크로 가는지:

| 스펙 | 태스크 |
|---|---|
| §2 범위 계산 분기 제거 | Task 2 Step 4 |
| §3.1 epoch 정의 | Task 1 Step 3 |
| §3.2 epoch 수명 | Task 1 Step 3·5 |
| §3.3 D45 관계 | Task 2 Step 5 (헤더 주석) |
| §4 실패 처리 5종 | Task 2 Step 3 |
| §5.1 Codex 사실 | Task 3 Step 3, Task 4 Step 2 |
| §5.2 이벤트 매핑 | Task 3 Step 3 |
| §5.3 정정할 문서·테스트 | Task 3 Step 1, Task 4 |
| §7 한계 6개 | Task 5 Step 4 |
| §8 테스트 계획 | Task 1 Step 1, Task 2 Step 1, Task 3 Step 1 |
| §9 D47 | Task 5 Step 6 |
| §10 구현 순서 | 이 문서의 태스크 순서 |

**의존성.** Task 1 → Task 2 (epoch 파일이 있어야 새 경로가 실제로 검증된다). Task 3 → Task 4. Task 5 는 전부 끝난 뒤. Task 3 은 Task 1·2 와 독립이라 병렬 가능하지만, 같은 `tests/` 를 돌리므로 순차 실행을 권한다.

**이름 일관성.** `epoch_args`(pre-push 지역 변수), `EPOCH`(두 파일의 경로 상수), `write_epoch_if_absent`(install.sh 함수), `QDIR`(두 파일에서 같은 뜻) — 태스크 사이에 철자가 어긋나지 않는다.
