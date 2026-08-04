[![CI](https://github.com/pereng11/kkochikkochi/actions/workflows/ci.yml/badge.svg)](https://github.com/pereng11/kkochikkochi/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Claude Code · Codex](https://img.shields.io/badge/Claude%20Code-%C2%B7%20Codex-black)

[English](README.md) • **한국어**

# KkochiKkochi 🦡

> **꼬치꼬치** — 부사. *낱낱이 따지고 캐어묻는 모양.*

에이전트는 순식간에 수백 줄의 코드를 작성합니다.
사람은 그 모든 맥락을 따라가기 어렵습니다.
이제 개발의 병목은 코드를 만드는 속도가 아니라, 사람이 이해하는 속도입니다.

그래서 우리는 코드를 이해하기보다, 일단 넘겨버립니다.

그 순간은 빨라질지 몰라도,
책임은 결국 미래의 나에게 돌아옵니다.

'꼬치꼬치'는 커밋 전에 묻습니다.
**"무엇을, 왜 바꿨나요?"**

설명하지 못하는 변경은, 커밋할 수 없습니다.

Claude Code와 Codex를 지원합니다. 이 문서는 [영어판](README.md)과 나란히 관리합니다.
둘이 어긋나면 영어판이 정본입니다.

## 동작

에이전트가 커밋을 시도하면 게이트가 먼저 멈춥니다. 이어지는 퀴즈를 통과해야 커밋할 수 있습니다.

아래는 실제 게이트 출력입니다. 퀴즈는 예시이고 실제 문항은 변경마다 새로 만듭니다.

```
$ git commit -m "add auth middleware"

🦡 KkochiKkochi — 이 커밋에 아직 검증되지 않은 변경이 있습니다.

   src/auth/middleware.ts
   src/lib/session.ts

이 변경을 이해했는지 먼저 확인해야 합니다.
kkochikkochi 스킬을 실행해 퀴즈를 통과한 뒤 다시 커밋하세요.
(판별 신호: handshake:claude-code)

Q1. 이 변경으로 auth 미들웨어가 통과시키는 경로는?
    A) /api/* 전체
    B) /api/public/*을 제외한 전체
    C) 정적 에셋만
    D) 모르겠다

→ B  ✓

Q2. 세션 저장소를 Redis 대신 JWT로 간 이유를 한 문장으로 적으세요.
→ ...

통과했습니다. 다시 커밋하세요.
```

Claude Code는 객관식을 `AskUserQuestion`으로 띄우고 사용자는 클릭해서 답합니다. Codex에는 같은 UI가 없어 평문으로 나오고 직접 입력해 답합니다. 문항 내용, 채점, 오답 재시도는 두 에이전트에서 동일합니다.

아직은 한국어만 지원합니다. 훅 메시지도 문항 생성 스킬도 한국어를 기준으로 만들었기 때문입니다. 다국어는 계획에 있습니다.

## 설치

**Claude Code**
```
/plugin marketplace add pereng11/kkochikkochi
/plugin install kkochikkochi
```
**Codex**
```
codex plugin marketplace add pereng11/kkochikkochi
codex plugin add kkochikkochi@kkochikkochi
```

git 훅은 `.git/hooks/`에 들어갑니다. 이 디렉터리는 Git이 추적하지 않기 때문에 저장소마다 따로 설치해야 하며 `git clone`으로도 함께 오지 않습니다.

그래서 새 저장소를 clone하면 게이트 없이 시작합니다. 하지만 대부분은 직접 설치할 필요가 없습니다.

에이전트가 처음 커밋을 시도하면 에이전트 훅이 git 훅의 부재(또는 버전 불일치)를 감지해 커밋을 멈추고 그대로 실행할 수 있는 설치 명령을 에이전트에게 전달합니다. 설치가 끝나면 다시 커밋하면 됩니다.

예외는 `core.hooksPath`를 사용하는 저장소입니다. 이 경우 실제 훅 디렉터리는 저장소 안에서 Git이 추적하므로 에이전트가 임의로 수정하지 않고 사용자에게 먼저 확인을 요청합니다([D32](docs/DECISIONS.md)).

수동으로 설치하려면 게이트를 걸 저장소에서 `bash <플러그인 디렉터리>/scripts/install.sh install` · `uninstall` · `status`를 실행하세요.

`status`의 종료 코드는 다음과 같습니다.

- `0`: 설치됨(최신)
- `1`: 미설치
- `2`: `core.hooksPath` 저장소라 설치 거부
- `3`: 우리 훅이지만 버전이 오래됨

`3`인 경우 `install`을 다시 실행하면 됩니다.

기존 `pre-commit` 훅이 있으면 덮어쓰지 않고 체이닝합니다. 기존 훅을 먼저 실행하고 0이 아닌 종료 코드가 나오면 그 결과를 그대로 반환합니다([D31](docs/DECISIONS.md)).

커밋 시점의 게이트는 에이전트가 커밋하려는 내용만 읽습니다. 사람이 직접 친 커밋에는 손대지 않습니다([D33](docs/DECISIONS.md), [D41](docs/DECISIONS.md)). `pre-push`는 다릅니다 — 커밋을 누가 썼는지 사후에 알아낼 방법이 없어서 사람이 친 커밋도 다시 검사합니다([D47](docs/DECISIONS.md)).

필요한 도구는 `git`과 `jq`입니다. [im-not-ai](https://github.com/epoko77-ai/im-not-ai)의 `humanize-korean` 스킬은 선택입니다 — 문항 문장을 다듬어 주지만 없어도 게이트는 그대로 동작합니다([D46](docs/DECISIONS.md)). 이 설치를 에이전트에게 맡기실 거라면 [AGENTS.md](AGENTS.md)를 보세요.

## 무엇을 막고 무엇을 막지 않는가

| 이 커밋은... | 게이트 |
|---|---|
| Claude Code나 Codex가 만든 커밋 | **켜짐.** 이 도구가 존재하는 이유입니다. |
| 사람이 터미널이나 IDE에서 직접 친 커밋 | **꺼짐.** 의도한 동작입니다 — 그 사람은 거기 있었고 이해가 병목이 아닙니다([D41](docs/DECISIONS.md), [D44](docs/DECISIONS.md)). |
| `git revert` · `cherry-pick` · `merge` | **커밋 시점에는 꺼짐.** git이 이 명령들에서 `pre-commit`을 아예 호출하지 않습니다(측정 확인). 병합 커밋이 새로 만든 내용은 `pre-push`가 다시 봅니다([D13](docs/DECISIONS.md), [D47](docs/DECISIONS.md)). |
| `git commit --no-verify` (짧게 `-n`) | **우회 가능.** 에이전트 훅이 거부를 시도합니다 — 최선 노력일 뿐 보장이 아닙니다([D29](docs/DECISIONS.md)). |

`git push --no-verify`도 사정이 같습니다. 에이전트 훅이 `push`도 같이 보고 거부를 시도하지만 역시 최선 노력일 뿐 보장이 아닙니다. 이 판정은 명령에 `git`이나 `g` 토큰이 있을 때만 들어갑니다. 그래서 다른 별칭으로 곁들인 `--no-verify`는 잡지 못합니다. 핸드셰이크를 남기는 프리필터도 여전히 `commit`만 봅니다([D29](docs/DECISIONS.md), [D44](docs/DECISIONS.md)). 위 목록에 없는 에이전트가 만든 커밋은 애매한 경우로 칩니다. 애매한 경우는 통과시킵니다([D35](docs/DECISIONS.md)).

충돌한 merge·cherry-pick·revert·rebase를 마무리하려고 직접 치는 `git commit`도 게이트가 건드리지 않습니다 — 진행 중 마커(`MERGE_HEAD`, `CHERRY_PICK_HEAD`, `REVERT_HEAD`, rebase 디렉터리)가 보이면 비켜섭니다. `git commit --amend` 에는 따로 규칙을 두지 않았습니다 — 메시지만 고치는 amend는 새로 스테이징할 변경분이 없어 그냥 통과합니다. 내용을 더 얹는 amend는 그 추가분만큼 게이트 대상입니다([D12](docs/DECISIONS.md)).

## 무엇을 묻는가

| 축 | 예시 |
|---|---|
| 변경 사실 | 어떤 파일의 무엇이 바뀌었나요 |
| 영향·리스크 | 이 변경으로 무엇이 깨질 수 있나요 |
| 설계 의도 | 왜 이 방식을 골랐고 무엇을 버렸나요 |
| 재현 가능성 | X를 바꾸려면 어디를 건드려야 하나요 |

문항은 최대 5개입니다. 원칙적으로는 최소 1개입니다. 질문할 만한 내용이 전혀 없으면(예: lockfile 재생성, 포매팅만) 예외로 0개와 함께 사유를 기록하고 통과시킵니다.

목표 시간은 3분입니다. 한 번에 모두 맞히는 경우뿐 아니라 오답 재시도까지 포함한 시간입니다.

코드나 대화에서 근거를 찾을 수 없는 질문은 만들지 않습니다([D14](docs/DECISIONS.md), [D17](docs/DECISIONS.md), [D19](docs/DECISIONS.md)).

## 동작 원리

훅은 두 개지만 실제 게이트는 하나입니다.

에이전트 훅(`PreToolUse`)은 두 가지 일을 합니다.

- `git` 명령 중 `commit`이나 `push`에서 `--no-verify`(`-n`) 사용을 감지하면 거부를 시도합니다.
- `commit` 명령일 때만 핸드셰이크를 남기고 이 저장소에 git 훅이 있는지와 버전이 최신인지 확인합니다.

둘 다 게이트는 아닙니다. 에이전트 훅이 무언가를 놓치더라도 마지막 판단은 git의 `pre-commit`이 합니다.

`pre-commit`은 git이 직접 호출하므로 `git diff --cached`가 곧 실제 커밋될 변경입니다. 커맨드 문자열을 따로 해석할 필요가 없습니다([D28](docs/DECISIONS.md), [D30](docs/DECISIONS.md), [D44](docs/DECISIONS.md)).

| 트리거 | 하는 일 |
|---|---|
| `SubagentStart` / `SubagentStop` | 번들을 열고 봉인합니다 (`agents/<hash>`) |
| `PostToolUse` (Claude Code `Task`, Codex `spawn_agent`) | 봉인된 번들의 검증을 부모 에이전트에게 요구합니다 |
| `Stop` | 미검증이 남은 채로 턴이 끝나는 것을 막습니다 |
| git `pre-push` | 최종 경계 — `Stop`은 Esc로 빠져나갈 수 있습니다 |

서브에이전트는 사람에게 질문할 수 없습니다. 그래서 `pre-commit`에서 막으면 그 자리에서는 퀴즈를 풀 방법이 없습니다.

대신 변경을 원장에 기록해 두고 부모 에이전트에게 돌아온 뒤 검증을 강제합니다.

게이트가 남기는 기록은 전부 `.git/` 안에만 있고 절대 커밋되지 않습니다([D08](docs/DECISIONS.md), [D11](docs/DECISIONS.md)).

## 명령

| 명령 | 설명 |
|---|---|
| `/kk` | 지금 스테이징된 변경으로 퀴즈를 받습니다 |
| `/kk-log` | 지금까지의 검증 기록과 취약한 축을 봅니다 |
| `/kk-defer` | 이번 턴은 서브에이전트 번들 퀴즈를 미루고 턴 끝에 몰아 받습니다 — 턴 끝까지만, 영구 우회가 아닙니다 |

## 한계

v2와 v3 마이그레이션 중 실측으로 확인한 것들입니다. 추측이 아닙니다. 근거는 하나하나
[docs/DECISIONS.md](docs/DECISIONS.md)에 있습니다.

| | |
|---|---|
| **빠져나가는 길** — 작정하고 우회하는 사람은 우회합니다 | `--no-verify`([D29](docs/DECISIONS.md)) · `make release`나 `bash deploy.sh` 안에 숨은 커밋 · 우리가 모르는 에이전트([D35](docs/DECISIONS.md)) · 도구를 pty로 감싸는 하네스([D41](docs/DECISIONS.md)) · `git -C <다른 저장소> commit`([D44](docs/DECISIONS.md)) · 퀴즈 없이 `record-pass.sh`를 직접 부르는 에이전트 — 빈 답변은 거부하지만 그 뒤로는 기록을 열어 보는 수밖에 없습니다([D10](docs/DECISIONS.md)) |
| **과하게 막는 길** — 막히지 않아야 할 때 막힐 수 있습니다 | `pre-push`는 커밋을 누가 썼는지 보지 않습니다([D47](docs/DECISIONS.md)) · 남에게서 cherry-pick 하거나 squash 해 온 작업 · 경로에 탭([D08](docs/DECISIONS.md))이나 개행([D43](docs/DECISIONS.md))이 든 파일 |
| **운영** | `jq`가 없으면 게이트가 열립니다([D42](docs/DECISIONS.md)) · 기록은 자동으로 정리되지 않습니다([D18](docs/DECISIONS.md)) · `uninstall`은 감사 로그까지 지우고 워크트리는 그 로그를 공유합니다([D11](docs/DECISIONS.md)) · 리모트 추적 ref가 stale 하면 이미 push 된 커밋을 다시 검사합니다 — `git fetch` 하면 풀립니다 |

이 중 어느 것에도 갇히지 않습니다. 과하게 막힐 때는 언제나 풀 길이 있고
최후 수단은 늘 `--no-verify`입니다.

> 이건 보안 장치가 아니라, 규율 장치입니다.
> 작정하고 우회하려는 사람을 막기 위해 만들지 않았습니다.
> *생각하지 않는 것*이 가장 쉬운 선택이 되지 않게 하려고 만들었습니다.

## 문서 · 라이선스

- [docs/DECISIONS.md](docs/DECISIONS.md) — 모든 설계 결정과 버린 대안. D00부터 읽으시면 됩니다. 나머지는 전부 거기에 답합니다.
- [CONTRIBUTING.md](CONTRIBUTING.md) — 개발 환경, 테스트, 이 코드베이스가 지키는 설계 규칙.
- [AGENTS.md](AGENTS.md) — 에이전트에게 설치를 맡길 때 쓰는 런북.
- [v2 아키텍처](docs/superpowers/specs/2026-07-30-kkochikkochi-v2-hybrid-design.md) — 게이트가 왜 git 훅 안으로 옮겨 갔는지.

MIT.
