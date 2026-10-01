---
uuid: 01a0f26e-2205-775e-b488-ce1446a98615
type: plan
audience: "다음 세션의 에이전트와 저장소 소유자. sherpa 공개 릴리스를 기기와 마켓플레이스에 적용할 때"
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
- 2026-10-01, `v0.7.1` 태그 push·릴리스 생성·자산 업로드는 소유자가 승인한 원격 쓰기다 (허브 세션이 전한 말).

## Session choices

- 공개 방식: 공개 시점에 추적 파일(`git archive HEAD`)을 단일 커밋으로 새 공개 저장소에 올린다. 옛 이력과
  릴리스는 공개하지 않는다. 지휘 세션이 정한 방식이다.
- `docs/testing/live-evidence.md` 에서 supply 시기 항목(2026-08-04 전부, 2026-08-06 baseline)만 지웠다.
  2026-08-01·08-05·08-10 항목은 개인 내용이 없어 남겼다.
- 개발용 로컬 tap 이름을 `xiyo/sherpa-dev` 로 정했다(런북 "Development installs"). 지금 이 Mac 에 깔린 CLI 는
  그보다 앞선 로컬 tap `xiyo/package-hole` 에서 왔다.
- README 들과 Formula caveats 의 마켓플레이스 추가 명령을 전체 URL(`https://github.com/XIYO/sherpa.git`,
  플러그인 README 의 plug-hole 은 `https://github.com/XIYO/plug-hole.git`)로 바꿨다.
  근거는 단축형의 SSH 복제 우려다. 다만 `marketplace add` 단축형은 이 Mac 에서 HTTPS remote 로 성공한
  관측이 있다(live-evidence 2026-09-21). SSH 로 실패한 것은 마켓플레이스 항목의 `owner/repo` 소스였다.
- 플러그인을 0.7.6 으로 올렸고 CLI 는 올리지 않았다(바이너리 소스가 바뀌지 않았다).
- ADR-0005 의 `status` 키도 다른 옛 키와 함께 지웠다.
- `v0.7.1` 은 주석 태그로 만들었고 릴리스 제목은 `v0.7.1`, 본문은 설치 명령 한 줄과 스킬이 따로 나간다는 문장이다.
- tap 변경은 `homebrew-tap` clone 안의 worktree `.claude/worktrees/sherpa-071`(브랜치 `release/sherpa-071`,
  `origin/main` 7c4e2d6 기준)에 두었다. README 는 미리보기 브랜치 `prepare/sherpa-071-preview`(c79d2f1)의
  것을 그대로 가져왔고 Formula 는 publish 실행이 만든 파일을 통째로 복사했다. 미리보기 worktree 는 지우지 않았다.
- 개발 원본 폴더를 바꿨다. 공개 clone 이 `sherpa` 가 되고, 옛 clone 은 `sherpa-archive` 로 이름을 바꿨다
  (내부 worktree `ph-sherpa-prepare` 는 `git worktree repair` 로 경로를 고쳤다). 두 clone 의 remote 는 각자의
  저장소 하나뿐이고 `pushurl` 은 없다.

## State

2026-10-01 기준.

- **판.** 플러그인 0.7.7, CLI 0.7.1. 공개 저장소 `XIYO/sherpa` 는 root commit `0ade90b` 하나이고 CI(hosted
  Windows) run 36792732514 이 success 다.
- **릴리스.** 태그 `v0.7.1` 이 `0ade90b` 에 있고 GitHub 릴리스가 있다. 자산
  `sherpa-0.7.1-aarch64-apple-darwin.tar.gz`(693680 bytes)는 `package.sh --publish` 가 올리고 다시 받아
  대조했다. sha256 `70c4cb18b4e3ce3e58f92c88844a05a898cb17c7af5f3b3e6ba2812558aa7a48`. 같은 실행의
  `target/dist/Formula/sherpa.rb` 가 그 해시를 박고 있다. 이 폴더는 다시 만들지 않는다 — Swift 빌드가 비결정적이라
  다른 실행의 해시는 다르다.
- **공개 tap.** `XIYO/homebrew-tap` `main` 이 0.7.1 Formula 와 새 README 를 갖는다(81958e6, 이어서 8692f83 이
  중복 `version` 줄을 뺐다). `brew audit --formula xiyo/tap/sherpa` 가 통과한다. Formula 변경은 url·sha256 밖에도
  미친다(desc·homepage·arch·caveats·test 블록) — 템플릿이 0.2.1 때와 다르기 때문이고 런북이 허용한 경우다.
  `version` 줄은 템플릿 결함이었다: Homebrew 가 url 의 아카이브 이름에서 판을 읽으므로 audit 이 redundant 로
  거부한다. 이 브랜치가 `package.sh` 템플릿과 `check-release.sh`(url 에서 판을 읽고 audit 을 스모크에 넣음)를 고친다.
- **보관.** 옛 저장소는 `XIYO/sherpa-archive` 로 이름을 바꿔 비공개로 archive 한다(이름은 지휘 세션이 정했다).
  옛 PR·이슈·Actions 기록은 거기 남는다. 옛 저장소의 self-hosted Windows 러너 등록은 그대로다. 등록 해제는
  소유자 승인 사항이다. 로컬 `sherpa-archive` clone 의 `release/sherpa-0.7.7` 은 원격보다 커밋 1개 앞서 있고
  push 하지 않았다.
- **이 Mac 의 CLI 설치본**은 공개 tap `xiyo/tap` 의 0.7.1 이다(`brew info` 의 tap 이 `xiyo/tap`, keg 하나, pinned 는
  옛 설치처럼 유지). 옛 로컬 tap `xiyo/package-hole` 은 untap 했다. `brew test sherpa` 통과.
- **마켓플레이스와 플러그인.** 두 기기의 모든 Claude 프로필과 Codex 홈이 새 이력의 마켓플레이스에서 0.7.7 을 받았다
  (맥 `sherpa@sherpa`, able-tei `.claude` 의 `sherpa@xiyo`; Windows 의 다른 프로필은 `macos_only` skip).
- **옛 front matter 키**(id·title·status·owner)가 문서 22개에 남아 있다. ADR·RFC 의 `status` 값은 정보를 담고
  있어 처분이 미결이다.

## Next

1. 이 PR(템플릿 수정과 이 인계)의 Windows CI 가 통과하면 손으로 병합한다(AGENTS 의 병합 규칙).
2. 옛 front matter 키가 남은 22개 문서를 정리한다.

## Blocked

- 옛 저장소 `XIYO/sherpa-archive` 의 self-hosted Windows 러너 등록 해제는 소유자 승인 사항이다.
