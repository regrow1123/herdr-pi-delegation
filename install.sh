#!/usr/bin/env bash
# herdr-pi-delegation installer
# Hermes(호스트) + herdr + pi(게스트) 위임 워크플로우 설치
#
# 설치 내용:
#   1. herdr 확인/안내 (0.8.x 필요, herdr update)
#   2. herdr↔pi 통합 설치 (herdr integration install pi)
#   3. 스킬 4개 설치 (~/.hermes/skills/autonomous-ai-agents/)
#   4. bin 스크립트 2개 설치 (~/.hermes/bin/)
#   5. PATH에 ~/.hermes/bin 추가 (이름으로 바로 실행 가능하게)
#
# 사용법: ./install.sh
set -euo pipefail

# repo 루트 (install.sh 위치 기준)
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
SKILL_DIR="$HERMES_HOME/skills/autonomous-ai-agents"
BIN_DIR="$HERMES_HOME/bin"

echo "=== herdr-pi-delegation 설치 ==="

# ---- 1. herdr 확인 ----
if ! command -v herdr >/dev/null 2>&1; then
  echo "[ERROR] herdr 미설치. 먼저 설치하세요: https://herdr.dev (또는 'herdr update')" >&2
  exit 1
fi
HDR_VER=$(herdr --version 2>/dev/null | head -1 || true)
echo "[1/5] herdr 확인: $HDR_VER (0.8.x 권장)"

# ---- 2. herdr↔pi 통합 ----
echo "[2/5] herdr↔pi 통합 설치 (완료 감지 이벤트)..."
herdr integration install pi 2>&1 | sed 's/^/      /' || echo "  [WARN] 통합 설치 실패 — 수동으로 'herdr integration install pi' 실행"

# ---- 3. 스킬 설치 ----
echo "[3/5] 스킬 설치 -> $SKILL_DIR"
mkdir -p "$SKILL_DIR"
for skill in pi-delegation delegation-review herdr-result-handling herdr; do
  SRC="$REPO_DIR/skills/$skill/SKILL.md"
  DST="$SKILL_DIR/$skill/SKILL.md"
  if [[ -f "$SRC" ]]; then
    mkdir -p "$SKILL_DIR/$skill"
    cp "$SRC" "$DST"
    echo "      ✓ $skill"
  else
    echo "      [WARN] $skill 스킬 파일 없음 (skip)" >&2
  fi
done

# ---- 4. bin 스크립트 ----
echo "[4/5] bin 스크립트 설치 -> $BIN_DIR"
mkdir -p "$BIN_DIR"
cp "$REPO_DIR/bin/herdr-spawn-pi.sh" "$BIN_DIR/"
cp "$REPO_DIR/bin/herdr-equalize.py" "$BIN_DIR/"
chmod +x "$BIN_DIR/herdr-spawn-pi.sh" "$BIN_DIR/herdr-equalize.py"
echo "      ✓ herdr-spawn-pi.sh"
echo "      ✓ herdr-equalize.py"

# ---- 5. PATH 등록 ----
echo "[5/5] PATH에 $BIN_DIR 추가"
SHELLRC=""
if [[ -n "${ZSH_VERSION:-}" ]]; then
  SHELLRC="$HOME/.zshrc"
elif [[ -n "${BASH_VERSION:-}" ]]; then
  SHELLRC="$HOME/.bashrc"
else
  SHELLRC="$HOME/.profile"
fi
if ! grep -qF "export PATH=\"$BIN_DIR" "$SHELLRC" 2>/dev/null; then
  printf '\n# herdr-pi-delegation\nexport PATH="%s:$PATH"\n' "$BIN_DIR" >> "$SHELLRC"
  echo "      ✓ $SHELLRC 에 추가됨"
else
  echo "      이미 $SHELLRC 에 있음 (skip)"
fi

echo
echo "=== 설치 완료 ==="
echo "새 셸에서 'herdr-spawn-pi.sh' 로 바로 실행할 수 있습니다 (PATH 반영)."
echo "다음에 '위임해', 'pi로 실행해' 라고 하면 pi-delegation 스킬이 로드됩니다."
echo "(스킬 반영은 새 세션(/reset)에서 적용)"
echo
echo "수동 설치(스킬 허브) 원하면:"
echo "  hermes skills tap add <github-user>/herdr-pi-delegation"
echo "  hermes skills install pi-delegation"
echo "  hermes skills install delegation-review"
echo "  hermes skills install herdr-result-handling"
echo "  hermes skills install herdr"