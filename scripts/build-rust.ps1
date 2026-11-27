param(
  [string]$ToolchainHome = $env:HSDA_RUST_HOME,
  [string[]]$Targets = @('aarch64-unknown-linux-ohos', 'x86_64-unknown-linux-ohos')
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ToolchainHome)) {
  $cargoExecutable = (Get-Command cargo -ErrorAction Stop).Source
  $ToolchainHome = Split-Path -Parent (Split-Path -Parent $cargoExecutable)
}
$cargoExecutable = Join-Path $ToolchainHome 'bin/cargo.exe'
$compilerExecutable = Join-Path $ToolchainHome 'bin/rustc.exe'
$previousCompiler = $env:RUSTC
$previousFlags = $env:RUSTFLAGS
try {
  $env:RUSTC = $compilerExecutable
  $env:RUSTFLAGS = '-C relocation-model=pic'
  foreach ($target in $Targets) {
    & $cargoExecutable build --offline --release --target $target `
      --manifest-path (Join-Path $projectRoot 'native/rust/Cargo.toml') `
      --target-dir (Join-Path $projectRoot 'entry/build/rust-native') -p hsda_core
    if ($LASTEXITCODE -ne 0) { throw "Rust 编译失败：$target" }
  }
} finally {
  $env:RUSTC = $previousCompiler
  $env:RUSTFLAGS = $previousFlags
}
