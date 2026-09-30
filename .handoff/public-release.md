---
uuid: 01a0f26e-2205-775e-b488-ce1446a98615
type: plan
audience: "다음 세션의 에이전트와 저장소 소유자. sherpa 를 공개 저장소로 옮기고 공개 tap 으로 배포할 때"
goal: "공개 전환에 남은 단계를 순서대로 밟고 누가 승인해야 하는지 알게 한다"
tone: "평어체. 확인한 것과 실행하지 않은 것을 가른다"
manner: "단계마다 필요한 승인과 선행 단계를 적고 절차는 릴리스 런북으로 내린다"
---

# sherpa 공개 전환

## Goal

추적 파일이 같은 이름의 새 공개 저장소 `XIYO/sherpa` 에 올라가 있다. 그 저장소의 `v0.7.1` 릴리스
자산을 공개 tap `XIYO/homebrew-tap` 의 Formula 가 가리키고, 새 Mac 에서
`brew install xiyo/tap/sherpa` 가 플러그인 계약(`minimumVersion` 0.7.1)을 만족하는 CLI 를 설치한다.
작업 트리에 공개하면 안 되는 값이 없다.

## Owner decisions

- "민감한건 수정못하면 지울꺼다" (2026-09-30, 부모 세션이 전한 소유자의 말).
- MIT 로 정리하고 커밋 트리를 깔끔하게 한다 (2026-09-30, 부모 세션이 전한 소유자 결정. 원문 인용이 아니다).
- `XIYO/homebrew-tap` 을 고치는 것은 소유자 승인 사항이다 (2026-09-30, 작업을 지휘한 세션이 전한 말).
- 2026-09-30, 공개 tap 교체를 두고: "승인한다 배포".
- 2026-09-30, 공개 방식을 두고 처음에는 "기존 저장소를 그대로해라 싹 초기화해도된다 포스 푸시" 라고 했다가, 옛 PR 이 force-push 뒤에도 남는다는 말을 듣고 "아하 그럼 많이 이상하네? 기존 sherpa를 아카이브 화해서이름바궈놓고 비공개해놓고 새로만드는게훨낫네?" 로 바꿨다. 뒤의 것이 이긴다. 이어서 "그래진행해라  rename 스스로가느하지?".

## Session choices

- 공개 방식: 공개 시점에 추적 파일(`git archive HEAD`)을 단일 커밋으로 새 공개 저장소에 올린다. 옛 이력과
  릴리스는 공개하지 않는다. 지휘 세션이 정한 방식이다.
- `docs/testing/live-evidence.md` 에서 supply 시기 항목(2026-08-04 전부, 2026-08-06 baseline)만 지웠다.
  2026-08-01·08-05·08-10 항목은 개인 내용이 없어 남겼다.
- 개발용 로컬 tap 이름을 `xiyo/sherpa-dev` 로 정했다(런북 "Development installs").
- README 들과 Formula caveats 의 마켓플레이스 추가 명령을 전체 URL(`https://github.com/XIYO/sherpa.git`,
  플러그인 README 의 plug-hole 은 `https://github.com/XIYO/plug-hole.git`)로 바꿨다.
  근거는 단축형의 SSH 복제 우려다. 다만 `marketplace add` 단축형은 이 Mac 에서 HTTPS remote 로 성공한
  관측이 있다(live-evidence 2026-09-21). SSH 로 실패한 것은 마켓플레이스 항목의 `owner/repo` 소스였다.
- 플러그인을 0.7.6 으로 올렸고 CLI 는 올리지 않았다(바이너리 소스가 바뀌지 않았다).
- ADR-0005 의 `status` 키도 다른 옛 키와 함께 지웠다.

## State

2026-09-30 기준.

- **판.** 플러그인 0.7.7, CLI 0.7.1. 공개 트리는 0.7.6 정리에 0.7.7(README 가 새 세션을 지시하지 않음)과 공개 전환 수정(CI 를 GitHub-hosted `windows-latest` 로, AGENTS 의 CI·병합 규칙, "비공개" 문장)을 더한 것이다.
- **보관.** 옛 저장소는 `XIYO/sherpa-archive` 로 이름을 바꿔 비공개로 archive 한다(이름은 지휘 세션이 정했다). 옛 PR·이슈·Actions 기록은 거기 남는다. 옛 저장소의 self-hosted Windows 러너 등록은 그대로다. 등록 해제는 소유자 승인 사항이다.
- **공개 tap 의 Formula 는 0.2.1 이다.** 새 공개 저장소의 `v0.7.1` 릴리스 자산을 올린 뒤 `package.sh` 가 만든 Formula 로 바꾼다.
- **이 Mac 의 CLI 설치본**은 원격 없는 옛 로컬 tap 에서 온 0.7.1 이다.
- **옛 front matter 키**(id·title·status·owner)가 문서 22개에 남아 있다. ADR·RFC 의 `status` 값은 정보를 담고 있어 처분이 미결이다.

## Next

1. 공개 저장소 `XIYO/sherpa` 의 첫 커밋 CI(hosted Windows)가 통과하는지 본다. 계정의 Actions 결제 차단이 공개 저장소에도 걸리면 소유자에게 알린다.
2. `v0.7.1` 태그와 릴리스를 만들고 `bash scripts/package.sh --publish` 로 자산을 올린다. 같은 실행의 Formula 로 `XIYO/homebrew-tap` 을 바꾼다.
3. 이 Mac 에서 `brew uninstall sherpa` 뒤 `brew install xiyo/tap/sherpa` 로 옮기고 옛 로컬 tap 을 `brew untap` 한다.
4. 각 프로필의 `sherpa` 마켓플레이스가 새 이력에서 갱신되는지 보고, 실패하면 다시 추가한다. 플러그인을 0.7.7 로 올린다.
5. 옛 front matter 키가 남은 22개 문서를 정리한다.
