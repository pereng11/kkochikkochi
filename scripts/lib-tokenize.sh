# shellcheck shell=bash
# 커맨드 문자열 파서 — gate.sh · pending-set.sh · record-pass.sh 가 공유한다.
#
# source 전용이다(실행 파일이 아니다). 아무것도 의존하지 않는다 —
# 의존 그래프를 비순환으로 유지하기 위해서다.
#
# **왜 공유하는가.** 예전에는 gate.sh 가 따옴표를 이해하는 상태 기계로,
# pending-set.sh 가 `${CMD#*git }` + `set -- $ARGS` 로 *같은 문자열*을 각각
# 파싱했다. 파서가 둘이면 답도 둘이다. 그 결과:
#   - `-m "fix: handle -- separator"` 의 `--` 가 독립 토큰이 되어 그 뒤 전부가
#     pathspec 이 되고, 커밋 대상 집합이 통째로 비어 게이트가 조용히 꺼졌다.
#   - `git commit -m x a.ts` 의 bare pathspec 이 어느 case 에도 걸리지 않고
#     버려져, 워크트리 내용이 검증 없이 커밋됐다.
# 파서는 하나여야 한다.

# tokenize_cmd "<커맨드 문자열>"
#
# 원본 커맨드를 통째로, 따옴표를 이해하는 상태 기계로 단 한 번에 토큰화한다.
# 세그먼트(; && || | 로 나뉘는 단위) 경계와 단어 분리를 같은 패스에서
# 처리하므로, 따옴표 안에 숨은 구분자 때문에 두 번 쪼갠 결과가 서로 다른
# 개수로 갈라지는 일이 구조적으로 있을 수 없다. eval 을 쓰지 않으므로 값
# 안에 $(...) 같은 게 있어도 실행하지 않는다.
#
# 결과: 전역 배열 TOKENS(모든 세그먼트를 통틀어 순서대로 나열한, 따옴표가
# 제거된 실제 토큰들)와 TOK_SEG(TOKENS 와 길이가 같고, 각 토큰이 속한
# 세그먼트 번호를 담는다. 0부터 시작).
tokenize_cmd() {
  TOKENS=()
  TOK_SEG=()
  local rest="$1" buf="" word="" c c2 i len blen last
  local in_sq=0 in_dq=0 have_word=0 seg=0 tab
  tab="$(printf '\t')"

  # 긴 커맨드에서 `${s:$i:1}` 은 매번 문자열 앞부분을 훑으므로 전체가
  # O(n^2) 가 된다(측정: 20 KB → 4.0 s, 훅 타임아웃 10 s 를 35 KB 근처에서
  # 넘긴다). 고정 크기 조각으로 잘라 처리하면 훑는 거리가 조각 크기로
  # 묶여 사실상 선형이 된다. 상태 기계이므로 조각 경계를 넘어가도 결과는
  # 같다 — 단 `&&` `||` 는 2글자라, 조각 끝에 걸린 `&`/`|` 는 다음 조각으로
  # 넘겨 경계에서 잘리지 않게 한다.
  while [ -n "$rest" ]; do
    buf="${rest:0:1024}"
    rest="${rest:1024}"
    if [ -n "$rest" ]; then
      blen=${#buf}
      last="${buf:$((blen - 1)):1}"
      case "$last" in
        "&" | "|")
          buf="${buf:0:$((blen - 1))}"
          rest="$last$rest"
          ;;
      esac
    fi

    i=0
    len=${#buf}
    while [ "$i" -lt "$len" ]; do
      c="${buf:$i:1}"
      if [ "$in_sq" -eq 1 ]; then
        if [ "$c" = "'" ]; then
          in_sq=0
        else
          word+="$c"
        fi
        i=$((i + 1))
        continue
      fi
      if [ "$in_dq" -eq 1 ]; then
        if [ "$c" = '"' ]; then
          in_dq=0
        else
          word+="$c"
        fi
        i=$((i + 1))
        continue
      fi
      # 따옴표 밖에 있을 때만 구분자/공백/따옴표 시작을 인식한다.
      c2="${buf:$i:2}"
      if [ "$c2" = "&&" ] || [ "$c2" = "||" ]; then
        if [ "$have_word" -eq 1 ]; then
          TOKENS+=("$word"); TOK_SEG+=("$seg"); word=""; have_word=0
        fi
        seg=$((seg + 1))
        i=$((i + 2))
        continue
      fi
      case "$c" in
        ";" | "|")
          if [ "$have_word" -eq 1 ]; then
            TOKENS+=("$word"); TOK_SEG+=("$seg"); word=""; have_word=0
          fi
          seg=$((seg + 1))
          ;;
        "'")
          in_sq=1
          have_word=1
          ;;
        '"')
          in_dq=1
          have_word=1
          ;;
        " " | "$tab")
          if [ "$have_word" -eq 1 ]; then
            TOKENS+=("$word"); TOK_SEG+=("$seg"); word=""; have_word=0
          fi
          ;;
        *)
          word+="$c"
          have_word=1
          ;;
      esac
      i=$((i + 1))
    done
  done

  if [ "$have_word" -eq 1 ]; then
    TOKENS+=("$word"); TOK_SEG+=("$seg")
  fi
}

# parse_git_commit "<커맨드 문자열>"
#
# 이 커맨드가 git commit 인가를 판정하고, 맞으면 그 호출의 정보를 채운다.
# 접두 매칭(`Bash(git commit:*)`)은 `cd x && git commit` 을 놓치므로 쓰지
# 않는다. 게이트에서는 누락이 곧 실패다. 직접 토큰 단위로 판정한다.
#
# 성공(0) 시 채우는 전역:
#   GIT_C_DIR   - `git -C <dir>` 의 값(없으면 빈 문자열). 여러 -C 는 합성하지
#                 않는다 — 마지막 값만 쓰고, 호출자의 기준 디렉터리로 바로
#                 해석한다(git 처럼 이전 -C 에 상대적으로 누적하지 않는다).
#   COMMIT_ARGS - `commit` 뒤에 오는, 같은 세그먼트의 토큰들. 이것이 이
#                 커밋의 인자 전부다. 세그먼트 경계 너머는 다른 명령이다.
#
# 실패(1) 시에도 두 전역은 초기화된 상태로 남는다(GIT_C_DIR="", 빈 배열).
parse_git_commit() {
  local i j n tok seg cur_seg found_git c_seg c_tok_idx
  # shellcheck disable=SC2034  # 호출자(gate.sh, record-pass.sh)가 읽는 출력이다
  GIT_C_DIR=""
  COMMIT_ARGS=()
  tokenize_cmd "$1"
  n=${#TOKENS[@]}
  cur_seg=-1
  found_git=0
  c_seg=-1
  c_tok_idx=-1
  i=0
  while [ "$i" -lt "$n" ]; do
    tok="${TOKENS[$i]}"
    seg="${TOK_SEG[$i]}"
    if [ "$seg" != "$cur_seg" ]; then
      cur_seg="$seg"
      found_git=0
    fi
    if [ "$found_git" -eq 0 ]; then
      case "$tok" in
        git | */git) found_git=1 ;;
      esac
    else
      case "$tok" in
        -C)
          # 값은 바로 다음 토큰이다. TOKENS 는 이미 따옴표가 제거된
          # 실제 값이므로, 나중에 다시 원본을 뒤질 필요가 없다.
          # 단, -C 가 자기 세그먼트의 마지막 토큰이면(예: `git -C;
          # git commit`) 다음 토큰은 완전히 다른 세그먼트의 것이다 —
          # 그걸 값으로 건너뛰면 그 세그먼트의 진짜 git 호출을 통째로
          # 건너뛰게 된다. 그래서 여기서도 아래 commit 판정과 똑같이
          # "같은 세그먼트인가" 를 확인한다.
          if [ "$((i + 1))" -lt "$n" ] && [ "${TOK_SEG[$((i + 1))]}" = "$cur_seg" ]; then
            c_seg="$cur_seg"
            c_tok_idx=$((i + 1))
            i=$((i + 1))   # -C 의 값 토큰은 분류 대상에서 건너뛴다
          fi
          ;;
        # git 레벨 옵션은 값까지 건너뛴다 — 단, 그 값이 같은
        # 세그먼트 안에 있을 때만. 세그먼트 경계 너머는 다른 명령이다.
        -c | --git-dir | --work-tree | --namespace)
          if [ "$((i + 1))" -lt "$n" ] && [ "${TOK_SEG[$((i + 1))]}" = "$cur_seg" ]; then
            i=$((i + 1))
          fi
          ;;
        --*=* | -*) : ;;
        commit)
          if [ "$c_seg" = "$cur_seg" ] && [ "$c_tok_idx" -ge 0 ] &&
             [ "$c_tok_idx" -lt "$n" ] && [ "${TOK_SEG[$c_tok_idx]}" = "$cur_seg" ]; then
            # shellcheck disable=SC2034  # 호출자가 읽는 출력 전역이다
            GIT_C_DIR="${TOKENS[$c_tok_idx]}"
          fi
          # commit 뒤, 같은 세그먼트에 남은 토큰이 이 커밋의 인자 전부다.
          j=$((i + 1))
          while [ "$j" -lt "$n" ] && [ "${TOK_SEG[$j]}" = "$cur_seg" ]; do
            COMMIT_ARGS+=("${TOKENS[$j]}")
            j=$((j + 1))
          done
          return 0
          ;;
        *)
          found_git=0   # 다른 서브커맨드 → 이 git 은 아님
          c_seg=-1
          c_tok_idx=-1
          ;;
      esac
    fi
    i=$((i + 1))
  done
  return 1
}
