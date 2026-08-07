<#
.SYNOPSIS
    Builds the Kyber module and runs the launcher locally with one command.
.DESCRIPTION
    Orchestrates the local dev loop for the Launcher + Module:
      1. (optional) melos bootstrap
      2. proto + FFI code generation
      3. Bazel build + deploy of the Module DLL
      4. flutter run in the Launcher

    No local API is needed for Launcher/Module development - the launcher
    talks to the module directly over localhost gRPC and uses the public API
    (prod/stage) for server browser/moderation as normal.

.PARAMETER Bootstrap
    Run `melos bootstrap` first (required on first checkout / after new deps).
.PARAMETER SkipGenerate
    Skip proto + FFI code generation.
.PARAMETER SkipModule
    Skip the Bazel module build + deploy (fast iteration on Dart-only changes).
.PARAMETER Force
    Clean the Bazel cache before building the module (full rebuild).
.EXAMPLE
    .\dev.ps1
    Full build + run (first time).
.EXAMPLE
    .\dev.ps1 -SkipModule -SkipGenerate
    Fast iteration on Dart-only changes.
#>
param(
    [switch]$Bootstrap,
    [switch]$SkipGenerate,
    [switch]$SkipModule,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ModuleDll = "$env:ProgramData\Kyber\Module\Kyber.dll"

Write-Host "==> Kyber dev: build module + run launcher" -ForegroundColor Cyan

# --- Preflight: required tools ---
function Assert-Command([string]$name) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        throw "Required tool '$name' was not found on PATH. See BUILDING.md for prerequisites."
    }
}
Assert-Command dart
Assert-Command flutter
Assert-Command protoc
# melos is a Dart global package; Get-Command also resolves the .bat shim.
if (-not (Get-Command melos -ErrorAction SilentlyContinue)) {
    throw "melos is not installed. Run: dart pub global activate melos"
}

# --- Bazel: resolve, or provision bazelisk as bazel.exe ---
# build.bat invokes `bazel`; the Module pins its version via .bazelversion
# (8.0.0), which bazelisk uses to fetch the right Bazel automatically.
$bazelDir = Join-Path $env:LOCALAPPDATA "Kyber\bazel"
$bazelExe = Join-Path $bazelDir "bazel.exe"
if (-not (Get-Command bazel -ErrorAction SilentlyContinue)) {
    if (-not (Test-Path $bazelExe)) {
        Write-Host "==> bazel not found on PATH; installing bazelisk as bazel.exe" -ForegroundColor Yellow
        New-Item -ItemType Directory -Force -Path $bazelDir | Out-Null
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $bazeliskUrl = "https://github.com/bazelbuild/bazelisk/releases/download/v1.25.0/bazelisk-windows-amd64.exe"
        Invoke-WebRequest -Uri $bazeliskUrl -OutFile $bazelExe
        if ($LASTEXITCODE -ne 0) { throw "Failed to download bazelisk from $bazeliskUrl" }
    }
    # Make `bazel` resolvable for this process and the child build.bat.
    $env:PATH = "$bazelDir;$env:PATH"
    Write-Host "==> Using bazel from $bazelExe" -ForegroundColor Cyan
}

# --- MSVC toolchain: prefer the newest compiler (C++23) ---
# Bazel's auto-detection uses vswhere, which only sees *registered* VS installs
# and may pick an older MSVC (e.g. 14.29) that lacks the C++23 <expected> header
# required by ThirdParty/safetyhook. Scan the known VS install roots for the
# newest MSVC version and pin Bazel to it.
if (-not $env:BAZEL_VC) {
    $vcCandidates = @()
    foreach ($vsRoot in @("${env:ProgramFiles(x86)}\Microsoft Visual Studio", "$env:ProgramFiles\Microsoft Visual Studio")) {
        if (Test-Path $vsRoot) {
            foreach ($year in (Get-ChildItem -Directory $vsRoot -ErrorAction SilentlyContinue)) {
                foreach ($edition in (Get-ChildItem -Directory $year.FullName -ErrorAction SilentlyContinue)) {
                    $msvcRoot = Join-Path $edition.FullName "VC\Tools\MSVC"
                    if (Test-Path $msvcRoot) {
                        foreach ($version in (Get-ChildItem -Directory $msvcRoot -ErrorAction SilentlyContinue)) {
                            $vcCandidates += [PSCustomObject]@{
                                Version    = [version]$version.Name
                                VersionStr = $version.Name
                                VcPath     = Join-Path $edition.FullName "VC"
                            }
                        }
                    }
                }
            }
        }
    }
    if ($vcCandidates.Count -gt 0) {
        $newest = $vcCandidates | Sort-Object Version -Descending | Select-Object -First 1
        $env:BAZEL_VC = $newest.VcPath
        $env:BAZEL_VC_FULL_VERSION = $newest.VersionStr
        Write-Host "==> Using MSVC $($newest.VersionStr) at $($newest.VcPath)" -ForegroundColor Cyan
    }
}

# 1. Bootstrap (first-time / after new dependencies)
if ($Bootstrap -or -not (Test-Path "$RepoRoot\Launcher\.dart_tool")) {
    Write-Host "==> melos bootstrap" -ForegroundColor Yellow
    Push-Location $RepoRoot
    melos bootstrap
    if ($LASTEXITCODE -ne 0) { throw "melos bootstrap failed" }
    Pop-Location
}

# 2. Generate proto + FFI bindings (needed after proto changes)
if (-not $SkipGenerate) {
    Write-Host "==> Generating proto bindings" -ForegroundColor Yellow
    Push-Location $RepoRoot
    melos run generate_proto
    if ($LASTEXITCODE -ne 0) { throw "proto generation failed" }
    Pop-Location

    Write-Host "==> Generating FFI bindings" -ForegroundColor Yellow
    Push-Location "$RepoRoot\Launcher"
    dart run tool/ffigen.dart
    if ($LASTEXITCODE -ne 0) { throw "ffigen failed" }
    Pop-Location
}

# 3. Build + deploy the Module DLL (Windows/MSVC only)
if (-not $SkipModule) {
    # Ensure the deploy directory exists for build.bat's xcopy.
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ModuleDll) | Out-Null

    Write-Host "==> Building Kyber module (Bazel)" -ForegroundColor Yellow
    Push-Location "$RepoRoot\Module"
    if ($Force) {
        bazel --output_user_root="C:\bz" clean
    }
    & .\build.bat
    if ($LASTEXITCODE -ne 0) { throw "Module build failed" }
    Pop-Location
} elseif (-not (Test-Path $ModuleDll)) {
    Write-Warning "Skipped module build but no DLL found at $ModuleDll - the game will fail to inject Kyber. Run without -SkipModule once first."
}

# 4. Run the launcher (foreground; exit flutter to stop)
Write-Host "==> Launching launcher" -ForegroundColor Green
Push-Location "$RepoRoot\Launcher"
flutter run
Pop-Location
