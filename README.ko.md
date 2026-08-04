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

Claude Code 와 Codex 를 지원합니다. 이 문서는 [영어판](README.md)과 나란히 관리합니다.
둘이 어긋나면 영어판이 정본입니다.

## 동작

에이전트가 커밋하면 게이트가 막습니다. 에이전트가 스킬을 실행하면 퀴즈가 이어집니다. 아래 게이트 메시지는 실제로 찍히는 문구 그대로입니다. 그 아래 퀴즈는 예시고요 — 문항은 스킬이 변경마다 새로 씁니다.

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
    B) /api/public/* 을 제외한 전체
    C) 정적 에셋만
    D) 모르겠다

→ B  ✓

Q2. 세션 저장소를 Redis 대신 JWT 로 간 이유를 한 문장으로 적으세요.
→ ...

통과했습니다. 다시 커밋하세요.
```

Claude Code 에서는 객관식이 `AskUserQuestion` 으로 나오고 클릭해서 답합니다. Codex 에는 그 대응 도구가 없어 위처럼 평문으로 나오고 타이핑으로 답합니다 — 문항 내용·채점·오답 루프는 두 에이전트에서 같습니다. 다른 언어는 아직 지원하지 않습니다. 훅 문구도 문항을 쓰는 스킬도 한국어로 썼기 때문입니다 — 다국어는 계획에 있습니다.

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

git 훅은 `.git/hooks/` 에 있는데, git 은 이 디렉터리를 추적하지 않습니다. 그래서 저장소마다 따로 설치해야 하고 `git clone` 을 따라가지도 않습니다 — 저장소를 새로 clone 하면 게이트가 없는 상태로 시작하니 그 저장소에서 다시 설치해야 합니다. 직접 하실 일은 보통 없습니다. 에이전트가 어떤 저장소에서 처음 커밋을 시도하면 에이전트 훅이 git 훅의 부재(또는 낡음)를 감지해 그 커밋을 거부하고 그대로 실행할 수 있는 설치 명령을 에이전트에게 건넵니다. 에이전트가 그 명령을 실행한 뒤 다시 커밋하면 됩니다 — 거부된 커밋 자체가 이어지지는 않습니다. 예외는 `core.hooksPath` 를 쓰는 저장소뿐입니다. 그 경우 실효 훅 디렉터리가 저장소에 추적되는 곳이라 에이전트가 말없이 쓰지 않고 사용자에게 확인을 구합니다([D32](docs/DECISIONS.md)).

수동으로 하시려면 게이트를 걸 저장소 안에서 `bash <플러그인 디렉터리>/scripts/install.sh install` · `uninstall` · `status` 를 실행하세요. `status` 의 종료 코드는 `0` 설치됨(그리고 최신) · `1` 미설치 · `2` `core.hooksPath` 저장소라 설치를 거부함 · `3` 우리 훅이지만 낡음입니다. 마지막 경우는 `install` 을 다시 실행하면 됩니다. 기존 `pre-commit` 훅이 있으면 갈아치우지 않고 체이닝합니다 — 먼저 실행하고 0 이 아닌 코드로 끝나면 커밋도 그 코드로 거기서 끝납니다([D31](docs/DECISIONS.md)).

커밋 시점의 게이트는 에이전트가 커밋하려는 내용만 읽습니다. 사람이 직접 친 커밋에는 손대지 않습니다([D33](docs/DECISIONS.md), [D41](docs/DECISIONS.md)). `pre-push` 는 다릅니다 — 커밋을 누가 썼는지 사후에 알아낼 방법이 없어서 사람이 친 커밋도 다시 검사합니다([D47](docs/DECISIONS.md)).

필요한 도구는 `git` 과 `jq` 입니다. [im-not-ai](https://github.com/epoko77-ai/im-not-ai) 의 `humanize-korean` 스킬은 선택입니다 — 문항 문장을 다듬어 주지만 없어도 게이트는 그대로 동작합니다([D46](docs/DECISIONS.md)). 이 설치를 에이전트에게 맡기실 거라면 [AGENTS.md](AGENTS.md) 를 보세요.

## 무엇을 막고 무엇을 막지 않는가

| 이 커밋은... | 게이트 |
|---|---|
| Claude Code 나 Codex 가 만든 커밋 | **켜짐.** 이 도구가 존재하는 이유입니다. |
| 사람이 터미널이나 IDE 에서 직접 친 커밋 | **꺼짐.** 의도한 동작입니다 — 그 사람은 거기 있었고 이해가 병목이 아닙니다([D41](docs/DECISIONS.md), [D44](docs/DECISIONS.md)). |
| `git revert` · `cherry-pick` · `merge` | **커밋 시점에는 꺼짐.** git 이 이 명령들에서 `pre-commit` 을 아예 호출하지 않습니다(측정 확인). 병합 커밋이 새로 만든 내용은 `pre-push` 가 다시 봅니다([D13](docs/DECISIONS.md), [D47](docs/DECISIONS.md)). |
| `git commit --no-verify` (짧게 `-n`) | **우회 가능.** 에이전트 훅이 거부를 시도합니다 — 최선 노력일 뿐 보장이 아닙니다([D29](docs/DECISIONS.md)). |

`git push --no-verify` 도 사정이 같습니다. 에이전트 훅이 `push` 도 같이 보고 거부를 시도하지만 역시 최선 노력일 뿐 보장이 아닙니다. 이 판정은 명령에 `git` 이나 `g` 토큰이 있을 때만 들어갑니다. 그래서 다른 별칭으로 곁들인 `--no-verify` 는 잡지 못합니다. 핸드셰이크를 남기는 프리필터도 여전히 `commit` 만 봅니다([D29](docs/DECISIONS.md), [D44](docs/DECISIONS.md)). 위 목록에 없는 에이전트가 만든 커밋은 애매한 경우로 칩니다. 애매한 경우는 통과시킵니다([D35](docs/DECISIONS.md)).

충돌한 merge·cherry-pick·revert·rebase 를 마무리하려고 직접 치는 `git commit` 도 게이트가 건드리지 않습니다 — 진행 중 마커(`MERGE_HEAD`, `CHERRY_PICK_HEAD`, `REVERT_HEAD`, rebase 디렉터리)가 보이면 비켜섭니다. `git commit --amend` 에는 따로 규칙을 두지 않았습니다 — 메시지만 고치는 amend 는 새로 스테이징할 변경분이 없어 그냥 통과합니다. 내용을 더 얹는 amend 는 그 추가분만큼 게이트 대상입니다([D12](docs/DECISIONS.md)).

## 무엇을 묻는가

| 축 | 예시 |
|---|---|
| 변경 사실 | 어떤 파일의 무엇이 바뀌었나요 |
| 영향·리스크 | 이 변경으로 무엇이 깨질 수 있나요 |
| 설계 의도 | 왜 이 방식을 골랐고 무엇을 버렸나요 |
| 재현 가능성 | X 를 바꾸려면 어디를 건드려야 하나요 |

문항은 최대 5개입니다. 원칙적으로 최소 1개이며 질문거리가 전혀 없는 경우(예: lockfile 재생성, 포매팅만)에 한해 예외적으로 0개 + 사유 기록으로 통과시킵니다. 목표는 3분입니다 — 한 번에 다 맞히는 경우만이 아니라 오답 재시도 루프까지 포함한 시간입니다. 근거를 코드나 대화에서 특정할 수 없으면 아예 묻지 않습니다([D14](docs/DECISIONS.md), [D17](docs/DECISIONS.md), [D19](docs/DECISIONS.md)).

## 동작 원리

훅 두 개가 일을 나눠 갖는데 그중 게이트는 하나뿐입니다. 에이전트 훅(`PreToolUse`)은 서로 다른 두 가지 일을 합니다. `git` 을 부르면서 커밋이나 push 로 보이는 명령에서는 `--no-verify` 와 짧은 형태 `-n` 을 잡아 거부를 시도합니다. 명령에 `commit` 이 들어 있을 때만 에이전트가 지금 커밋하려 한다는 핸드셰이크를 남기고 이 저장소에 git 훅이 설치돼 있는지 낡지 않았는지 건강검진합니다. 둘 다 게이트는 아닙니다 — 에이전트 훅이 뭔가 놓쳐도 그 아래는 그대로입니다. 그 아래가 git 의 `pre-commit` 입니다. git 이 직접 호출하므로 이 훅 안에서 `git diff --cached` 는 커밋될 내용 그 자체입니다. 커맨드 문자열을 파싱할 일이 없습니다([D28](docs/DECISIONS.md), [D30](docs/DECISIONS.md), [D44](docs/DECISIONS.md)).

| 트리거 | 하는 일 |
|---|---|
| `SubagentStart` / `SubagentStop` | 번들을 열고 봉인합니다 (`agents/<hash>`) |
| `PostToolUse` (Claude Code `Task`, Codex `spawn_agent`) | 봉인된 번들의 검증을 부모 에이전트에게 요구합니다 |
| `Stop` | 미검증이 남은 채로 턴이 끝나는 것을 막습니다 |
| git `pre-push` | 최종 경계 — `Stop` 은 Esc 로 빠져나갈 수 있습니다 |

서브에이전트는 사람에게 물을 수 없어서 `pre-commit` 에서 막으면 통과할 방법이
없습니다. 그래서 막지 않고 원장에 적어 두고 뒤에서 강제합니다.

게이트가 남기는 기록은 전부 `.git/` 안에만 있고 절대 커밋되지 않습니다([D08](docs/DECISIONS.md), [D11](docs/DECISIONS.md)).

## 명령

| 명령 | 설명 |
|---|---|
| `/kk` | 지금 스테이징된 변경으로 퀴즈를 받습니다 |
| `/kk-log` | 지금까지의 검증 기록과 취약한 축을 봅니다 |
| `/kk-defer` | 이번 턴은 서브에이전트 번들 퀴즈를 미루고 턴 끝에 몰아 받습니다 — 턴 끝까지만, 영구 우회가 아닙니다 |

## 한계

v2 와 v3 마이그레이션 중 실측으로 확인한 것들입니다. 추측이 아닙니다. 근거는 하나하나
[docs/DECISIONS.md](docs/DECISIONS.md) 에 있습니다.

| | |
|---|---|
| **빠져나가는 길** — 작정하고 우회하는 사람은 우회합니다 | `--no-verify`([D29](docs/DECISIONS.md)) · `make release` 나 `bash deploy.sh` 안에 숨은 커밋 · 우리가 모르는 에이전트([D35](docs/DECISIONS.md)) · 도구를 pty 로 감싸는 하네스([D41](docs/DECISIONS.md)) · `git -C <다른 저장소> commit`([D44](docs/DECISIONS.md)) · 퀴즈 없이 `record-pass.sh` 를 직접 부르는 에이전트 — 빈 답변은 거부하지만 그 뒤로는 기록을 열어 보는 수밖에 없습니다([D10](docs/DECISIONS.md)) |
| **과하게 막는 길** — 막히지 않아야 할 때 막힐 수 있습니다 | `pre-push` 는 커밋을 누가 썼는지 보지 않습니다([D47](docs/DECISIONS.md)) · 남에게서 cherry-pick 하거나 squash 해 온 작업 · 경로에 탭([D08](docs/DECISIONS.md))이나 개행([D43](docs/DECISIONS.md))이 든 파일 |
| **운영** | `jq` 가 없으면 게이트가 열립니다([D42](docs/DECISIONS.md)) · 기록은 자동으로 정리되지 않습니다([D18](docs/DECISIONS.md)) · `uninstall` 은 감사 로그까지 지우고 워크트리는 그 로그를 공유합니다([D11](docs/DECISIONS.md)) · 리모트 추적 ref 가 stale 하면 이미 push 된 커밋을 다시 검사합니다 — `git fetch` 하면 풀립니다 |

이 중 어느 것에도 갇히지 않습니다. 과하게 막힐 때는 언제나 풀 길이 있고
최후 수단은 늘 `--no-verify` 입니다.

> 이건 규율 장치이지 보안 경계가 아닙니다.
> 작정하고 우회하려는 사람을 막아내려고 만들지 않았습니다.
> *생각하지 않는 쪽*이 가장 편한 길이 되지 않게 하려고 만들었습니다.

## 문서 · 라이선스

- [docs/DECISIONS.md](docs/DECISIONS.md) — 모든 설계 결정과 버린 대안. D00 부터 읽으시면 됩니다. 나머지는 전부 거기에 답합니다.
- [CONTRIBUTING.md](CONTRIBUTING.md) — 개발 환경, 테스트, 이 코드베이스가 지키는 설계 규칙.
- [AGENTS.md](AGENTS.md) — 에이전트에게 설치를 맡길 때 쓰는 런북.
- [v2 아키텍처](docs/superpowers/specs/2026-07-30-kkochikkochi-v2-hybrid-design.md) — 게이트가 왜 git 훅 안으로 옮겨 갔는지.

MIT.
