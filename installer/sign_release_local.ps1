<#
.SYNOPSIS
  Signs a published Cybergram release on your own Windows PC with a Certum
  code-signing certificate (SimplySign or a card reader), then uploads the
  signed files back to the GitHub release.

.DESCRIPTION
  Certum keys cannot be exported as a .pfx, so CI cannot sign them. Run this
  once after each release:

    1. Downloads CybergramSetup-<ver>.exe (and, with -Portable, the two Windows
       .zip packages) plus SHA256SUMS.txt from the release.
    2. Signs every .exe with signtool: SHA-256, RFC 3161 timestamp from Certum.
       SimplySign Desktop must be running and logged in, so the certificate
       shows in your Windows certificate store.
    3. Verifies each signature (signtool verify /pa).
    4. Rewrites the changed lines of SHA256SUMS.txt.
    5. Uploads the signed files and SHA256SUMS.txt with --clobber.

  Signing the installer is what matters for SmartScreen. Files the installer
  extracts get no "downloaded from the internet" mark, so Windows does not
  re-check them. The launcher's update feed is signed separately (Ed25519) and
  is not touched here.

.PARAMETER Version
  Release tag, e.g. v0.14.0.

.PARAMETER Thumbprint
  SHA-1 thumbprint of the code-signing certificate. Optional when exactly one
  code-signing certificate is in CurrentUser\My.

.PARAMETER Portable
  Also sign Cybergram.exe and CybergramLauncher.exe inside the portable
  Windows .zip packages, then repack the zips.

.PARAMETER DryRun
  Download and sign in the work folder, but do not upload.

.EXAMPLE
  .\installer\sign_release_local.ps1 -Version v0.14.0
  .\installer\sign_release_local.ps1 -Version v0.14.0 -Portable -DryRun

.NOTES
  Needs:
  - GitHub CLI `gh`, logged in with `gh auth login`, with write access to the
    repository.
  - signtool.exe from the Windows SDK ("Windows SDK Signing Tools for Desktop
    Apps"). It is found automatically.
  Nothing is stored. The work folder is deleted at the end unless -DryRun is
  set.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][ValidatePattern('^v\d+\.\d+\.\d+$')][string]$Version,
  [string]$Thumbprint = "",
  [string]$Repo = "LetsManu/Cybergram",
  [string]$TimestampUrl = "http://time.certum.pl",
  [switch]$Portable,
  [switch]$DryRun
)
$ErrorActionPreference = "Stop"

function Find-SignTool {
  $cmd = Get-Command signtool.exe -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $kits = Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\bin"
  $hit = Get-ChildItem $kits -Recurse -Filter signtool.exe -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\x64\\' } | Sort-Object FullName -Descending | Select-Object -First 1
  if ($hit) { return $hit.FullName }
  throw "signtool.exe not found. Install the Windows SDK signing tools (Visual Studio Installer or winget install Microsoft.WindowsSDK)."
}

function Find-Thumbprint {
  $certs = @(Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Where-Object { $_.NotAfter -gt (Get-Date) })
  if ($certs.Count -eq 1) { return $certs[0].Thumbprint }
  if ($certs.Count -eq 0) {
    throw "No valid code-signing certificate in CurrentUser\My. Start SimplySign Desktop and log in (or insert the card), then try again."
  }
  $list = ($certs | ForEach-Object { "  $($_.Thumbprint)  $($_.Subject)  (until $($_.NotAfter.ToString('yyyy-MM-dd')))" }) -join "`n"
  throw "Several code-signing certificates found; pass -Thumbprint:`n$list"
}

function Sign-File([string]$path) {
  Write-Host "  signing $(Split-Path $path -Leaf)"
  & $script:signtool sign /sha1 $script:thumb /fd SHA256 /tr $TimestampUrl /td SHA256 /d "Cybergram" $path
  if ($LASTEXITCODE -ne 0) { throw "signtool sign failed for $path" }
  & $script:signtool verify /pa /q $path
  if ($LASTEXITCODE -ne 0) { throw "signature check failed for $path" }
}

function Update-Sum([string]$sums, [string]$file) {
  $name = Split-Path $file -Leaf
  $hash = (Get-FileHash $file -Algorithm SHA256).Hash.ToLower()
  $lines = Get-Content $sums | ForEach-Object {
    if ($_ -match "^[0-9a-f]{64}\s+\*?$([regex]::Escape($name))$") { "$hash  $name" } else { $_ }
  }
  # LF line endings and no BOM, like the CI-generated file (sha256sum -c reads it).
  [IO.File]::WriteAllText($sums, (($lines -join "`n") + "`n"))
}

# --- preflight -------------------------------------------------------------
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw "GitHub CLI 'gh' not found (winget install GitHub.cli, then gh auth login)." }
gh auth status 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { throw "gh is not logged in: run 'gh auth login' first." }
$script:signtool = Find-SignTool
$script:thumb = if ($Thumbprint) { $Thumbprint } else { Find-Thumbprint }
Write-Host "signtool:    $script:signtool"
Write-Host "certificate: $script:thumb"
Write-Host "release:     $Repo $Version$(if ($DryRun) { '  (dry run, nothing is uploaded)' })"

$ver = $Version.TrimStart('v')
$work = Join-Path $env:TEMP "cybergram-sign-$ver"
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item -ItemType Directory $work | Out-Null

try {
  # --- download --------------------------------------------------------------
  $patterns = @("CybergramSetup-$ver.exe", "SHA256SUMS.txt")
  if ($Portable) { $patterns += @("Cybergram-$Version-windows-x86_64.zip", "CybergramLauncher-windows.zip") }
  $ghArgs = @("release", "download", $Version, "--repo", $Repo, "--dir", $work)
  foreach ($p in $patterns) { $ghArgs += @("--pattern", $p) }
  & gh @ghArgs
  if ($LASTEXITCODE -ne 0) { throw "download failed (is $Version published?)" }
  $sums = Join-Path $work "SHA256SUMS.txt"
  $changed = @()

  # --- installer ---------------------------------------------------------------
  $setup = Join-Path $work "CybergramSetup-$ver.exe"
  Sign-File $setup
  Update-Sum $sums $setup
  $changed += $setup

  # --- portable zips (optional) --------------------------------------------
  if ($Portable) {
    foreach ($zipName in @("Cybergram-$Version-windows-x86_64.zip", "CybergramLauncher-windows.zip")) {
      $zip = Join-Path $work $zipName
      $dir = Join-Path $work ($zipName -replace '\.zip$', '')
      Expand-Archive $zip -DestinationPath $dir -Force
      Get-ChildItem $dir -Recurse -Filter *.exe | ForEach-Object { Sign-File $_.FullName }
      Remove-Item $zip
      Compress-Archive -Path (Join-Path $dir '*') -DestinationPath $zip -CompressionLevel Optimal
      Update-Sum $sums $zip
      $changed += $zip
    }
  }

  # --- upload --------------------------------------------------------------
  if ($DryRun) {
    Write-Host "`nDry run: signed files are in $work (not uploaded)."
    return
  }
  & gh release upload $Version @changed $sums --repo $Repo --clobber
  if ($LASTEXITCODE -ne 0) { throw "upload failed" }
  Write-Host "`nDone: $($changed.Count) file(s) signed and uploaded, SHA256SUMS.txt updated."
}
finally {
  if (-not $DryRun -and (Test-Path $work)) { Remove-Item $work -Recurse -Force }
}
