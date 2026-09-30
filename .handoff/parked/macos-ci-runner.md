---
uuid: 01a0ed84-ef03-769e-94a6-5bd90b0d622d
type: plan
audience: "다음 세션의 에이전트와 저장소 소유자. macOS 게이트를 CI 에 올릴지 다시 볼 때"
goal: "맥 self-hosted 러너를 등록하는 조건과 등록해도 남는 한계를 알고 재개 여부를 정하게 한다"
tone: "평어체. 확인한 제약과 보지 못한 실패 양상을 가른다"
manner: "조건만 적고 CI 설계의 근거는 verify.yml 주석과 AGENTS.md 로 내린다"
---

# macOS 게이트를 CI 에 올리기

## Goal

`bash scripts/check-all.sh` 의 macOS 게이트(Swift 패키지 셋, 매니페스트·계약·문서 검사)가 병합 전
로컬 실행에 기대지 않고 self-hosted 맥 러너에서 실행된다.

## Owner decisions

없음. 이 저장소에 맥 러너를 등록하라는 소유자 지시는 없다.

## Session choices

- 앞선 세션이 이 일을 다음 후보로만 두고 등록하지 않았다. 게이트의 릴리스 스모크가 작업용 Mac 에 침습적이고,
  노트북 러너는 뚜껑이 닫히면 잠들어 잡이 큐에 매달리기 때문이다.

## State

2026-09-29 확인.

- CI 는 잡 하나다. `.github/workflows/verify.yml` 의 `runs-on: [self-hosted, Windows]` 가
  `plugins/sherpa/scripts/check-windows.ps1` 을 실행한다. macOS 게이트는 어느 러너도 실행하지 않는다.
- 릴리스 스모크 `scripts/check-release.sh` 는 `brew unlink sherpa` 뒤 `brew link --overwrite` 로 실제
  brew 링크를 바꾼다.
- `apple/foundation-models-service` 가 `platforms: [.macOS(.v26)]` 라 게이트 전체가 macOS 26 이상을
  요구한다. 그 미만에서 어떻게 깨지는지는 본 적이 없다.
- 브랜치 보호와 룰셋 API 가 둘 다 403 을 돌려준다(비공개이고 GitHub Pro 가 아니다). 러너를 등록해도 그 잡을
  필수 체크로 걸 수 없다.

## Next

1. 재개한다면 조건은 셋이다. 스모크를 뺀 게이트(`SHERPA_SKIP_RELEASE=1`), 잠들지 않는 기기, macOS 26
   이상.
2. Actions 결제가 풀리면 hosted 두 잡을 `36ecba2` 이전의 `verify.yml` 에서 되살릴 수 있다.
