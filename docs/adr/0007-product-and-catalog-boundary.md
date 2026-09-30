---
uuid: 01a0ed87-80cb-70b3-aae5-84aeb019c43c
type: adr
audience: "이 저장소와 plug-hole 을 고치는 사람. 상품과 카탈로그의 경계를 다시 볼 때"
goal: "Sherpa 의 소스·릴리스가 왜 이 저장소에 남고 plug-hole 은 진입점만 갖는지 확인하게 한다"
tone: "평어체. 결정과 실측과 추론을 가른다"
manner: "결정 본문은 고치지 않고 바뀐 사실은 정정으로 덧붙인다"
---

# Sherpa는 제품이고 Plug Hole은 카탈로그다

> **정정 (2026-09-21).** 아래 Consequences와 `## 검증`이 적는 "버전 번호가 캐시 무효화의
> 유일한 신호다"는 **Claude Code 한정**이다. Codex는 버전을 비교하지 않고 `codex plugin add`
> 를 돌릴 때마다 소스를 다시 체크아웃하며, `ref`·`sha` 고정도 실제로 따른다. 결정 자체는
> 바뀌지 않았고 결정 본문도 그대로 둔다 — 근거와 실측은 `## 검증`의
> "Codex(codex-cli 0.155.1, macOS)" 절에 있다.
>
> **정정 (2026-09-30).** 본문의 `xiyo/package-hole` 은 원격 없는 로컬 tap 이었다. 저장소를
> 공개하면서 CLI 설치의 정본은 공개 tap `XIYO/homebrew-tap` 의 `brew install xiyo/tap/sherpa`
> 이고, Formula 는 이 저장소의 릴리스 자산을 가리킨다. 로컬 tap 은 개발용으로만 남는다 —
> 절차는 [릴리스 런북](../testing/local-homebrew-release.md)에 있다. 결정은 그대로다.

## Context

Sherpa는 한 저장소에서 두 가지를 배포한다 — brew로 나가는 네이티브 CLI와
plugin marketplace로 나가는 에이전트 스킬. 그래서 사용자 머신에서 설치 경로가
둘로 갈리고, "스킬이 플러그인으로 등록되면 코어 CLI는 어떻게 따라오는가"라는
질문이 반복해서 돌아온다.

2026-08-27에 스킬을 `XIYO/plug-hole`로 옮겼다가 같은 날 되돌렸다(plug-hole
`265455e`). 되돌린 근거는 한 기능(`kakaotalk-local-search`)이 CLI 어댑터와
스킬로 갈려 커밋 두 개로 쪼개진 실제 사례였다.

2026-09-21에 그 근거를 재검토했고, **둘은 약해졌다**.

- 그때 옮긴 것은 스킬뿐이었다. CLI까지 같이 옮기면 한 기능이 두 저장소로
  갈리는 문제는 생기지 않는다. 런타임 소스·설치 스크립트·명령·훅을
  스킬과 같은 상품 폴더에 둘 수 있다.
- plug-hole CI는 이미 `macos-latest`와 `windows-latest`를 돈다. Swift 빌드
  러너가 없다는 반대 근거도 성립하지 않는다.

그럼에도 합치지 않는다. 근거가 바뀌었을 뿐 결론은 같다.

## Decision

**Sherpa는 독립 저장소로 남는다.** CLI 소스, 에이전트 스킬, 릴리스
파이프라인(`scripts/package.sh` → tarball → Formula 렌더 → `xiyo/package-hole`
tap), 게이트(`scripts/check-all.sh`)가 모두 여기 있다.

**Plug Hole은 큐레이션 카탈로그로 남는다.** `catalog-policy.json`이
`primary`와 `published` 목록을 관리하는 플러그인 목록이다.

경계를 가르는 기준은 소스 위치나 저장소 개수가 아니라 **릴리스 파이프라인의
소유권**이다. Sherpa는 컴파일 산출물을 만들어 tap으로 내보내는 제품이고, 그
파이프라인을 카탈로그 저장소로 들고 들어가는 것이 합칠 때의 실제 비용이다.
인터프리터 스크립트를 복사하는 상품에는 같은 컴파일 비용이 없다.

**카탈로그 진입점.** plug-hole은 Sherpa를 *설치 진입점*으로 제공한다
(2026-09-21, XIYO/plug-hole PR #5). 이것은 이 결정과 모순되지 않는다.
마켓플레이스 항목이 다른 저장소의 하위 디렉터리를 가리킬 수 있기 때문이다 —
`git-subdir` 소스가 `plugins/sherpa/`만 설치하는 것을 실제 설치로 확인했고, 그
항목으로 `sherpa@xiyo`를 설치했다(아래 `## 검증`). 소스와 릴리스는 이 저장소에
남고 plug-hole은 목록만 갖는다. 카탈로그는 진입점일 뿐이다 — plug-hole에는
`plugins/sherpa/` 디렉터리가 없고, 그쪽 checker는 `catalog-policy.json`의
`external` 선언과 두 카탈로그 항목이 일치하는지만 본다.

## Consequences

- 설치는 두 단계로 남는다 — `claude plugin install sherpa@sherpa`와
  `brew install xiyo/package-hole/sherpa`. 이것은 결함이 아니라 제품 형태의
  결과다. 대신 어긋남을 사용자가 늦게 알아채지 않도록 가드를 둔다. 플러그인
  쪽 경로는 이제 둘이다 — 이 저장소 자체의 마켓플레이스(`sherpa@sherpa`)와
  plug-hole 카탈로그(`sherpa@xiyo`). 둘 다 같은 `plugins/sherpa/`를 받고, CLI는
  어느 쪽으로도 따라오지 않는다.
- 버전 가드는 두 겹이다. `cli-contract.json`의 `minimumVersion`을
  `scripts/require-cli.sh`가 확인하고, CLI를 부르는 스킬 넷이 첫 명령 전에
  통과해야 한다. 그 위에 `hooks/session-start.sh`가 세션 첫머리에 같은 가드를
  한 번 돌려, 스킬을 부르기 전에 알린다. 판정은 가드 하나에만 있다.
- 플러그인 내용을 바꾸면 같은 변경에서 `plugin.json` 버전을 올린다. 버전
  번호가 설치 캐시 무효화의 유일한 신호다. 0.7.0을 올리지 않고 재배포했더니
  `claude plugin update`가 "already at the latest version"을 답하고 캐시가
  낡은 채 남아, 없어진 tap 이름을 설치 안내로 내보냈다. `git-subdir` 진입점도
  같다 — update는 버전 번호만 비교하고 커밋은 보지 않는다(아래 `## 검증`).
  (2026-09-21 정정: 이 문단은 Claude Code 한정이다 — 위 문서 첫머리의 정정.)

## Rejected alternatives

- **스킬만 plug-hole로 옮긴다.** 2026-08-27에 실제로 해보고 되돌렸다. 한 기능이
  두 저장소로 갈린다.
- **CLI까지 통째로 plug-hole로 옮긴다.** 기술적으로 막히는 곳은 없다(위 Context
  참조). 카탈로그 저장소가 컴파일 산출물의 릴리스 파이프라인과 tap 렌더링을
  떠안게 되는 것이 비용이고, 그만한 이득이 없다.
- **tap을 저장소에 합친다.** formula는 `package.sh`가 만드는 생성물이고 tarball은
  다른 곳에 있어 실익이 없다.

## 검증

마켓플레이스 항목이 다른 저장소의 하위 디렉터리(`plugins/sherpa`)를 가리킬 때
어떤 필드가 실제로 쓰이는지를 2026-09-21에 실제 설치로 확인했다. claude
2.1.278, 빈 `CLAUDE_CONFIG_DIR`, 로컬 디렉터리 마켓플레이스에 변형을 나란히 넣고
`claude plugin install`을 돌린 뒤 캐시를 열어 봤다. 전체 기록은
[실측 기록](../testing/live-evidence.md)에 있다.

| 소스 | `validate --strict` | `install` | 캐시에 들어온 것 |
| --- | --- | --- | --- |
| `git-subdir` + `path` | 통과 | 성공 | `plugins/sherpa/`의 내용만. 루트에 `.claude-plugin/plugin.json`과 `skills/`, 버전 `0.7.1`, 스킬 5·훅 1 인식 |
| `github` + `path` | 통과 | 성공 | 저장소 루트 통째. 버전은 커밋 해시 앞 12자, 스킬 0·훅 0 |
| `github` + `subdirectory` | 통과 | 성공 | 위와 같다 |

**하위 디렉터리를 해석하는 것은 `git-subdir`뿐이다.** `github` 소스는 `path`도
`subdirectory`도 조용히 버리고 저장소 루트를 복사한 뒤, 거기서 플러그인
매니페스트를 찾지 못한 채 구성 요소가 0개인 플러그인을 enabled로 등록한다.
validate, install, list 어디에서도 오류를 내지 않는다. 통과와 설치 성공 어느
쪽도 해석했다는 뜻이 아니었다.

`url` 표기도 갈린다. `XIYO/sherpa` 단축형은 `git-subdir`에서도 `github`에서도
SSH(`git@github.com:`)로 복제하고, 이 Mac에는 GitHub SSH 키가 없어
`Permission denied (publickey)`로 끝났다. 전체 HTTPS URL은 시스템 credential
helper(`gh auth git-credential`)를 타고 private 저장소를 그대로 받았다. 단축형
변형들은 프로세스 환경 변수로만 건 `insteadOf` 재작성 아래에서 관찰했다.

plug-hole에 올라간 항목의 `source`는 다음과 같다(XIYO/plug-hole PR #5). Claude
매니페스트(`.claude-plugin/marketplace.json`)와 Codex
매니페스트(`.agents/plugins/marketplace.json`)가 같은 객체를 갖는다.

```json
{
  "name": "sherpa",
  "source": {
    "source": "git-subdir",
    "url": "https://github.com/XIYO/sherpa.git",
    "path": "plugins/sherpa"
  }
}
```

plug-hole의 checker는 원래 저장소 내부 상품만 받았다(항목 = published =
`plugins/` 디렉터리, source는 `./plugins/<name>`). 그래서 `catalog-policy.json`에
`external` 선언을 새로 두고, 선언된 외부 상품만 인정하게 했다 — published에
있어야 하고 primary일 수 없으며, url은 전체 `https://….git`, path는 상대 경로,
두 카탈로그의 source 객체가 선언과 키까지 같아야 하고, `ref`·`sha` 고정과
`github` 소스는 거부한다. 테스트 넷이 이를 덮는다. PR #5는 macOS·Windows CI가
둘 다 pass였고 병합 후 main CI도 success였다.

그 항목을 같은 날 실제로 돌렸다. claude 2.1.278, 매번 새 빈
`CLAUDE_CONFIG_DIR`. 전체 기록은 [실측 기록](../testing/live-evidence.md)에 있다.

| 확인한 것 | 결과 |
| --- | --- |
| `claude plugin install sherpa@xiyo` | exit 0. 캐시 `cache/xiyo/sherpa/0.7.1/`에 `plugins/sherpa/`의 내용만 28파일, `.git` 없음. 0.7.1, 스킬 5·훅 1(SessionStart) |
| `sherpa@sherpa`와 공존 | 둘 다 0.7.1 enabled, 충돌 메시지 없음. 디버그 로그는 스킬 10개를 읽었다고 하지만 init 이벤트의 이름은 `sherpa:*` 5개뿐. 훅은 `Skipping duplicate hook registration`으로 한 번만 등록. 이름만 쓴 `plugin details sherpa`는 `sherpa@xiyo`로 해석 |
| `claude plugin update sherpa@xiyo` | "already at the latest version (0.7.1)" |
| `ref`·`sha` 고정(임시 probe) | 둘 다 validate 통과·설치. 고정을 풀고 갱신하면 `ref: v0.7.0` 쪽은 0.7.0 → 0.7.1로 올라가고 옛 캐시 디렉터리가 남는다. `sha` 쪽은 "already at the latest"로 끝나고 기록된 커밋도 그대로 |
| 세션 로드(로그인 없는 `claude -p`) | init 이벤트에 캐시 경로와 `sherpa:*` 스킬 5개, SessionStart 훅 exit 0. 결과는 "Not logged in" |
| 병합 후 원격 | `claude plugin marketplace add XIYO/plug-hole` exit 0(결과 remote는 HTTPS) → `install sherpa@xiyo` exit 0, 0.7.1·스킬 5·훅 1 |
| Codex(codex-cli 0.155.1, 빈 `CODEX_HOME`) | `codex plugin add` exit 0, 버전 `0.7.1+codex.20260921101159`, 캐시에 `plugins/sherpa` 트리(스킬 5) |

**`claude plugin update`는 버전 번호만 비교하고 커밋은 보지 않는다.** `sha`로 깐
같은 0.7.1의 옛 커밋이 고정을 풀어도 그대로 남은 것이 그 증거다. 버전 번호가
캐시 무효화의 유일한 신호라는 Consequences의 판정이 `git-subdir`에서도 그대로
성립한다 — **Claude Code에 대해서만 그렇다. Codex는 아래처럼 다르다.**

또 하나가 확정됐다. **Claude Code는 스킬 이름을 플러그인 이름만으로 짓는다** —
`sherpa:planner`이고, 마켓플레이스 이름은 이름에 들어가지 않는다. 근거는 공식
문서 두 곳(`code.claude.com/docs/en/discover-plugins`의 "Plugin skills are
namespaced by the plugin name", `plugins-reference`의 `plugin-dev:agent-creator`
예시)과 claude 2.1.278 번들의 이름 생성부다. 따라서 `sherpa@sherpa`와
`sherpa@xiyo`를 함께 깔면 같은 이름의 스킬 다섯 개와 훅 하나가 겹치고 **구분해
부를 방법이 없다.** 위 공존 행의 `Skipping duplicate hook registration for plugin
"sherpa" from sherpa@sherpa`는 밀려나는 쪽을 주어로 적으므로, 그 실측에서 이긴
것은 `sherpa@xiyo`였다. 무엇이 승부를 가르는지는 아직 추론이다 —
`## 미검증`.

### Codex(codex-cli 0.155.1, macOS)

2026-09-21에 임시 `CODEX_HOME` 셋과 로컬 프로브 마켓플레이스로 Codex 쪽을 갈랐다.
전체 기록은 [실측 기록](../testing/live-evidence.md)에 있다.

| 확인한 것 | 결과 |
| --- | --- |
| `codex plugin update` | **그런 명령이 없다.** 하위 명령은 add·list·marketplace·remove뿐. 갱신 경로는 `codex plugin marketplace upgrade [NAME]`과 `codex plugin add <plugin>@<marketplace>` 재실행 둘 |
| `add` 재실행 | **버전을 비교하지 않고 매번 다시 체크아웃한다.** 캐시 디렉터리 inode가 `1789998717` → `1789998735`로 바뀌고 심어 둔 `PROBE-MARKER.txt`가 사라졌다(파일 수는 28로 동일) |
| 같은 버전 문자열·다른 커밋 | `0.7.0+codex.20260827020000`을 갖는 두 커밋(`0dc0efc4` 훅 없음 / `1b6408c0` SessionStart 훅 있음) 사이를 `sha`만 바꿔 왕복시키면 파일 수가 22 ↔ 28, `hooks/` 없음 ↔ `hooks.json`+`session-start.sh`로 내용이 실제로 갈린다 |
| 옛 캐시 | **지운다.** 마켓플레이스당 캐시가 항상 하나다(Claude Code는 `ref` 고정을 풀고 갱신하면 옛 디렉터리를 남긴다) |
| `ref`·`sha` 고정 | **Codex도 실제로 고정한다.** `ref: v0.7.0` → 0.7.0 설치, `sha: ce628821…`(0.7.1 커밋) → 0.7.1 설치, `ref: main` + `sha`를 함께 주면 `sha`가 이긴다 |
| 없는 `sha` | 조용히 tip으로 떨어지지 않는다. `Error: git checkout deadbeef… failed with status exit status: 128` / `fatal: upload-pack: not our ref`로 **exit 1** |
| 모르는 필드 | `zzzbogus`는 무반응 통과. 조용히 버려지는 것은 모르는 필드뿐이다 |
| `marketplace upgrade` 출력 | 변화가 없어도 `Upgraded marketplace … to the latest configured revision.`이라고 답한다. 진실을 말하는 것은 `--json`의 `upgradedRoots: []`뿐 |
| 세션 로드 | `codex debug prompt-input [PROMPT]`가 로그인 없이 exit 0. 출력의 `<skills_instructions>`에 `sherpa:*` 스킬 다섯 개가 설치 캐시 경로를 skill root로 삼아 들어 있다 |

`sha`가 Codex에서 실제로 먹는다는 것은 plug-hole checker가 `ref`·`sha` 고정을
거부하는 정책의 근거를 **강화**한다. 이유가 "Codex가 무시하니까"가 아니라
"Codex도 실제로 고정하니까"로 바뀐다 — 고정된 카탈로그 항목은 두 도구 모두에서
버전 번호를 올려도 따라오지 않는 설치를 만든다.

사용자의 실제 설정 디렉터리(`~/.claude`, `~/.claude-secondary`, 다른 Claude 프로필 디렉터리
둘, `~/.codex`)와 전역 git 설정은 전후가 같다. 위 Codex
프로브도 임시 `CODEX_HOME` 안에서만 돌았고 `~/.codex/plugins`에 쓰인 파일은
0개다.

## 미검증

- `sherpa@sherpa`와 `sherpa@xiyo`가 함께 설치된 기기에서 **무엇이 승부를 가르는지**
  는 모른다. 이름이 겹친다는 것과 기록된 실측에서 `sherpa@xiyo`가 이겼다는 것은
  확정이다(`## 검증`). **추론**: 승부는 `settings.json`의 `enabledPlugins` 키
  순서로 갈리고 스킬 목록 조립이 first-wins이며, 버전은 승부에 관여하지 않으므로
  낡은 쪽이 이길 수 있다. 난독화된 번들을 읽어 얻은 것이고 재현하지 않았다. 이
  Mac에는 지금 공존 상태가 없다 — 네 프로필 모두 `sherpa@sherpa` 0.7.2뿐이고
  `sherpa@xiyo`는 어디에도 설치돼 있지 않다.
- 세션 로드는 두 도구 모두 **모델이 실제로 부르기 직전까지**다. Claude Code는
  로그인 없는 init 이벤트, Codex는 로그인 없는 `codex debug prompt-input`의
  `<skills_instructions>`까지 확인했다. `codex exec`는 401 Unauthorized에서
  막혔다.
- **Codex가 이 플러그인의 SessionStart 훅을 등록·실행하는지는 모른다.**
  `.codex-plugin/plugin.json`은 `skills`만 선언하고 hooks 키가 없으며, 캐시의
  `hooks/hooks.json`은 스스로를 "Claude Code adapter"라 적고 명령이
  `${CLAUDE_PLUGIN_ROOT}`를 쓴다. codex 바이너리에 `hooks/hooks.json` 문자열은
  있지만 `RUST_LOG=debug`로도 훅 로그가 나오지 않았다. 등록된다고도 안 된다고도
  말할 수 없다.
- Codex 관측은 전부 **codex-cli 0.155.1 / macOS**의 것이다. Windows 11 기기의
  0.154.0이나 Windows에서 같은지는 보지 않았다.
- `marketplace add XIYO/plug-hole` 단축형이 SSH를 먼저 시도했는지는 보지 않았다.
  결과 remote가 HTTPS라는 것만 확인했다.
- Windows에서 남은 것은 하나다 — **`python3`이 없는 실제 Windows
  기기에서 훅의 `python3` → `python` 폴백이 도는 사례가 아직 없다.** 그 Windows
  기기의 `python3`은 `WindowsApps`의 App Execution Alias(Python Manager로 가는 실제
  인터프리터, 실행 exit 0)라 훅이 `python3`을 그대로 썼다. 폴백은 게이트의
  흉내(`renamed`)로만 태웠다. Windows 기기를 다루는 세션의 보고로 닫힌 것:
  `claude plugin marketplace update xiyo` 뒤 목록은 `sherpa@xiyo / Version:
  0.7.1 / Scope: user`였고, `claude plugin update sherpa@xiyo --scope user`가
  "updated from 0.7.1 to 0.7.2 for scope user"를 답했다(캐시에 0.7.1·0.7.2 둘,
  목록은 0.7.2, uninstall 불필요). 0.7.2의 훅은 네 상태(없음·정상·낡음·앞섬)에서
  의도한 분기를 탔고 전부 exit 0, payload에 CR이 없다. Windows Codex는
  `git-subdir`를 해석한다(`codex plugin marketplace upgrade` 뒤
  `codex plugin add sherpa@xiyo` exit 0, 28파일, Claude Code 캐시와 파일 목록
  동일). `require-cli.sh`는 Windows에서 정확히 끝난다. 이 저장소 CI의
  Windows 잡이 `check-windows.ps1`로 훅 검사를 돌리고, plug-hole의 Windows 게이트는 여전히 `plugins/` 디렉터리만 돌아
  sherpa에 대해 아무것도 실행하지 않는다. 기록은 live-evidence 2026-09-21 항목들.
- 플러그인 0.7.3(비 macOS에서 훅 침묵, 가드가 `unsupported`)은 Windows 실기에
  설치된 캐시에서 훅의 빈 출력·exit 0과 가드의 `unsupported`·exit 1까지
  확인됐다(Windows 기기를 다루는 세션의 보고 — live-evidence 2026-09-21 "Installed plugin
  0.7.3"). **로그인된 실제 Claude Code 세션이 비 macOS에서 조용한지**는 그
  세션도 보지 못했다. 위의 스킬 호출 항목과 같은 뿌리이고, 남은 범위는
  `.handoff/`의 인계 문서가 적는다.
- 이 목록과 CI·설치본에 관한 나머지 미해결은 `.handoff/`의 인계 문서가
  지금의 정본이다.
- `XIYO/plug-hole`과 `XIYO/sherpa`는 둘 다 private이다. plug-hole이 공개되면
  sherpa 접근 권한이 없는 계정은 이 항목의 설치가 실패할 것이다 — 추론이다.
  권한 없는 계정으로 돌려 보지 않았다. Windows 기기의
  `git ls-remote https://github.com/XIYO/sherpa.git` exit 0은 권한이 있는 기기의
  결과라 이 항목을 닫지 못한다.

## Related

- [ADR-0005: Unsigned Homebrew Distribution](0005-unsigned-homebrew-distribution.md)
- [아키텍처](../architecture/README.md)
- [릴리스 런북](../testing/local-homebrew-release.md)
