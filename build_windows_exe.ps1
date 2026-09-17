$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Python = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
$EntryPoint = Join-Path $ProjectRoot "desktop\animal_sound_detector.py"
$BuildRoot = Join-Path $ProjectRoot ".build\pyinstaller"
$BirdNetBuildCache = Join-Path $ProjectRoot ".build\birdnet_cache"

if (-not (Test-Path -LiteralPath $Python)) {
    throw "Project virtual environment not found: $Python"
}

New-Item -ItemType Directory -Force -Path $BirdNetBuildCache | Out-Null
$env:BIRDNET_APP_DATA = $BirdNetBuildCache

Push-Location $ProjectRoot
try {
    & $Python -m PyInstaller `
        --noconfirm `
        --clean `
        --onefile `
        --windowed `
        --name "EleAid_Desktop" `
        --hidden-import "tf_keras.src.engine.base_layer_v1" `
        --hidden-import "scipy.io.matlab.mio_utils" `
        --hidden-import "scipy.io.matlab._mio_utils" `
        --collect-submodules "scipy.io.matlab" `
        --collect-all "birdnet" `
        --distpath $ProjectRoot `
        --workpath $BuildRoot `
        --specpath $BuildRoot `
        $EntryPoint

    if ($LASTEXITCODE -ne 0) {
        throw "PyInstaller failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

$RootExe = Join-Path $ProjectRoot "EleAid_Desktop.exe"
if (-not (Test-Path -LiteralPath $RootExe)) {
    throw "PyInstaller completed but did not create: $RootExe"
}

Write-Host "Created: $RootExe"
