---
name: pi-delegation
description: Delegate a single task to the pi coding agent via herdr panes — when the user says "위임해/pi로 실행해", split a fresh pane, start pi, submit the prompt, wait for completion (event-based), and return the result file. Execution-only; review and parallel orchestration live in sibling skills.
---

# pi 위임 실행 (herdr pane 기반)

사용자가 작업을 pi에 위임하라고 할 때 herdr pane을 새로 만들고 pi를 기동해 작업을 전달한다. **이 스킬은 "단일 작업 실행"만** 담당한다. 리뷰는 `delegation-review`, 병렬은 `pi-delegation`의 병렬 섹션 또는 스크립트 반복 호출.

## 트리거
- "pi한테 위임해", "pi로 실행해", "이거 pi한테 시켜" 등 단일 작업 위임

## 아키텍처 (호스트-게스트)
```
호스트 hermes (판단·분배·리뷰)          게스트 pi (herdr pane, 실행)
├─ 작업 분해 / 위임 결정  ──────────►  ├─ 구현 실행
├─ pi 기동 + 프롬프트                 ├─ 결과를 파일로 저장
└─ 완료 감지 (herdr 이벤트)  ◄──────  └─ (독립, 병렬 가능)
```
- 리뷰어는 hermes(호스트)가 기본 — `delegation-review` 스킬 참조.
- 게스트(pi)는 실행 담당. 자기 작업을 스스로 리뷰하지 않음.

## 필수 전제: herdr↔pi 통합 설치 (완료 감지의 정답)
```bash
herdr integration install pi
```
`~/.pi/agent/extensions/herdr-agent-state.ts` 생성. 확장이 HERDR_ENV/HERDR_SOCKET_PATH/HERDR_PANE_ID 있을 때(herdr이 기동 시 자동 주입) 활성화:
- `agent_start` → working, `agent_settled` + isIdle → idle/done 보고
- 상태 확인: `agent_status` + `screen_detection_skipped: true` (통합이 상태 소유 = 정상)
설치 후 `herdr agent prompt <이름> "<작업>" --wait --timeout 120000` 가 stall 없이 동작.

## 실행 (검증된 스크립트 사용)
```bash
~/.hermes/bin/herdr-spawn-pi.sh "<작업 설명>" [--cwd /경로] [--out 결과경로]
```
스크립트가 하는 일 (실측 검증, herdr 0.8.0 + pi 통합):
1. 포커스된 탭의 레이아웃에서 **hermes 우측 경계**(`rect.x+width`) 계산
2. hermes 우측에 pane이 없으면 → hermes에서 `split right` (첫 2단 분리)
3. 우측 열이 있으면 → 우측 열(`rect.x >= hermes우측경계`)에서 **가장 아래 pane**에 `split down` (세로 적층)
4. **분할 결정~실행을 flock으로 직렬화** (`~/.hermes/bin/.herdr-split.lock`) → 병렬 시작해도 첫 split right는 1번만, 나머지는 전부 down
5. split 반환값에서 새 pane ID 직접 추출
6. `agent start pi-<pid>-<nanotime>` (전역 고유 이름, 항상 새 기동)
7. `agent prompt` 에 "결과를 `<파일>`에 저장하라" 자동 추가 → `--wait --timeout 120000`
8. 완료 후 결과 파일 stdout 출력 (파일 버스)
9. **우측 열 등분 재조정** — split 후 `herdr-equalize.py`가 모든 down-split ratio를 leaf 수 기준으로 재설정 (`herdr pane resize`로는 불가, 소켓 `layout.set_split_ratio` 직접 호출)
10. agent start 실패 시 새 pane 자동 close

결과 레이아웃 (보장): `[ hermes 전체높이 | pi 세로 등분 적층 ]` — 우측 열은 k개면 각각 정확히 1/k 높이.

## 결과 확인 (파일 버스)
- 결과: `~/.hermes/delegation-results/<pi-name>.md` (기본) / `--out` 지정
- pi가 저장 안 하면 WARN → `herdr agent read <이름> --source recent-unwrapped` 폴백
- **결과 처리 규칙은 `herdr-result-handling` 스킬 참조** (출력 보존, 자동수정 금지)

## 피드백 / 수정 재위임
- 리뷰에서 FAIL 시: **같은 스크립트를 다시 호출**해서 새 pi에 수정 지시 (재사용 금지 원칙 유지).
- task에 **이전 결과 파일 경로 + 지적사항**을 포함한다 (pi는 이전 맥락이 없으므로 파일로 맥락 전달):
  ```bash
  ~/.hermes/bin/herdr-spawn-pi.sh "이전 결과 파일(~/.hermes/delegation-results/<이전파일>.md)을 읽고,
  아래 지적사항 반영해서 수정한 뒤 새 결과 파일을 저장해: - 지적1 ..."
  ```
- 자세한 리뷰/수정 루프 절차는 `delegation-review` 스킬 참조.

## 병렬 실행
- N개 작업 = 스크립트 N번 호출. 레이아웃 기반 분할이라 **자동으로 우측 열 적층** 유지.
- 백그라운드 병렬: `~/.hermes/bin/herdr-spawn-pi.sh "작업A" & ... wait` (또는 execute_code에서 subprocess.Popen 동시 실행)
- **병렬 안전장치 (실측 필수)**:
  - PI_NAME은 `pi-$$-$(date +%s%N)` (PID+나노초) — `date +%s`만 쓰면 동시 시작 시 **같은 초 = 이름 충돌** (`agent_name_taken`).
  - 새 pane ID는 **split 반환값에서 직접 추출** (`jq -r '.result.pane.pane_id'`) — 차집합은 동시 실행 레이스.
  - **flock 직렬화** (`~/.hermes/bin/.herdr-split.lock`): 분할 결정+실행을 락으로 묶어, 병렬 시작해도 첫 split right 1번 + 나머지 down 보장.
  - 병렬 시작 직후엔 모든 프로세스가 같은 레이아웃을 읽을 수 있지만, flock이 순서를 보장 → 경합 없음.

## 함정 (전부 실측)
- agent 이름은 **전역 고유** — `agent start pi`는 pi 있으면 `agent_name_taken`. `pi-$(date +%s)` 필수.
- 미등록 pane(직접 `pi` 실행)은 이름 검사 대상 아님, 상태 추적 불가.
- `herdr pane wait-output --match/--regex`는 0.8.0 파싱 버그 (사용 금지, 0.8.2 확인).
- `pane read`는 `--source recent-unwrapped` 필수 (softwrap 잘림).
- pane ID는 bijective base-32 (10번째 = `pA`). 하드코딩 금지.

## 참조
- herdr CLI 상세: `herdr` 스킬
- 리뷰 루프: `delegation-review` 스킬