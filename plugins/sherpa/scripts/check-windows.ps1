# 플러그인 검사 진입점(Windows). CI 의 Windows 잡이 호출한다.
#
# Sherpa CLI 는 EventKit·Mail.app·iMessage 를 직접 다루는 macOS 전용 실행 파일이고,
# 이 플러그인의 스킬은 전부 그 CLI 를 호출한다. Windows 에서 돌릴 CLI 는 없다.
# 그러나 SessionStart 훅은 돈다 — hooks.json 이 훅을 무조건 등록하므로 Windows 의
# Claude Code 가 세션마다 Git Bash 로 session-start.sh 를 실행한다. "Windows 에서 실행할
# 것이 없다"고 보고 매니페스트만 확인하던 동안, 훅이 Windows 에서 모든 상태를 "확인에
# 실패"로 읽는 결함이 게이트 밖에 있었다. 그래서 매니페스트 정합성에 더해 훅 검사를
# 여기서도 돌린다. CLI 명령 실재 같은 나머지는 건너뛴다.
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ScriptRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
$PluginRoot = [System.IO.Path]::GetFullPath((Join-Path $ScriptRoot ".."))

Write-Error -Message "[check:sherpa:start] platform=windows" -ErrorAction Continue

$ClaudeManifest = Join-Path $PluginRoot ".claude-plugin/plugin.json"
$CodexManifest = Join-Path $PluginRoot ".codex-plugin/plugin.json"
$Contract = Join-Path $PluginRoot "cli-contract.json"

foreach ($path in @($ClaudeManifest, $CodexManifest, $Contract)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Write-Error -Message "[check:sherpa:failure] reason=missing_file path=$path"
        exit 1
    }
}

try {
    $claude = Get-Content -LiteralPath $ClaudeManifest -Raw | ConvertFrom-Json
    $codex = Get-Content -LiteralPath $CodexManifest -Raw | ConvertFrom-Json
    $contract = Get-Content -LiteralPath $Contract -Raw | ConvertFrom-Json
} catch {
    Write-Error -Message "[check:sherpa:failure] reason=invalid_json detail=$($_.Exception.Message)"
    exit 1
}

if ($claude.name -ne "sherpa" -or $codex.name -ne "sherpa") {
    Write-Error -Message "[check:sherpa:failure] reason=name_mismatch"
    exit 1
}

$claudeBase = ($claude.version -split '\+')[0]
$codexBase = ($codex.version -split '\+')[0]
if ($claudeBase -ne $codexBase) {
    Write-Error -Message "[check:sherpa:failure] reason=version_mismatch claude=$claudeBase codex=$codexBase"
    exit 1
}

if ($contract.minimumVersion -notmatch '^\d+\.\d+\.\d+$') {
    Write-Error -Message "[check:sherpa:failure] reason=cli_contract_invalid minimum=$($contract.minimumVersion)"
    exit 1
}

# 훅 검사. python 을 이름 하나로 단정하지 않고 실제로 도는 것을 고른다.
$python = $null
foreach ($name in @("python3", "python")) {
    $found = Get-Command -Name $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $found) { continue }
    & $found.Source -c "import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)" 2>$null
    if ($LASTEXITCODE -eq 0) {
        $python = $found.Source
        break
    }
}
if (-not $python) {
    Write-Error -Message "[check:sherpa:failure] reason=python_missing"
    exit 1
}

& $python (Join-Path $ScriptRoot "checks/verify_session_start.py") $PluginRoot
if ($LASTEXITCODE -ne 0) {
    Write-Error -Message "[check:sherpa:failure] reason=session_start_hook_invalid"
    exit 1
}
Write-Error -Message "[check:sherpa:hook] verified with $python" -ErrorAction Continue

Write-Error -Message "[check:sherpa:success] hook=verified cli_checks=skipped reason=macos_only version=$claudeBase minimum_cli=$($contract.minimumVersion)" -ErrorAction Continue
exit 0
