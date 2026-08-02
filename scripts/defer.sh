#!/usr/bin/env bash
# 유예 모드 — 구현 중에는 묻지 않고 턴 끝에 몰아 받는다.
#
# 사용법: defer.sh on|off|status
#
# 왜 파일인가: 훅의 timeout(기본 60초)은 시간이 지나면 훅을 죽여 판정을
# 잃는다. async + asyncTimeout 도 훅 실행을 미루는 것이지 사람의 답을
# 기다리는 것이 아니다. 그래서 유예를 훅 기능으로는 만들 수 없다. 파일이면
# 세션이 죽어도 살아남고, pre-push 가 마지막에 잡는다.
#
# 범위는 턴 끝까지다. Stop 훅은 유예와 무관하게 막고, 통과할 때 이 파일을
# 지운다 (scripts/stop-gate.sh). "영구히 묻지 않기"는 만들지 않는다 —
# 빠져나갈 문을 만들면 그 문이 기본 경로가 된다 (D06).
#
# uninstall 이 이 파일도 함께 지운다: scripts/install.sh 의 cmd_uninstall 은
# quiz-gate 디렉터리 전체를 rm -rf 하므로, defer 도 별도 정리 없이 사라진다.

set -uo pipefail

die() { echo "kkochikkochi: $1" >&2; exit 1; }

git rev-parse --git-common-dir >/dev/null 2>&1 || die "git 저장소가 아닙니다"
qdir="$(git rev-parse --git-common-dir)/quiz-gate"
flag="$qdir/defer"

case "${1:-status}" in
  on)
    mkdir -p "$qdir" || die "상태 디렉터리를 만들 수 없습니다"
    : > "$flag" || die "유예 상태를 켤 수 없습니다"
    echo "kkochikkochi: 유예 모드 — 이번 턴 동안 서브에이전트 번들 퀴즈를 내지 않습니다." >&2
    echo "  턴을 마치려 할 때 몰아서 받습니다. push 는 그때까지 막힙니다." >&2
    ;;
  off)
    rm -f "$flag" 2>/dev/null || :
    echo "kkochikkochi: 유예 모드를 해제했습니다." >&2
    ;;
  status)
    [ -e "$flag" ] && echo "on" || echo "off"
    ;;
  *)
    die "사용법: defer.sh [on|off|status]"
    ;;
esac
exit 0
