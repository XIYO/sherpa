---
uuid: 01a0ed5e-6dc7-74b3-a2ba-6b39e4060eeb
type: changelog
audience: "Sherpa 플러그인과 CLI 를 갱신하는 소유자. 무엇이 바뀌었고 왜 올려야 하는지 볼 때"
goal: "릴리스마다 사용자에게 보이는 변경과 그 근거를 확인하고 갱신 여부를 판단하게 한다"
tone: "평어체. 바뀐 동작과 고친 결함을 재현한 사실로 적는다"
manner: "버전별로 Added·Changed·Fixed 를 나누고 긴 실측 근거는 live-evidence 로 내린다"
---

# Changelog

## [Unreleased]

## [0.7.13] - 2026-10-07

### Changed

- 다섯 스킬의 description 을 400~480자에서 250자 안팎으로 줄였다. description 은 Claude Code 세션마다 실리므로,
  본문이 이미 맡는 소스 열거와 스킬 사이 경계 설명을 빼고 스킬을 가르는 단어(최근·과거·로컬·분석·일정)만 남겼다.

### Fixed

- `scripts/package.sh` 가 렌더하는 Homebrew Formula 에서 `version` 줄을 뺀다. Homebrew 는 url 의
  아카이브 이름에서 판을 읽고, 같은 값을 명시하면 `brew audit` 이 "redundant with version scanned
  from URL" 로 거부했다(0.7.1 공개 tap 실측). 릴리스 스모크(`scripts/check-release.sh`)는 판을 url 에서
  읽고 `version` 줄이 생기면 `formula_version_line_redundant` 로 거부한다.

## [0.7.12] - 2026-10-05

### Fixed

- 설치 안내에 비공개 `XIYO/plug-hole` 저장소의 접근 권한이 필요하다는 조건을 밝혔다.

## [0.7.11] - 2026-10-05

### Changed

- 플러그인의 설치 진입점을 `sherpa@plug-hole` 하나로 정리했다. Sherpa 저장소의 자체
  마켓플레이스를 없애고 두 README 와 Homebrew 안내도 같은 ID 를 가리킨다.

## [0.7.10] - 2026-10-05

### Fixed

- 두 README 의 검증 명령이 `sherpa` 마켓플레이스 캐시 경로에만 묶인 문제를 고쳤다. 이제 `sherpa` 와 `plug-hole` 어느 진입점에서도 CLI와 호스트의 플러그인 목록을 확인한다.

## [0.7.9] - 2026-10-05

### Fixed

- 두 README 의 공용 카탈로그 설치 ID 를 실제 `sherpa@plug-hole` 로 고쳤다. 옛 `sherpa@xiyo` 명령은 현재 카탈로그에서 실패한다. 플러그인에 SessionStart 훅이 포함된다는 설명도 바로잡았다.

## [0.7.8] - 2026-10-05

### Fixed

- SessionStart 훅이 Python 없이 Bash 와 기존 CLI 가드만으로 설치·버전 상태를 알린다. Python 이 없는 Mac 에서도 정상 CLI 에는 침묵하고, 누락·버전 불일치에는 조치를 안내한다.

## [0.7.7] - 2026-09-30

### Changed

- 두 README 가 설치 뒤 새 세션을 시작하라고 지시하지 않고, 새 세션이 스킬을 불러오고 열린 세션은
  이미 실은 판을 계속 쓴다고 사실로 적는다.
- 두 README 에서 이 저장소가 비공개라는 문장을 뺀다. 저장소가 공개로 바뀌었다.

## [0.7.6] - 2026-09-30

### Added

- 플러그인 폴더에 `LICENSE`(MIT)를 넣는다.

### Changed

- CLI 설치 안내를 공개 tap 의 `brew install xiyo/tap/sherpa` 로 바꾼다
  (`cli-contract.json` 의 `install`, 두 README). CLI 가 없거나 낡았을 때 가드와
  SessionStart 훅이 이 명령을 안내한다. 전에는 원격 없는 로컬 tap 을 가리켜 다른
  Mac 에서는 설치되지 않았다.
- 두 README 의 마켓플레이스 추가 명령이 `XIYO/sherpa`·`XIYO/plug-hole` 단축형 대신
  `https://github.com/XIYO/sherpa.git`·`https://github.com/XIYO/plug-hole.git` 를
  쓴다. 단축형이 SSH 로 복제되면 GitHub SSH 키가 없는 기기에서 실패한다.
- `planner` 의 한국어 이벤트 작성 지침에서 예시의 업체·매장·금융 상품·날짜를
  자리표시자로 바꾼다. 규칙은 그대로다.

## [0.7.5] - 2026-09-29

### Changed

- 스킬이 요구하는 CLI 를 0.7.1 이상으로 올린다(`cli-contract.json` 의
  `minimumVersion`). 0.7.0 CLI 에서는 가드가 `mismatch` 와 `brew upgrade` 안내를
  낸다. 0.7.1 이 고친 아래 세 결함이 `planner request`·`operations list` 를 쓰는
  스킬의 판단을 바꾸기 때문이다.

### Fixed (CLI 0.7.1)

- **이미 보낸 메시지를 `failed` 로 기록할 수 있던 결함.** `imessage send`·`mail
  send` 는 전송과 완료 기록을 한 예외 경계에서 처리했다. 전송이 성공한 뒤 완료
  기록이 실패하면 같은 경계가 그 작업을 `failed` 로 다시 쓰려 했고, 두 번째
  쓰기가 성공하면 이미 보낸 작업이 실패로 남았다 — 사람이 같은 메시지를 다시
  보낼 수 있는 상태다. 이제 전송 시도와 각 기록 쓰기는 따로 잡힌다. 상태는
  전송 결과만으로 정하고, 기록 쓰기가 실패해도 상태를 바꾸거나 다른 상태로 다시
  쓰지 않는다. 그 작업은 기록부에 `started` 로 남는다. 보낸 뒤 기록하지 못한
  전송은 종료 코드 0 과 `{"journal_error":"journal.finish_failed","operation_id":…,"status":"completed"}`
  로 답한다.
- **보낸 뒤 출력을 읽지 못한 전송이 `failed` 로 남던 결함.** 명령 실행기는 자식
  명령을 실행한 뒤의 출력 크기·읽기 검사를 종료 상태 판정보다 먼저 했고, 그 오류는
  `uncertain` 으로 바뀌지 않았다. 이제 변경 명령이 입력을 받은 뒤의 실패는 무엇이든
  `uncertain` 이다. 실패 응답의 `status` 도 기록과 같다(`uncertain` 이면
  `"status":"uncertain"`)이고, 기록된 작업이면 `operation_id` 가 함께 나온다.
- **`planner request` 의 변경이 적용된 뒤 기록이 실패하면 응답 대신 실패를
  내던 결함.** 이제 응답을 그대로 내고 기록 실패는 stderr 에
  `[cli:sherpa:journal-failure]` 로 남긴다. 기록부에서 그 작업은 `started` 다.
- **알 수 없는 실패가 아무 출력 없이 끝나던 결함.** `printf '{}' | sherpa planner
  request` 는 종료 코드 1 에 stdout·stderr 가 모두 0 바이트였다. 이제 모든 실패가
  stdout 에 이름 있는 코드를 낸다 — 프로토콜 오류는 그 코드(`protocol.invalid_envelope`
  등), 코드가 없는 오류는 `sherpa.internal_failure`. 오류 원문은 내지 않는다.
  stderr 에는 `[cli:sherpa:command-failure]` 한 줄이 코드와 오류 타입 이름만 남긴다.
  게이트가 이 호출을 직접 실행해 확인한다.

## [0.7.4] - 2026-09-21

### Added

- `skills/agent-messenger/SKILL.md`가 Discord 커스텀 이모지·스티커 명령을 적는다.
  `emoji list`·`sticker list`와 `server info`는 "읽기 먼저" 절에, `emoji
  create/delete`·`sticker create/delete`는 "명시적 의도가 있을 때만 쓰기" 절에
  둔다 — 뒤의 넷은 길드 전체가 공유하는 자원을 바꾸므로 메시지 전송과 같은
  기준을 받아야 한다. 상류 `agent-messenger/agent-messenger#337`이 **npm
  `agent-messenger@2.38.0`에 실린 것을 확인한 뒤에** 적었다(근거는 live-evidence
  2026-09-21 항목: 병합 시각과 발행 시각의 선후, `gitHead`의 계보, tarball의
  파일과 `cli.ts` 등록, 그리고 실제 `--help` 실행). `$AM` 정의는 그대로 핀하지
  않는다 — 핀하면 상류 수정을 받지 못한다. 대신 이 명령들이 2.38.0 이상을
  요구한다는 것을 한 줄로 적는다.
- 같은 문서가 에이전트가 틀리기 쉬운 네 가지만 산문으로 남긴다. 이름과 파일
  형식 검증은 **요청 전 로컬**이고 형식은 확장자가 아니라 바이트로 판별하므로
  거부된 파일을 같은 내용으로 재시도하는 것은 의미가 없다. `sticker create`의
  `--tags <emoji>`는 필수다. 남은 슬롯은 `emoji list`가 아니라 `server info`가
  답한다(#337이 같이 고친 `owner_id` 버그와 함께 들어간 부스트 티어·슬롯
  필드). `create`·`delete`는 `MANAGE_GUILD_EXPRESSIONS`가 필요하고 CLI는 사전
  탐침 없이 Discord의 오류를 그대로 내보낸다.
- 스킬 `description`이 이모지·스티커 관리를 트리거로 포함한다. 전의 문장은
  "메시지 읽기/보내기"만 말해 길드 표현 관리 요청에 이 스킬이 걸리지 않았다.
- 두 README 의 설치 절이 카탈로그 진입점 `sherpa@xiyo`(`XIYO/plug-hole`)를
  나란히 적고, **둘 중 하나만 설치하라**는 금지를 함께 적는다. Claude Code 는
  스킬 이름을 마켓플레이스가 아니라 플러그인 이름만으로 짓기 때문에(공식 문서
  `discover-plugins`·`plugins-reference` 와 claude 2.1.278 번들의 이름 생성부)
  두 벌을 깔면 같은 이름의 스킬 다섯 개와 SessionStart 훅이 겹치고, 각각 하나만
  남되 어느 쪽이 남는지 알려주지 않는다 — 남은 것이 더 새 버전이라는 보장도
  없다. 카탈로그 경로에 접근 권한상의 이점이 없다는 것도 적는다. `git-subdir`
  소스가 설치 시점에 `XIYO/sherpa` 를 직접 클론하므로 두 경로가 같은 읽기 권한을
  요구한다 — 이걸 적지 않으면 비공개 저장소의 우회로로 오해된다.

### Fixed

- 플러그인 README 둘의 "검증" 절이 **존재하지 않는 명령**을 안내하던 것을 고친다.
  `bash "$(claude plugin path sherpa@sherpa)/scripts/require-cli.sh"` 의
  `claude plugin path` 는 하위 명령이 아니다 — claude 2.1.278 에서
  `error: unknown command 'path'`(`Did you mean update?`)가 나고,
  `claude plugin --help` 의 목록에도 없다. `codex plugin --help`(codex-cli
  0.155.1)에도 `path` 가 없다. 명령 치환이 빈 문자열로 접혀 가드가 아니라
  `/scripts/require-cli.sh` 를 찾던 셈이라, 이 문구를 따라 한 사람은 한 번도
  가드를 돌려 보지 못했다. 스킬 내부는 `${CLAUDE_PLUGIN_ROOT}` 를 쓰므로
  영향이 없다 — 깨진 것은 README 문구뿐이었다.
- 대신 설치 캐시 경로를 적는다. 캐시된 버전을 먼저 `ls -d` 로 보이고, 가드는
  `sort -V | tail -1` 로 고른 가장 새 버전에서 돌린다. 이 Mac 에서 실행해
  `{"status":"ready","installed":"0.7.0","minimum":"0.7.0"}` 와 종료 코드 0 을
  확인했다. 글로브를 그대로 쓰지 않는 이유도 적었다 — 버전이 둘 이상 캐시되면
  `bash …/*/scripts/require-cli.sh` 는 첫 번째만 실행하고 나머지를 그 스크립트의
  인자로 넘긴다(가짜 디렉터리 둘로 재현했다). 설정 디렉터리가 `~/.claude` 가
  아닐 수 있다는 것도 문구가 말한다.

### Changed

- 플러그인 버전을 올린다. 스킬과 README 만 바꾼 릴리스라도 버전 번호가 캐시
  무효화의 유일한 신호다(0.7.1 항목과 ADR-0007 `## 검증`).

## [0.7.3] - 2026-09-21

### Changed

- `scripts/require-cli.sh`가 macOS가 아닌 곳에서 새 상태 `unsupported`를 답한다 —
  `{"status":"unsupported","reason":"macos_only","platform":"<uname -s>","remedy":"…"}`,
  종료 코드 1. CLI는 macOS 전용이라 다른 플랫폼에서는 언제나 `missing`이었고,
  그 응답은 그 기기에서 실행할 수 없는 `brew install …`을 권했다. 플랫폼은
  계약 파일보다 먼저 본다. `uname -s`가 실패하면 `unsupported`가 아니라
  `failed`(`platform_probe_failed`)다 — 모르는 것을 침묵하는 쪽으로 보내지 않는다.
- `hooks/session-start.sh`가 `unsupported`에 침묵한다. 0.7.2의 훅은 Windows에서
  매 세션 "설치되어 있지 않습니다 … 설치: brew install …"을 읽혔다. 거짓은
  아니지만 따를 수 없는 안내였다. 말하는 자리는 가드로 옮겼다 — 스킬을 부르면
  "macOS 전용"이라는 답을 받는다. 판정은 여전히 가드 하나에만 있고 훅은 다시
  계산하지 않는다.
- CLI를 부르는 스킬 넷(`sherpa`, `planner`, `context`, `kakaotalk-local-search`)의
  가드 안내가 상태별 해석을 적는다. 전에는 `ready`가 아니면 무엇이든 "CLI 버전
  어긋남"으로 보고하라고 했다. `unsupported`에서는 macOS 전용임을 말하고 설치
  명령을 권하지 않는다.
- `scripts/checks/verify_session_start.py` — 가짜 `uname`으로 플랫폼을 흉내 낸다.
  기존 네 상태는 `Darwin`으로 고정해 macOS와 Windows 러너가 같은 것을 검사하고,
  `MINGW64_NT-…`와 `Linux`에서 훅의 침묵·exit 0과 가드의 상태·사유·종료 코드,
  그리고 출력 어디에도 `brew`가 없음을 본다. `uname`이 실패하면 훅이 침묵하지
  않는 것도 본다. 가짜 디렉터리는 bash 안에서 PATH 맨 앞에 한 번 더 둔다 — Git for
  Windows의 `bin/bash.exe`가 진짜 `uname`이 있는 자기 `usr/bin`을 앞에 붙일 수
  있어서다.
- 같은 검사의 bash 탐색이 나쁜 디렉터리를 빼는 대신 후보를 돌려 본다. Windows에서는
  PATH와 `git` 기준 경로의 후보마다 `bash -c 'echo $OSTYPE'`를 실행해 `msys`·`cygwin`인
  첫 번째만 쓴다. 전에는 `SystemRoot` 아래만 건너뛰어 `…\Microsoft\WindowsApps\bash.exe`
  (WSL을 여는 Store alias)를 집었고, 실기에서 모든 케이스가 exit 126이었다. 쓸 수 있는
  bash가 없으면 후보마다 탈락 이유를 담아 실패한다. 선택 로직은 가짜 후보로 macOS
  게이트에서도 검사한다. 배포되는 훅과 가드는 그대로다.

## [0.7.2] - 2026-09-21

### Fixed

- `hooks/session-start.sh`가 Windows에서 모든 상태를 "확인에 실패" 분기로 읽던
  것을 고친다. Windows의 python은 stdout이 text mode라 `print()`가 `\r\n`을 쓰고,
  bash `read`는 `\n`만 떼어 `\r`을 남긴다. `ready\r`·`missing\r`·`mismatch\r`이
  `case`의 어느 패턴에도 맞지 않아, CLI가 계약을 만족해도 매 세션 실패 문장을
  읽혔다 — "정상이면 침묵"이 Windows에서 전부 깨져 있었다. 훅의 두 python 호출이
  `sys.stdout.reconfigure(newline="\n")`으로 줄 끝을 고정한다. CLI는 macOS
  전용이지만 훅은 `hooks.json`에 무조건 등록되어 Windows의 Claude Code도 돌린다.
- 훅이 python을 `python3`이라는 이름 하나로 부르던 것을 고친다. `python3`,
  `python` 순으로 실제로 돌려 보고 3.7 이상인 것을 쓴다. 전에는 `python3`이
  실행되지 않으면 훅이 아무 말 없이 끝나 CLI가 없어도 알리지 못했다. 둘 다 없으면
  그 사실을 고정 문장으로 알린다. 종료 코드는 여전히 0이다.

### Changed

- `scripts/checks/verify_session_start.py` — 설치 명령이 "포함되는가"가 아니라
  **어느 분기의 문장인가**를 묻는다. 전의 물음은 "확인에 실패" 분기도 remedy를
  끼워 넣으므로 위 결함을 통과시켰다. 컨텍스트와 payload 어디에도 `\r`이 없는지
  보고, 줄 끝을 `\r\n`으로 쓰는 python·`python3`이 실행되지 않는 기기·python이
  없는 기기를 흉내 내어 같은 상태를 다시 태운다. 경로 구분자와 bash·python의
  위치를 단정하지 않아 Windows(Git Bash)에서도 돈다.
- `scripts/check-windows.ps1`이 매니페스트 정합성에 더해 위 훅 검사를 돌린다.
  "Windows에서 실행할 것이 없다"는 전제는 CLI에 대해서만 맞았다. 저장소 CI의
  `windows-latest` 잡이 이 스크립트를 부른다 — 전에는 부르는 곳이 없었다.

## [0.7.1] - 2026-09-21

### Added

- `hooks/session-start.sh`와 `hooks/hooks.json` — 세션이 시작될 때 CLI 계약을
  한 번 확인하고, 어긋날 때만 말한다. `require-cli.sh` 가드는 스킬을 부를 때
  돌기 때문에 사용자는 일을 시키고 나서야 CLI가 없거나 낡았음을 알았다. 판정은
  여전히 가드 하나에만 있고 훅은 알리는 시점만 앞당긴다. 정상이면 침묵하고,
  어떤 상태에서도 세션을 실패시키지 않는다.
- `scripts/checks/verify_session_start.py` — 가짜 CLI를 PATH에 두고 훅의 네
  상태(정상·없음·낡음·앞섬)와 종료 코드를 게이트에서 검사한다.

### Fixed

- 플러그인 버전을 올린다. 0.7.0을 올리지 않은 채 내용만 바꿔 재배포한 탓에
  `claude plugin update`가 "already at the latest version"을 답하고 설치
  캐시가 낡은 채로 남았다. 그 캐시의 `cli-contract.json`은 없어진 tap
  `xiyo/local/sherpa`를 설치 안내로 내보내고 있었다. 버전 번호가 캐시 무효화의
  유일한 신호이므로, 플러그인 내용을 바꾸면 같은 변경에서 버전을 올린다.

## [0.7.0] - 2026-08-27

### Added

- `cli-contract.json`과 `scripts/require-cli.sh` — 스킬이 요구하는 최소 CLI
  버전을 한 곳에 두고, CLI를 호출하는 스킬(`sherpa`, `planner`, `context`,
  `kakaotalk-local-search`)이 첫 명령 전에 확인한다. 플러그인과 CLI는 같은
  저장소에서 나가지만 설치 경로가 달라(`plugin install` / `brew`) 사용자
  머신에서 버전이 어긋날 수 있다. 그 어긋남을 작업 중간이 아니라 시작 전에
  잡는다.
- `kakaotalk-local-search` 스킬 — Mac에 동기화된 KakaoTalk 텍스트를 키워드
  검색, 한 방 7일 히스토리, 명시한 날짜부터의 전체 방 아카이브로 읽는다.
  로컬 텍스트 체크포인트는 Agent Messenger 체크포인트와 분리된다. CLI 0.7.0
  이상이 필요하다.
- `scripts/check.sh`, `scripts/check-windows.ps1` — 매니페스트 정합성, 스킬
  집합, 가드 참조, 절대경로 유출, 빌드 산출물 혼입을 검사한다. Windows는
  매니페스트만 확인하고 건너뛴다(CLI가 macOS 전용).

### Changed

- 마켓플레이스가 `sherpa-runtime`에서 `sherpa`로 바뀌었다. 이제
  `claude plugin marketplace add XIYO/sherpa` 뒤 `sherpa@sherpa`로 설치한다.
- 플러그인을 CLI 아카이브에 번들하고 `sherpa plugin install`로 등록하던 방식을
  걷어냈다. 그 방식은 죽은 심링크만 남겼다.

### Removed

- 스킬 프론트매터의 `contract_version`과 본문의 고정 버전 문구. CLI와 스킬을
  같은 버전으로 강제하던 계약을 최소 버전 가드가 대신한다.
- `supply` 스킬. 대응하는 CLI 명령이 없어 호출하면 `invalidRequest`로 실패했다.
  복원이 필요하면 커밋 `ecbc1eb`에서 가져온다.
- `.antigravity-plugin` 매니페스트.
