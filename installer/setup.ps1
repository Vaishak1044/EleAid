$ErrorActionPreference = "Stop"

$sourceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$installRoot = Join-Path ([Environment]::GetFolderPath("LocalApplicationData")) "EleAid"
$sourceExe = Join-Path $sourceRoot "EleAid_Desktop.exe"

if (-not (Test-Path -LiteralPath $sourceExe)) {
    throw "The package is missing EleAid_Desktop.exe."
}

New-Item -ItemType Directory -Force -Path $installRoot | Out-Null
Get-ChildItem -LiteralPath $sourceRoot -Force |
    Where-Object { $_.Name -notin @("setup.cmd", "setup.ps1") } |
    Copy-Item -Destination $installRoot -Recurse -Force

$installedExe = Join-Path $installRoot "EleAid_Desktop.exe"
$desktop = [Environment]::GetFolderPath("Desktop")
$shortcutPath = Join-Path $desktop "EleAid Acoustic Sound Classifier.lnk"
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $installedExe
$shortcut.WorkingDirectory = $installRoot
$shortcut.Description = "EleAid acoustic sound classifier"
$shortcut.Save()

Write-Host "Installed EleAid to $installRoot"
Write-Host "Created desktop shortcut: $shortcutPath"
Start-Process -FilePath $installedExe -WorkingDirectory $installRoot
