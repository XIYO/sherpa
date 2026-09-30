---
uuid: 01a0ed84-eef6-7223-913b-46f038e2dfbe
type: plan
audience: "다음 세션의 에이전트와 저장소 소유자. CLI 0.7.1 뒤의 결함을 고칠 때"
goal: "0.7.1 에 남은 결함 둘과 확인할 것 하나를 코드 위치와 함께 알고 다음 CLI 릴리스로 닫게 한다"
tone: "평어체. 코드로 확인한 것과 재현하지 않은 것을 가른다"
manner: "결함마다 파일과 함수를 짚고 근거는 코드와 CHANGELOG 로 내린다"
---

# CLI 0.7.1 뒤에 남은 결함

## Goal

다음 CLI 릴리스에서 아래 두 결함을 결정적 테스트와 함께 닫고, `imsg send` 에 전달하는 1 바이트를
남길지 정한다. 스킬이 새 동작을 요구하면 `cli-contract.json` 의 `minimumVersion` 과 플러그인
버전을 함께 올린다.

## Owner decisions

없음.

## Session choices

- `imsg send` 의 1 바이트 stdin(`0x01`)은 0.7.1 을 만든 세션이 남겼다. 살아 있는 전송기의 입력을
  바꾸지 않으려는 선택이었고, 소유자가 정한 것이 아니다.
- 과대 응답 결함은 워커의 결과가 이미 제한돼 있다는 이유로 재현하지 않았다.

## State

2026-09-29, `f7a6557`(CLI 0.7.1) 의 코드로 확인했다.

- **KakaoTalk 로컬 검색 어댑터의 로그가 `LOG_LEVEL` 을 보지 않는다.**
  `apple/eventkit-service/Sources/SherpaNativeCommandAdapter/KakaoTalkLocalSearchAdapter.swift` 의
  `localSearchLog` 는 수준과 상관없이 stderr 에 쓴다. 호출 열 곳 중 여섯이 `info` 라 기본 수준에서도
  찍힌다. `SherpaWorkerProtocol` 의 `WorkerLog` 는 `LOG_LEVEL` 을 읽고 기본값이 `warn` 이다. 이
  어댑터 target 은 `SherpaWorkerProtocol` 에 의존하지 않는다(`Package.swift`) — `WorkerLog` 를 쓰려면
  의존을 하나 더해야 한다. 어느 쪽으로 고칠지는 아직 정하지 않았다.
- **적용된 변경의 응답이 8 MiB 를 넘으면 `failed` 로 보고된다.** `main.swift` 의 `plannerRequest()`
  는 `journaled` 로 변경을 기록한 뒤 `encoded(maximumBytes: 8 MiB)` 로 응답을 인코딩한다. 넘으면
  `WorkerProtocolError.resultTooLarge` 가 최상위 catch 에서 `{"status":"failed","error":
  "protocol.result_too_large"}` 가 된다. 기록부에는 워커가 답한 상태가 남고 출력은 `failed` 다.
  코드를 읽어 얻은 결론이고 재현하지 않았다.
- **`imsg send` 가 여전히 stdin 으로 `0x01` 을 받는다.** `ChatAdapters.swift` 의 `send` 가
  `stdin: Data([0x01])` 를 전달한다. 이 바이트가 하던 "변경 명령" 표지는 이제 `effect: .mutation` 이
  맡는다. `imsg` 가 이 바이트를 읽는지는 확인하지 않았다.

## Next

1. 과대 응답: 적용된 변경을 `failed` 로 내지 않게 한다. 인코딩을 기록 전에 끝내는 길과, 초과를
   이름 있는 오류와 함께 `completed`·`uncertain` 으로 내는 길이 있다. 먼저 초과 응답을 흉내 내는
   결정적 테스트를 세워 지금 `failed` 가 나오는 것을 본다.
2. KakaoTalk 로그: 기본 수준에서 `info` 줄이 나오지 않는다는 테스트를 먼저 세우고, 수준 판정을
   `WorkerLog` 와 같은 규칙으로 맞춘다.
3. `imsg` 의 도움말이나 소스로 `send` 가 stdin 을 읽는지 본다. 읽지 않으면 그 바이트를 뺀다.
4. 릴리스는 `AGENTS.md` 의 버전 규칙을 따르고, 병합 전에 macOS 에서 `bash scripts/check-all.sh`
   전체를 실행한다.
