#!/usr/bin/env bash
# git pre-commit 훅 설치 / 제거 / 상태 확인
#
# 자기 식별 마커로 "내 훅"을 판별한다 — pre-commit 프레임워크 방식. (D38)
# core.hooksPath 가 설정된 저장소에서는 설치하지 않는다: 실효 디렉터리가
# 저장소에 추적되므로, 말없이 쓰면 git status 에 뜨고 커밋에 섞인다. (D32)

set -uo pipefail

MARKER="KKOCHIKKOCHI-HOOK-v1"
CHAINED_SUFFIX=".kkochikkochi-chained"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/../hooks/pre-commit"

die() { echo "kkochikkochi: $1" >&2; exit 1; }

git rev-parse --git-dir >/dev/null 2>&1 || die "git 저장소가 아닙니다"

HOOKS_DIR="$(git rev-parse --git-path hooks)"
TARGET="$HOOKS_DIR/pre-commit"
CHAINED="$TARGET$CHAINED_SUFFIX"

is_ours() { [ -f "$1" ] && grep -q "$MARKER" "$1" 2>/dev/null; }

hookspath_set() { [ -n "$(git config --get core.hooksPath || true)" ]; }

cmd_status() { is_ours "$TARGET" && exit 0 || exit 1; }

cmd_install() {
  if hookspath_set; then
    cat >&2 <<MSG
kkochikkochi: 이 저장소는 core.hooksPath 를 사용합니다 ($(git config --get core.hooksPath)).
  그 경우 .git/hooks/ 는 무시되고, 실효 훅 디렉터리는 저장소에 추적되는 곳입니다.
  거기에 파일을 쓰면 git status 에 뜨고 커밋에 섞일 수 있어 자동으로 설치하지 않습니다.

  선택지:
    1) 그 디렉터리에 직접 설치 — 추적되는 변경이 생깁니다
    2) core.hooksPath 를 해제하고 다시 실행
    3) 이 저장소에서는 게이트를 쓰지 않음
MSG
    exit 2
  fi

  mkdir -p "$HOOKS_DIR" || die "훅 디렉터리를 만들 수 없습니다"
  [ -r "$SRC" ] || die "훅 원본을 찾을 수 없습니다: $SRC"

  # 기존 훅이 우리 것이 아니면 체이닝으로 옮긴다.
  # 이미 체이닝 파일이 있으면 덮어쓰지 않는다 — 사용자의 원래 훅을 잃게 된다.
  if [ -f "$TARGET" ] && ! is_ours "$TARGET"; then
    if [ -f "$CHAINED" ]; then
      die "체이닝 파일이 이미 있습니다: $CHAINED — 수동으로 정리하세요"
    fi
    mv "$TARGET" "$CHAINED" || die "기존 훅을 옮길 수 없습니다"
    chmod +x "$CHAINED" 2>/dev/null || true
    echo "kkochikkochi: 기존 pre-commit 훅을 $CHAINED 로 옮기고 체이닝합니다" >&2
  fi

  cp "$SRC" "$TARGET" || die "훅을 설치할 수 없습니다"
  chmod +x "$TARGET" || die "실행 권한을 줄 수 없습니다"
  echo "kkochikkochi: 설치 완료 — $TARGET" >&2
}

cmd_uninstall() {
  is_ours "$TARGET" || die "우리 훅이 설치돼 있지 않습니다"
  rm -f "$TARGET" || die "훅을 지울 수 없습니다"
  if [ -f "$CHAINED" ]; then
    mv "$CHAINED" "$TARGET" || die "체이닝된 훅을 복구할 수 없습니다"
    echo "kkochikkochi: 기존 훅을 복구했습니다" >&2
  fi
  echo "kkochikkochi: 제거 완료" >&2
}

case "${1:-install}" in
  install)   cmd_install ;;
  uninstall) cmd_uninstall ;;
  status)    cmd_status ;;
  *)         die "사용법: install.sh [install|uninstall|status]" ;;
esac
