---
description: 지금까지의 이해도 검증 기록을 보여준다
---

이 저장소의 KkochiKkochi 기록을 요약해서 보여줘라.

```bash
QDIR="$(git rev-parse --git-dir)/quiz-gate"
if [ ! -d "$QDIR/passes" ]; then
  echo "아직 검증 이력이 없습니다."
  exit 0
fi
echo "=== 검증된 파일 경로 수 (중복 제외) ==="
[ -f "$QDIR/covered.tsv" ] && cut -f2 "$QDIR/covered.tsv" | sort -u | wc -l || echo 0
echo "=== 검증 횟수 ==="
find "$QDIR/passes" -name 'p-*.json' | wc -l
echo "=== 최근 5건 ==="
find "$QDIR/passes" -name 'p-*.json' | sort | tail -5
```

모든 기록 파일(`passes/p-*.json`)을 읽고 다음을 표로 정리해 보여줘라.

- 축별 1차 정답률 (각 축에서 `attempts == 1 && gave_up == false` 인 비율)
- `gave_up` 이 true 인 문항 수
- 가장 자주 틀린 축 (오답(`attempts > 1 && gave_up == false`)이 많은 축)
