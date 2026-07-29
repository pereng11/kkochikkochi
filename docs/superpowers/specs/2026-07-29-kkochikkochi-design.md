# KkochiKkochi 설계 문서

작성일: 2026-07-29

> **KkochiKkochi** *(kko-chi-kko-chi)* — Korean, adv. *questioning in relentless, minute detail.*
> It won't let you commit code you can't explain.

---

## 1. 배경

코딩 에이전트로 작업하면 코드 생산 속도가 사람의 이해 속도를 앞지른다. 그 결과 **사람의 이해가 병목이자 리스크**가 된다. 이해하지 못한 코드가 저장소에 쌓이면 디버깅, 리뷰, 온보딩, 사고 대응이 전부 느려진다.

이 문제는 코드 품질 도구로 풀리지 않는다. 린터와 테스트는 코드를 검증하지만 **사람의 이해는 검증하지 않는다.** 필요한 것은 코드에 대한 게이트가 아니라 사람에 대한 게이트다.

## 2. 목표 / 비목표

**목표**

- 커밋 직전에 사람의 이해를 강제로 검증한다
- 이해를 증명하지 못하면 커밋을 **실제로 차단**한다
- 검증에 걸리는 시간은 오답 루프를 포함해 **3분 이내** (전형값 40~65초)
- 커밋 이외의 관문(PR, 배포 등)으로 확장 가능한 구조

**비목표**

- 코드 품질·보안·버그 검사 (기존 도구의 영역)
- 악의적 우회 방지 — 막으려는 상대는 **바쁜 사람의 관성**이지 공격자가 아니다
- 학습 커리큘럼·진도 관리

## 3. 선행 조사 결과

전수 조사 결과 동일 기능은 없다. 인접한 것들:

| 대상 | 성격 | 차이 |
|---|---|---|
| `learning-output-style` (Anthropic) | 결정 지점에서 사용자에게 코드 기여 요구 | 작업 *중*이고, 퀴즈가 아니라 코딩 요구 |
| `explanatory-output-style` (Anthropic) | 구현 선택 이유 해설 | 일방향, 게이트 없음 |
| `lesson-quiz` (luongnv89/claude-howto) | 10문항 퀴즈 + 채점 리포트 | 대상이 튜토리얼 강의 내용 |
| `vibe-guard-skills` / `/vibe-explain` | 이해도 패스 | 설명해주는 쪽. 사용자를 시험하지 않음 |

**"작업 종료 시점 + 실제 변경분 기반 + 통과해야 진행"** 세 조건을 동시에 만족하는 것은 없다.

## 4. 아키텍처

훅은 문지기, 스킬은 시험관. **판정 로직에 LLM을 두지 않는다.**

```
git commit ──▶ PreToolUse 훅 (순수 셸)
                 │ 커밋될 (경로, blob SHA) 집합을 covered.tsv 와 대조
                 ├─ 전부 커버 ──▶ allow, 커밋 진행 ✓
                 └─ 미커버 존재 ─▶ deny + "kkochikkochi 스킬 먼저 실행하라"
                                      │
                                 스킬 (LLM)
                                 staged diff + 대화 맥락 + 레포 컨텍스트
                                 → 출제 → 채점 → 오답 루프
                                      │ 통과
                                 record-pass.sh
                                      ▼
                                 커밋 재시도 ─▶ allow ✓
```

**이 구조를 택한 이유**

- 훅이 단순해 결정적으로 테스트된다. 게이트가 오작동하면 도구 전체가 버려지므로 이 성질이 가장 중요하다
- 스킬은 **대화 맥락에 접근할 수 있다.** "왜 이 설계를 택했는가"는 diff에 없고 대화에만 있으므로, 훅 안에서 LLM을 돌리는 대안은 4축 중 2축을 원천적으로 포기하게 된다

## 5. 통과 토큰

### 5.1 저장 위치와 구조

```
$(git rev-parse --git-dir)/quiz-gate/
├── covered.tsv          검증 전용. 자유 텍스트 없음
│     <40자 blob SHA>\t<경로>\t<pass_id>
└── passes/
      p-20260729-1403.json    문답 전문 1건 = 파일 1개
```

`.git/` 안에 두는 이유: 절대 커밋되지 않고, 레포 단위로 자동 격리되며, `git worktree`에서 `--git-dir`이 `.git/worktrees/<name>`을 가리키므로 워크트리별 격리가 공짜로 따라온다. `.claude/`는 추적되는 경우가 많아 토큰이 커밋에 섞인다.

**검증용과 감사용을 분리하는 이유는 성능이 아니라 정합성이다.** 문답 전문에는 SHA 문자열이 인용될 수 있고(문항이 커밋 해시를 언급하는 경우), 검증 파일에 자유 텍스트가 섞이면 엉뚱한 필드 매치로 **조용한 오통과**가 발생한다. 검증 파일에서 자유 텍스트를 제거하면 이 실패 모드가 구조적으로 불가능해진다.

### 5.2 무엇에 묶이는가

`covered.tsv`의 키는 **git blob SHA** — 파일 내용물의 지문이다. 두 성질만 쓴다:

- 내용이 같으면 SHA가 같다 (경로·시각·커밋 무관)
- 1바이트만 달라도 SHA가 완전히 다르다

git이 이미 완성된 형태로 제공한다:

```sh
git diff --cached --raw --abbrev=40 --no-renames | awk '{print $4"\t"$6}'
#   $4 = new blob SHA (삭제 시 40자리 0 — git 기본 동작)
#   $6 = 경로
```

- `--abbrev=40` 필수 — 기본 7자리 축약은 큰 레포에서 모호하다
- `--no-renames` 필수 — rename 감지가 켜지면 `R100` 상태에서 경로가 두 개 나와 컬럼이 밀린다

### 5.3 검증 규칙

> **커밋될 모든 `(경로, blob SHA)` 쌍이 `covered.tsv`의 합집합 안에 있는가.**

전부 있으면 allow, 하나라도 없으면 deny. 훅이 하는 일은 이것뿐이다.

### 5.4 파일 단위 맵을 쓰는 이유

diff 전체를 통째로 해싱하면 단순하지만 분할 커밋이 매번 재퀴즈된다. 파일 단위 blob SHA 맵이면 다음이 자연스럽게 통과한다:

```
퀴즈 1회 통과   covered = { a.ts: 0b0901b, b.ts: 3cfff03 }
a.ts 만 커밋    HEAD 이동
b.ts 커밋 시도  b.ts -> 3cfff03  →  covered 안에 있음  →  allow (재퀴즈 없음)
```

정확도 손실은 없다. a.ts를 한 글자라도 고치면 SHA가 바뀌어 **a.ts만** 무효화되고 b.ts는 영향받지 않는다.

### 5.5 무효화 정책

| 사건 | 상태 | 근거 |
|---|---|---|
| 커버된 파일 재편집 | 그 파일만 무효 | blob SHA 변경 |
| 커밋 성공, HEAD 이동 | **유효 유지** | 무효화하면 분할 커밋이 깨짐. `head`는 감사 기록용 |
| 세션 종료 | 유효 유지 | v1은 TTL 없음 |
| 브랜치 전환 / `reset --hard` / `restore` | 자동 처리 | 내용이 바뀌면 SHA가 바뀌므로 별도 로직 불필요 |

부수 성질: revert 후 다시 되돌리면 내용물이 원래 SHA로 복귀하므로 **토큰이 되살아난다.** 같은 코드를 두 번 묻지 않는다.

### 5.6 보존 정책

v1에서는 아무것도 하지 않는다. `covered.tsv`는 한 줄 약 60바이트이므로 1만 줄이라도 600KB이고, 앵커된 grep으로 단일 ms 안에 끝난다. 커지면 90일 이전 라인을 제거하는 트림 명령을 나중에 추가한다.

## 6. 트리거 정책

| 명령 | 처리 | 근거 |
|---|---|---|
| `git commit` | **게이트** | 새 내용물 |
| `git commit --amend` (내용 추가) | **게이트** | 새 내용물 |
| `git commit --amend` (메시지만) | 통과 | `git diff --cached`가 비어 있음 |
| `git revert` | 통과 + 로그 | 비상 레버. 게이트가 롤백을 늦추면 사고를 키운다 |
| `git cherry-pick` / `git merge` | 통과 | 남의 커밋 |
| `git reset --hard` / `restore` / `checkout .` | 무관 | 커밋을 만들지 않음 |

**amend는 특수 코드가 필요 없다.** `git diff --cached`가 HEAD 대비 새로 스테이징된 델타만 주므로, 메시지만 수정하면 자동으로 빈 집합이 되어 통과하고, 내용을 얹으면 그 델타만 퀴즈 대상이 된다. HEAD에 이미 들어간 내용은 커밋될 때 한 번 통과했으므로 다시 묻지 않는 것이 옳다.

`git revert`는 `git commit`을 거치지 않고 자체적으로 커밋을 만든다. 매처가 `git commit`만 보면 자연히 통과하므로 별도 처리가 필요 없다.

### 6.1 알려진 구멍

- Bash를 거치지 않는 커밋 경로(git MCP 도구, IDE 커밋 버튼)는 훅을 타지 않는다. v1에서는 문서에만 명시한다

## 7. 문항 생성

### 7.1 축별 재료

축마다 정답의 근거가 다른 곳에 있으므로, 하나의 생성기로 뭉뚱그리지 않는다.

| 축 | 근거 위치 | 형식 | 채점 |
|---|---|---|---|
| 변경 사실 확인 | staged diff | 객관식 | 결정적 — diff 대조 |
| 영향·리스크 | diff + 레포 grep (호출부·의존) | 객관식 | 결정적 — 참조 실재 여부 |
| 재현 가능성 | 레포 구조 | 짧은 답 (파일명/심볼명) | 기계적 — 존재 확인 |
| 설계 의도 | **대화 맥락** | 서술 (한 문장) | LLM 판정 |

### 7.2 문항 예산

- **상한 5문항.** 억지로 채우지 않는다 — 근거 있는 문항만 낸다. 상한은 큰 변경에서만 닿는다
- **하한 1문항.** 예외적으로, 질문할 거리가 전혀 없으면(lockfile 재생성, 포매팅만) **0문항 + 사유 기록** 후 통과한다. `package-lock.json`에 퀴즈를 내면 도구가 웃음거리가 된다
- 서술형은 **조건부** — 대화 맥락에 명확한 설계 결정이 있을 때만. 단순 버그 수정이면 내지 않는다
- **시간 목표 3분.** 상한 5문항에 오답 루프까지 포함한 전체 목표다

소요 시간 근거는 객관식 약 20초, 짧은 답 약 20초, 서술 한 문장 약 25초.

| | 문항 수 | 소요 |
|---|---|---|
| 전형값 | 2~3 | 약 40~65초 |
| 상한, 전부 정답 | 5 | 약 100초 |
| 상한, 오답 루프 포함 | 5 + 재출제 | 3분 |

3분을 넘는다면 문항이 과하거나 변경 규모가 지나치게 크다는 신호다. v1에서는 강제로 중단하지 않고 목표로만 둔다.

### 7.3 축 우선순위와 출제 순서

| 순위 | 축 | 형식 | 생략 조건 |
|---|---|---|---|
| 1 | 변경 사실 확인 | 객관식 | 거의 없음 (diff가 있으면 항상 가능) |
| 2 | 영향·리스크 | 객관식 | 호출부·의존이 전혀 없는 고립된 변경 |
| 3 | 설계 의도 | 서술 (한 문장) | 대화에 명확한 설계 결정이 없을 때 |
| 4 | 재현 가능성 | 짧은 답 | 레포 구조상 물을 지점이 없을 때 |

**상한 5는 4축을 전부 담고도 한 자리가 남는다.** 남는 자리는 우선순위 2(영향·리스크)에 배정한다. 리스크에 가장 직결되는 축이고, 변경이 클수록 파급 지점이 여러 곳이라 한 문항으로 부족해지는 축이기 때문이다.

**출제 순서는 우선순위 순이되, 서술형은 항상 마지막에 놓는다.** 앞선 객관식이 변경 내용을 상기시켜 서술 답변의 질이 올라가기 때문이다. 백지 상태에서 서술을 요구하면 "잘 기억 안 나는데"로 시작한다.

전형적인 조합:

```
고립된 소규모 변경      1
단순 버그 수정          1 → 2 → 4
설계 결정이 있는 작업    1 → 2 → 4 → 3(서술, 마지막)
대규모 변경 (상한)      1 → 2 → 2' → 4 → 3(서술, 마지막)
```

### 7.4 오답 선택지 규칙

LLM이 자기가 쓴 코드에 문제를 내면 오답이 너무 티가 나서, 코드를 읽지 않고 소거법으로 통과할 수 있다. **이 실패가 발생하면 게이트가 무력화된다.**

1. 오답은 "그럴듯한 오해"에서 뽑는다 — 이전 버전의 실제 동작, 인접 함수가 실제로 하는 일
2. 오답은 **레포에서 실제 문자열을 길어 올린다** — 실존하는 다른 경로·함수명. 지어낸 이름 금지
3. **금지 선택지** — "변함 없음", "위 전부", "해당 없음", "모름"
4. 정답 위치를 무작위화한다 (LLM은 B·C 편향이 있다)

### 7.5 교착 방지 — 근거 없는 문항은 폐기

하드 게이트 + 통과할 때까지 조합에서 **가장 치명적인 실패는 LLM이 낸 정답이 틀린 것**이다. 사용자가 맞는 답을 하는데 계속 오답 처리되면 탈출구도 소용없이 갇힌다.

> 모든 문항은 정답 근거를 `파일:줄` 또는 `대화 내 발언`으로 특정할 수 있어야 한다. 특정하지 못하면 출제 전 폐기한다.

근거는 문항과 함께 `passes/*.json`에 기록한다.

### 7.6 오답 / "모르겠다" 루프

```
오답        → 해설(코드 인용 필수) → 같은 축, 다른 각도로 재출제
"모르겠다"  → 해당 지점을 실제 코드 인용해 설명 → 확인 → 다른 각도로 재출제
```

**같은 문항 반복 금지.** 반복하면 코드를 이해해서가 아니라 정답을 외워서 통과한다. 게이트의 목적이 정확히 무너지는 지점이다.

두 경로 모두 `attempts`를 올리고 `gave_up`을 기록한다.

### 7.7 기록 스키마

```json
{
  "v": 1,
  "at": "2026-07-29T14:03:11Z",
  "session": "...",
  "head": "a1b2c3d4",
  "covered": { "src/auth/middleware.ts": "9f2b1c8e..." },
  "transcript": [
    { "axis": "impact", "q": "...", "evidence": "src/auth/middleware.ts:42",
      "answer": "B", "correct": "B", "attempts": 1, "gave_up": false }
  ]
}
```

`axis` / `attempts` / `gave_up`은 v1에서 쓰이지 않지만 처음부터 기록한다. 나중에 축별 취약도 리포트를 만들 때의 재료이며, 나중에 추가하면 과거 데이터가 없다.

## 8. 플러그인 구조

널리 쓰이는 플러그인 저장소(`superpowers`, `security-guidance`, `ralph-loop`, `caveman`)의 구조를 조사해 관례를 따른다.

```
kkochikkochi/
├── .claude-plugin/plugin.json
├── hooks/
│   ├── hooks.json                   PreToolUse 등록
│   └── gate.sh                      훅 진입점. 판정만, LLM 없음
├── scripts/
│   ├── pending-set.sh               "커밋될 (SHA, 경로)" 계산  ← 훅·스킬 공용
│   └── record-pass.sh               통과 기록. 스킬이 호출
├── skills/kkochikkochi/SKILL.md     유일한 LLM 컴포넌트
├── commands/{kk,kk-log}.md
├── tests/
│   ├── fixtures/                    픽스처 레포 생성 스크립트
│   ├── pending-set.bats
│   ├── gate.bats
│   └── record-pass.bats
├── .github/workflows/ci.yml         bats 실행 + shellcheck
├── docs/
│   ├── DECISIONS.md
│   └── superpowers/specs/
├── README.md                        어원 + 설치 + 동작 원리
├── CHANGELOG.md
├── CONTRIBUTING.md
├── LICENSE                          MIT
├── .gitignore
└── .editorconfig
```

명명 규약: 식별자는 소문자 `kkochikkochi`, 표시명은 `KkochiKkochi`. 플러그인 이름이 커맨드 앞에 붙으므로 커맨드는 짧게 (`/kk`, `/kk-log`).

### 8.1 `hooks/` 와 `scripts/` 의 구분

조사한 플러그인들의 관례가 갈린다.

| 플러그인 | 방식 |
|---|---|
| `ralph-loop` | `hooks/stop-hook.sh`(훅 진입점) + `scripts/setup-*.sh`(사용자 유틸) |
| `security-guidance` | 훅 관련 코드 전부 `hooks/` (`gitutil.py`, `diffstate.py` 등) |
| `superpowers` | 둘 다 사용 |

우리는 **호출 주체**로 나눈다. `gate.sh`는 훅만 호출하므로 `hooks/`, `pending-set.sh`와 `record-pass.sh`는 스킬도 호출하므로 `scripts/`. 디렉터리가 의존 방향을 드러낸다.

### 8.2 단일 저장소 = 플러그인 배포물

`caveman`은 TypeScript 모노레포에서 `plugins/caveman/`로 산출물을 동기화하는 CI를 둔다. 컴파일 산출물이 있기 때문이다.

**우리는 빌드 단계가 없다** — 셸 스크립트와 마크다운이 그대로 배포물이다. 저장소 루트가 곧 플러그인 루트이며, 동기화 CI를 두지 않는다. 소스와 배포물이 갈라질 여지를 만들지 않는 편이 낫다.

### 8.3 `plugin.json`

`superpowers`가 가장 완전한 필드 집합을 쓴다. 이를 따른다.

```json
{
  "name": "kkochikkochi",
  "version": "0.1.0",
  "description": "A comprehension gate for AI-assisted coding. Blocks the commit until you can explain what changed.",
  "author": { "name": "...", "email": "..." },
  "homepage": "https://github.com/<owner>/kkochikkochi",
  "repository": "https://github.com/<owner>/kkochikkochi",
  "license": "MIT",
  "keywords": ["gate", "comprehension", "quiz", "review", "git", "commit"]
}
```

### 8.4 `hooks/hooks.json`

```json
{
  "description": "Comprehension gate before commit.",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/gate.sh\"",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

경로는 반드시 `${CLAUDE_PLUGIN_ROOT}`를 쓴다 — 조사한 플러그인 전부가 이 규약을 따른다. `timeout`은 짧게 잡는다. 게이트는 해시 비교뿐이라 10초면 충분하고, 길게 잡으면 훅이 멈췄을 때 사용자가 오래 붙잡힌다.

## 9. 인터페이스 계약

### `pending-set.sh`

훅과 스킬이 **같은 파일 집합을 보게 하는** 유일한 장치. 이 정의가 두 군데로 갈라지면 서로 다른 집합을 보게 되어 영원히 통과하지 못하는 교착이 난다.

```
입력   원본 커맨드 문자열 ( -a / pathspec 파싱용 )
출력   stdout: <40자 SHA>\t<경로>
종료   0 = 정상 · 2 = 게이트 무관(레포 아님, 커밋 아님)
```

`-a` / `--all` 또는 pathspec이 있으면 index가 아니라 **워크트리 파일을 `git hash-object`로 직접 해싱**해야 한다. `-a`는 훅 실행 *후에* 스테이징하므로 index만 보면 헛것을 본다.

### `gate.sh`

```
입력   stdin JSON (훅 프로토콜) → tool_input.command
처리   git commit 매칭 → pending-set.sh → covered.tsv 대조
출력   {"hookSpecificOutput":{"permissionDecision":"deny",
                              "permissionDecisionReason":"..."}}
금지   LLM 호출 · 파일 수정 · git 상태 변경
```

매처는 넓게 잡는다 (`git -C <path> commit`, `cd x && git commit` 포함). 애매하면 deny 쪽으로 기운다.

**훅 설정의 `if` 필드를 쓰지 않는 이유** — 훅 항목에는 `"if": "Bash(git commit:*)"` 같은 세밀한 매처가 있고 `security-guidance`가 실제로 이를 사용한다. 그러나 이 문법은 접두 매칭이라 `cd sub && git commit`이나 `git -C path commit`을 놓친다. 게이트에서는 누락이 곧 실패이므로, `matcher: "Bash"`로 넓게 받고 `gate.sh` 안에서 직접 파싱한다. 파싱 비용은 무시할 수준이고, 놓친 커밋은 되돌릴 수 없다.

### `record-pass.sh`

```
입력   stdin: 문답 transcript JSON
처리   pending-set.sh 를 스스로 재호출해 SHA 계산
       ← 에이전트가 건네준 SHA를 신뢰하지 않음
출력   covered.tsv 추가 + passes/<id>.json
거부   문항 0개 · 서술형 답변 공백
```

## 10. 신뢰 경계

에이전트는 퀴즈를 건너뛰고 `record-pass.sh`를 호출할 수 있다. **이것은 보안 경계가 아니라 규율 장치다.** 방어선은 둘뿐이다:

1. `record-pass.sh`는 문항 0개나 공백 서술 답변을 거부한다
2. 문답 전문이 `passes/`에 남아 사후 확인이 가능하다

막으려는 상대가 공격자가 아니라 관성이므로 이 정도로 충분하다. 더 조이려면 훅 안에서 LLM을 돌려야 하고, 그러면 대화 맥락을 잃어 4축 중 2축이 사라진다.

## 11. 오류 처리 — fail-open

게이트에 문제가 생기면 **통과시킨다.**

| 상황 | 동작 |
|---|---|
| git 없음 / 레포 아님 | no-op 통과 |
| `pending-set.sh` 실패 | 통과 + stderr 경고 |
| `covered.tsv` 일부 손상 | 파싱 가능한 라인만으로 판정 |
| 퀴즈 중 사용자 중단 | 기록 없음 → 다음 커밋에서 다시 물음 |

근거: 하드 게이트에서 fail-closed는 **버그 하나가 레포를 벽돌로 만든다.** 사용자가 커밋을 못 해 플러그인을 삭제하는 것이, 게이트가 한 번 새는 것보다 큰 손해다.

## 12. 테스트 전략

**셸 3종은 픽스처 레포로 완전 자동화한다.** 판정 로직에 LLM이 없다는 것의 실질적 배당금이다.

```
pending-set.sh   수정 / 신규 / 삭제 / rename / -a / pathspec /
                 --amend / 빈 diff / 레포 아님
gate.sh          covered.tsv 픽스처 × pending 조합 → allow/deny 판정표
                 + 커맨드 파싱 (cd x && git commit, git -C path commit)
record-pass.sh   거부 조건(빈 문항, 공백 서술)
```

`bats`로 작성해 `tests/`에 둔다. CI(`.github/workflows/ci.yml`)에서 `bats` 실행과 `shellcheck`를 함께 돌린다. 픽스처 레포는 `tests/fixtures/`의 생성 스크립트로 매번 새로 만든다 — 커밋된 `.git` 디렉터리를 저장소에 넣지 않는다.

**SKILL.md는 자동 테스트가 어렵다.** 문항 품질("오답이 그럴듯한가")은 기계로 측정되지 않는다. `superpowers/skills/writing-skills/testing-skills-with-subagents.md` 방식으로, 서브에이전트에게 실제 diff를 주고 출제시킨 뒤 문항을 사람이 평가하는 루프로 간다.

## 13. v1 범위 밖

- **TTL** — `at` 필드는 기록해두므로 나중에 추가 가능
- **`covered.tsv` 자동 트림**
- **축별 취약도 리포트** — 데이터는 쌓이지만 집계 기능은 만들지 않는다
- **커밋 외 관문**(PR, 배포) — 이름과 구조는 확장 가능하게 두되 구현하지 않는다

## 14. 결정 기록

결정의 전체 목록과 근거, 기각된 대안, 번복 이력은 별도 문서에서 관리한다.

→ [`docs/DECISIONS.md`](../../DECISIONS.md)

이 문서는 **무엇을 만드는가**를 기술하고, 결정 로그는 **왜 그렇게 정했고 무엇을 버렸는가**를 기록한다. 중복 기술은 표류를 낳으므로 결정의 근거는 로그를 단일 출처로 삼는다.
