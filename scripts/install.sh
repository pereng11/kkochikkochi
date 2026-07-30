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

# core.hooksPath 가 설정돼 있으면 "설치됨/아님"을 가를 수 없다 — 애초에
# 우리가 설치를 거부하는 상태이므로, install 과 같은 exit 2 로 통일해
# 호출자(예: Task 4 의 헬스체크)가 "바로 설치해도 됨"과 "사람 판단이
# 필요함"을 구분할 수 있게 한다.
cmd_status() {
  hookspath_set && exit 2
  is_ours "$TARGET" && exit 0 || exit 1
}

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

  # 새 훅을 같은 디렉터리의 임시 파일로 먼저 완성해 둔다. cp·chmod 가 여기서
  # 실패해도 기존 훅(있다면)은 아직 전혀 건드리지 않았으므로 안전하다.
  TMP_HOOK="$TARGET.kkochikkochi-tmp.$$"
  rm -f "$TMP_HOOK"
  cp "$SRC" "$TMP_HOOK" || { rm -f "$TMP_HOOK"; die "훅을 준비할 수 없습니다"; }
  chmod +x "$TMP_HOOK" || { rm -f "$TMP_HOOK"; die "실행 권한을 줄 수 없습니다"; }

  # 기존 훅이 우리 것이 아니면 체이닝으로 옮긴다 — 새 훅이 이미 완성된
  # 뒤이므로, 여기부터 실패해도 무엇을 되돌려야 할지 알 수 있다.
  # 이미 체이닝 파일이 있으면 덮어쓰지 않는다 — 사용자의 원래 훅을 잃게 된다.
  moved_aside=0
  if [ -f "$TARGET" ] && ! is_ours "$TARGET"; then
    if [ -f "$CHAINED" ]; then
      rm -f "$TMP_HOOK"
      die "체이닝 파일이 이미 있습니다: $CHAINED — 수동으로 정리하세요"
    fi
    mv "$TARGET" "$CHAINED" || { rm -f "$TMP_HOOK"; die "기존 훅을 옮길 수 없습니다"; }
    moved_aside=1
    chmod +x "$CHAINED" 2>/dev/null ||
      echo "kkochikkochi: 경고 — $CHAINED 에 실행 권한을 줄 수 없습니다. 수동으로 chmod +x 하세요" >&2
    echo "kkochikkochi: 기존 pre-commit 훅을 $CHAINED 로 옮기고 체이닝합니다" >&2
  fi

  # 같은 디렉터리 안에서의 rename 은 원자적이다 — 이 한 걸음 이후 TARGET 은
  # 옛 파일이거나 새 파일이거나 둘 중 하나이지, 결코 "둘 다 없음"이 되지
  # 않는다. 그래도 이 rename 자체가 실패하면(디스크가 꽉 찼다거나 권한이
  # 바뀌는 등) 바로 위에서 옮겨 둔 기존 훅을 제자리로 되돌린다.
  if ! mv "$TMP_HOOK" "$TARGET"; then
    rm -f "$TMP_HOOK"
    if [ "$moved_aside" -eq 1 ] && mv "$CHAINED" "$TARGET" 2>/dev/null; then
      die "훅을 설치할 수 없습니다 (기존 훅을 복구했습니다)"
    fi
    die "훅을 설치할 수 없습니다"
  fi

  echo "kkochikkochi: 설치 완료 — $TARGET" >&2
}

cmd_uninstall() {
  is_ours "$TARGET" || die "우리 훅이 설치돼 있지 않습니다"
  if [ -f "$CHAINED" ]; then
    # 복구를 먼저(그리고 하나의 rename 으로) 한다 — 이 rename 이 실패해도
    # 우리 훅은 TARGET 에 그대로 남아 있다. 먼저 지우고 나중에 복구하면
    # 그 사이에 복구가 실패했을 때 저장소에 훅이 하나도 없는 상태로
    # 떨어진다.
    mv "$CHAINED" "$TARGET" || die "체이닝된 훅을 복구할 수 없습니다 — 우리 훅이 그대로 있습니다"
    echo "kkochikkochi: 기존 훅을 복구했습니다" >&2
  else
    rm -f "$TARGET" || die "훅을 지울 수 없습니다"
  fi
  echo "kkochikkochi: 제거 완료" >&2
}

case "${1:-install}" in
  install)   cmd_install ;;
  uninstall) cmd_uninstall ;;
  status)    cmd_status ;;
  *)         die "사용법: install.sh [install|uninstall|status]" ;;
esac
