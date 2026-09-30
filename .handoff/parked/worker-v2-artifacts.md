---
uuid: 01a0ed84-ef0a-777a-9908-347c9306f5ad
type: plan
audience: "다음 세션의 에이전트. Worker Protocol V2 경계를 손댈 때"
goal: "V2 문서가 약속만 하고 만든 적 없는 스키마와 fixture 두 자리를 알고 채우거나 지우게 한다"
tone: "평어체. 히스토리로 확인한 것만 적는다"
manner: "두 자리의 줄과 경로를 짚고 결정은 경계 작업에 맡긴다"
---

# Worker Protocol V2 가 약속한 파일

## Goal

아래 두 문서가 존재하지 않는 파일을 가리키지 않는다. 약속한 스키마와 fixture 를 만들거나, 약속한 문장을
지금의 검증 경로로 고친다.

## Owner decisions

없음.

## Session choices

- 앞선 세션이 이 결정을 V2 경계를 손댈 때로 미뤘다. 끊긴 참조를 고친 PR #14 의 범위 밖이었다.

## State

2026-09-29 확인.

- `docs/contracts/worker-protocol.md:85` 가 `protocols/worker-v2.schema.json` 을,
  `docs/testing/README.md:149` 가 `protocols/fixtures/worker-v2` 를 정본과 공유 fixture 로 적는다.
- 저장소에 `protocols/` 디렉터리가 없다. `git log --all` 에 두 경로가 한 번도 나오지 않는다. 있었던
  것은 `protocols/worker-v1.schema.json` 뿐이고 `1ca44ef` 가 지웠다.
- 두 자리는 코드 스팬이라 `scripts/checks/verify_docs.py` 의 링크 검사가 잡지 않는다.

## Next

1. V2 경계를 손대는 작업이 열리면, 스키마를 실제로 두고 게이트가 검증하게 할지 두 문장을 고칠지 정한다.
