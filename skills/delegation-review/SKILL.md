---
name: delegation-review
description: Review and fix-loop for delegated work — when the user says "리뷰해/검토해/결과 검증해", the host (hermes) reviews the pi result file, and if not passing, re-delegates fixes to pi with a bounded loop (MAX_ROUNDS).
---

# 위임 결과 리뷰 (hermes가 수행 — 게이트)

pi(또는 다른 게스트)가 위임 작업을 끝내고 결과 파일을 남겼을 때, **hermes(호스트)가 직접 리뷰**하고 통과/수정을 결정한다. codex-plugin-cc의 adversarial-review에 대응하는 "호스트 판단" 단계.

## 트리거
- "리뷰해", "검토해", "결과 검증해", "이거 괜찮은지 봐줘" (위임 결과에 대해)
- 위임 워크플로우(`pi-delegation`)에서 결과 파일을 받은 직후 자동 수행

## 핵심 원칙
- **리뷰어는 hermes(호스트)가 기본.** 결과는 파일 버스로 호스트에 도착, 판단/게이트는 호스트 몫.
- 게스트(pi)는 자기 작업을 스스로 리뷰하지 않음.
- **제3자 교차검증은 예외적으로만**: hermes 리뷰에 맹점(같은 계열 모델)이 우려될 때 다른 공급업체 게스트(codex 등)를 read-only 리뷰어로 추가.

## 리뷰 절차
1. **결과 파일 읽기**: `~/.hermes/delegation-results/<name>.md` (또는 지정 경로). 파일 없으면 `herdr agent read <이름> --source recent-unwrapped` 폴백.
2. **리뷰 기준 체크** (필요에 따라):
   - 요구사항 충족 (지시한 작업을 다 했는가)
   - 품질 (코드/문서/산출물의 완성도)
   - 위험 (보안, 성능, 오류, 데이터 손실, 롤백)
   - 누락 (빠진 파일, 테스트, 문서)
3. **판정**:
   - **통과** → 종료, 결과를 사용자에게 요약
   - **불통과** → 수정 재위임 (아래)

## 수정 루프 (bounded)
- 불통과 시 **허용 최대 라운드: 3회** (MAX_ROUNDS, 커뮤니티 공통 패턴 — 무한루프 방지)
- 각 라운드: 새 pi(또는 같은 세션 resume)에 "이전 결과 + 지적사항" 을 넘겨 수정 후 다시 파일 저장 지시. (`pi-delegation` 실행 스킬 사용)
- 라운드 초과 → **사용자에게 에스컬레이션** (자동 계속 금지)
- 라운드를 세는 상태는 대화에서 직접 유지 (파일/변수 불필요 — 세션 짧음)

## 결과 처리 (표시 규칙)
- 리뷰 결과는 `herdr-result-handling` 스킬의 규칙을 따른다: 구조 보존, 심각도 순, 자동 수정 금지, 실패 시 대체 답변 생성 금지.

## 주의
- 리뷰 과정에서 **자동으로 코드를 고치지 않는다** — 수정은 항상 게스트(pi) 재위임 또는 사용자 명시 요청 시에만.
- 제3자 리뷰어를 쓸 땐 **read-only 지시 필수** (파일 수정 금지).