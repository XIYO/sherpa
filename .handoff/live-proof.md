---
uuid: 01a0ed84-eefd-777b-8e92-967a7f21a59f
type: plan
audience: "다음 세션의 에이전트와 저장소 소유자. 실기에서 아직 보지 못한 것을 닫을 때"
goal: "테스트나 전해 들은 보고로만 선 주장을 골라 어떤 실기 관측이 그것을 닫는지 알게 한다"
tone: "평어체. 본 것, 전해 들은 것, 보지 못한 것을 가른다"
manner: "항목마다 지금 선 근거를 적고 긴 기록은 live-evidence 의 날짜 항목으로 내린다"
---

# 실기로 아직 증명하지 못한 것

## Goal

아래 항목마다 소유자가 직접 하는 실기 관측을 하나씩 얻어 `docs/testing/live-evidence.md` 에 날짜로 적고,
닫힌 항목을 여기서 지운다. 관측이 주장을 뒤집으면 해당 문서와 코드를 같은 변경에서 고친다.

## Owner decisions

- "sherpa는 mac 전용이다" (2026-09-21, Windows 기기를 다루는 세션이 전한 소유자의 말). 플러그인 0.7.3 의
  비 macOS 동작은 이 말과 병합 지시에 기댄다.

## Session choices

- 0.7.3 의 형태(비 macOS 에서 훅은 침묵하고 가드가 `unsupported` 로 답한다)는 세션이 골랐다. 소유자가
  설계를 보고 동의한 것은 아니다. 비 macOS 에서 훅이 한 번은 말해야 한다고 소유자가 보면 다음 플러그인
  버전으로 되돌린다. 버전을 올리지 않으면 Claude Code 캐시가 바뀌지 않는다.

## State

2026-10-05 기준.

- **설치 진입점.** 이 Mac 의 Claude 프로필 둘과 Codex 프로필 넷은 `sherpa@plug-hole`을 쓴다.
  brew CLI 는 0.7.1 이다. Windows 기본 Claude 프로필도 같은 설치 ID 를 쓴다.
  두 기기의 프로필·설치 목록을 되읽어 옛 `sherpa`·`xiyo` 마켓플레이스와 그 설치 ID 가 없음을 확인했다.
- **0.7.1 의 기록 상태는 결정적 테스트로만 증명했다.** 실제 iMessage·Mail 전송과, 전송 뒤의 실제
  SQLite 쓰기 실패는 일으킨 적이 없다. 기록 실패 경로는 가짜 기록부로만 탔다(live-evidence 2026-09-29).
- **검증 행렬의 `SR-CX-013` 은 "D stale" 이다**(`docs/testing/verification-matrix.md`). 0.7.1 이 다시
  보인 것은 전송의 typed uncertain failure 하나이고, 일회용 확인과 자동 재시도 금지는 다시 보지 않았다.
- **로그인된 세션에서 스킬 호출을 본 적이 없다.** 2026-09-29 이 Mac 의 로그인된 Claude Code 세션
  (두 번째 Claude 프로필)이 받은 스킬 목록에 `sherpa:*` 다섯이 실려 있다. 모델이 그중 하나를 실제로 부르는
  것은 Claude Code 에서도 Codex 에서도 보지 않았다.
- **비 macOS 의 대화형 세션 화면은 보지 않았다.** Windows 기기의 로그인된 headless Claude Code 세션은
  Sherpa 0.7.8 을 실었고 경고를 내지 않았다. 디버그 로그에는 조용한 `session-start.sh` 의 실행 줄이 없어,
  그 훅이 실제 호출됐다는 실기 증거는 아니다(live-evidence 2026-10-05).
- **Discord 이모지·스티커 명령**은 `agent-messenger@2.38.0` 에 있고 `--help` 가 exit 0 이라는 것까지다.
  실제 길드에서 목록·업로드·삭제를 실행한 적이 없다(live-evidence 2026-09-21).

## Next

1. 소유자가 고른 대화에 0.7.1 로 iMessage 한 통과 Mail 한 통을 명시 확인을 거쳐 보내고, 출력의
   `operation_id` 와 기록부의 `completed` 를 되읽는다.
2. 로그인된 Claude Code 세션과 Codex 세션에서 `sherpa:planner` 로 읽기 요청 하나를 시켜 스킬 호출을 본다.
3. Windows 기기에서 로그인된 대화형 Claude Code 세션을 열어 훅이 화면에 아무것도 띄우지 않는지 본다.
4. `SR-CX-013` 을 지금의 프로세스 경계로 다시 검증하고 행렬의 상태를 고친다.

## Blocked

- 실제 전송, 로그인된 세션, Windows 기기 화면은 소유자의 조작이나 승인이 있어야 한다. CI 러너는 어느 도구도
  실행하지 않으므로 CI 로는 닫지 못한다.
