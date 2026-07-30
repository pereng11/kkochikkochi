# Changelog

이 프로젝트는 [Keep a Changelog](https://keepachangelog.com/) 형식과
[Semantic Versioning](https://semver.org/) 을 따른다.

## [Unreleased]

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
