# Contributing

## 개발 환경

```bash
brew install bats-core shellcheck jq     # macOS
sudo apt-get install -y bats shellcheck jq   # Debian/Ubuntu
```

macOS 의 기본 `/bin/bash` 는 3.2 버전이며, 이 버전의 bats 실행기는 비-ASCII `@test` 이름(이 저장소의 테스트 이름은 전부 한글이다)을 깨뜨려 `bats: unknown test name` 류의 알쏭달쏭한 오류를 낸다. macOS 에서는 `brew install bash` 로 최신 bash 를 설치하고 PATH 앞쪽에 두어 `bats` 가 그 bash 로 실행되게 하라(예: `PATH="/opt/homebrew/bin:$PATH"`).

이 요구사항은 **테스트 실행기 한정**이다. 플러그인이 실제로 배포하는 `scripts/*.sh` 는 여전히 bash 3.2 와 호환되게 작성한다 — 연관 배열 등 3.2 에 없는 기능을 쓰지 않는다. `hooks/pre-commit` 은 bash 조차 아닌 **POSIX sh** 다 — git 이 이 파일을 직접 실행 가능한 스크립트로 호출하고, 사용자 환경에 어떤 셸이 `/bin/sh` 인지 우리가 정할 수 없기 때문이다. 런타임에 bash 5 나 특정 셸을 요구하도록 "고치지" 말 것.

## 테스트

```bash
bats tests/                                        # 전체
bats tests/pre-commit.bats                         # 개별
shellcheck scripts/*.sh tests/helper.bash
shellcheck -s sh hooks/pre-commit                  # POSIX sh 이므로 별도 지정
```

테스트는 매번 `mktemp -d` 로 새 git 저장소를 만든다. 커밋된 `.git` 픽스처를 저장소에 넣지 않는다.

## 설계 원칙

이 원칙들은 v1 의 세 차례 수정 웨이브가 남긴 교훈이다. v1 은 Claude 훅에서 bash 커맨드 문자열을 파싱해 무엇이 커밋될지 알아내려 했고, 구현과 세 웨이브에서 나온 결함이 거의 전부 그 파싱 한 곳에서 나왔다. v2 는 그 자리를 git 이 직접 호출하는 `pre-commit` 훅으로 대체해 파싱 자체를 없앴다.

1. **게이트는 git 훅이다. 에이전트 훅은 안전 경로가 아니다.** git `pre-commit` 훅이 실제 게이트이고, git 이 직접 호출하므로 그 안의 `git diff --cached` 는 커밋될 내용 그 자체다. Claude/Codex `PreToolUse` 훅은 핸드셰이크 기록과 설치 상태 건강검진만 한다 — **거기서 로직이 틀려도 게이트는 여전히 걸린다.** 안전을 그 훅의 정확성에 기대는 코드를 추가하지 않는다
2. **명령 문자열을 파싱하지 않는다.** v1 결함의 거의 전부가 거기서 나왔다 — 인용된 메시지 안의 `--`, 맨 pathspec 누락, `--pathspec-from-file` 미처리, 토크나이저 O(n²) 타임아웃. `git diff --cached` 가 이미 정답을 알고 있는데 그 위에 파서를 다시 얹지 않는다
3. **에이전트 판별의 1차 신호는 핸드셰이크다.** 에이전트 훅이 발동했다는 사실 자체가 증거이고, 변수 이름을 하나도 보지 않으므로 에이전트의 어떤 버전 변경에도 살아남는다. 환경변수는 2차 백업일 뿐이며, **직접 관찰한 것만** 목록에 넣는다 — 추측으로 채운 변수는 남의 환경에서 조용히 오작동한다
4. **애매하면 통과시킨다.** 막아야 할 것을 정확히 막는 게 목표지 많이 막는 게 목표가 아니다. TTY 도 없고 알려진 신호도 없는 경우(IDE 커밋, CI, 우리가 모르는 에이전트가 뒤섞인 덩어리)를 억지로 가르려 하면 사람의 커밋까지 막게 되고, 도구는 문제를 풀지 않으면서 마찰만 만들다 꺼진다
5. **판정에 LLM 을 넣지 않는다.** git 훅과 에이전트 훅 모두 결정적이어야 셸 스크립트로 테스트할 수 있다. 문항 생성·채점처럼 대화 맥락이 필요한 부분만 스킬(LLM)이 맡는다
6. **fail-open.** 게이트 버그, git 부재, `covered.tsv` 손상은 경고만 남기고 커밋을 허용한다. 하드 게이트에서 fail-closed 는 버그 하나가 저장소를 벽돌로 만든다
7. **근거 없는 문항은 출제하지 않는다.** 모든 문항은 정답 근거를 `파일:줄` 또는 대화 내 발언으로 특정할 수 있어야 한다. 틀린 정답은 사용자를 진짜로 가둔다

설계 결정과 기각된 대안은 [docs/DECISIONS.md](docs/DECISIONS.md) 에 있다. **D00** 이 다른 모든 결정의 기준점이므로 먼저 읽을 것. 결정을 바꿀 때는 항목을 지우지 말고 상태와 변경 이력을 덧붙인다.

## 커밋 메시지

Conventional Commits 를 쓴다: `feat:`, `fix:`, `test:`, `docs:`, `chore:`
