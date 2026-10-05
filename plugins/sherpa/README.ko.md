---
uuid: 01a0f252-d266-7311-bd25-486f59b094a3
type: guide
audience: "Claude Code나 Codex에서 Sherpa 플러그인과 CLI를 설치하려는 Mac 사용자"
goal: "CLI와 플러그인 진입점 하나를 설치하고 첫 요청을 실행하며 어떤 데이터가 로컬에 남는지 알게 한다"
tone: "사용자에게 쓰는 합니다체. 단계 앞에 요구 조건을 먼저 밝힌다"
manner: "결과 → 설치 → 선행 조건 → 첫 사용 → 검증 → 데이터 경계 → 제한 순서를 지킨다"
---

# Sherpa

[English](README.md)

Sherpa는 플래닝 의도를 내 Mac 안에서 처리하는, 범위가 정해지고 증거를 확인하는
작업으로 바꿉니다. 네이티브 `sherpa` CLI로 Calendar, Reminders, Mail, iMessage,
KakaoTalk을 읽고, 변경을 제안하고, 정확한 내용을 확인받은 다음에만 실행합니다.
명시적으로 보내는 것 말고는 이 컴퓨터를 벗어나지 않습니다.

## 설치

플러그인은 스킬과 SessionStart 훅을 담고 있습니다. CLI를 먼저 설치하세요.

```bash
brew install xiyo/tap/sherpa
sherpa --version
```

GitHub 계정에 비공개 `XIYO/plug-hole` 저장소의 접근 권한이 필요합니다.

```bash
claude plugin marketplace add https://github.com/XIYO/plug-hole.git
claude plugin install sherpa@plug-hole
```

```bash
codex plugin marketplace add https://github.com/XIYO/plug-hole.git
codex plugin add sherpa@plug-hole
```

`plug-hole`은 이 저장소의 `plugins/sherpa/`에서 플러그인을 받습니다. CLI는
Homebrew로 따로 설치합니다.

새 세션이 스킬을 불러옵니다. 스킬은 세션 시작 시점의 스냅샷에서 불러오므로 열린
세션은 이미 실은 판을 계속 씁니다.

## 선행 조건

- macOS 14 이상, Apple silicon
- Calendar와 Reminders 권한 — 처음 읽을 때 요청합니다
- Mail과 iMessage를 위한 호스트 애플리케이션의 전체 디스크 접근 권한
- 로컬 KakaoTalk 읽기를 위한 공식 `kakaocli` 실행 파일

## 첫 사용

평소 말로 요청하면 `sherpa` 스킬이 알맞은 곳으로 보냅니다.

```text
오늘 일정과 할 일을 정리해줘.
새 메시지에서 일정 후보를 찾아줘.
```

스킬 다섯 개가 일을 나눠 맡습니다.

| 스킬 | 담당 |
|---|---|
| `sherpa` | 진입점. 의도를 라우팅하고 증거 루프를 돌립니다. |
| `planner` | 검증된 제안과 readback을 거치는 Calendar와 Reminders. |
| `context` | 범위가 정해진 Mail·iMessage·KakaoTalk 읽기, 약속과 후보 추출. |
| `kakaotalk-local-search` | 로컬 KakaoTalk 텍스트 — 키워드 검색, 한 방 히스토리, 날짜 아카이브. |
| `agent-messenger` | 상류 CLI로 처리하는 서버 기반 KakaoTalk·Discord·iMessage·Instagram. |

## 검증

```bash
sherpa --version
claude plugin list
```

Codex에서는 `codex plugin list --marketplace plug-hole`을 실행합니다. 목록에서 Sherpa가
설치·활성 상태인지 확인합니다. 새 세션은 macOS에서 번들 CLI 가드를 실행합니다.
CLI가 준비됐으면 침묵하고, 버전이 다르면 `mismatch`와 두 버전을, 없으면
`missing`을 알립니다. 각 스킬도 첫 CLI 명령 전에 같은 가드를 실행합니다.

macOS가 아닌 곳에서는 가드가 CLI를 찾아보지 않고 `unsupported`
(`"reason":"macos_only"`)를 답하며 설치 명령을 권하지 않습니다.

## 버전 계약

플러그인과 CLI는 한 저장소에 있지만 컴퓨터에 도착하는 경로가 다릅니다. 스킬은
`plugin install`로, CLI는 Homebrew로 들어옵니다. 두 설치를 맞춰 주는 장치가
없으므로 버전이 어긋날 수 있습니다. 중요한 제약은 `cli-contract.json` 하나에 담았습니다 — 이
스킬들이 요구하는 최소 CLI 버전, 같은 MAJOR 안에서. CLI를 호출하는 모든 스킬은
첫 명령 전에 `scripts/require-cli.sh`를 실행합니다. 그래서 낡은 CLI는 작업
중간에 깨지는 대신 명확한 메시지와 함께 멈춥니다.

## 데이터 경계

읽기는 명시한 개수와 체크포인트로 범위가 정해지고, 모든 결과는 자기 커버리지를
함께 보고합니다. 로컬 KakaoTalk 읽기는 동기화된 텍스트만 다룹니다 — 첨부는
읽지 못하고, 서버에 더 없다는 증거도 되지 못합니다. 이 체크포인트는 Agent
Messenger 체크포인트와 분리되어 있고 분석을 마친 뒤에만 커밋됩니다.

보내는 메시지와 메일은 먼저 초안을 만들고, 정확한 수신자와 내용을 승인받은
다음에만 발송합니다. Calendar와 Reminders 변경도 같은 확인 경계를 지납니다.
Sherpa는 불투명 참조만 돌려주며 제공자의 네이티브 식별자는 넘기지 않습니다.

## 제한 사항

- macOS 전용입니다. Windows와 Linux의 Claude Code도 SessionStart 훅은 실행하지만
  거기서는 훅이 침묵하고, 스킬을 부르면 가드의 `unsupported` 응답에서 멈춥니다.
  저장소의 Windows 검사는 매니페스트와 그 훅만 확인하고 나머지는 건너뜁니다.
- `sherpa`는 어떤 서비스의 완전한 아카이브도 아닙니다.
- CLI는 함께 묶이지 않습니다. 플러그인을 올려도 CLI는 올라가지 않습니다.

## 개발

플러그인은 `plugins/sherpa/`에, CLI는 `apple/eventkit-service` Swift 패키지에
있습니다. 둘 다 이 저장소에서 배포합니다.

```bash
bash scripts/check-all.sh
```
