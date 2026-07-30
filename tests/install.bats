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
