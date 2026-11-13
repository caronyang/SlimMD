# ---------------------------------------------------------------------------
# SlimMD build pipeline:
#   1. regenerate the logo/ico (optional, requires Python + Pillow)
#   2. build the solution
#   3. run renderer tests (optional, requires Node)
#   4. self-contained publish to publish\
#   5. compile the Inno Setup installer into dist\
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File build.ps1
#   powershell -ExecutionPolicy Bypass -File build.ps1 -SkipIcon -SkipTests
# ---------------------------------------------------------------------------
param(
    [switch]$SkipIcon,     # skip logo regeneration
    [switch]$SkipTests,    # skip renderer unit tests
    [switch]$SkipInstaller # publish only, do not build the installer
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

# 1. icon -------------------------------------------------------------------
if (-not $SkipIcon) {
    Step "Generating logo (tools\make_icon.py)"
    $py = Get-Command python -ErrorAction SilentlyContinue
    if ($py) {
        & python tools\make_icon.py
        if ($LASTEXITCODE -ne 0) { Write-Warning "icon generation failed; keeping existing SlimMD.ico" }
    } else {
        Write-Warning "python not found; keeping existing SlimMD.ico"
    }
}

# 2. build ------------------------------------------------------------------
Step "Building SlimMD.sln (Release)"
dotnet build SlimMD.sln -c Release -v q
if ($LASTEXITCODE -ne 0) { throw "build failed" }

# 3. renderer tests ---------------------------------------------------------
if (-not $SkipTests) {
    if (Get-Command node -ErrorAction SilentlyContinue) {
        Step "Renderer tests"
        node tests\render.test.js
        if ($LASTEXITCODE -ne 0) { throw "renderer tests failed" }
    } else {
        Write-Warning "node not found; skipping renderer tests"
    }
}

# 4. publish ----------------------------------------------------------------
Step "Publishing self-contained win-x64 to publish\"
if (Test-Path publish) { Remove-Item publish -Recurse -Force }
dotnet publish src\SlimMD -c Release -r win-x64 --self-contained true -o publish -v q
if ($LASTEXITCODE -ne 0) { throw "publish failed" }

if ($SkipInstaller) { Write-Host "Done (installer skipped)." -ForegroundColor Green; exit 0 }

# 5. installer --------------------------------------------------------------
Step "Compiling installer"
$issc = Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'
if (-not (Test-Path $issc)) { throw "Inno Setup 6 not found: $issc" }
& $issc installer\SlimMD.iss
if ($LASTEXITCODE -ne 0) { throw "installer compile failed" }

$setup = Get-Item dist\SlimMD-*-Setup.exe | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Write-Host "Done: $($setup.FullName) ($([math]::Round($setup.Length/1MB,1)) MB)" -ForegroundColor Green
