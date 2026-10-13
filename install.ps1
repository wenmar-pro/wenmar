# Install the wenmar client on Windows (PowerShell):
#   irm https://raw.githubusercontent.com/wenmar-pro/wenmar/main/install.ps1 | iex
# Env:
#   WENMAR_VERSION       version to install, e.g. 0.2.0 (default: the latest release)
#   WENMAR_INSTALL_DIR   where to put wenmar.exe (default: %LOCALAPPDATA%\Programs\wenmar)
#   WENMAR_DOWNLOAD_URL  release downloads (default: GitHub releases of wenmar-pro/wenmar)
#   WENMAR_STATION       the shop's access code: also sign this computer in to that station
#   WENMAR_VIEW          foxpro or modern: the view of `wenmar tui` (with WENMAR_STATION)
#   WENMAR_NO_SHORTCUT   set to make no desktop shortcut
#   WENMAR_DESKTOP_DIR   where the shortcut goes (default: the desktop folder)
# The download is checked against the release's SHA256SUMS before install.
# Needs Windows 10 1803+ or Windows 11 (tar.exe).
# Source of truth: dist/github-releases-repo/ in the private wenmar repository.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$DownloadUrl = if ($env:WENMAR_DOWNLOAD_URL) { $env:WENMAR_DOWNLOAD_URL.TrimEnd('/') } else { 'https://github.com/wenmar-pro/wenmar/releases' }
$InstallDir = if ($env:WENMAR_INSTALL_DIR) { $env:WENMAR_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA 'Programs\wenmar' }

if (-not [Environment]::Is64BitOperatingSystem) { throw 'wenmar needs 64-bit Windows' }
$Target = 'x86_64-pc-windows-gnu'
$Asset = "wenmar-$Target.tar.gz"

if ($env:WENMAR_VERSION) {
    $Version = $env:WENMAR_VERSION.TrimStart('v')
    $Base = "$DownloadUrl/download/v$Version"
    $Label = "wenmar $Version"
} else {
    $Base = "$DownloadUrl/latest/download"
    $Label = 'the latest wenmar'
}

$Tmp = Join-Path ([IO.Path]::GetTempPath()) ("wenmar-install-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $Tmp | Out-Null
try {
    Write-Host "Downloading $Asset ($Label)"
    $sumsPath = Join-Path $Tmp 'SHA256SUMS'
    $assetPath = Join-Path $Tmp $Asset
    Invoke-WebRequest -Uri "$Base/SHA256SUMS" -OutFile $sumsPath -UseBasicParsing
    Invoke-WebRequest -Uri "$Base/$Asset" -OutFile $assetPath -UseBasicParsing

    $expected = $null
    foreach ($line in Get-Content $sumsPath) {
        $parts = $line.Trim() -split '\s+'
        if ($parts.Count -ge 2 -and $parts[1].TrimStart('*') -eq $Asset) { $expected = $parts[0].ToLower(); break }
    }
    if (-not $expected) { throw "SHA256SUMS has no line for $Asset" }
    $actual = (Get-FileHash -Algorithm SHA256 -Path $assetPath).Hash.ToLower()
    if ($actual -ne $expected) { throw "checksum mismatch for $Asset (expected $expected, got $actual); nothing was installed" }

    tar -xzf $assetPath -C $Tmp wenmar.exe
    if ($LASTEXITCODE -ne 0) { throw 'could not extract wenmar.exe (needs Windows 10 1803 or later for tar.exe)' }

    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    $dest = Join-Path $InstallDir 'wenmar.exe'
    # A running wenmar.exe cannot be overwritten but can be renamed.
    if (Test-Path $dest) { Move-Item -Force $dest "$dest.old" }
    Move-Item -Force (Join-Path $Tmp 'wenmar.exe') $dest
    Remove-Item -Force "$dest.old" -ErrorAction SilentlyContinue

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $userPath) { $userPath = '' }
    if (-not (($userPath -split ';') -contains $InstallDir)) {
        $newPath = if ($userPath) { $userPath.TrimEnd(';') + ';' + $InstallDir } else { $InstallDir }
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        Write-Host "Added $InstallDir to your PATH (open a new terminal)"
    }
    Write-Host "Installed $Label to $dest"
    $next = 'wenmar setup, then wenmar tui'
    if ($env:WENMAR_STATION) {
        $setupArgs = @('setup', '--yes', '--access-code', $env:WENMAR_STATION)
        if ($env:WENMAR_VIEW) { $setupArgs += @('--view', $env:WENMAR_VIEW) }
        & $dest @setupArgs | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "This computer is set up for station $($env:WENMAR_STATION)"
            $next = 'wenmar tui'
        } else {
            Write-Host 'Could not set up the station; run: wenmar setup'
        }
    }
    if (-not $env:WENMAR_NO_SHORTCUT) {
        try {
            $desktop = if ($env:WENMAR_DESKTOP_DIR) { $env:WENMAR_DESKTOP_DIR } else { [Environment]::GetFolderPath('Desktop') }
            $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $desktop 'Wenmar.lnk'))
            $shortcut.TargetPath = $dest
            $shortcut.Arguments = 'tui'
            $shortcut.WorkingDirectory = $env:USERPROFILE
            $shortcut.Description = 'Wenmar'
            $shortcut.Save()
            Write-Host 'Added Wenmar to the desktop'
        } catch {
            Write-Host "Could not add the desktop shortcut: $_"
        }
    }
    Write-Host "Next: $next"
} finally {
    Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
}
