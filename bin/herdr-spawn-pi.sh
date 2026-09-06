#!/usr/bin/env bash
# herdr-spawn-pi: 현재 탭에 병렬 작업용 pane을 만들고 pi 에이전트를 띄워 작업을 위임한다.
#
# 분할 규칙 (hermes=좌측 전체, pi=우측 세로 적층):
#   - hermes 우측에 아무 것도 없으면 -> hermes에서 split right (첫 2단 분리)
#   - 우측 열이 있으면              -> 우측 열 가장 아래 pane에서 split down (적층)
#   - 병렬 경합은 flock으로 직렬화
#   - 분할 후 우측 열 등분 재조정 (herdr-equalize.py)
#
# 응답 방식 (파일 버스 패턴):
#   pi에게 "결과를 <결과 디렉토리>/<name>.md 로 저장하라" 지시를 자동 추가하고,
#   완료 후 해당 파일을 읽어 stdout으로 출력한다. (터미널 스크롤 파싱 대신)
#
# 사용법:
#   herdr-spawn-pi.sh "<task description>"
#   herdr-spawn-pi.sh "<task>" --cwd /path/to/project
#   herdr-spawn-pi.sh "<task>" --out /custom/result.md
#
# 환경변수:
#   HERDR_OUT_DIR   결과 파일 디렉토리 (기본 ~/.hermes/delegation-results)
#
# 의존성: herdr (>= 0.8.0, pi integration 설치), jq, python3
set -euo pipefail

# 스크립트가 설치된 디렉토리 (lock/equalize 탐색 기준)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TASK=""
CWD="$HOME"
OUT_DIR="${HERDR_OUT_DIR:-$HOME/.hermes/delegation-results}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cwd) CWD="$2"; shift 2 ;;
    --out) OUT_DIR="$2"; shift 2 ;;
    *)     TASK="$1"; shift ;;
  esac
done

if [[ -z "$TASK" ]]; then
  echo "usage: $0 <task> [--cwd /path] [--out /path/to/result.md]" >&2
  exit 1
fi

# 결과 파일 경로 (PI_NAME 기반 고유 이름 — PID+나노초로 병렬 충돌 방지)
PI_NAME="pi-$$-$(date +%s%N)"
OUT_FILE="${OUT_DIR}/${PI_NAME}.md"
mkdir -p "$OUT_DIR"

# ---- 1. 현재(포커스된) 탭과 상태 파악 ----
CUR_TAB=$(herdr tab list | jq -r '.result.tabs[] | select(.focused==true) | .tab_id')
PANE_COUNT=$(herdr tab list | jq -r --arg t "$CUR_TAB" '.result.tabs[] | select(.tab_id==$t) | .pane_count')
echo "[herdr] tab=$CUR_TAB panes=$PANE_COUNT"

# ---- 2. 레이아웃 기반 분할 결정 (hermes=좌측 전체, pi=우측 세로 적층) ----
# 병렬 경합 방지: 분할 결정~실행을 파일락으로 직렬화 (3개 동시 split right 방지)
LOCK_FILE="${HERDR_LOCK_FILE:-$SCRIPT_DIR/.herdr-split.lock}"
exec 9>"$LOCK_FILE"
flock 9

# 레이아웃에서 hermes pane과 hermes 우측 경계를 구한다
LAYOUT_JSON=$(herdr pane layout 2>/dev/null)
HERMES_PANE=$(herdr pane list | jq -r --arg t "$CUR_TAB" \
  '.result.panes[] | select(.tab_id==$t and .agent=="hermes") | .pane_id' | head -1)
H_RIGHT=$(echo "$LAYOUT_JSON" | jq -r --arg h "$HERMES_PANE" \
  '[.result.layout.panes[] | select(.pane_id==$h) | .rect.x + .rect.width][0] // empty')

# 우측 열(hermes와 x 겹치지 않는 pane들) 판별
RIGHT_PANES=$(echo "$LAYOUT_JSON" | jq -r --arg h "$HERMES_PANE" --argjson hr "${H_RIGHT:-0}" '
  [.result.layout.panes[] | select(.pane_id != $h and .rect.x >= $hr)]
  | sort_by(.rect.y + .rect.height)
  | .[-1].pane_id // empty')

if [[ -z "$RIGHT_PANES" ]]; then
  # 우측 열 없음 → hermes에서 split right (첫 2단 분리)
  TARGET_PANE="--current"
  DIR="right"
  echo "[herdr] 우측 열 없음 -> hermes에서 split right"
else
  # 우측 열에서 가장 아래 pane에 split down (pi 스택 적층)
  TARGET_PANE="$RIGHT_PANES"
  DIR="down"
  echo "[herdr] 우측 열 가장 아래 $RIGHT_PANES -> split down"
fi

# ---- 3. 새 pane ID: split 반환값에서 직접 추출 (병렬 레이스 방지 — 차집합은 동시 실행 시 깨짐) ----
# (락을 split 실행까지 유지: 결정+실행 원자화)
SPLIT_JSON=$(herdr pane split $TARGET_PANE --direction "$DIR" --cwd "$CWD")
flock -u 9
NEW_PANE=$(echo "$SPLIT_JSON" | jq -r '.result.pane.pane_id // empty')
if [[ -z "$NEW_PANE" ]]; then
  echo "[herdr] ERROR: split 실패 — 응답에서 pane_id 못 얻음" >&2
  echo "$SPLIT_JSON" >&2
  exit 1
fi
echo "[herdr] new pane=$NEW_PANE"

# 우측 열 등분 재조정 (분할 후 모든 down-split 비율을 leaf 수 기준으로)
EQUALIZE="${HERDR_EQUALIZE:-$SCRIPT_DIR/herdr-equalize.py}"
if [[ -f "$EQUALIZE" ]]; then
  python3 "$EQUALIZE" "$CUR_TAB" >/dev/null 2>&1 || echo "[herdr] WARN: 등분 재조정 실패 (무시)" >&2
else
  echo "[herdr] WARN: herdr-equalize.py 없음 (등분 생략)" >&2
fi

# ---- 4. 새 pane에 pi 기동 후 작업 위임 (항상 새로 기동, 재사용 안 함) ----
# agent 이름은 전역 고유(agent_name_taken) — PID+나노초 기반 이름
if ! herdr agent start "$PI_NAME" --kind pi --pane "$NEW_PANE"; then
  echo "[herdr] ERROR: pi 기동 실패 — 새 pane $NEW_PANE 정리" >&2
  herdr pane close "$NEW_PANE" >/dev/null 2>&1
  exit 1
fi
echo "[herdr] pi 기동: $PI_NAME @ $NEW_PANE"

# 파일 버스 프롬프트: 결과를 OUT_FILE에 저장하라는 지시 추가
FULL_TASK="$TASK

[중요] 작업이 끝나면 결과를 반드시 다음 경로에 마크다운 형식으로 저장하세요: $OUT_FILE
저장 후 마지막 줄에 DONE 이라고 출력하세요. (파일 저장을 빼먹지 마세요)"
herdr agent prompt "$PI_NAME" "$FULL_TASK" --wait --timeout 120000
echo "[herdr] pi 작업 완료 (상태: done/idle)"

# 결과 파일 출력 (pi가 저장한 결과를 hermes가 읽음)
if [[ -f "$OUT_FILE" ]]; then
  echo "===== 결과 파일: $OUT_FILE ====="
  cat "$OUT_FILE"
  echo "===== 끝 ====="
else
  echo "[herdr] WARN: 결과 파일 없음: $OUT_FILE (pi가 저장 안 함) — pane read $NEW_PANE 로 확인" >&2
fi
echo "[herdr] done (pane=$NEW_PANE name=$PI_NAME)"