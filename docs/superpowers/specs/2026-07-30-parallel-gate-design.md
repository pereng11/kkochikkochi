# KkochiKkochi v3 — 병렬 서브에이전트 게이트 설계

작성일: 2026-07-30
대체 대상: `2026-07-30-kkochikkochi-v2-hybrid-design.md` §3(아키텍처)에 층을 추가한다. v2의 단일 에이전트 경로는 **그대로 유효하다.**

---

## 0. 기준점

> **우리가 푸는 문제는 "AI가 사람이 흡수하는 속도보다 빠르게 코드를 만든다"는 것이다.**
> **따라서 이 도구는 에이전트가 만든 커밋에서만 켜진다.**
> **다만 정확한 타이밍을 보장하고 깔끔하게 동작하기 위해 git 훅 기반으로 설계한다.**

D00 이 그대로 기준점이다. 이 문서가 건드리는 것은 "언제 묻는가"이고, "왜 묻는가"와 "누구의 커밋에서 켜는가"는 바꾸지 않는다.

## 1. 왜 바꾸는가

v2 의 게이트는 `pre-commit` 에서 커밋을 **차단한다.** 병렬 서브에이전트에서는 이것이 작동하지 않는다.

**차단이 풀릴 방법이 없다.** 퀴즈는 `AskUserQuestion` 으로 사람에게 낸다(`ask/claude-code.md`). 서브에이전트는 사용자에게 물을 수 없다. 그래서 서브에이전트가 게이트에 막히면 통과할 길이 없고, 최선이 부모에게 실패를 보고하는 것이다. 병렬 N개가 커밋하면 N개가 전부 그 상태가 된다.

**상태 파일이 섞인다.** `.git/quiz-gate/` 는 저장소당 하나이고 잠금이 없다. 실측한 경합은 §2에 적는다.

## 2. 실측 — 병렬 서브에이전트에서 무엇이 관찰되는가

라이브 `PreToolUse` 훅에 임시 로깅을 넣고, 완료 순서가 실행 순서와 다르도록 서브에이전트 3개를 띄웠다. 실행 A(2초)·B(30초)·C(14초), 완료 A·C·B.

```
 +24.72  a3afdf6e…  A  python3 -c "…sleep(2)"
 +24.86  a0715418…  B  python3 -c "…sleep(30)"
 +26.79  adf5ba0d…  C  python3 -c "…sleep(14)"
 +26.85  a3afdf6e…  A  echo kkprobe-A-done
 +34.19  (메인)        (부모가 자기 일을 한다)
 +42.71  adf5ba0d…  C  echo kkprobe-C-done
 +56.79  a0715418…  B  echo kkprobe-B-done
```

| 관찰 | 값 | 설계에 주는 제약 |
|---|---|---|
| `agent_id` | 서브에이전트마다 다르고 안정적, 메인 스레드는 `null` | 모드 판별과 번들 귀속의 **유일한** 키 |
| `agent_type` | `general-purpose` 로 실려 옴 | 번들 이름표 |
| `session_id` | **메인과 세 서브에이전트가 전부 동일** | 현행 마커 `claude-code/<session_id>` 는 귀속 정보가 없다 |
| `cwd` | 전부 동일 (워크트리 격리 없이) | cwd 로는 가를 수 없다 |
| 훅 이벤트 | 같은 채널에 직렬화, 같은 시각에 겹치지 않음 | 마커 쓰기가 원자적일 필요는 없다 |
| 스탬프 간격 | A 와 B 가 **0.14초** | 단일 마커 파일은 실제로 덮어써진다 |
| 완료 알림 | 완료 순서대로 하나씩 따로 도착 | 번들은 순차로 처리할 수 있다 |
| 부모의 행동 | 알림 사이에 자기 일을 한다 | 번들 여러 개가 한 번에 도착할 수 있다 |

SDK 타입 정의가 같은 것을 말한다.

> `agent_id`: Sub-agent identifier. Present only when the hook fires from inside a Task-spawned sub-agent; absent on the main thread. When multiple sub-agents run in parallel their tool-lifecycle hooks interleave over the same control channel — this is the only reliable way to attribute each one to the correct sub-agent.

워크트리 격리를 쓰면 상태 위치도 갈린다. 실측:

```
링크된 워크트리:  --git-path quiz-gate → .git/worktrees/wt1/quiz-gate   (워크트리별)
                 --git-path hooks     → .git/hooks                      (공유)
```

훅은 공유되므로 워크트리에서도 게이트가 켜지지만, 상태가 워크트리별이라 **메인 세션의 훅이 그 커밋을 보지 못한다.**

## 3. 층

| 훅 | 조건 | 행동 |
|---|---|---|
| `pre-commit` | 신선한 `agent_id` 마커 없음 | **막는다** — v2 로직 그대로 |
| `pre-commit` | 신선한 `agent_id` 마커 있음 | 원장에 적고 **통과** |
| `PostToolUse` (`Task`) | 유예 모드 아님 | 그 `agent_id` 의 번들을 부모 문맥에 밀어 넣어 퀴즈 |
| `PostToolUse` (`Task`) | 유예 모드 | 아무것도 하지 않는다 |
| `SubagentStart` | — | `agents/<agent_id>` 에 `agent_type` 과 시작 시각을 적는다 |
| `SubagentStop` | — | 그 번들을 닫는다 (종료 시각 기록) |
| `Stop` | 원장에 미검증 번들 있음 | `decision: "block"` — 유예 모드와 무관하게 |
| `pre-push` | push 범위에 미검증 커밋 | 거부하고 `/kk` 를 안내 |

### 왜 `SubagentStop` 에서 퀴즈를 내지 않는가

`SubagentStop` 은 서브에이전트 문맥에서 돈다. 거기서 `block` 을 내면 **그 서브에이전트가 계속 일하게 된다.** 사람에게 묻는 채널이 없으므로 검증은 불가능하고, 번들 경계를 확정하는 데만 쓸 수 있다.

가장 가까운 자리가 `PostToolUse` + matcher `Task` 다. 서브에이전트가 끝나 결과가 부모로 돌아오는 순간 **부모 문맥에서** 발동하므로, 거기서는 `AskUserQuestion` 을 쓸 수 있다.

밀어 넣는 방법은 `hookSpecificOutput.additionalContext` 다. 훅이 "이 번들에 미검증 변경이 있다, kkochikkochi 스킬을 실행해 검증하라"와 `agent_id` 를 넘긴다. 훅이 직접 퀴즈를 내지 않는다 — 훅에는 사람에게 묻는 채널이 없고 `timeout` 이 걸려 있다(§6).

### `Stop` 훅과 무한 루프

`Stop` 페이로드에는 `stop_hook_active` 가 있다. 이미 `Stop` 훅 때문에 진행 중이라는 뜻이다. **그래도 계속 막는다** — 미검증 번들이 남아 있는 한 막는 것이 이 게이트의 존재 이유이고, 원장이 비면 자연히 통과하므로 종료 조건은 있다. 사람이 인터럽트로 빠져나가는 경로는 §10에 한계로 적는다.

### 왜 `Stop` 은 `command` 훅인가

`prompt` 타입(LLM 판정)도 지원된다. 쓰지 않는다. 이 프로젝트가 내내 싸워온 실패 모드가 **게이트가 조용히 꺼지는 것**이고, 판정을 LLM 에 맡기면 그 실패 모드를 설계에 초대한다.

## 4. 오판을 안전한 방향으로만 고정한다

`pre-commit` 은 git 이 부른 프로세스이므로 자기가 어느 에이전트인지 모른다. 마커가 여럿일 때 무엇을 볼지가 문제다.

> **규칙: 신선한 `agent_id` 마커가 하나라도 있으면 "적고 통과"로 간다.**

"신선한"의 기준은 현행 `FRESH_SECS=600` 을 그대로 쓴다. D44 가 그 값을 정한 근거(에이전트 셸 기동, 복합 명령에서 커밋 앞에 오는 것들, 체이닝된 훅의 실행 시간)가 병렬에서도 그대로 유효하고, 오히려 병렬에서는 커밋 앞에 오는 것이 더 길어질 수 있다.

두 방향의 오판이 대칭이 아니기 때문이다.

| 오판 | 결과 | 판정 |
|---|---|---|
| 메인 커밋을 서브에이전트로 봄 | 막지 않고 원장에 적는다 → `Stop` 과 `pre-push` 가 잡는다 | 검증이 사라지지 않고 **자리만 옮겨진다** |
| 서브에이전트 커밋을 메인으로 봄 | 막는다 → 서브에이전트는 사람에게 못 묻는다 | **갇힌다** |

대가는 하나다. 서브에이전트가 도는 동안 메인이 직접 커밋하면 `pre-commit` 에서 막히지 않고 턴 끝에 막힌다. 받아들인다 — D00 은 "막아야 할 커밋을 정확히 막는 것"이 목표라고 말하고, 이 경우 그 커밋은 막힌다. 시점만 다르다.

## 5. 상태

`git rev-parse --git-common-dir` 아래에 둔다. `--git-path` 는 워크트리마다 따로 만들어서, 워크트리로 격리된 서브에이전트의 커밋을 메인 세션 훅이 보지 못한다(§2 실측).

```
<common-dir>/quiz-gate/
  ledger.tsv        blob_sha  path  agent_id  agent_type  at
  covered.tsv       (현행 유지) blob_sha  path  pass_id
  pending           (현행 유지) 단일 에이전트 경로 전용
  marker/main       agent_id 없는 Bash 호출
  marker/<agent_id> 서브에이전트 Bash 호출
  agents/<agent_id> agent_type, 시작·종료 시각
  passes/<pass_id>.json
  defer             있으면 유예 모드
```

`commit_sha` 는 담지 않는다. `pre-commit` 은 커밋이 만들어지기 **전**에 도므로 그 값을 모른다. 필요도 없다 — `pre-push` 는 push 범위의 `git diff --raw` 를 `covered.tsv` 와 직접 대조하고, 원장은 번들 묶기와 `Stop` 판정에만 쓰인다.

### 마커를 `agent_id` 별로 쪼갠다

현행은 단일 `agent-session` 파일이다. §2에서 0.14초 간격의 덮어쓰기를 실측했다. `agent_id`(없으면 `main`)를 파일명으로 쓰면 병렬에서 서로 덮지 않는다.

### 원장의 경로 표기

`ledger.tsv` 는 탭 구분이므로 `covered.tsv` 와 **같은 제약과 같은 철자**를 쓴다. `git -c core.quotePath=false diff --cached --raw -z --abbrev=40 --no-renames` 로 얻은 원문 그대로 적고, 경로에 탭이나 개행이 있으면 `pending.sh` 가 이미 하는 것처럼 거부한다. 철자가 한 글자라도 달라지면 그 경로는 어떤 퀴즈로도 통과시킬 수 없는 채로 영영 막힌다.

### `pre-push` 의 push 범위

`pre-push` 훅은 stdin 으로 한 줄에 `<local ref> <local sha> <remote ref> <remote sha>` 를 받는다. `<remote sha>..<local sha>` 가 이번에 넘어가는 커밋이다. remote sha 가 40개의 0이면 새 브랜치이므로 `--not --remotes` 로 범위를 잡는다. 그 범위의 커밋에 `ledger.tsv` 의 미검증 항목이 걸리면 거부한다.

### `pass_id` 충돌을 막는다

현행 `pass_id="p-$(date -u +%Y%m%d-%H%M%S)"` 는 초 해상도다. 같은 초에 두 건이 통과하면 `mv` 가 앞 건의 `passes/<id>.json` 을 덮고, `covered.tsv` 는 남의 문답을 가리킨다. 감사 기록이 조용히 사라진다. `$$` 를 붙여 `p-<시각>-<pid>` 로 한다.

## 6. 유예 모드

큰 작업을 돌려놓고 나중에 확인하는 흐름을 지원한다. 구현 중에는 묻지 않고 맨 마지막에 몰아서 받는다.

**훅 기능으로는 만들 수 없다.** 훅의 `timeout`(기본 60초)은 시간이 지나면 훅을 **죽인다** — 판정이 사라지므로 훅이 사람의 답을 기다리는 구조는 성립하지 않는다. `async: true` + `asyncTimeout` 은 훅 실행을 미루는 것이지 사람의 답을 기다리는 것이 아니다.

그래서 파일 상태로 만든다. 오히려 더 튼튼하다 — 세션이 죽어도 살아남고 `pre-push` 가 마지막에 잡는다.

| | |
|---|---|
| 켜는 법 | `/kk defer` → `quiz-gate/defer` 를 만든다 |
| 효과 | `PostToolUse(Task)` 가 퀴즈를 내지 않고 원장만 쌓는다 |
| 범위 | **턴 끝까지.** `Stop` 은 유예와 무관하게 막는다 |
| 끄는 법 | `Stop` 이 통과되면 `defer` 를 지운다 |

자동 유예(살아있는 에이전트가 있으면 묻지 않음)는 채택하지 않는다. 사용자가 선언하는 편이 예측 가능하고, 자동 규칙은 "언제 물어볼지 모르겠다"는 상태를 만든다.

## 7. 번들 여러 개를 한 번에 받을 때

실측에서 부모는 알림 사이에 자기 일을 했다(+34.19, +45.65). 부모가 긴 도구 호출 안에 있으면 두 알림이 함께 도착한다.

- 번들을 **완료 순서대로 하나씩** 처리한다
- 번들마다 문항 예산은 5문항 상한을 그대로 유지한다 (SKILL.md §2)
- 번들 이름표는 `agents/<agent_id>` 의 `agent_type` 을 쓴다 — "code-reviewer 가 만든 3 커밋"

병렬 5개면 퀴즈가 5번이다. 이것이 "에이전트마다 한 번"의 대가이고 의도된 것이다. 커밋마다 내면 15번이 되고, 다 합쳐 한 번 내면 누가 무엇을 만들었는지가 사라진다.

## 8. 불변 조건

차단 경로가 넷이다 — `pre-commit`, `PostToolUse(Task)`, `Stop`, `pre-push`. D45 는 **"규칙이 두 벌 있으면 반드시 한쪽이 낡는다"**고 말하고, 이 저장소에서 이미 세 번 겪었다.

> **불변 조건: "지금 검증할 대상은 무엇인가"의 판정은 `scripts/pending.sh` 한 곳에만 있다. 네 경로가 모두 그것만 부른다.**

`pending.sh` 를 확장해 두 모드를 받는다.

| 호출 | 반환 |
|---|---|
| `pending.sh` | 단일 에이전트 경로 — 현행 그대로 (`pending` 또는 `git diff --cached`) |
| `pending.sh --bundle <agent_id>` | 그 번들의 미검증 (blob_sha, path) — `ledger.tsv` 에서 `covered.tsv` 를 뺀 것 |
| `pending.sh --all-unverified` | 원장 전체의 미검증 — `Stop` 과 `pre-push` 가 쓴다 |

출력 형식은 세 모드 모두 `<40자리 blob SHA>\t<경로>` 한 줄에 하나로 같다. `record-pass.sh` 는 같은 인자를 그대로 넘겨받아 부른다.

## 9. 기존 결정과의 관계

| 결정 | 상태 |
|---|---|
| D00 (제품 논지) | 유지. 바뀌는 것은 "언제 묻는가"뿐 |
| D01 (하드 차단) | 유지. 차단 지점이 `pre-commit` 하나에서 넷으로 늘어난다 |
| D40 (훅이 자기 답을 발표한다) | 유지·확장. `pending` 에 더해 `ledger.tsv` 도 훅이 발표한다 |
| D41 (TTY 우선) | 유지. 단일 에이전트 경로에 그대로 필요하다 |
| D44 (커밋처럼 보이는 명령에서만 스탬프) | 유지. 마커 파일명만 `agent_id` 별로 쪼갠다 |
| D45 (판정은 한 곳) | 유지·강화. §8 불변 조건 |
| D42 (jq 없으면 fail-open) | 유지. 새 훅도 같은 규칙을 따른다 |

## 10. 한계

| 한계 | 설명 |
|---|---|
| **같은 워크트리 병렬 커밋은 애초에 작동하지 않는다** | git 이 `index.lock` 으로 한쪽을 떨구고, 인덱스가 공유라 A 의 `git add` 가 B 의 파일을 실어 간다. 이 설계가 고치는 문제가 아니라 git 의 성질이다. 병렬 커밋을 원하면 워크트리 격리를 써야 한다 |
| **Esc 로 빠져나갈 수 있다** | `Stop` 훅은 에이전트를 막지만 사람은 언제든 인터럽트한다. 원장이 남으므로 다음 턴에 또 막히고, `pre-push` 가 최종 경계다 |
| **`git merge` 는 여전히 우회한다** | 클린 병합은 `pre-merge-commit` 을 부른다. 그 훅을 설치하지 않는다. v2 한계표 그대로 |
| **번들 이름표는 틀릴 수 있다** | 같은 워크트리에서 마커가 섞이면 `agent_id` 귀속이 틀린다. 검증 여부는 틀리지 않는다(§4) — 표시만 틀린다 |
| **`pre-push` 에서는 퀴즈를 낼 수 없다** | push 는 보통 명령 하나이고 사람에게 묻는 채널이 없다. 거부하고 안내만 한다 |

## 11. 테스트 계획

`tests/` 의 bats 구조를 그대로 쓴다.

| 파일 | 무엇을 |
|---|---|
| `pre-commit.bats` (확장) | `agent_id` 마커 있음 → 통과하고 원장에 적힌다 / 없음 → 막는다 / 여러 마커 중 하나만 `agent_id` → 통과 (§4 규칙) |
| `ledger.bats` (신규) | 원장 형식, 탭·개행 든 경로, `covered.tsv` 와의 차집합 |
| `pending.bats` (확장) | 세 모드가 같은 형식을 낸다, 번들 모드가 다른 에이전트 것을 섞지 않는다 |
| `stop-hook.bats` (신규) | 미검증 있음 → `decision: block` / 없음 → 통과 / `defer` 가 있어도 막는다 |
| `pre-push.bats` (신규) | push 범위 계산, 미검증 섞임 → 거부 |
| `record-pass.bats` (확장) | `pass_id` 에 pid 가 붙어 같은 초에 두 건이 충돌하지 않는다 |
| `defer.bats` (신규) | `defer` 가 `PostToolUse` 를 조용히 통과시킨다, `Stop` 통과 후 지워진다 |

## 12. 구현 순서

한 계획으로 담기에 크므로 아래 순서로 쪼갠다. 각 단계가 끝난 지점에서 게이트는 항상 동작하는 상태여야 한다 — 중간 상태에서 게이트가 꺼져 있으면 안 된다.

1. **상태 이전** — `--git-path` 에서 `--git-common-dir` 로, 마커를 `agent_id` 별 파일로, `pass_id` 에 pid 추가. 기존 단일 에이전트 경로의 동작은 바뀌지 않는다
2. **원장** — `ledger.tsv` 와 `pending.sh` 의 세 모드. 아직 아무 훅도 이것을 읽지 않는다
3. **`pre-commit` 분기** — §4 규칙. 이 단계에서 병렬 서브에이전트의 커밋이 처음으로 통과한다
4. **`Stop` 훅** — 3단계에서 통과시킨 것을 붙잡는 그물. **3과 4는 같은 변경으로 묶는다** — 3만 들어가면 그 사이 게이트가 헐거워진다
5. **`PostToolUse(Task)` 와 `SubagentStart`/`SubagentStop`** — 번들 단위 퀴즈와 이름표
6. **`pre-push`** — 최종 경계
7. **`/kk defer`** — 유예 모드
