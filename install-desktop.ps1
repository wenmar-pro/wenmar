# Install the Wenmar Pro desktop app on Windows (PowerShell):
#   irm https://app.wenmarpro.com/install-desktop.ps1 | iex
# The quiet way in, not the advertised one: /apps links the installer itself
# (https://app.wenmarpro.com/download/windows) and most people use that. This
# line is for scripted or managed installs, and it is not listed anywhere a
# customer reads. install.ps1 is the terminal client, not this.
# Env:
#   WENMAR_DESKTOP_VERSION   version to install, e.g. 0.5.0 (default: the newest desktop release)
#   WENMAR_DOWNLOAD_URL      release downloads (default: GitHub releases of wenmar-pro/wenmar)
#   WENMAR_DESKTOP_MANIFEST  the desktop updater's manifest, which names the newest version and
#                            its Windows package (default: desktop/latest.json in that repository)
#   WENMAR_DESKTOP_VISIBLE   set to run the installer with its own window instead of silently
# The download must carry a valid Authenticode signature (Get-AuthenticodeSignature 'Valid':
# the same check the release makes before publishing it) or nothing runs. A pass in
# SmartScreen is the one thing this cannot avoid: the Store would, and Windows ships from
# GitHub instead.
# Source of truth: dist/github-releases-repo/ in the private wenmar repository.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$DownloadUrl = if ($env:WENMAR_DOWNLOAD_URL) { $env:WENMAR_DOWNLOAD_URL.TrimEnd('/') } else { 'https://github.com/wenmar-pro/wenmar/releases' }
$ManifestUrl = if ($env:WENMAR_DESKTOP_MANIFEST) { $env:WENMAR_DESKTOP_MANIFEST } else { 'https://raw.githubusercontent.com/wenmar-pro/wenmar/main/desktop/latest.json' }
$Asset = 'wenmar-desktop-x86_64-windows-setup.exe'
$Platform = 'windows-x86_64'

if (-not [Environment]::Is64BitOperatingSystem) { throw 'Wenmar Pro needs 64-bit Windows' }

if ($env:WENMAR_DESKTOP_VERSION) {
    $Version = $env:WENMAR_DESKTOP_VERSION.TrimStart('v')
} else {
    $manifest = Invoke-RestMethod -Uri $ManifestUrl -UseBasicParsing
    $Version = "$($manifest.version)".Trim()
    if (-not $Version) { throw "$ManifestUrl names no version" }
    if (-not $manifest.platforms.$Platform) {
        throw "desktop-v$Version has no Windows package yet ($ManifestUrl): download the installer from https://app.wenmarpro.com/apps"
    }
}
# A mirror (`WENMAR_DOWNLOAD_URL`) is built from the version; otherwise the release's own
# manifest names the asset, so a rename there cannot leave this script behind.
$Url = if ($env:WENMAR_DOWNLOAD_URL -or -not $manifest) {
    "$DownloadUrl/download/desktop-v$Version/$Asset"
} else {
    $manifest.platforms.$Platform.url
}
if (-not $Url) { throw "$ManifestUrl names no URL for $Platform" }
$Label = "Wenmar Pro $Version"

$Tmp = Join-Path ([IO.Path]::GetTempPath()) ("wenmar-desktop-install-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $Tmp | Out-Null
try {
    $installer = Join-Path $Tmp $Asset
    Write-Host "Downloading the Wenmar Pro installer ($Label)"
    Invoke-WebRequest -Uri $Url -OutFile $installer -UseBasicParsing

    $signature = Get-AuthenticodeSignature -FilePath $installer
    if ($signature.Status -ne 'Valid') {
        throw "the installer is not signed by a trusted publisher (Get-AuthenticodeSignature: $($signature.Status)); nothing was installed"
    }
    Write-Host "Verified the signature of $($signature.SignerCertificate.Subject)"

    # /S is NSIS's silent install (per user, %LOCALAPPDATA%\Wenmar Pro\); the app is then
    # started from the Start menu, and from there it keeps itself up to date.
    $arguments = @()
    if (-not $env:WENMAR_DESKTOP_VISIBLE) { $arguments += '/S' }
    $process = Start-Process -FilePath $installer -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "the installer stopped with exit code $($process.ExitCode)" }

    $exe = Join-Path $env:LOCALAPPDATA 'Wenmar Pro\wenmar-desktop.exe'
    if (Test-Path $exe) {
        Write-Host "Installed $Label to $exe"
    } else {
        Write-Host "Installed $Label"
    }
    Write-Host 'Next: open Wenmar Pro from the Start menu, then enter the pairing code the shop owner made for this computer'
} finally {
    Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
}
