# KkochiKkochi — push 검사 범위와 Codex 트리거 매핑 설계

작성일: 2026-08-01
보완 대상: `2026-07-30-parallel-gate-design.md`. 그 문서의 층 구조는 그대로 두고, **`pre-push` 가 무엇을 볼 것인가**를 좁히고, 같은 문서가 틀린 전제 위에 세워 둔 **Codex 이벤트 매핑**을 사실로 교체한다.

---

## 0. 기준점

> **우리가 푸는 문제는 "AI가 사람이 흡수하는 속도보다 빠르게 코드를 만든다"는 것이다.**
> **따라서 이 도구는 에이전트가 만든 커밋에서만 켜진다.**

D00 은 그대로다. 이 문서는 그 문장을 `pre-push` 에 처음으로 적용한다 — 지금 `pre-push` 는 D00 을 전혀 참조하지 않고 `covered.tsv` 에 없는 blob 이면 무엇이든 막는다.

여기에 규칙 하나를 더한다.

> **게이트는 자기가 볼 수 있었던 적 없는 커밋에 대해 의견을 갖지 않는다.**

`git pull` 로 들어온 남의 커밋, 원격 브랜치에서 분기할 때 딸려온 기준점, 게이트를 설치하기 전의 이력 — 이 셋은 사용자가 에이전트로 작업한 코드가 아니다. 게이트가 존재하지도 않던 시점에 만들어진 것을 막는 것은 D00 이 말하는 "막아야 할 커밋"이 아니다.

## 1. 왜 바꾸는가 — 실측한 구멍

`hooks/pre-push:114-119` 의 범위 계산이 두 갈래다.

```sh
if is_null_sha "$remote_sha"; then range="$local_sha --not --remotes"
else                              range="$remote_sha..$local_sha"; fi
```

격리된 픽스처에서 재현했다. (모든 git 명령에 `-C <절대경로>`, scratchpad 안에서만 — `progress.md` 의 2026-08-01 사고 재발 방지)

| 실험 | 관찰 | 뜻 |
|---|---|---|
| 1. 리모트 추적 ref 가 하나도 없을 때 `rev-list HEAD --not --remotes` | **1 커밋** (초기 커밋이 남는다) | `git init` 저장소의 첫 push 는 초기 커밋이 검사 대상이다 |
| 2. push 후 `origin/main` 이 생긴 뒤 같은 명령 | **0 커밋** | clone 해 온 이력은 `--remotes` 만으로 전부 빠진다 |
| 3. feature 를 push 해 둔 뒤 `git pull origin main`, 그리고 다시 push. 현행 `remote..local` | 동료 커밋 `colleague work` 가 **검사 대상에 들어온다** | **주된 구멍.** 기존 브랜치 경로가 pull 을 못 뺀다 |
| 3'. 같은 상황, `local --not --remotes` | 동료 커밋이 빠지고 내 커밋 2개만 남는다 | 새 브랜치 경로의 규칙이 이 문제를 이미 풀고 있다 |
| 4. 깨끗한 pull 병합 커밋에 `diff-tree --cc` | **0줄** | 자동 병합분은 원래부터 안 본다. 병합 커밋이 범위에 남아도 무해하다 |
| 5. `rev-list HEAD --not <없는 객체>` | **rc=128** (`cat-file -e` 는 rc=1) | 제외 목록에 죽은 sha 가 하나라도 있으면 fail-closed 가 **모든 push 를 영구 차단**한다 |
| 6. `rev-list HEAD --not --remotes <sha>` | 전체 5 → `--not --remotes` 2 → sha 하나 더 부정 **1** | `--not` 은 뒤따르는 sha 에도 적용된다. epoch 을 `--remotes` 뒤에 이어 붙이면 된다 |
| 7. epoch 인자가 빈 문자열일 때 | 실험 6의 2와 같고 **rc=0** | epoch 파일이 없거나 비어 있어도 명령이 깨지지 않는다 |

즉 **새 브랜치 경로는 이미 옳고, 기존 브랜치 경로만 틀렸다.** 그리고 두 경로 다 게이트 설치 이전의 로컬 이력은 못 뺀다(실험 1).

## 2. 규칙 — 범위 계산에서 분기를 없앤다

```sh
range="$local_sha --not --remotes $epoch_args"
```

`$epoch_args` 는 살아 있는 epoch sha 를 공백으로 이은 문자열이고, 비어 있어도 된다(실험 6·7). `--not` 하나가 `--remotes` 와 뒤따르는 sha 전부에 적용되므로 `--not` 을 반복할 필요가 없다.

`remote_sha` 는 범위 계산에서 **완전히 빠진다.** 대신 로컬의 리모트 추적 ref 를 본다.

이 교체는 **안전 방향으로만 틀린다.**

| 추적 ref 상태 | 결과 |
|---|---|
| stale (fetch 안 함) — `remote_sha` 가 더 앞서 있다 | 덜 빼서 **더 많이** 검사한다 |
| 앞서 있다 (fetch 했지만 push 안 함) | 앞선 부분은 애초에 push 범위 밖이라 무관하다 |

`--remotes` 는 **모든 리모트**를 본다(사용자 결정). fork 워크플로에서 `upstream/main` 에서 도달 가능한 코드도 내가 에이전트로 쓴 것이 아니므로 제외 대상이다. `--remotes=<remote>/*` 로 좁히면 첫 fork push 가 퀴즈로 풀 수 없는 이유로 막힌다.

**남기는 것**: `local_sha` 의 16진수 가드(`:96`). `--not --remotes` 도 단어 분리를 거치므로 `local_sha` 자리에 `--all` 같은 진짜 rev-list 옵션이 들어가면 범위가 통째로 바뀐다 — `tests/pre-push.bats:99` 가 지키는 성질이고 그대로 유효하다.

**지우는 것**: `remote_sha` 의 16진수 가드(`:103-109`). 쓰지 않는 값을 검증할 이유가 없다.

**손대지 않는 것**: `hooks/pre-commit`. staged diff 만 보고, merge/cherry-pick/rebase 마커는 `:57` 에서 이미 통과시킨다.

## 3. epoch — 게이트가 볼 수 있었던 적 없는 이력

`--not --remotes` 로 안 풀리는 것이 하나 남는다: **리모트가 아직 없는 저장소의 로컬 이력**(실험 1). `git init` 직후의 초기 커밋, 게이트를 설치하기 전에 손으로 쌓아 둔 커밋이 여기 해당한다.

### 3.1 정의

| 항목 | 내용 |
|---|---|
| 무엇 | 게이트가 이 저장소에 설치될 때 **이미 존재하던 모든 ref 팁** |
| 위치 | `$(git rev-parse --git-common-dir)/quiz-gate/epoch`, 한 줄에 sha 하나 |
| 만드는 곳 | `scripts/install.sh install`, 훅을 놓기 **전에** |
| 읽는 곳 | `hooks/pre-push` **만** |
| 내용 | `git for-each-ref --format='%(objectname)' refs/heads refs/tags refs/remotes` + `git rev-parse --verify HEAD`(detached 대비), 중복 제거 |

ref 가 하나도 없는 저장소(첫 커밋 전 설치)에서는 빈 파일이 된다. 뺄 이력이 없으니 맞다.

### 3.2 수명 — `quiz-gate` 디렉터리와 생사를 같이한다

| 시점 | 동작 |
|---|---|
| `install` — epoch 파일이 **없으면** | 쓴다 |
| `install` — epoch 파일이 있으면 | 그대로 둔다 |
| `uninstall` | `.git/quiz-gate/` 를 통째로 지운다. 무엇을 지웠는지 stderr 에 알린다 |

**규칙이 하나다.** "파일이 없으면 쓴다"만으로 세 경우가 전부 맞는다.

```
uninstall 후 install   → quiz-gate 가 없다 → epoch 새로 씀   (새 출발)
플러그인 갱신 install   → epoch 이 있다     → 유지            (게이트가 조용히 리셋되지 않는다)
구버전에서 업그레이드   → epoch 만 없다     → 씀
```

두 번째 줄이 중요한 이유: `install` 은 "처음 설치"만 뜻하지 않는다. 훅이 낡으면 `stamp-agent.sh:126-131` 이 커밋을 거부하면서 **에이전트에게 `install` 을 시킨다.** 즉 플러그인이 업데이트될 때마다 모든 실유저의 저장소에서 `install` 이 다시 돈다. 여기서 epoch 을 갱신하면 사용자는 "업데이트했을 뿐"인데 그때까지 쌓인 미검증 커밋이 전부 면제된다 — 이 프로젝트가 내내 싸워온 "게이트가 조용히 꺼지는 것"의 새로운 모양이다.

**감수하는 대가**: 세 번째 줄. epoch 없는 버전에서 업그레이드하는 저장소는 그 시점까지의 미검증 커밋을 **1회 면제받는다.** 여기까지 살아남은 미검증 커밋은 `pre-commit` 과 `Stop` 두 층을 모두 빠져나온 것이라 드물고, 반대쪽 손해(초기 커밋이 어떤 퀴즈로도 안 풀리는 채로 영영 막힘)는 확실하다. 1회성이며 그 뒤로는 안정 상태다. README 한계 표에 적는다.

`uninstall` 이 `covered.tsv`·`passes/`·`ledger.tsv` 까지 지우는 것은 의도된 것이다(사용자 결정). epoch 과 커버리지가 함께 리셋되므로 "이력은 지워졌는데 검사는 계속되는" 어긋난 상태가 나지 않는다. 지금 `cmd_uninstall`(`install.sh:161-179`)은 훅 파일만 건드리므로 이 동작은 신규다.

### 3.3 D45 와의 관계

D45 는 "검증 대상을 고르는 규칙은 `scripts/pending.sh` 한 곳"이다. `pre-push` 는 이미 그 규칙을 지킬 수 없다 — 설치된 사본에서 플러그인의 `scripts/` 로 돌아갈 경로가 없어 `covered.tsv` 대조를 직접 다시 구현하고 있다(`hooks/pre-push:14-26` 이 그 긴장을 명시해 뒀다).

epoch 은 그 중복을 늘리지 않는다. **쓰기는 `install.sh` 에만, 읽기는 `pre-push` 에만** 있는 단방향이라 같은 규칙이 두 벌 생기지 않는다.

## 4. 실패를 어느 쪽으로 넘길 것인가

`pre-push` 는 fail-closed 층이라 "못 뺐다"가 곧 "막는다"가 된다. 그런데 **초기 이력은 퀴즈로 풀 수 없다** — `pending.sh` 는 staged 만 보므로 이미 커밋된 과거 blob 을 `covered.tsv` 에 넣을 방법이 없다. 그래서 epoch 관련 실패는 이미 있는 `unparseable` 범주로 보내 `--no-verify` 탈출구를 반드시 남긴다.

| 실패 | 처리 | 방향 |
|---|---|---|
| epoch 파일이 있는데 못 읽는다 (권한) | `unparseable` 로 쌓아 거부 + `--no-verify` 안내 | 막지만 탈출구가 있다 |
| epoch 의 어떤 줄이 죽은 객체다 (GC·브랜치 삭제) | **그 줄만 버리고 stderr 경고** | 덜 빼서 더 검사 |
| epoch 의 어떤 줄이 16진수가 아니다 | 같은 처리 (인자 주입 방어를 겸한다) | 덜 빼서 더 검사 |
| epoch 파일이 아예 없다 | 제외하지 않는다 = 현행 동작 | 회귀 아님 |
| `--remotes` 가 stale | 덜 빼서 더 검사 | 안전 방향 |

죽은 줄을 버리는 것이 필수인 이유는 실험 5다. 없는 객체 **하나**가 `rev-list` 를 128 로 죽이고, fail-closed 라 그 순간 저장소의 모든 push 가 퀴즈로도 못 푸는 상태로 영구 차단된다. D00/D42 가 금지하는 바로 그 모양이라, 여기서는 "애매하면 통과"가 아니라 **"애매한 줄만 버린다"** 가 답이다. 사전 검사는 `git cat-file -e` 로 한다(실험 5에서 rc=1 로 갈라짐을 확인).

## 5. Codex 트리거 매핑 — 틀린 전제를 사실로 교체한다

`2026-07-30-parallel-gate-design.md` 와 그 계획의 Global Constraints 는 "Codex 페이로드에는 `agent_id` 가 없다"를 전제로 서브에이전트 층을 Claude Code 전용으로 만들었다. `progress.md:96` 이 이미 그 전제를 정정했고, 이번에 `openai/codex` 원본에서 다시 확인했다.

근거: [`codex-rs/hooks/schema/generated/*.schema.json`](https://github.com/openai/codex/tree/main/codex-rs/hooks/schema/generated), [`codex-rs/core/src/tools/hook_names.rs`](https://github.com/openai/codex/blob/main/codex-rs/core/src/tools/hook_names.rs)

### 5.1 확인된 사실

| 항목 | 사실 | 현재 코드/문서 | 판정 |
|---|---|---|---|
| 셸 도구 hook name | `"Bash"` (`HookToolName::bash()`) | 루트 `hooks.json` 의 `matcher:"Bash"` | 맞다 |
| `agent_id`·`agent_type` | `PreToolUse`·`PostToolUse` 에 **optional**(서브에이전트일 때만 실린다), `SubagentStart`·`SubagentStop` 에 **required** | `tests/manifests.bats:97` 주석 "Codex 페이로드에는 agent_id 가 없다" | **거짓** |
| 서브에이전트 생성 도구 | `spawn_agent` (matcher alias `Agent`) | 계획이 Claude Code 를 따라 `Task` 를 상정 | **`Task` 는 Codex 에서 아무것도 매칭하지 않는다** |
| `SubagentStop` 실행 문맥 | **부모 세션**, `decision:"block"` + `reason` 지원 | `seal-bundle.sh:11-13` "서브에이전트 문맥이라 block 이 무의미하다" | **Claude Code 에만 해당** |
| `PreToolUse` 출력 | `hookSpecificOutput.{permissionDecision: allow\|deny\|ask, permissionDecisionReason}` | `stamp-agent.sh:88-95` 의 `deny()` | 와이어가 동일 — 그대로 동작 |
| `Stop`·`SubagentStop`·`SubagentStart`·`PreToolUse` | `cwd` 가 전부 required | `stop-gate.sh`·`seal-bundle.sh`·`bundle-notify.sh` 의 cwd 처리 | 그대로 동작 |
| 출력 스키마 | 전부 `additionalProperties: false` | 우리 JSON 에 잉여 키 없음 | 맞다 |
| `config` 스키마가 `Stop`·`SubagentStart`·`SubagentStop` 에 `matcher` 키를 허용하는가 | `codex-rs/config/src/hook_config.rs`: `HookEventsToml` 의 11개 이벤트가 전부 균일하게 `Vec<MatcherGroup>` 이고, `MatcherGroup { matcher: Option<String>, hooks: Vec<HookHandlerConfig> }` 의 `matcher` 는 `#[serde(default)]` — `deny_unknown_fields` 는 최상위 `HooksFile`(`description`·`hooks`)에만 있고 `MatcherGroup` 에는 없다 | 루트 `hooks.json` 이 `Stop`/`SubagentStart`/`SubagentStop` 에도 `matcher:"*"` 를 씀 | 문제없이 파싱된다 — 안 쓰일 뿐이고, 거부돼 매니페스트 전체(`PreToolUse` 핸드셰이크 포함)가 로드 실패하는 일은 없다 |

### 5.2 이벤트 매핑

두 에이전트의 층 구조는 같지만 **어느 이벤트에 거는지가 다르다.** 특히 `SubagentStop` 의 실행 문맥이 반대라, Codex 는 Claude Code 가 못 하는 일을 할 수 있다.

| 역할 | Claude Code | Codex |
|---|---|---|
| 핸드셰이크 | `PreToolUse(Bash)` → `stamp-agent.sh` | 동일 |
| 번들 열기 | `SubagentStart` → `seal-bundle.sh --event start` | 동일 |
| 번들 봉인 | `SubagentStop` → `seal-bundle.sh --event stop` | 동일 |
| 검증 요구 | `PostToolUse(Task)` → `bundle-notify.sh` (부모 문맥, 차단 불가) | `PostToolUse(spawn_agent)` → `bundle-notify.sh` |
| 턴 차단 | `Stop` → `stop-gate.sh` | 동일 |

`SubagentStop` 의 실행 문맥이 두 에이전트에서 반대인데도 `seal-bundle.sh` 를 그대로 쓸 수 있는 이유: 이 스크립트는 **판정하지 않고 기록만 한다.** 필요한 것은 `agent_id`(두 에이전트 모두 required)와 `cwd`(두 에이전트 모두 required)뿐이고, 출력이 없으므로 문맥에 따라 달라지는 차단 의미론에 닿지 않는다.

`bundle-notify.sh` 를 `PostToolUse` 에 그대로 두는 이유: `SubagentStop` 은 봉인을 담당하고, 봉인된 번들을 근거로 요구를 만드는 것은 그 **다음** 단계다. 한 이벤트에 두 스크립트를 매다는 것보다 두 에이전트의 배선이 같아지는 쪽이 낫다 — `bundle-notify.sh` 가 봉인 여부를 `agents/<hash>` 의 `sealed_at` 으로 판정하는 현재 구조(`bundle-notify.sh:119-120`)를 그대로 쓸 수 있다.

Codex 의 `SubagentStop` 이 `decision:"block"` 을 지원한다는 사실은 **이번 범위에서 쓰지 않는다.** 쓰면 두 에이전트의 층이 갈라져 유지보수가 두 벌이 되고, `Stop` 이 이미 같은 일을 하며 그쪽은 두 에이전트가 공유한다. 이 문서에 사실만 기록해 두고 필요해지면 그때 꺼낸다.

표의 "차단 불가"는 두 에이전트 모두에 해당한다. `PostToolUse` 는 스키마상 `decision:"block"` 을 받지만 **도구가 이미 실행된 뒤**라 그 커밋을 되돌리지 못한다(`bundle-notify.sh:69-71`). 그래서 이 자리의 역할은 요구를 주입하는 것이고, 실제 차단은 `Stop` 이 한다.

### 5.3 정정해야 할 문서·테스트

- `tests/manifests.bats:97` "Codex 매니페스트에는 서브에이전트 훅이 없다" — **뒤집는다.** 주석의 전제도 함께 지운다
- `docs/superpowers/plans/2026-07-30-parallel-gate.md` 의 Global Constraints — "Codex 페이로드에는 agent_id 가 없다" 삭제
- `2026-07-30-parallel-gate-design.md` — 같은 전제가 남아 있으면 정정
- 미지 하네스(매니페스트 없음 → 마커 없음 → `pre-commit:120` 의 D35 통과)를 테스트로 고정한다. 지금은 의도된 동작인데 못이 박혀 있지 않다

## 6. 불변 조건

1. **이해와 무관한 이유로 커밋·push 를 영구히 막지 않는다.** epoch 관련 모든 실패는 `--no-verify` 탈출구를 메시지에 남긴다 (D00/D42)
2. **범위 계산의 오판은 "더 많이 검사하는" 쪽으로만 흐른다.** stale 추적 ref, 죽은 epoch 줄, 손상된 epoch 줄 전부 이 방향이다
3. **epoch 은 단방향이다.** `install.sh` 만 쓰고 `pre-push` 만 읽는다 (D45 의 정신)
4. **`pre-push` 는 여전히 fail-closed 다.** `rev-list` 실패와 어긋난 `--raw` 스트림은 그대로 막는다 (Task 7 의 Critical 2)
5. **두 에이전트의 층 구조는 같다.** 이벤트 이름만 다르다 (D36, D37 의 연장)

## 7. 한계 (README 에 반영한다)

| 한계 | 설명 |
|---|---|
| `cherry-pick`·squash 로 가져온 남의 커밋은 제외되지 않는다 | 새 SHA 라 도달성 판정에 안 걸린다. 제대로 하려면 patch-id 를 리모트 전체에 돌려야 하는데 push 마다 비용이 크다. **교착은 아니다** — 막히면 퀴즈로 풀린다. `pre-commit` 은 `CHERRY_PICK_HEAD` 를 보고 이미 통과시키므로 두 층의 판단이 갈리는 지점이다 |
| epoch 없는 버전에서 업그레이드하면 미검증 커밋이 1회 면제된다 | §3.2 참고. 1회성이다 |
| **`pre-push` 는 사람이 손으로 만든 커밋도 막는다** | 이 층은 출처를 보지 않는다. `pre-commit` 의 TTY·핸드셰이크 신호를 사후에 복원할 방법이 없기 때문이다. 지금도 그러하나 README 한계 표에 빠져 있다 |
| 추적 ref 가 stale 하면 이미 리모트에 있는 커밋도 검사한다 | `git fetch` 하면 풀린다. 안전 방향이라 그대로 둔다 |
| `uninstall` 은 검증 이력을 함께 지운다 | `passes/*.json`(`/kk-log` 가 읽는 감사 기록)은 복구되지 않는다. 무엇을 지웠는지 stderr 에 알린다 |
| 워크트리는 `quiz-gate` 를 공유한다 | 한 워크트리에서 `uninstall` 하면 전부 사라진다. 훅(`.git/hooks/`)도 공유되므로 동작 자체는 일관된다 |

## 8. 테스트 계획

이 저장소 관례대로 **"되돌려도 통과하는 테스트"는 만들지 않는다**(`progress.md:131` 의 품질 메모). 각 항목은 해당 코드를 지웠을 때 실제로 빨개지는지 확인한 뒤 넣는다.

### 뒤집히는 기존 테스트 (`tests/pre-push.bats`)

| 테스트 | 어떻게 |
|---|---|
| `:53` 새 브랜치에서도 범위를 잡는다 | 분기가 사라졌으므로 "`remote_sha` 가 0이든 아니든 같은 규칙"으로 |
| `:117` remote sha 형식이 이상하면 거부한다 | **뒤집는다** — "`remote_sha` 가 무엇이든 범위 계산에 영향을 주지 않는다" |
| `:130` 범위를 계산할 수 없으면 거부한다 | **재현 방법을 바꾼다.** 모르는 `remote_sha` 로는 더 이상 `rev-list` 가 죽지 않는다 → 로컬에 없는 `local_sha` 로 재현. Critical 2 의 fail-closed 성질은 반드시 유지 |

### 새 테스트

- pull 로 들어온 남의 커밋이 검사에서 빠진다 (실험 3)
- 리모트 기준으로 새 브랜치를 만들었을 때 기준점 커밋이 빠진다
- 리모트가 없는 `git init` 저장소에서 epoch 이 초기 커밋을 뺀다 (실험 1)
- epoch 의 죽은 sha 가 push 를 막지 못한다 (실험 5)
- epoch 의 16진수 아닌 줄이 `rev-list` 인자로 새지 않는다
- 깨끗한 pull 병합 커밋이 아무것도 요구하지 않는다 (실험 4 — `--cc` 회귀 가드)
- `install` 이 epoch 이 없을 때만 쓴다 / `uninstall` 이 `quiz-gate` 를 지운다
- 미지 하네스는 마커가 없어 통과한다 (§5.3)

### 격리 규칙 (반드시 브리핑에 넣는다)

`progress.md:181` 의 2026-08-01 사고 — 리뷰가 "진짜 push 를 해 보라"고 지시하면서 격리를 강제하지 않아 `cd` 실패가 감지되지 않았고, 실제 저장소의 `main` 이 두 번 오염됐다.

- git 을 변형하는 명령은 scratchpad 아래에서만 실행한다
- **모든 git 명령에 `-C <절대경로>` 를 붙인다. `cd` 에 의존하지 않는다**
- 이 저장소에서 `commit`·`push`·`checkout`·`reset`·`branch` 를 절대 실행하지 않는다
- 리모트를 건드리는 명령은 `origin` 이 로컬 경로일 때만 허용한다

## 9. 새 결정 — D47

> **D47. 게이트는 자기가 볼 수 있었던 적 없는 커밋에 의견을 갖지 않는다** ✅
>
> `pre-push` 의 검사 범위에서 (a) 어느 리모트 추적 ref 에서든 도달 가능한 커밋과 (b) 게이트 설치 시점(epoch)의 ref 팁에서 도달 가능한 커밋을 뺀다.
>
> **왜**: D00 은 "AI 가 사람이 흡수하는 속도보다 빠르게 코드를 만든다"를 문제로 놓는다. `git pull` 로 들어온 남의 커밋, 브랜치 분기점, 게이트 설치 이전의 이력은 그 문제에 해당하지 않는다. 그것들을 막는 것은 D00 이 말하는 "막아야 할 커밋을 정확히 막는 것"이 아니라 "더 많이 막는 것"이다 — D44 가 같은 이유로 핸드셰이크를 좁혔다.
>
> **대가**: `cherry-pick` 으로 가져온 남의 커밋은 새 SHA 라 여전히 걸린다(§7). 그리고 epoch 이 없는 저장소를 업그레이드하면 1회 면제가 생긴다(§3.2).
>
> **되돌리는 조건**: 도달성 제외 때문에 실제로 검증되어야 할 코드가 새어나간 사례가 관찰되면.

## 10. 구현 순서

두 갈래는 건드리는 파일이 겹치지 않아 독립적으로 진행할 수 있다.

| 순서 | 범위 | 파일 |
|---|---|---|
| A1 | epoch 쓰기·`uninstall` 정리 | `scripts/install.sh`, `tests/install.bats` |
| A2 | `pre-push` 범위 계산 교체 + epoch 읽기 | `hooks/pre-push`, `tests/pre-push.bats` |
| B1 | Codex 매니페스트에 훅 4종 등록 (`spawn_agent` 매처 포함) | `hooks.json`, `tests/manifests.bats` |
| B2 | 계획·스펙의 틀린 Codex 전제 삭제, 미지 하네스 테스트 고정 | `docs/superpowers/plans/2026-07-30-parallel-gate.md`, `2026-07-30-parallel-gate-design.md`, `tests/manifests.bats` |
| C | 문서 갱신 | `README.md`(§7 한계 표·통과 커맨드 절), `docs/DECISIONS.md`(D47), `CHANGELOG.md` |

A1 이 A2 보다 먼저다 — epoch 파일이 없으면 A2 는 현행 동작으로 떨어지므로 순서를 지켜야 새 경로가 실제로 검증된다.

C 의 README 갱신은 이 브랜치가 미뤄 온 부채를 함께 갚는다. `progress.md:44` 가 "README·CHANGELOG 갱신이 Task 1~8 어디에도 없다"고 기록해 둔 그 구멍이다 — v3 의 훅 4종·`pre-push`·원장·번들이 아직 README 에 없고, `README.md:156` 의 `pass_id` 초 해상도 한계는 이미 고쳐져 거짓이다.
