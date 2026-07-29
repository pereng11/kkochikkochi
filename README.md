# KkochiKkochi 🦡

> **KkochiKkochi** *(kko-chi-kko-chi)* — Korean, adv. *questioning in relentless, minute detail.*
> It won't let you commit code you can't explain.

AI 코딩 에이전트는 사람이 읽는 속도보다 빠르게 코드를 만든다. 그래서 **사람의 이해가 병목이자 리스크**가 된다. 린터와 테스트는 코드를 검증하지만 사람의 이해는 검증하지 않는다.

KkochiKkochi 는 커밋 직전에 당신이 방금 무엇을 바꿨는지 묻는다. 답하지 못하면 커밋이 막힌다.

## 동작

```
$ git commit -m "add auth middleware"

🦡 KkochiKkochi — 미검증 변경이 있습니다.

   src/auth/middleware.ts
   src/lib/session.ts

   이 변경을 이해했는지 먼저 확인해야 합니다.

Q1. 이 변경으로 auth 미들웨어가 통과시키는 경로는?
    A) /api/* 전체
    B) /api/public/* 을 제외한 전체
    C) 정적 에셋만
    D) 모르겠다

→ B  ✓

Q2. 세션 저장소를 Redis 대신 JWT 로 간 이유를 한 문장으로 적으세요.
→ ...

통과했습니다. 다시 커밋하세요.
```

## 설치

```
/plugin marketplace add <owner>/kkochikkochi
/plugin install kkochikkochi
```

필요 도구: `git`, `jq`

## 무엇을 묻는가

| 축 | 예시 |
|---|---|
| 변경 사실 | 어떤 파일의 무엇이 바뀌었나 |
| 영향·리스크 | 이 변경으로 무엇이 깨질 수 있나 |
| 설계 의도 | 왜 이 방식을 골랐고 무엇을 버렸나 |
| 재현 가능성 | X 를 바꾸려면 어디를 건드려야 하나 |

문항은 최대 5개. 원칙적으로 최소 1개이며, 질문거리가 전혀 없는 경우(예: lockfile 재생성, 포매팅만)에 한해 예외적으로 0개 + 사유 기록으로 통과시킨다. 목표 3분 — 한 번에 다 맞히는 경우만이 아니라 오답 재시도 루프까지 포함한 시간이다. 근거를 코드나 대화에서 특정할 수 없는 문항은 출제되지 않는다.

## 언제 막지 않는가

- `git revert`, `git cherry-pick`, `git merge` — 이들은 자체적으로 커밋을 만들고 `git commit` 커맨드를 거치지 않는다. 게이트는 `git commit` 호출만 가로채므로 원래부터 대상이 아니다. revert 는 특히 롤백이라는 비상 레버라, 걸었다면 사고를 키웠을 것이다
- 위 작업이 충돌해 사용자가 직접 `git commit` 으로 마무리할 때 — 진행 중인 merge/cherry-pick/revert/rebase 마커(`MERGE_HEAD` 등)가 있으면 그 커밋도 대상에서 제외한다
- `git commit --amend` 로 **메시지만** 고칠 때 — 워크트리 내용이 HEAD 와 같아 커밋될 변경분이 없기 때문이다. **내용을 더 얹는 amend 는 그 추가분만큼 게이트 대상이다** — 검증 없이 슬쩍 끼워 넣는 경로를 막기 위해서다
- 게이트 자체에 문제가 생겼을 때 (fail-open)

## 어떻게 기억하는가

파일 내용의 blob SHA 를 `.git/quiz-gate/covered.tsv` 에 `(SHA, 경로, pass_id)` 형태로 기록한다. 파일을 한 글자라도 고치면 SHA 가 바뀌어 그 파일만 다시 물어본다. 한 번 통과한 변경은 여러 커밋으로 나눠 올려도 다시 묻지 않는다.

문답 전문은 `.git/quiz-gate/passes/<pass_id>.json` 에 1건 1파일로 남는다 — 검증에는 쓰이지 않고 감사 기록용이다.

기록은 `.git/` 안에만 있고 절대 커밋되지 않는다.

## 명령

| 명령 | 설명 |
|---|---|
| `/kk` | 지금 스테이징된 변경으로 퀴즈를 받는다 |
| `/kk-log` | 지금까지의 검증 기록과 취약한 축을 본다 |

## 한계

- Bash 를 거치지 않는 커밋(IDE 커밋 버튼, git MCP 도구)은 훅을 타지 않는다
- 에이전트가 퀴즈를 건너뛰고 통과를 기록할 수 있다. 이것은 보안 경계가 아니라 규율 장치다
- `covered.tsv` 와 `passes/*.json` 은 커밋마다 계속 쌓이고 자동으로 정리되지 않는다. v1 범위에서 의도적으로 뺀 기능이다([docs/DECISIONS.md](docs/DECISIONS.md) D18)

설계 근거는 [docs/DECISIONS.md](docs/DECISIONS.md) 참조.

## License

MIT
