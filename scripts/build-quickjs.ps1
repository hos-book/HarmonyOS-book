param(
  [string]$DevEcoRoot = $env:DEVECO_HOME,
  [switch]$RequireReleaseSdk
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($DevEcoRoot)) {
  throw 'DEVECO_HOME 未配置，请通过 -DevEcoRoot 指定 DevEco Studio 安装目录'
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$quickJsRoot = Join-Path $projectRoot 'third_party\quickjs'
$nodeExecutable = Join-Path $DevEcoRoot 'tools\node\node.exe'
$ohpmCli = Join-Path $DevEcoRoot 'tools\ohpm\bin\pm-cli.js'
$hvigorCli = Join-Path $DevEcoRoot 'tools\hvigor\bin\hvigorw.js'
$sdkRoot = Join-Path $DevEcoRoot 'sdk'
$builtHar = Join-Path $quickJsRoot 'quickjs\build\default\outputs\default\quickjs.har'
$targetHar = Join-Path $projectRoot 'entry\libs\quickjs.har'

foreach ($requiredPath in @($nodeExecutable, $ohpmCli, $hvigorCli)) {
  if (-not (Test-Path -LiteralPath $requiredPath)) {
    throw "缺少构建工具：$requiredPath"
  }
}

if ($RequireReleaseSdk) {
  $sdkMetadata = Get-Content -LiteralPath (Join-Path $sdkRoot 'default\sdk-pkg.json') -Raw | ConvertFrom-Json
  if ($sdkMetadata.data.releaseType -ne 'Release') {
    throw '发布依赖必须使用 Release SDK，不能使用 Beta 或 Canary'
  }
}

$previousSdkRoot = $env:DEVECO_SDK_HOME
Push-Location $quickJsRoot
try {
  $env:DEVECO_SDK_HOME = $sdkRoot
  & $nodeExecutable $ohpmCli install
  if ($LASTEXITCODE -ne 0) { throw "ohpm install 失败：$LASTEXITCODE" }

  & $nodeExecutable --max-old-space-size=8192 --expose-gc $hvigorCli clean
  if ($LASTEXITCODE -ne 0) { throw "QuickJS clean 失败：$LASTEXITCODE" }

  & $nodeExecutable --max-old-space-size=8192 --expose-gc $hvigorCli `
    assembleHar --mode module -p product=default -p module=quickjs@default -p buildMode=release --no-daemon
  if ($LASTEXITCODE -ne 0) { throw "QuickJS HAR 构建失败：$LASTEXITCODE" }
} finally {
  Pop-Location
  $env:DEVECO_SDK_HOME = $previousSdkRoot
}

if (-not (Test-Path -LiteralPath $builtHar)) {
  throw "未找到 HAR 产物：$builtHar"
}

New-Item -ItemType Directory -Force (Split-Path -Parent $targetHar) | Out-Null
Copy-Item -LiteralPath $builtHar -Destination $targetHar -Force
Write-Host "QuickJS HAR: $targetHar"
