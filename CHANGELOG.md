# Changelog

이 프로젝트는 [Keep a Changelog](https://keepachangelog.com/) 형식과
[Semantic Versioning](https://semver.org/) 을 따른다.

## [Unreleased]

### Added
- **git `pre-push` 훅 — 최종 경계.** `Stop` 훅은 Esc 로 빠져나갈 수 있으므로, 미검증 커밋이 남에게 넘어가는 것은 이제 push 시점에 한 번 더 막는다. 커밋 시점에는 우회했던 `git merge` 도 여기서 다시 훑는다(결합 diff). 사람이 직접 만든 커밋도 이 층은 출처를 보지 않으므로 대상이다 — `git fetch`·`git push --no-verify` 탈출구를 메시지에 안내한다([D47](docs/DECISIONS.md))
- **서브에이전트 병렬 게이트 — 네 개의 새 층.** 서브에이전트는 사람에게 물을 수 없어 `pre-commit` 에서 막을 수 없다. 그래서 원장(`ledger.tsv`)에 적어 두고 뒤에서 강제한다: `SubagentStart`/`SubagentStop` 이 번들을 열고 봉인하고(`agents/<hash>`), `PostToolUse`(`Task`/`spawn_agent`)가 봉인된 번들의 검증을 부모 에이전트에게 요구하고, `Stop` 이 미검증이 남은 채로 턴이 끝나는 것을 막는다
- `/kk-defer` — 이번 턴은 서브에이전트 번들 퀴즈를 미루고 턴 끝에 몰아 받는다(턴 끝까지만, 영구 우회 아님)
- Codex 매니페스트(`hooks.json`)가 `Stop`·`PostToolUse`·`SubagentStart`·`SubagentStop` 을 등록한다. 서브에이전트 생성 도구 이름은 `Task` 가 아니라 `spawn_agent` 다
- `install.sh install` 이 설치 시점의 ref 팁을 `.git/quiz-gate/epoch` 에 남긴다. 파일이 없을 때만 쓰므로 플러그인 업데이트가 게이트를 리셋하지 않는다
- `install.sh uninstall` 이 `.git/quiz-gate/` 를 통째로 지운다. 무엇을 지웠는지 stderr 에 알린다
- `tests/manifests.bats` — 두 훅 매니페스트의 `command` 문자열을 **실제로 실행해** 핸드셰이크가 남는지 확인한다. 변수 이름이 틀리면 JSON 은 멀쩡한데 모든 에이전트 커밋이 "사람"으로 분류되는데, 그 실패에 행동 커버리지가 전혀 없었다
- `scripts/pending.sh` — 검증 대상 결정 규칙의 유일한 구현. 스킬과 `record-pass.sh` 가 둘 다 호출한다
- `tests/pending.bats` — 스킬이 보는 집합과 기록되는 집합이 언제나 같다는 계약을 지킨다

### Fixed
- **`pre-push` 가 `git pull` 로 들어온 남의 커밋, 원격 브랜치 분기점, `clone` 해 온 이력을 검사 대상으로 잡던 문제.** 이제 "사용자가 에이전트로 작업한 코드"만 본다 — 어느 리모트 추적 ref 에서든 도달 가능한 커밋과, 게이트 설치 이전의 로컬 이력이 전부 빠진다. 새 브랜치 경로는 이미 옳았고 기존 브랜치 경로만 틀렸다 ([D47](docs/DECISIONS.md))
- README 한계 표의 `pass_id` 초 해상도 항목이 이미 고쳐진 문제(`96e801c`)를 계속 적고 있던 것
- **IDE·GUI git 클라이언트에서 만든 커밋이 실제로는 막히던 문제.** README 는 막지 않는다고 약속했지만, 핸드셰이크가 매 Bash 호출마다 갱신돼 에이전트가 이 저장소에서 무엇이든 하는 동안 들어온 **모든** 커밋이 에이전트 커밋으로 판정됐다. IDE 는 git 을 pty 가 아니라 파이프로 띄우므로 TTY 구제도 닿지 않았다. 이제 핸드셰이크는 **커밋처럼 보이는 명령에서만** 남는다([D44](docs/DECISIONS.md)). `FRESH_SECS` 는 그에 맞춰 120초 → 600초
- **스킬과 기록자가 낡은 `pending` 에 대해 서로 다른 파일 집합을 보던 문제.** `SKILL.md` 는 신선도 검사 없이 파일을 읽고 `record-pass.sh` 는 900초를 요구해서, 창이 지나면 사용자가 A 를 풀고 B 가 검증된 것으로 기록됐다. 규칙을 `scripts/pending.sh` 한 곳으로 옮기고 양쪽이 그것을 부르게 했다([D45](docs/DECISIONS.md))
- **잘린 `pending` 줄에서 `record-pass.sh` 가 성공을 보고하던 문제** — 사용자는 통과했다는 말을 듣지만 커밋은 그대로 막혀 있었다. 이제 시끄럽게 거부한다
- 훅이 `pending` 을 쓰지 못했을 때 조용히 넘어가던 것 — C1(영구 교착)이 소리 없이 되살아나는 경로였다. 경고를 낸다
- **`git commit -am` 이 영구 교착이던 문제.** git 은 `-a` 와 `-- <path>` 커밋에서 훅에게 임시 인덱스를 물려주므로, 훅 밖에서 도는 `record-pass.sh` 의 같은 `git diff --cached` 는 다른 답을 냈다. 이제 훅이 자기가 계산한 `(SHA, 경로)` 를 `pending` 에 발표하고 `record-pass.sh` 가 그것을 소비한다([D40](docs/DECISIONS.md)). 부분 스테이징 변종(`git commit -m x -- tracked.txt` 가 그 커밋에 없는 파일을 기록하던 것)도 함께 닫혔다
- **낡은 훅이 "설치됨"으로 보고되던 문제.** 마커 문자열만 보던 탓에 옛 판의 훅이 남아 있어도 `status` 가 0을 냈고, 건강검진은 0이 아닐 때만 반응하므로 **어떤 수정도 이미 설치된 저장소에 도달하지 못했다.** `status` 가 플러그인 원본과 내용을 비교해 새 종료 코드 3(낡음)을 낸다([D39](docs/DECISIONS.md))
- **`git commit -n` 이 아무 흔적 없이 우회하던 문제.** 에이전트 훅이 `--no-verify` 리터럴만 보고 있었다. 짧은 형태(`-n`·`-nm`·`-qn` 등 묶음 포함)도 유계 검사로 감지한다
- **한 창에서 에이전트를 돌리는 동안 옆 창에서 손으로 친 커밋이 막히던 문제.** 실제 터미널(TTY) 신호가 이제 핸드셰이크보다 우선한다([D41](docs/DECISIONS.md))
- **`jq` 없는 기계에서 통과할 방법이 없는 게이트가 만들어지던 문제.** 설치기가 `jq` 없이는 설치하지 않고, 설치 이후에 사라진 경우 훅이 경고와 함께 통과시킨다([D42](docs/DECISIONS.md))
- **경로에 개행이 있으면 그 경로 하나가 아니라 뒤따르는 파일들이 통째로 게이트를 빠져나가던 문제.** 어긋난 `--raw` 스트림을 감지해 경고와 함께 커밋 전체를 통과시키고, `record-pass.sh` 는 쓰레기 기록을 거부한다([D43](docs/DECISIONS.md))
- 실행 권한이 없는 훅이 "설치됨"으로 보고되던 문제 — git 은 그런 훅을 무시하므로 게이트가 조용히 없는 상태였다
- **`git push --no-verify`(짧은 형태 포함)가 에이전트 훅을 무저항으로 통과하던 문제.** 프리필터가 `*commit*` 만 봤던 탓에 `--no-verify` 판정 자체가 이 명령에 아예 도달하지 못했다 — `pre-push` 를 잡으려고 만든 최종 경계가 정작 `pre-push` 를 우회하는 그 명령 앞에서 아무것도 하지 않았다. `--no-verify`/`-n` 판정만 `*push*` 도 함께 보게 넓혔다 — 마커 쓰기와 설치 건강검진은 여전히 `*commit*` 만 본다(넓히면 D44 가 되살아난다)

### Changed
- `README.md` — 경로에 탭이 든 경우를 "복구 불가능"이라고 적었던 것을 바로잡았다(`--no-verify` 와 `uninstall` 로 회복된다). 건강검진이 매 Bash 호출마다 도는 것처럼 읽히던 설명과, 설치가 훅에 의해 자동 실행되고 커밋이 이어지는 것처럼 읽히던 설명도 실제 동작에 맞췄다
- `tests/helper.bash` 의 `mark_covered()` 를 `stub_covered_line()` 으로 바꿨다. 이름이 진짜 writer 처럼 읽혀 `git commit -am` 교착을 가리고 있었다 — 왕복 주장에는 진짜 `record-pass.sh` 만 쓴다
- **오답 선택지에만 되묻는 문장이 붙어 정답이 새던 문제.** "그렇다면 ~이지 않을까?" 같은 표지가 오답에만 달려, 코드를 읽지 않고 그것만 지워도 정답에 닿았다. 모든 선택지를 같은 문법으로 쓰고 평서문으로 끝낸다(`SKILL.md` §2, `ask/claude-code.md`)
- **문항 한글이 깨져 나오던 문제.** 도구 인자에 한글을 `\uXXXX` 로 손수 적다가 음절이 어긋났다(바뀐 → 바뀌, 멀쩡한 → 멀짎ka한). 이제 리터럴로만 쓴다(`skills/kkochikkochi/ask/claude-code.md`)
- **Claude Code 에서 문항이 터미널 폭에 잘려 읽히지 않던 문제.** `AskUserQuestion` 의 `question`·`label` 이 잘려 사용자가 문제를 읽지 못한 채 막히는 것을 실측했다. 이제 한 번에 1문항만 내고, 문항 전문과 근거 코드는 모든 선택지의 `preview` 에 반복해 싣는다(`skills/kkochikkochi/ask/claude-code.md`)
- 문항 문장 규칙을 `SKILL.md` §2 에 넣었다. 번역투·좌향 수식·이중 조사처럼 문항에서 반복되는 것만 표로 추렸고, 룰북 전문은 `skills/kkochikkochi/references/korean-sentences.md` 에 두었다([im-not-ai](https://github.com/epoko77-ai/im-not-ai) 사본, MIT). 더 손이 필요하면 `humanize-korean` 을 부르고, 설치돼 있지 않으면 그냥 진행한다([D46](docs/DECISIONS.md))

## [0.2.0] - 2026-07-30

아키텍처가 바뀌었다. 게이트가 걸리는 방식과 무엇을 막는지가 모두 달라졌으므로, 이전 버전 사용자는 아래 Changed 를 반드시 읽어야 한다.

### Changed
- **게이트를 Claude Code `PreToolUse` 훅에서 git `pre-commit` 훅으로 옮겼다.** git 이 커밋 직전에 직접 호출하는 훅이므로 `git diff --cached` 가 커밋될 내용 그 자체다 — 더 이상 Bash 커맨드 문자열을 파싱하지 않는다
- **게이트가 켜지는 조건이 "`git commit` 처럼 보이는 커맨드"에서 "에이전트가 만든 커밋"으로 바뀌었다.** 사람이 터미널이나 IDE 에서 직접 만든 커밋은 이제 막지 않는다(v1 은 Bash 를 거치는 모든 `git commit` 을 대상으로 했다)
- Claude 훅의 역할이 판정에서 **핸드셰이크 기록 + 설치 상태 건강검진 + `--no-verify` 감지**로 축소됐다. 이 훅은 더 이상 안전 경로가 아니다 — 여기서 놓쳐도 git 훅이 그대로 막는다
- `scripts/record-pass.sh` 가 커맨드 문자열이나 SHA 를 인자로 받지 않는다. 대상은 `git diff --cached` 로 스스로 계산한다
- 에이전트 판별 방식이 커맨드 매칭에서 3층 구조(핸드셰이크 → 알려진 환경변수 → TTY 음성 신호)로 바뀌었다
- Codex 를 지원 에이전트로 추가했다. 같은 저장소가 Claude Code 플러그인과 Codex 플러그인을 겸한다 — 매니페스트와 훅 등록만 에이전트별로 갈리고 나머지는 공유한다
- 질문 제시 방법을 `skills/kkochikkochi/ask/{claude-code,codex}.md` 로 분리했다. 채점·오답 루프·문항 규칙은 두 에이전트에서 동일하다

### Removed
- `scripts/lib-tokenize.sh` (커맨드 토크나이저) 전체를 삭제했다 — 그것을 쓰던 `gate.sh` 의 토크나이저·매처·마커 계산과 `pending-set.sh` 의 인자 파싱도 함께 사라졌다. v1 결함의 거의 전부가 이 파싱에서 나왔다
- `tests/command-forms.bats` 삭제 — 더 이상 파싱할 커맨드 형태가 없다
- `SKILL.md` 의 `<BLOCKED_COMMAND>` 전달과 `'\''` 셸 이스케이프 규칙을 제거했다 — 훅이 더 이상 커맨드 문자열을 스킬에 넘기지 않는다

### Added
- git `pre-commit` 훅(`hooks/pre-commit`, POSIX sh) — 실제 게이트
- 훅 설치기 `scripts/install.sh` — 기존 `pre-commit` 훅 체이닝, 멱등 재설치, 깔끔한 제거, `core.hooksPath` 저장소 거부
- 에이전트 핸드셰이크 `scripts/stamp-agent.sh` — Claude Code 와 Codex 가 공유하는 판별 신호이자 설치 상태 건강검진
- `.codex-plugin/plugin.json`, `.agents/plugins/marketplace.json`, 루트 `hooks.json` — Codex 플러그인·마켓플레이스·훅 등록 매니페스트

## [0.1.0] - 2026-07-29

### Added
- `git commit` 을 가로채는 PreToolUse 이해 검증 게이트
- 파일 단위 blob SHA 바인딩으로 분할 커밋 지원
- 4축 문항 생성 (변경 사실 · 영향·리스크 · 설계 의도 · 재현 가능성)
- 오답 시 다른 각도로 재출제하는 학습 루프
- `/kk`, `/kk-log` 슬래시 커맨드
- `scripts/lib-tokenize.sh` — 훅·스킬이 공유하는 단일 커맨드 파서

### Fixed
- 커밋 메시지 안의 `--` (heredoc 서명 구분선 포함)가 게이트를 통째로 무력화하던 문제
- `git commit -m x <path>` 의 맨 pathspec 이 무시되어 워크트리 내용이 검증 없이 커밋되던 문제
- 스킬이 `"git commit"` 을 하드코딩해 `git commit -am x` 등에서 영구 교착이 나던 문제
- 비ASCII(한글) 경로가 `core.quotePath` 기본값에서 `NULL_SHA` 로 기록되어 이후 어떤 변경에도 재출제되지 않던 문제
- 긴 Bash 커맨드에서 토크나이저가 O(n²)라 훅 타임아웃 → fail-open 하던 문제
- 초기 커밋 + `-a` 에서 `fatal: ambiguous argument 'HEAD'` 가 스킬 입력에 새던 문제
- `record-pass.sh` 가 `git -C` 를 무시하고 세션 저장소에 기록하던 문제
- `--pathspec-from-file` / `--pathspec-file-nul` 이 인식 목록에 있어, 파일 안에 적힌 커밋 경로가 게이트를 통째로 빠져나가던 문제
- 커밋 메시지 안의 작은따옴표가 스킬의 셸 호출을 문법 오류로 만들어 커밋이 영구히 막히던 문제
- deny 사유의 삼중 백틱 구분선이 커맨드 자체의 백틱과 충돌해 스킬이 잘린 문자열을 받을 수 있던 문제
- 토크나이저 조각 경계에 정확히 걸린 `&&` / `||` 에서 세그먼트 구분자가 사라지던 문제
