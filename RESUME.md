---
uuid: 01a10fac-ba94-769e-9531-8805c8da7f2e
type: note
audience: Sherpa 의 남은 결함·문서 정리·실기 증명을 이어받는 세션과 저장소 소유자
goal: CLI 결함 셋, 옛 front matter 키, 끊긴 V2 참조, 실기로 못 닫은 주장을 알고 다음 행동을 고른다
tone: 평어체. 코드로 확인한 것, 재현하지 않은 것, 소유자 몫을 가른다
manner: 항목마다 파일과 다음 행동을 대고 옛 인계 전문은 커밋으로 가리킨다
---

# Sherpa 남은 일

옛 `.handoff/` 전문은 `398013f` 에 있다(`cli-followups.md`·`live-proof.md`·`public-release.md`·
`parked/worker-v2-artifacts.md`). 아래 "확인함" 은 2026-10-06 `398013f` 의 코드로 다시 본 것이다.

## 소유자 결정

- "sherpa는 mac 전용이다"(2026-09-21, Windows 기기를 다루는 세션이 전한 말). 플러그인의 비 macOS 동작
  (훅 침묵, 가드 `unsupported`)은 세션이 고른 모양이고 소유자가 설계를 보고 동의한 것은 아니다.
- CLI 결함·문서 항목에는 소유자 결정이 없다.

## 1. CLI 0.7.1 뒤의 결함 (다음 CLI 릴리스)

- **적용된 변경의 응답이 8 MiB 를 넘으면 `failed` 로 보고된다.** `apple/eventkit-service/Sources/SherpaNative/main.swift`
  가 변경을 기록한 뒤 `encoded(maximumBytes: 8 MiB)` 로 인코딩해, 넘으면 최상위 catch 가
  `protocol.result_too_large` 로 `failed` 를 낸다(코드로 확인, 재현 안 함).
  다음: 초과 응답을 흉내 내는 결정적 시험을 먼저 세워 `failed` 를 본 뒤, 인코딩을 기록 전에 끝내거나 초과를
  이름 있는 오류와 함께 `completed`·`uncertain` 으로 낸다.
- **KakaoTalk 로컬 검색 로그가 `LOG_LEVEL` 을 보지 않는다.** `KakaoTalkLocalSearchAdapter.swift` 의
  `localSearchLog` 가 수준과 상관없이 stderr 에 쓴다(확인함). `WorkerLog` 를 쓰려면 이 target 에
  `SherpaWorkerProtocol` 의존을 더해야 한다. 다음: 기본 수준에서 `info` 줄이 안 나온다는 시험을 먼저 세운다.
- **`imsg send` 가 stdin 으로 `0x01` 을 받는다.** `ChatAdapters.swift:37`(확인함). 변경 표지는 이제
  `effect: .mutation` 이 맡는다. 다음: `imsg` 가 stdin 을 읽는지 도움말·소스로 보고, 안 읽으면 뺀다.
- 스킬이 새 동작을 요구하면 `cli-contract.json` 의 `minimumVersion` 과 플러그인 버전을 함께 올린다.

## 2. 문서 정리

- **옛 front matter 키**(`id`·`title`·`status`·`owner`)가 `docs/` 의 22개 문서에 남아 있다(확인함). ADR·RFC 의
  `status` 값은 정보를 담고 있어 처분이 미결이다. 다음: 상태 정보를 본문이나 경로로 옮길지 정한 뒤 키를 지운다.
- **V2 가 약속한 파일이 없다.** `docs/contracts/worker-protocol.md:85` 의 `protocols/worker-v2.schema.json` 과
  `docs/testing/README.md:153` 의 `protocols/fixtures/worker-v2` 가 가리키는 `protocols/` 가 없다(확인함). 코드
  스팬이라 링크 검사가 잡지 않는다. 다음: V2 경계를 손댈 때 스키마를 두고 게이트에 넣을지, 두 문장을 고칠지 정한다.

## 3. 실기로 아직 증명하지 못한 것 (소유자 조작 필요)

관측을 얻으면 `docs/testing/live-evidence.md` 에 날짜로 적고 여기서 지운다.

1. 소유자가 고른 대화에 0.7.1 로 iMessage·Mail 한 통씩 명시 확인을 거쳐 보내고 `operation_id` 와 기록부의
   `completed` 를 되읽는다. 지금까지는 결정적 시험과 가짜 기록부로만 증명했다.
2. 로그인된 Claude Code·Codex 세션에서 `sherpa:planner` 로 읽기 요청 하나를 시켜 스킬 호출을 본다.
3. Windows 기기의 로그인된 대화형 Claude Code 세션에서 훅이 화면에 아무것도 띄우지 않는지 본다.
4. `docs/testing/verification-matrix.md` 의 `SR-CX-013`("D stale")을 지금의 프로세스 경계로 다시 검증한다.
5. Discord 이모지·스티커 명령을 실제 길드에서 실행한 적이 없다.

## 막힌 것

- 3번 전부와 옛 저장소 `XIYO/sherpa-archive` 의 self-hosted Windows 러너 등록 해제는 소유자 몫이다.
