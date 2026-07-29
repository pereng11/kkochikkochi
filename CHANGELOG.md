# Changelog

이 프로젝트는 [Keep a Changelog](https://keepachangelog.com/) 형식과
[Semantic Versioning](https://semver.org/) 을 따른다.

## [Unreleased]

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
