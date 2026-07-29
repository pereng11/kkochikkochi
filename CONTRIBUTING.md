# Contributing

## 개발 환경

```bash
brew install bats-core shellcheck jq     # macOS
sudo apt-get install -y bats shellcheck jq   # Debian/Ubuntu
```

macOS 의 기본 `/bin/bash` 는 3.2 버전이며, 이 버전의 bats 실행기는 비-ASCII `@test` 이름(이 저장소의 테스트 이름은 전부 한글이다)을 깨뜨려 `bats: unknown test name` 류의 알쏭달쏭한 오류를 낸다. macOS 에서는 `brew install bash` 로 최신 bash 를 설치하고 PATH 앞쪽에 두어 `bats` 가 그 bash 로 실행되게 하라(예: `PATH="/opt/homebrew/bin:$PATH"`).

이 요구사항은 **테스트 실행기 한정**이다. 플러그인이 실제로 배포하는 `scripts/*.sh`, `hooks/*.sh` 는 여전히 bash 3.2 와 호환되게 작성한다 — 연관 배열 등 3.2 에 없는 기능을 쓰지 않는다. 런타임에 bash 5 를 요구하도록 "고치지" 말 것.

## 테스트

```bash
bats tests/                                        # 전체
bats tests/pending-set.bats                        # 개별
shellcheck scripts/*.sh hooks/*.sh tests/helper.bash
```

테스트는 매번 `mktemp -d` 로 새 git 저장소를 만든다. 커밋된 `.git` 픽스처를 저장소에 넣지 않는다.

## 설계 원칙

1. **훅에 LLM 을 넣지 않는다.** 판정은 결정적이어야 테스트할 수 있다
2. **fail-open.** 게이트 버그가 커밋을 영구 차단해서는 안 된다
3. **`pending-set.sh` 는 단일 진실 공급원이다.** "무엇이 커밋되는가"의 정의가 갈라지면 교착이 난다
4. **근거 없는 문항은 출제하지 않는다.** 틀린 정답은 사용자를 가둔다

설계 결정과 기각된 대안은 [docs/DECISIONS.md](docs/DECISIONS.md) 에 있다. 결정을 바꿀 때는 항목을 지우지 말고 상태와 변경 이력을 덧붙인다.

## 커밋 메시지

Conventional Commits 를 쓴다: `feat:`, `fix:`, `test:`, `docs:`, `chore:`
