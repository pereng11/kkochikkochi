#!/usr/bin/env bats

load helper

setup() { setup_repo; seed_repo; }
teardown() { teardown_repo; }

inst() { bash "$PLUGIN_ROOT/scripts/install.sh" "$@"; }

@test "install 이 훅을 놓는다" {
  run inst install
  [ "$status" -eq 0 ]
  [ -x "$(hooksdir)/pre-commit" ]
  grep -q 'KKOCHIKKOCHI-HOOK-v1' "$(hooksdir)/pre-commit"
}

@test "status 는 설치 전 1, 설치 후 0" {
  run inst status
  [ "$status" -eq 1 ]
  inst install
  run inst status
  [ "$status" -eq 0 ]
}

@test "기존 훅을 체이닝 파일로 옮긴다" {
  printf '#!/bin/sh\nexit 0\n' > "$(hooksdir)/pre-commit"; chmod +x "$(hooksdir)/pre-commit"
  inst install
  [ -f "$(hooksdir)/pre-commit.kkochikkochi-chained" ]
  grep -q 'KKOCHIKKOCHI-HOOK-v1' "$(hooksdir)/pre-commit"
}

@test "재설치는 멱등이며 체이닝 파일을 덮어쓰지 않는다" {
  printf '#!/bin/sh\necho ORIGINAL\nexit 0\n' > "$(hooksdir)/pre-commit"; chmod +x "$(hooksdir)/pre-commit"
  inst install
  inst install
  run cat "$(hooksdir)/pre-commit.kkochikkochi-chained"
  [[ "$output" == *"ORIGINAL"* ]]
}

@test "uninstall 이 기존 훅을 원상복구한다" {
  printf '#!/bin/sh\necho ORIGINAL\nexit 0\n' > "$(hooksdir)/pre-commit"; chmod +x "$(hooksdir)/pre-commit"
  inst install
  # 대조군: install 이 실제로 우리 훅을 놓았는지 먼저 확인한다. 이게 없으면
  # install 이 아무 일도 안 하는 스텁이어도 ORIGINAL 이 애초에 안 건드려져
  # 아래 검사를 우연히 통과한다.
  grep -q 'KKOCHIKKOCHI-HOOK-v1' "$(hooksdir)/pre-commit"
  inst uninstall
  run cat "$(hooksdir)/pre-commit"
  [[ "$output" == *"ORIGINAL"* ]]
  [ ! -f "$(hooksdir)/pre-commit.kkochikkochi-chained" ]
}

@test "체이닝할 것이 없으면 uninstall 이 훅만 지운다" {
  inst install
  # 대조군: install 이 실제로 훅을 놓았는지 먼저 확인한다. 이게 없으면
  # install 이 아무 일도 안 하는 스텁이어도 애초에 파일이 없어 아래 검사를
  # 우연히 통과한다.
  [ -x "$(hooksdir)/pre-commit" ]
  inst uninstall
  [ ! -f "$(hooksdir)/pre-commit" ]
}

@test "core.hooksPath 가 설정돼 있으면 설치를 거부하고 exit 2" {
  mkdir -p .myhooks
  git config core.hooksPath .myhooks
  run inst install
  [ "$status" -eq 2 ]
  [ ! -f ".myhooks/pre-commit" ]
  [[ "$output" == *"core.hooksPath"* ]]
}

@test "설치 후 게이트가 실제로 동작한다 (종단 확인)" {
  inst install
  printf 'C1\n' > c.ts; git add c.ts
  stamp
  run commit_as_human -m x
  [ "$status" -ne 0 ]
}

@test "core.hooksPath 가 설정돼 있으면 status 도 exit 2" {
  mkdir -p .myhooks
  git config core.hooksPath .myhooks
  run inst status
  [ "$status" -eq 2 ]
}

# ── I5: 낡은 설치는 0 이 아니라 3 이다 ──

@test "마커는 있지만 내용이 다른 훅은 status 3 (낡음)" {
  # 예전에는 마커 문자열만 보고 0("설치됨")을 냈다. 그래서 어떤 수정도
  # 이미 설치된 저장소에 영원히 도달하지 못했다 — 헬스체크는 0 이 아닐
  # 때만 반응하기 때문이다.
  printf '#!/bin/sh\n# KKOCHIKKOCHI-HOOK-v1 (ancient)\nexit 0\n' > "$(hooksdir)/pre-commit"
  chmod +x "$(hooksdir)/pre-commit"
  run inst status
  [ "$status" -eq 3 ]
  # 그리고 install 이 실제로 그것을 고쳐 0 으로 되돌린다
  inst install
  run inst status
  [ "$status" -eq 0 ]
}

@test "실행 권한이 없는 우리 훅도 status 3" {
  # git 은 실행 권한 없는 훅을 무시한다 — 0 을 내면 게이트가 조용히 없다.
  inst install
  run inst status
  [ "$status" -eq 0 ]              # 대조군
  chmod -x "$(hooksdir)/pre-commit"
  run inst status
  [ "$status" -eq 3 ]
}

@test "설치 직후 status 는 3 이 아니라 0 이다 (거짓 낡음 없음)" {
  # 내용 비교가 항상 어긋나면 헬스체크가 재설치를 무한 요구하게 된다.
  inst install
  run inst status
  [ "$status" -eq 0 ]
  inst install                     # 재설치도 멱등
  run inst status
  [ "$status" -eq 0 ]
}

# ── I4: jq 없이 설치하지 않는다 ──

@test "jq 가 없으면 설치를 거부한다" {
  nojq="$(mktemp -d)"
  for b in git bash sh awk sed grep cat date stat mkdir rm mv cp chmod ln printf tr head find wc env dirname uname id sort cut touch cmp expr basename; do
    p="$(command -v "$b" 2>/dev/null)" && ln -sf "$p" "$nojq/$b"
  done
  PATH="$nojq" run inst install
  [ "$status" -ne 0 ]
  [[ "$output" == *"jq"* ]]
  # 게이트가 설치되지 않았어야 한다 — 통과할 방법이 없는 게이트를 남기면 안 된다
  [ ! -f "$(hooksdir)/pre-commit" ]
  # 대조군: jq 가 있으면 같은 명령이 설치한다
  run inst install
  [ "$status" -eq 0 ]
  [ -x "$(hooksdir)/pre-commit" ]
}

# ── 실패 시 훅이 사라지지 않는다 (cp/mv 를 가짜로 바꿔 중간 실패를 흉내낸다) ──

@test "새 훅 준비(cp)가 실패해도 기존 훅이 사라지지 않는다" {
  printf '#!/bin/sh\necho ORIGINAL\nexit 0\n' > "$(hooksdir)/pre-commit"; chmod +x "$(hooksdir)/pre-commit"
  # BATS_TEST_TMPDIR 는 bats-core 1.5 이전엔 정의되지 않는다(Ubuntu 22.04
  # apt 의 bats 1.2.1 로 실측 — 미정의 상태에서 "$BATS_TEST_TMPDIR/fakebin"
  # 은 그냥 "/fakebin" 이 되어 테스트 사이에 상태가 새어 나간다). 그래서
  # 버전에 기대지 않고 매번 mktemp -d 로 테스트마다 독립된 디렉터리를 만든다.
  fakebin="$(mktemp -d)"
  mkdir -p "$fakebin"
  printf '#!/bin/sh\nexit 1\n' > "$fakebin/cp"
  chmod +x "$fakebin/cp"
  PATH="$fakebin:$PATH" run inst install
  [ "$status" -ne 0 ]
  # 체이닝 이동은 cp 성공 이후에만 일어나므로, cp 가 실패하면 기존 훅은
  # 옮겨지지도 않고 그 자리에 그대로 있어야 한다 — 체이닝 파일도 없어야 한다.
  [ -f "$(hooksdir)/pre-commit" ]
  [ ! -f "$(hooksdir)/pre-commit.kkochikkochi-chained" ]
  run cat "$(hooksdir)/pre-commit"
  [[ "$output" == *"ORIGINAL"* ]]
}

@test "설치 마지막 이동이 실패해도 기존 훅이 사라지지 않는다 (복구됨)" {
  printf '#!/bin/sh\necho ORIGINAL\nexit 0\n' > "$(hooksdir)/pre-commit"; chmod +x "$(hooksdir)/pre-commit"
  # BATS_TEST_TMPDIR 는 bats-core 1.5 이전엔 정의되지 않는다(Ubuntu 22.04
  # apt 의 bats 1.2.1 로 실측 — 미정의 상태에서 "$BATS_TEST_TMPDIR/fakebin"
  # 은 그냥 "/fakebin" 이 되어 테스트 사이에 상태가 새어 나간다). 그래서
  # 버전에 기대지 않고 매번 mktemp -d 로 테스트마다 독립된 디렉터리를 만든다.
  fakebin="$(mktemp -d)"
  mkdir -p "$fakebin"
  # 임시 파일을 최종 위치로 옮기는 그 마지막 mv 만 실패시킨다. 기존 훅을
  # 체이닝 위치로 옮기는 첫 번째 mv 는 그대로 통과시켜야, 실제로 다음 순서로
  # 실패하는 시나리오(기존 훅은 이미 치워졌는데 새 훅을 놓다가 죽는 상황)를
  # 재현할 수 있다.
  cat > "$fakebin/mv" <<'FAKEMV'
#!/bin/sh
case "$1" in
  *.kkochikkochi-tmp.*) exit 1 ;;
esac
exec /bin/mv "$@"
FAKEMV
  chmod +x "$fakebin/mv"
  PATH="$fakebin:$PATH" run inst install
  [ "$status" -ne 0 ]
  # TARGET 이 완전히 사라진 채로 끝나면 안 된다 — 기존 훅이 복구돼 있어야
  # 하고, 체이닝 파일은 다시 남아 있지 않아야 한다.
  [ -f "$(hooksdir)/pre-commit" ]
  [ ! -f "$(hooksdir)/pre-commit.kkochikkochi-chained" ]
  run cat "$(hooksdir)/pre-commit"
  [[ "$output" == *"ORIGINAL"* ]]
}

@test "uninstall 의 복구 이동이 실패해도 우리 훅이 남아있다" {
  printf '#!/bin/sh\necho ORIGINAL\nexit 0\n' > "$(hooksdir)/pre-commit"; chmod +x "$(hooksdir)/pre-commit"
  inst install
  # 대조군: 체이닝이 실제로 걸려 있는지 먼저 확인한다.
  [ -f "$(hooksdir)/pre-commit.kkochikkochi-chained" ]
  grep -q 'KKOCHIKKOCHI-HOOK-v1' "$(hooksdir)/pre-commit"
  # BATS_TEST_TMPDIR 는 bats-core 1.5 이전엔 정의되지 않는다(Ubuntu 22.04
  # apt 의 bats 1.2.1 로 실측 — 미정의 상태에서 "$BATS_TEST_TMPDIR/fakebin"
  # 은 그냥 "/fakebin" 이 되어 테스트 사이에 상태가 새어 나간다). 그래서
  # 버전에 기대지 않고 매번 mktemp -d 로 테스트마다 독립된 디렉터리를 만든다.
  fakebin="$(mktemp -d)"
  mkdir -p "$fakebin"
  printf '#!/bin/sh\nexit 1\n' > "$fakebin/mv"
  chmod +x "$fakebin/mv"
  PATH="$fakebin:$PATH" run inst uninstall
  [ "$status" -ne 0 ]
  # 복구가 실패해도 저장소가 훅이 하나도 없는 상태로 떨어지면 안 된다 —
  # 우리 훅이 그대로 남아 있어야 한다(먼저 지우고 나중에 복구하는 순서였다면
  # 여기서 pre-commit 자체가 사라진다).
  [ -f "$(hooksdir)/pre-commit" ]
  grep -q 'KKOCHIKKOCHI-HOOK-v1' "$(hooksdir)/pre-commit"
}

# ── 체이닝은 하드 링크로 한다 — TARGET 이 사라지는 순간 자체가 없다 ──
# (이동 방식은 두 mv 사이에 TARGET 이 잠깐 존재하지 않는 창을 남긴다.
# 진짜 SIGKILL 인터럽트는 bats 로 재현하기 어려우므로, 그 창에 해당하는
# 관찰 가능한 시점 — 마지막 rename 이 시도되는 바로 그 순간 — 에서
# TARGET 의 존재 여부를 기록해 확인한다.)

@test "체이닝은 하드 링크를 써서 마지막 rename 시점에도 TARGET 이 이미 존재한다" {
  printf '#!/bin/sh\necho ORIGINAL\nexit 0\n' > "$(hooksdir)/pre-commit"; chmod +x "$(hooksdir)/pre-commit"
  # BATS_TEST_TMPDIR 는 bats-core 1.5 이전엔 정의되지 않는다(Ubuntu 22.04
  # apt 의 bats 1.2.1 로 실측 — 미정의 상태에서 "$BATS_TEST_TMPDIR/fakebin"
  # 은 그냥 "/fakebin" 이 되어 테스트 사이에 상태가 새어 나간다). 그래서
  # 버전에 기대지 않고 매번 mktemp -d 로 테스트마다 독립된 디렉터리를 만든다.
  fakebin="$(mktemp -d)"
  mkdir -p "$fakebin"
  observed="$(mktemp -d)/observed"
  cat > "$fakebin/mv" <<FAKEMV
#!/bin/sh
case "\$1" in
  *.kkochikkochi-tmp.*)
    if [ -f "\$2" ]; then echo PRESENT > "$observed"; else echo ABSENT > "$observed"; fi
    exit 1
    ;;
esac
exec /bin/mv "\$@"
FAKEMV
  chmod +x "$fakebin/mv"
  PATH="$fakebin:$PATH" run inst install
  [ "$status" -ne 0 ]
  [ -f "$observed" ]
  # 예전(파괴적 이동) 방식이었다면 이 시점엔 TARGET 이 이미 옮겨져 없어야
  # 정상이었다 — 하드 링크로 바꾼 뒤에는 이 시점에도 여전히 있어야 한다.
  [ "$(cat "$observed")" = "PRESENT" ]
}

@test "설치 뒤 TARGET 과 CHAINED 는 같은 inode 를 공유하지 않는다 (링크가 분리됐다)" {
  printf '#!/bin/sh\necho ORIGINAL\nexit 0\n' > "$(hooksdir)/pre-commit"; chmod +x "$(hooksdir)/pre-commit"
  inst install
  [ -f "$(hooksdir)/pre-commit.kkochikkochi-chained" ]
  # 마지막 rename 이 TARGET 이라는 "이름"만 새 inode 로 바꿔치웠으므로,
  # CHAINED 는 계속 원본 inode 를 가리켜야 한다 — 둘이 같은 파일이면 안 된다.
  ! [ "$(hooksdir)/pre-commit" -ef "$(hooksdir)/pre-commit.kkochikkochi-chained" ]
  run cat "$(hooksdir)/pre-commit.kkochikkochi-chained"
  [[ "$output" == *"ORIGINAL"* ]]
  grep -q 'KKOCHIKKOCHI-HOOK-v1' "$(hooksdir)/pre-commit"
  ! grep -q 'KKOCHIKKOCHI-HOOK-v1' "$(hooksdir)/pre-commit.kkochikkochi-chained"
}

@test "install 이 pre-push 도 설치한다" {
  bash "$PLUGIN_ROOT/scripts/install.sh" install
  [ -x "$(hooksdir)/pre-push" ]
  run grep -c 'KKOCHIKKOCHI-HOOK-v1' "$(hooksdir)/pre-push"
  [ "$output" -ge 1 ]
}

@test "pre-push 가 없으면 status 가 3(낡음)을 낸다" {
  bash "$PLUGIN_ROOT/scripts/install.sh" install
  rm -f "$(hooksdir)/pre-push"
  run bash "$PLUGIN_ROOT/scripts/install.sh" status
  [ "$status" -eq 3 ]
}

@test "pre-push 가 낡으면 status 가 3 을 낸다" {
  bash "$PLUGIN_ROOT/scripts/install.sh" install
  printf '#!/bin/sh\n# KKOCHIKKOCHI-HOOK-v1\nexit 0\n' > "$(hooksdir)/pre-push"
  chmod +x "$(hooksdir)/pre-push"
  run bash "$PLUGIN_ROOT/scripts/install.sh" status
  [ "$status" -eq 3 ]
}

@test "둘 다 최신이면 status 가 0 을 낸다" {
  bash "$PLUGIN_ROOT/scripts/install.sh" install
  run bash "$PLUGIN_ROOT/scripts/install.sh" status
  [ "$status" -eq 0 ]
}

@test "uninstall 이 둘 다 지운다" {
  bash "$PLUGIN_ROOT/scripts/install.sh" install
  bash "$PLUGIN_ROOT/scripts/install.sh" uninstall
  [ ! -e "$(hooksdir)/pre-commit" ]
  [ ! -e "$(hooksdir)/pre-push" ]
}

@test "기존 pre-push 훅도 체이닝한다" {
  mkdir -p "$(hooksdir)"
  printf '#!/bin/sh\necho theirs-push\nexit 0\n' > "$(hooksdir)/pre-push"
  chmod +x "$(hooksdir)/pre-push"
  bash "$PLUGIN_ROOT/scripts/install.sh" install
  [ -x "$(hooksdir)/pre-push.kkochikkochi-chained" ]
  run cat "$(hooksdir)/pre-push.kkochikkochi-chained"
  [[ "$output" == *"theirs-push"* ]]
}

@test "ln 이 실패하면 예전 방식(이동)으로 물러나 설치를 계속한다" {
  printf '#!/bin/sh\necho ORIGINAL\nexit 0\n' > "$(hooksdir)/pre-commit"; chmod +x "$(hooksdir)/pre-commit"
  # BATS_TEST_TMPDIR 는 bats-core 1.5 이전엔 정의되지 않는다(Ubuntu 22.04
  # apt 의 bats 1.2.1 로 실측 — 미정의 상태에서 "$BATS_TEST_TMPDIR/fakebin"
  # 은 그냥 "/fakebin" 이 되어 테스트 사이에 상태가 새어 나간다). 그래서
  # 버전에 기대지 않고 매번 mktemp -d 로 테스트마다 독립된 디렉터리를 만든다.
  fakebin="$(mktemp -d)"
  mkdir -p "$fakebin"
  printf '#!/bin/sh\nexit 1\n' > "$fakebin/ln"
  chmod +x "$fakebin/ln"
  PATH="$fakebin:$PATH" run inst install
  [ "$status" -eq 0 ]
  grep -q 'KKOCHIKKOCHI-HOOK-v1' "$(hooksdir)/pre-commit"
  run cat "$(hooksdir)/pre-commit.kkochikkochi-chained"
  [[ "$output" == *"ORIGINAL"* ]]
  # 폴백 경로로 설치된 뒤에도 uninstall 왕복이 정상 동작해야 한다 —
  # 체이닝 방식이 달라졌다고 복구 로직까지 달라지면 안 된다.
  run inst uninstall
  [ "$status" -eq 0 ]
  run cat "$(hooksdir)/pre-commit"
  [[ "$output" == *"ORIGINAL"* ]]
  [ ! -f "$(hooksdir)/pre-commit.kkochikkochi-chained" ]
}

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
