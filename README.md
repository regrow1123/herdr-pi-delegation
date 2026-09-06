# herdr-pi-delegation

Hermes(호스트) → herdr pane → pi(게스트) **위임 워크플로우** 패키지.

herdr(터미널 멀티플렉서)에서 좌측에 hermes 세션을 두고, 우측 열에 pi 에이전트들을 **세로 등분 적층**하며 병렬 작업을 위임한다. codex-plugin-cc(OpenAI 공식, Claude Code↔Codex)를 벤치마크한 구조.

```
┌────────────────┬───────────────┐
│                │  pi #1        │
│   hermes       ├───────────────┤
│   (호스트)      │  pi #2        │  ← split down으로 세로 등분 적층
│   · 분해/판단   ├───────────────┤
│   · 리뷰       │  pi #3        │
└────────────────┴───────────────┘
```

## 요구사항

- [herdr](https://herdr.dev) 0.8.x (tmux-style workspace manager)
- [pi](https://pi.dev) 코딩 에이전트
- [Hermes](https://hermes-agent.nousresearch.com) (호스트로 사용)

## 설치

```bash
git clone https://github.com/regrow1123/herdr-pi-delegation
cd herdr-pi-delegation
./install.sh
```

또는 스킬 허브 방식:

```bash
hermes skills tap add regrow1123/herdr-pi-delegation
hermes skills install pi-delegation
hermes skills install delegation-review
hermes skills install herdr-result-handling
hermes skills install herdr
```

## 사용법

Hermes에서 그냥 말하면 된다:

| 말 | 동작 |
|---|---|
| "pi한테 위임해: <작업>" | 새 pane → pi 기동 → 작업 → 결과 파일 반환 |
| "리뷰해" | hermes가 결과를 리뷰 → 통과/수정 재위임 |
| "병렬로: 작업A, 작업B, 작업C" | 3개 pane 병렬 실행 (자동 등분 적층) |

실행 예:
```bash
~/.hermes/bin/herdr-spawn-pi.sh "이 repo의 README를 다듬어줘" --cwd ~/myproject
```

결과는 `~/.hermes/delegation-results/<name>.md` (파일 버스)에 저장되고 그대로 출력된다.

### 피드백 / 수정

리뷰 불통과 시 **같은 스크립트를 다시 호출**해서 새 pi에 수정 지시 (항상 새 pi, 재사용 안 함).
이전 결과 파일 경로 + 지적사항을 task에 포함한다 — pi는 이전 대화 맥락이 없으므로 파일로 맥락을 전달:

```bash
~/.hermes/bin/herdr-spawn-pi.sh "이전 결과 파일(~/.hermes/delegation-results/<이전파일>.md)을 읽고,
아래 지적사항 반영해서 수정한 뒤 새 결과 파일을 저장해:
- 지적 1: ...
- 지적 2: ..."
```

수정 루프는 최대 3회 (MAX_ROUNDS), 초과 시 사용자에게 에스컬레이션.

## 구조

```
skills/
├─ pi-delegation/          "위임해" — 단일 위임 실행 (스크립트 호출)
├─ delegation-review/      "리뷰해" — hermes 리뷰 + 수정 루프 (MAX_ROUNDS=3)
├─ herdr-result-handling/  결과 표시 규칙 (자동수정 금지 등)
└─ herdr/                  herdr CLI 레퍼런스 (내부용)
bin/
├─ herdr-spawn-pi.sh       위임 스크립트 (split→pi→완료→결과)
└─ herdr-equalize.py       우측 열 등분 재조정 (소켓 layout.set_split_ratio)
install.sh                 원클릭 설치
```

## 아키텍처

- **호스트-게스트**: hermes = 분해/판단/리뷰, pi = 실행.
- **완료 감지**: `herdr integration install pi` 확장이 `agent_settled` 이벤트로 상태 보고 → `agent prompt --wait` 가 정확히 동작 (polling 없음).
- **파일 버스**: 결과는 터미널 스크롤이 아니라 파일로 교환.
- **등분 적층**: split 후 `herdr-equalize.py`가 우측 열의 down-split ratio를 leaf 수 기준으로 재설정 (`layout.set_split_ratio` 소켓 호출).

## 함정 (전부 실측)

- pi 에이전트 이름은 **전역 고유** — 스크립트가 `pi-<pid>-<nanotime>` 자동 생성.
- 첫 split만 right, 이후엔 우측 열 down — 병렬 시작해도 flock이 직렬화.
- herdr 0.8.0 `wait-output --match` 버그 → 직접 폴링 대신 통합 이벤트 사용.

## 라이선스

MIT