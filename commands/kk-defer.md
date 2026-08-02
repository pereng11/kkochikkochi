---
description: 이번 턴은 서브에이전트 번들 퀴즈를 미루고 턴 끝에 몰아 받는다
---

유예 모드를 켠다. 큰 작업을 돌려놓고 나중에 확인할 때 쓴다.

```bash
bash "${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}/scripts/defer.sh" on
```

켜져 있는 동안 `PostToolUse` 훅(Claude Code 는 `Task`, Codex 는 `spawn_agent`)은 서브에이전트 번들 퀴즈를 요구하지 않는다. 원장은 계속 쌓이고, 턴을 마치려 할 때 `Stop` 훅이 붙잡아 몰아서 받는다.

유예는 **턴 끝까지**다. 영구 우회가 아니다 — `Stop` 은 유예와 무관하게 막고, `pre-push` 도 그대로 막는다.

해제하려면:

```bash
bash "${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}/scripts/defer.sh" off
```
