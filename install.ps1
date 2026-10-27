# Install the wenmar client on Windows (PowerShell):
#   irm https://raw.githubusercontent.com/wenmar-pro/wenmar/main/install.ps1 | iex
# Env:
#   WENMAR_VERSION       version to install, e.g. 0.2.0 (default: the latest release)
#   WENMAR_INSTALL_DIR   where to put wenmar.exe (default: %LOCALAPPDATA%\Programs\wenmar)
#   WENMAR_DOWNLOAD_URL  release downloads (default: GitHub releases of wenmar-pro/wenmar)
#   WENMAR_PAIR          a pairing code from the shop's owner: also pair this computer with the shop
#   WENMAR_VIEW          foxpro or modern: the view of `wenmar tui` (with WENMAR_PAIR)
#   WENMAR_NO_SHORTCUT   set to make no desktop shortcut
#   WENMAR_DESKTOP_DIR   where the shortcut goes (default: the desktop folder)
#   WENMAR_NO_SUMATRA    set to skip installing SumatraPDF (wenmar prints through it without a dialog)
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
    if ($env:WENMAR_PAIR) {
        $setupArgs = @('setup', '--yes', '--pairing-code', $env:WENMAR_PAIR)
        if ($env:WENMAR_VIEW) { $setupArgs += @('--view', $env:WENMAR_VIEW) }
        # What setup prints is for a person who ran it by hand (its own next
        # steps): it is shown only when setup fails. 'Continue' because Windows
        # PowerShell turns a redirected stderr line into an error.
        $oldPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try { $setupOut = & $dest @setupArgs 2>&1 } finally { $ErrorActionPreference = $oldPreference }
        if ($LASTEXITCODE -eq 0) {
            Write-Host 'This computer is paired with the shop'
            $next = 'wenmar tui'
        } else {
            $setupOut | ForEach-Object { Write-Host "$_" }
            Write-Host 'Could not pair this computer; run: wenmar setup'
        }
    }
    # Printing without a dialog (printed-forms spec F11): wenmar's "auto" print mode hands the
    # PDF to SumatraPDF. winget --scope user puts it in %LOCALAPPDATA%\SumatraPDF, the first
    # place wenmar looks.
    if (-not $env:WENMAR_NO_SUMATRA) {
        $sumatraDirs = @($env:LOCALAPPDATA, $env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }
        $sumatra = $sumatraDirs | ForEach-Object { Join-Path $_ 'SumatraPDF\SumatraPDF.exe' } | Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($sumatra) {
            Write-Host 'SumatraPDF found: wenmar prints without a dialog'
        } elseif (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Host 'Installing SumatraPDF so wenmar can print without a dialog'
            $oldPreference = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try {
                winget install --id SumatraPDF.SumatraPDF --exact --silent --scope user --accept-package-agreements --accept-source-agreements | Out-Host
            } finally { $ErrorActionPreference = $oldPreference }
            if ($LASTEXITCODE -ne 0) {
                Write-Host 'Could not install SumatraPDF: wenmar opens each PDF in the viewer instead (https://www.sumatrapdfreader.org)'
            }
        } else {
            Write-Host 'Install SumatraPDF (https://www.sumatrapdfreader.org) to print without a dialog: until then wenmar opens each PDF in the viewer'
        }
    }
    if (-not $env:WENMAR_NO_SHORTCUT) {
        try {
            $desktop = if ($env:WENMAR_DESKTOP_DIR) { $env:WENMAR_DESKTOP_DIR } else { [Environment]::GetFolderPath('Desktop') }
            # The shortcut of an earlier install, named before "Wenmar Pro".
            Remove-Item -Force (Join-Path $desktop 'Wenmar.lnk') -ErrorAction SilentlyContinue
            $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $desktop 'Wenmar Pro.lnk'))
            # conhost.exe, not Windows Terminal: only the console host lets
            # `wenmar tui --font-size` make the text large.
            $shortcut.TargetPath = Join-Path $env:SystemRoot 'System32\conhost.exe'
            $shortcut.Arguments = "`"$dest`" tui --font-size 20"
            $shortcut.IconLocation = "$dest,0"
            $shortcut.WorkingDirectory = $env:USERPROFILE
            $shortcut.Description = 'Wenmar Pro'
            $shortcut.Save()
            Write-Host 'Added Wenmar Pro to the desktop'
        } catch {
            Write-Host "Could not add the desktop shortcut: $_"
        }
    }
    Write-Host "Next: $next"
} finally {
    Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
}
