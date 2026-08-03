# README 재작성 설계

작성일: 2026-08-03
대상: `README.md`, `README.ko.md`(신규), `AGENTS.md`(신규)

## 1. 문제

현재 `README.md` 는 188줄이고, 한 파일이 여섯 가지 일을 동시에 한다 — 설득, 소개, 설치 안내, 동작 레퍼런스, 내부 구조 문서, 면책. 그래서 어느 독자에게도 최적이 아니다. 구체적으로 세 가지가 어긋나 있다.

**무게중심이 정확성에 쏠려 있다.** "왜 이 도구가 필요한가"가 3문장(6~8행)인데 그 뒤 한계 표가 19행이다. 지금 구조는 이미 설득된 사람이 정밀하게 읽는 문서지, 처음 온 사람을 공감시키는 문서가 아니다. 이 도구의 핵심 주장 — 개발을 빠르게 하는 도구가 아니라 책임감 있게 하는 도구이고, AI 시대의 병목은 사람의 인지부하이며 가장 위험한 것은 게으름이라는 것 — 이 README 어디에도 정면으로 적혀 있지 않다.

**언어가 갈려 있다.** 제목 밑 두 줄과 `plugin.json` 의 `description` 만 영어이고 본문은 전부 한국어다. GitHub 첫인상과 본문이 어긋난다.

**에이전트에게 그대로 던지면 첫 줄에서 막힌다.** 설치 절이 `/plugin marketplace add ...` 슬래시 명령만 제시하는데, 슬래시 명령은 사람이 직접 타이핑해야 하는 것이라 에이전트가 실행할 수 없다. `claude plugin marketplace add` / `claude plugin install` 이라는 bash 경로가 실재하는데 문서에 없다(2026-08-03 `claude plugin --help` 로 확인).

## 2. 목표

1. 처음 온 사람이 첫 화면에서 **왜 이 도구가 존재하는지에 공감**하게 한다. 기능 나열보다 논지가 먼저다
2. 사람이 직접 읽지 않고 **LLM 에게 시키기만 해도 설치에 걸림돌이 없게** 한다
3. 사람이 직접 읽어도 **끝까지 읽히게** 한다 — 188줄에서 약 120줄로 줄인다
4. 정직함을 잃지 않는다. 한계를 숨기는 README 는 "게으름을 경계하는 도구"라는 주장과 자기모순이다

### 비목표

- 코드 변경 없음. 문서만 바꾼다
- 별도 사용자 문서(`LIMITS.md`, `HOW-IT-WORKS.md`, `TROUBLESHOOTING.md`) 를 만들지 않는다. 3절 근거 참조
- `CONTRIBUTING.md`, `docs/DECISIONS.md` 의 성격과 언어는 그대로 둔다

## 3. 레퍼런스 조사 결과

`juliusbrussee/caveman`(사용자 지정 레퍼런스), `obra/superpowers`, `nizos/tdd-guard`, `pre-commit/pre-commit` 네 종의 README 구조를 비교했다.

| | caveman | superpowers | tdd-guard | pre-commit |
|---|---|---|---|---|
| 여는 문장 | 밈 한 줄 + 숫자 | 정의 한 문장 | 정의 한 문장 | 정의 한 문장 |
| 그 다음 | Before/After 비교표 + 그래프 | Quickstart 링크 | Features 5개 | 없음 |
| 설치 위치 | 3번째 | 4번째 | 2번째 | 없음 |
| 접기(`<details>`) | 3곳 | 없음 | 없음 | 없음 |

배운 것 셋. ① caveman 은 첫 화면에서 주장 대신 **증거**를 보여준다. ② 자랑과 한계를 같은 섹션에 묶어 둔다. ③ 부차적인 것은 접어 스크롤 길이를 방어한다.

**`tdd-guard` 가 이 프로젝트와 가장 가까운 비교 대상이다** — "에이전트를 막는 Claude Code 훅"이라는 같은 장르인데, README 가 "왜 이게 필요한가"를 전혀 팔지 않고 기능 나열로 간다. 그 자리가 비어 있다.

### 별도 문서를 만들지 않는 근거

GitHub 파일명 검색으로 관행 여부를 측정했다(2026-08-03, `CONTRIBUTING.md` 219,584건이 기준선).

| 파일명 | 건수 |
|---|---:|
| `ARCHITECTURE.md` | 96,344 |
| `DESIGN.md` | 49,616 |
| `TROUBLESHOOTING.md` | 48,032 |
| `LIMITATIONS.md` | 6,368 |
| `LIMITS.md` | 5,896 |
| `HOW-IT-WORKS.md` | 3,852 |
| `CAVEATS.md` | 1,756 |

`HOW-IT-WORKS.md` 와 `LIMITATIONS.md` 는 관행이라 부를 빈도가 아니다. `HOW-IT-WORKS.md` 자리의 관행 이름은 `ARCHITECTURE.md`(25배)지만, 그 정의는 matklad 가 2021년에 제안한 **기여자용 코드맵**이고 권장 규모가 10k~200k LOC 다. 이 저장소는 셸 1,961줄 + 테스트 3,519줄로 미달한다. 그리고 caveman 과 superpowers 는 둘 다 "How it works" 를 README 의 H2 로 두고 별도 파일을 만들지 않았다 — 이 규모에서의 실제 관행은 README 안이다.

반면 `AGENTS.md` 는 관행이다. Codex·Cursor·Copilot 이 지원하고 6만 개 이상 저장소가 쓴다.

## 4. 문서 세트

| 파일 | 독자 | 상태 | 언어 |
|---|---|---|---|
| `README.md` | 처음 온 사람 — 설득 → 설치 → 판단 | 새로 씀 | 영어 |
| `README.ko.md` | 한국어 독자 | 신규 (미러) | 한국어 |
| `AGENTS.md` | 이 플러그인을 설치·운영하는 에이전트 | 신규 | 영어 |
| `CONTRIBUTING.md` | 이 저장소 기여자 | 유지 | 한국어 |
| `docs/DECISIONS.md` | 설계 근거 | 유지 + 흡수 보강 | 한국어 |

규칙 하나로 정리하면 **사용자 문서는 영어, 기여자 문서는 한국어**다.

### `AGENTS.md` 의 범위 충돌 해소

`AGENTS.md` 의 통상적 의미는 "이 저장소에서 작업하는 에이전트를 위한 규칙"이다. 여기서는 "이 플러그인을 남에게 설치해 주는 에이전트를 위한 런북"으로 쓰므로 의미가 어긋난다. 파일 첫 줄에 범위를 명시해 해소한다.

> This file is for an agent installing and operating KkochiKkochi.
> If you are contributing to this repository, read CONTRIBUTING.md instead.

### 번역본 동기화 부채

`README.ko.md` 가 생기는 순간 README 수정이 두 번이 된다. 이 저장소는 README 사실관계 수정이 잦았다(`9061b2f`, `0c28520`, `7c5b142` 가 전부 README 오류 수정). 완화책 둘.

- `README.ko.md` 상단에 정본을 명시한다: "정본은 `README.md`. 어긋나면 영어를 따르세요."
- 자주 바뀌는 사실(한계 세부, 판별 순서, 파일 포맷)은 애초에 README 밖 `DECISIONS.md` 에 둔다. 이번 구조가 그렇게 되어 있다

## 5. `README.md` 명세

목표 분량 약 120줄. H2 8개.

### 5.0 도입부 (H2 이전)

배지 한 줄 → 제목 → 정의 인용 → 선언문 4문단 → 언어 전환 링크.

배지 세 개. CI 상태(`https://github.com/pereng11/kkochikkochi/actions/workflows/ci.yml/badge.svg`, 워크플로 이름은 `CI`), MIT 라이선스, `Claude Code · Codex` 지원 표시. 현재 README 에는 배지가 하나도 없고, 레퍼런스 4종 중 3종이 배지로 시작한다.

선언문은 다음 골자를 지킨다. 문면은 작성 시 다듬되 순서와 논지는 바꾸지 않는다.

```
# KkochiKkochi 🦡

> Korean, adv. — questioning in relentless, minute detail.

**Not a tool to ship faster.
A tool to ship responsibly.**

How many lines did you merge today?
How many did you actually read?

The bottleneck in agentic coding was never typing speed.
It's your own comprehension — and the cheapest thing to skip
is understanding.

KkochiKkochi puts a wall exactly where the skipping happens:
your agent stops, and waits for *your* answer. Miss it, and
the commit does not land.
```

논지 세 개가 이 순서로 들어가야 한다. ① 속도가 아니라 책임. ② 병목은 사람의 인지부하이고 위험한 것은 게으름. ③ 에이전트가 멈추고 답을 기다리는 순간을 만들어 강제로 이해시킨다.

**용어는 `agentic coding` 을 쓴다. `AI-assisted coding` 을 쓰지 않는다.** 2026-08-03 조사 결과, `AI-assisted coding` 은 자동완성 시대까지 포함하는 우산 범주라 에이전트가 커밋을 만드는 이 도구의 상황을 가리키지 못한다. 현재 표준어는 Karpathy 가 2026년에 내놓은 `agentic engineering` 계열이고, 문장 안에서 활동을 가리킬 때는 `agentic coding` 이 자연스럽다. `vibe coding`(Karpathy 2025년 초, Collins 2025 올해의 단어, "꼼꼼히 살피지 않고 받아들이는 것")은 이 도구가 막으려는 실패 모드와 정의가 일치해 유혹적이지만, 밈에 기대는 만큼 유행이 지나면 낡으므로 쓰지 않는다.

### 5.1 `## See it work` (~20줄)

차단 화면과 퀴즈를 한 덩어리 트랜스크립트로 보여준다. 현재 README 의 "동작" 절 내용을 영어로 옮기되, 두 코드 블록을 하나로 합쳐 스크롤을 줄인다. Claude Code 는 객관식이 `AskUserQuestion` 으로 클릭 선택되고 Codex 는 평문 타이핑이라는 차이는 블록 아래 한 문장으로 남긴다.

### 5.2 `## Install` (~20줄)

1. Claude Code 슬래시 2줄, Codex 슬래시 2줄
2. 저장소별 git 훅 — 보통 직접 할 필요 없다는 사실(에이전트가 첫 커밋 시도에서 안내받아 설치한다)과 `bash scripts/install.sh install|uninstall|status`, `status` 종료 코드 0/1/2/3
3. 필요 도구 `git`, `jq`. 선택 도구 `im-not-ai` 의 `humanize-korean`
4. `AGENTS.md` 포인터: "Setting this up with an agent? See AGENTS.md"

**이 섹션에 안심 문장 하나를 넣는다** — `It never touches commits you type yourself.` `What gets gated` 표를 9행에서 4행으로 줄이면서 빠지는 정보인데, 설치 결정에 실제로 영향을 주므로 산문으로 살린다.

### 5.3 `## What gets gated` (~8줄)

현재 8행 표를 4행으로 압축한다.

| 커밋 | 게이트 |
|---|---|
| Claude Code / Codex 가 만든 커밋 | 켜짐 — 이 도구가 존재하는 이유 |
| 사람이 터미널·IDE 에서 직접 만든 커밋 | 꺼짐 — 의도된 동작 |
| `revert` · `cherry-pick` · `merge` | 꺼짐 — git 이 `pre-commit` 을 부르지 않는다 |
| `--no-verify` | 우회 가능 — 에이전트 훅이 거부를 시도하지만 최선 노력이다 |

현재 표의 나머지 3행(옆 창에 에이전트가 떠 있는 사람 커밋, 미지원 에이전트, `core.hooksPath` 거부)이 담던 뉘앙스는 `DECISIONS.md` 의 D41·D35·D32 로 링크한다. 현재 README 의 별도 절인 "게이트가 통과시키는 git 커맨드" 6항목도 이 표에 흡수하고, 상세는 D13·D47 링크로 대신한다.

### 5.4 `## What it asks` (~10줄)

현재 "무엇을 묻는가" 절을 그대로 옮긴다. 4축 표(변경 사실 · 영향과 리스크 · 설계 의도 · 재현 가능성)와 문항 예산 규칙(최대 5, 원칙적으로 최소 1, 질문거리가 없으면 예외적으로 0 + 사유 기록, 목표 3분은 오답 재시도 포함, 근거를 특정할 수 없는 문항은 출제하지 않음).

### 5.5 `## How it holds` (~12줄)

두 개의 훅이 어떻게 나뉘는지 한 문단 — 에이전트 훅은 핸드셰이크와 건강검진만 하고 게이트가 아니며, 실제 게이트는 git `pre-commit` 이라 커맨드 문자열을 파싱하지 않는다는 것. 그다음 4겹 층 표(`SubagentStart`/`Stop` 번들, `PostToolUse` 요구, `Stop` 차단, git `pre-push` 최종 경계).

**기록 위치는 한 문장으로 남긴다** — 검증 기록은 `.git/` 안에만 있고 절대 커밋되지 않는다는 것. 현재 "어떻게 기억하는가" 절의 나머지(`covered.tsv` 포맷, `passes/*.json`, `marker/`, `ledger.tsv`, `epoch`)는 삭제하고 D08·D11·D40·D47 링크로 대신한다.

판별 순서(TTY → 핸드셰이크 → 환경변수)와 핸드셰이크 신선도 600초는 README 에서 뺀다. D41·D34 에 있다.

### 5.6 `## Commands` (~6줄)

`/kk`, `/kk-log`, `/kk-defer` 3행 표. 현재 내용 유지.

### 5.7 `## What it misses` (~12줄)

19항목을 3그룹으로 재분류한 표 하나와 규율 장치 인용구.

| 그룹 | 담기는 것 |
|---|---|
| **Ways out** — 빠져나가려는 사람은 빠져나간다 | `--no-verify`, `make release` 안에 숨긴 커밋, 미지원 에이전트, pty 로 감싸는 하네스, `git -C <다른 저장소>` |
| **Ways it over-blocks** — 막히지 말아야 할 때 막힌다 | `pre-push` 는 출처를 보지 않는다, cherry-pick·squash 로 가져온 남의 커밋, 탭·개행이 든 경로 |
| **Operational** | `jq` 가 없으면 게이트가 열린다 · 기록은 자동 정리되지 않는다 · `uninstall` 은 감사 기록을 함께 지운다 · 워크트리는 상태를 공유한다 · stale 추적 ref 는 `git fetch` 로 풀린다 |

인용구로 닫는다.

> This is a discipline device, not a security boundary.
> It is not built to survive someone who wants around it.
> It is built so that *not thinking* is no longer the path of least resistance.

**정보 손실은 없다.** 19항목의 설계 근거는 대부분 이미 `DECISIONS.md` 에 있다 — 신뢰 경계 D10, revert/cherry-pick/merge D13, fail-open D16, TTL 없음 D18, TTY 우선 D41, `jq` D42, 개행 경로 D43, 핸드셰이크 범위 D44, epoch 과 도달성 D47. 집 없는 것은 순수 운영 대처법 넷(탭 경로 탈출법, stale ref 는 `git fetch`, `uninstall` 이 `passes/*.json` 을 지움, 워크트리 상태 공유)뿐이고 위 표 셋째 줄에 압축한다. `--no-verify` 오탐 규칙의 구체(하이픈 하나로 시작하는 낱말 안에 `n` 이 있으면 무엇이든 걸린다, `git`·`g` 토큰이 있을 때만 판정한다, 다른 별칭은 잡지 못한다)는 D44 본문에 흡수한다.

### 5.8 `## Docs · License` (~5줄)

`docs/DECISIONS.md`(설계 근거), `CONTRIBUTING.md`(기여), v2 아키텍처 전환 스펙 링크. MIT.

## 6. `README.ko.md` 명세

`README.md` 의 한국어 미러. 섹션 구조와 순서를 1:1 로 맞춘다. 상단에 정본 표기.

`agentic coding` 은 한국어에서 `에이전틱 코딩` 으로 음차하되, 문맥상 어색하면 `에이전트가 코드를 쓰는 개발` 처럼 풀어 쓴다. `AI 보조 코딩` 으로 옮기지 않는다 — 영어에서 피한 우산 범주를 한국어로 되살리는 셈이 된다.

한국어 문장은 리터럴로 작성한다 — `\uXXXX` 이스케이프를 쓰지 않는다. 긴 산문은 파일에 쓴 뒤 읽어서 검토한다. 번역투가 남으면 `im-not-ai` 의 `humanize-korean` 규칙을 참고해 다듬는다.

## 7. `AGENTS.md` 명세

영어. 에이전트가 위에서 아래로 실행할 수 있는 런북 형태로 쓴다. 산문 최소, 실행 가능한 블록 우선.

1. **범위 선언** — 4절의 두 줄
2. **플러그인 설치**
   ```bash
   claude plugin marketplace add pereng11/kkochikkochi
   claude plugin install kkochikkochi@kkochikkochi
   ```
   설치 후 Claude Code 재시작이 필요하다는 사실을 명시한다
3. **저장소별 git 훅 설치** — `bash scripts/install.sh install`, `status` 종료 코드 0/1/2/3 의 의미와 각 코드에서 할 일
4. **`core.hooksPath` 저장소** — 말없이 쓰지 말고 사용자에게 확인을 구할 것
5. **게이트에 막혔을 때** — `kkochikkochi` 스킬을 실행하고, 통과 후 커밋을 **다시 시도**할 것(거부된 커밋이 이어지지 않는다). `--no-verify` 로 우회하지 말 것
6. **필요 도구** — `git`, `jq`

Codex 의 `codex plugin ...` 형식은 현재 README 표기를 그대로 옮긴다. 이 환경에서는 로컬 `codex` 바이너리가 깨져 있어(2026-08-03 `ENOENT`) 실행 확인을 하지 못했다.

## 8. 작성 규칙

- **주장에는 근거를 붙인다.** "측정으로 확인" 같은 표현은 실제로 측정한 것에만 쓴다. 현재 README 의 검증된 사실 진술은 그대로 보존한다
- **부정확한 축약을 만들지 않는다.** 압축 과정에서 조건을 떨어뜨려 문장이 실제보다 강해지는 것을 경계한다. 특히 `--no-verify`, `merge`, `pre-push` 관련 문장
- **링크는 `DECISIONS.md` 의 D 번호로 건다.** 절 제목이 아니라 번호로 걸어야 문서가 재배치돼도 살아남는다
- **`<details>` 를 쓰지 않는다.** 이번 구조는 접을 만큼 긴 덩어리가 없고, 접힌 내용은 GitHub 검색과 LLM 읽기에는 그대로 노출되어 실질 길이가 줄지 않는다

## 9. 완료 기준

1. `README.md` 가 약 120줄이고 H2 8개다
2. 도입부 4문단에 논지 세 개(속도 아닌 책임 · 병목은 인지부하 · 멈추는 순간을 만든다)가 이 순서로 있다
3. `README.md` 의 모든 사실 진술이 현재 README 또는 `DECISIONS.md` 에서 근거를 찾을 수 있다. 새로 만들어낸 주장이 없다
4. `AGENTS.md` 만 읽은 에이전트가 슬래시 명령 없이 설치를 끝낼 수 있다
5. `README.ko.md` 의 H2 목록이 `README.md` 와 1:1 로 대응한다
6. 삭제된 19항목 중 `DECISIONS.md` 에 근거가 없던 것이 해당 D 항목에 흡수됐다
7. 기존 문서의 상대 링크(`docs/DECISIONS.md`, `CONTRIBUTING.md`, v2 스펙)가 전부 유효하다
