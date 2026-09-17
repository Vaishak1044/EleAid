$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Exe = Join-Path $ProjectRoot "EleAid_Desktop.exe"
$ReleaseModels = Join-Path $ProjectRoot "release_models"
$DesktopModels = Join-Path $ReleaseModels "desktop"
$FfmpegDir = Join-Path $ReleaseModels "tools\ffmpeg"
$BirdNetDir = Join-Path $ProjectRoot "desktop\data\birdnet"
$SevenZip = "C:\Program Files\7-Zip\7z.exe"
$Sfx = "C:\Program Files\7-Zip\7z.sfx"
$BuildRoot = Join-Path $ProjectRoot ".build\lightweight_installer"
$Payload = Join-Path $BuildRoot "payload"
$Archive = Join-Path $BuildRoot "payload.7z"
$Config = Join-Path $BuildRoot "config.txt"
$Output = Join-Path $ProjectRoot "EleAid_Lightweight_Installer.exe"

foreach ($path in @($Exe, $DesktopModels, $BirdNetDir, $FfmpegDir, $SevenZip, $Sfx)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required packaging input is missing: $path"
    }
}
foreach ($file in @("ffmpeg.exe", "ffprobe.exe")) {
    if (-not (Test-Path -LiteralPath (Join-Path $FfmpegDir $file))) {
        throw "Missing FFmpeg binary: $(Join-Path $FfmpegDir $file)"
    }
}
$BirdNetModel = Join-Path $BirdNetDir "acoustic-models\v2.4\tf\model-fp32.tflite"
if (-not (Test-Path -LiteralPath $BirdNetModel)) {
    throw "Bundled BirdNET v2.4 TensorFlow model is missing: $BirdNetModel"
}

if (Test-Path -LiteralPath $BuildRoot) {
    $resolvedBuild = (Resolve-Path -LiteralPath $BuildRoot).Path
    $resolvedProject = (Resolve-Path -LiteralPath $ProjectRoot).Path
    if (-not $resolvedBuild.StartsWith($resolvedProject, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove a staging path outside the project: $resolvedBuild"
    }
    Remove-Item -LiteralPath $BuildRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $Payload | Out-Null

Copy-Item -LiteralPath $Exe -Destination (Join-Path $Payload "EleAid_Desktop.exe")
Copy-Item -LiteralPath $DesktopModels -Destination (Join-Path $Payload "desktop\data\models") -Recurse
Copy-Item -LiteralPath $BirdNetDir -Destination (Join-Path $Payload "desktop\data\birdnet") -Recurse
New-Item -ItemType Directory -Force -Path (Join-Path $Payload "desktop\data\dataset") | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "default_labels.json") -Destination (Join-Path $Payload "desktop\data\labels.json")
if (Test-Path -LiteralPath (Join-Path $ProjectRoot "desktop\sample_data")) {
    Copy-Item -LiteralPath (Join-Path $ProjectRoot "desktop\sample_data") -Destination (Join-Path $Payload "desktop\sample_data") -Recurse
}
Copy-Item -LiteralPath $FfmpegDir -Destination (Join-Path $Payload "tools\ffmpeg") -Recurse
Copy-Item -LiteralPath (Join-Path $ProjectRoot "README.md") -Destination $Payload
Copy-Item -LiteralPath (Join-Path $ProjectRoot "LICENSE") -Destination $Payload
Copy-Item -LiteralPath (Join-Path $ProjectRoot "docs") -Destination $Payload -Recurse
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "THIRD_PARTY_NOTICES.txt") -Destination $Payload
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "setup.ps1") -Destination $Payload
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "setup.cmd") -Destination $Payload

Push-Location $Payload
try {
    & $SevenZip a -t7z -mx=5 -mmt=on $Archive .\* | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "7-Zip archive creation failed with exit code $LASTEXITCODE" }
}
finally { Pop-Location }

# The SFX config terminator must be the exact marker expected by 7-Zip.
Set-Content -LiteralPath $Config -Encoding UTF8 -Value @(
    ';!@Install@!UTF-8!'
    'Title="EleAid Lightweight Installer"'
    'RunProgram="setup.cmd"'
    ';!@InstallEnd@!'
)

$sfxBytes = [IO.File]::ReadAllBytes($Sfx)
$configBytes = [Text.Encoding]::UTF8.GetBytes((Get-Content -Raw -LiteralPath $Config))
$archiveBytes = [IO.File]::ReadAllBytes($Archive)
$outStream = [IO.File]::Open($Output, [IO.FileMode]::Create, [IO.FileAccess]::Write)
try {
    $outStream.Write($sfxBytes, 0, $sfxBytes.Length)
    $outStream.Write($configBytes, 0, $configBytes.Length)
    $outStream.Write($archiveBytes, 0, $archiveBytes.Length)
}
finally { $outStream.Dispose() }

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Output).Hash
Write-Host "Created: $Output"
Write-Host "SHA-256: $hash"
