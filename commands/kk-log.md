---
description: 지금까지의 이해도 검증 기록을 보여준다
---

이 저장소의 KkochiKkochi 기록을 요약해서 보여줘라.

```bash
QDIR="$(git rev-parse --git-dir)/quiz-gate"
echo "=== 커버된 파일 수 ==="
[ -f "$QDIR/covered.tsv" ] && wc -l < "$QDIR/covered.tsv" || echo 0
echo "=== 검증 횟수 ==="
[ -d "$QDIR/passes" ] && find "$QDIR/passes" -name 'p-*.json' | wc -l || echo 0
echo "=== 최근 5건 ==="
[ -d "$QDIR/passes" ] && find "$QDIR/passes" -name 'p-*.json' | sort | tail -5
```

찾은 기록 파일들을 읽고 다음을 표로 정리해 보여줘라.

- 축별 1차 정답률 (`attempts == 1` 인 비율)
- `gave_up` 이 true 인 문항 수
- 가장 자주 틀린 축

기록이 없으면 아직 검증 이력이 없다고 알려줘라.
