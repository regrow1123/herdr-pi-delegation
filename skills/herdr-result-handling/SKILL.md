---
name: herdr-result-handling
description: Rules for presenting pi/herdr delegation output back to the user — preserve structure, severity order, no auto-fixing, no substitute answers on failure. Internal guidance loaded with pi-delegation/delegation-review.
---

# 위임 결과 처리 규칙 (herdr/pi 출력 표시)

pi가 파일 버스(`~/.hermes/delegation-results/*.md`)로 남긴 결과를 사용자에게 보여줄 때의 규칙. codex-plugin-cc의 codex-result-handling에 대응.

## 표시 규칙
- **구조 보존**: pi가 저장한 verdict/요약/발견사항/다음 단계 구조를 그대로 유지.
- **리뷰 결과**: 발견사항을 먼저, **심각도 순**으로 (blocking → important → nit).
- **파일 경로/라인 번호**: pi가 보고한 그대로 사용 (추측 금지).
- **증거 경계 보존**: pi가 "추측/불확실/후속 질문"으로 표시한 건 그 구분을 유지.
- **섹션 보존**: 요청이 관찰사실/추론/미해결 질문/수정 파일/다음 단계 섹션을 요구했으면 그대로.
- **발견 없음**: 명시적으로 "발견 없음" + 잔여 위험 메모는 짧게.

## 금지 규칙
- **자동 수정 금지 (CRITICAL)**: 리뷰 결과를 제시한 뒤 코드를 고치지 않는다. 어떤 이슈를 고칠지 **사용자에게 명시적으로 물어본 뒤에만**. 명백해 보여도 자동 적용 금지.
- **실패 시 대체 답변 금지**: pi가 실패/불완전하면 hermes가 대신 구현하지 않는다. 실패 보고 후 중단.
- **미기동 시 답변 생성 금지**: pi가 아예 호출 안 됐으면 대신 답을 만들지 않는다.
- **말썽 출력 시**: 가장 유용한 stderr 라인만 포함하고 거기서 중단 (추측 금지).
- **설정/인증 필요 시**: `/codex:setup` 같은 안내만 (우리는 `herdr integration install pi` 안내) — 즉흥 대체 금지.

## 적용
- `pi-delegation` 실행 후 결과 표시
- `delegation-review` 리뷰 결과 표시
- 병렬 실행 여러 결과 취합 시에도 각각 이 규칙 적용 (임의 요약/왜곡 금지)