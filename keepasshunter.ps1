param(
  [switch]$Aggressive,       # do full deep recurse; otherwise use a sane depth cap
  [int]$MaxOwners = 50       # only resolve owners for top-N newest results (perf)
)

# === KeePass Hunter: focuses on .kdbx ===
$ErrorActionPreference = 'SilentlyContinue'

$OutDir   = "$env:PUBLIC\loot"
$null     = New-Item -Path $OutDir -ItemType Directory -Force
$KdbxOut  = Join-Path $OutDir 'keepass_kdbx.csv'
$SideOut  = Join-Path $OutDir 'keepass_sidefiles.csv'
$MetaOut  = Join-Path $OutDir 'keepass_meta.txt'

# Roots to search
$Roots = @(
  'C:\Users',
  'C:\ProgramData',
  'C:\inetpub',
  (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Free -ne $null }).Root
) | Where-Object { $_ } | Select-Object -Unique

# Skip list + attributes to skip (reparse points can loop/slow)
$Skip = @('C:\Windows','C:\$Recycle.Bin','C:\System Volume Information')

$depth = if ($Aggressive) { [int]::MaxValue } else { 6 }  # adjust as you like

Write-Host "[*] Searching for KeePass databases (*.kdbx) ..." -ForegroundColor Cyan

# Fast crawl for *.kdbx (skip junctions/reparse; include hidden/system)
$kdbx = foreach ($root in $Roots) {
  if ($Skip -contains $root) { continue }
  try {
    Get-ChildItem -Path $root -Recurse -Depth $depth -Filter '*.kdbx' -File -Force `
      -ErrorAction SilentlyContinue |
      Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } |
      Select-Object FullName, Length, LastWriteTime
  } catch {}
}

# Sort newest first
$kdbx = $kdbx | Sort-Object LastWriteTime -Descending

# Add Owner for top-N newest only (perf)
$withOwner = $kdbx | Select-Object -First $MaxOwners | ForEach-Object {
  $owner = try { (Get-Acl $_.FullName).Owner } catch { $null }
  [pscustomobject]@{
    FullName      = $_.FullName
    Length        = $_.Length
    LastWriteTime = $_.LastWriteTime
    Owner         = $owner
  }
}

$rest = $kdbx | Select-Object -Skip $MaxOwners | ForEach-Object {
  [pscustomobject]@{
    FullName      = $_.FullName
    Length        = $_.Length
    LastWriteTime = $_.LastWriteTime
    Owner         = $null
  }
}

$final = @($withOwner + $rest)

# Write machine-readable CSV and also show a compact table
$final | Export-Csv -NoTypeInformation -Path $KdbxOut -Encoding UTF8
$final | Select-Object FullName,Length,LastWriteTime,Owner | Format-Table -Auto

Write-Host "[+] Results saved to $KdbxOut" -ForegroundColor Green

# ---- quick context sweep ----
"================== KeePass Context ==================" | Tee-Object -FilePath $MetaOut
"Time: $(Get-Date)" | Tee-Object -FilePath $MetaOut -Append
"Aggressive mode: $Aggressive" | Tee-Object -FilePath $MetaOut -Append

# Running processes and command lines (can reveal DB paths)
"--- Running processes containing 'keepass' ---" | Tee-Object -FilePath $MetaOut -Append
try {
  Get-CimInstance Win32_Process |
    Where-Object { $_.Name -match 'keepass' } |
    Select-Object ProcessId, Name, ExecutablePath, CommandLine |
    Out-String | Tee-Object -FilePath $MetaOut -Append
} catch {}

# Installed programs (KeePass / KeePassXC)
"--- Installed programs mentioning KeePass ---" | Tee-Object -FilePath $MetaOut -Append
$uninstPaths = @(
  'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
foreach ($p in $uninstPaths) {
  try {
    Get-ItemProperty $p |
      Where-Object { $_.DisplayName -match 'keepass|keepassxc' } |
      Select-Object DisplayName, DisplayVersion, Publisher, InstallLocation |
      Out-String | Tee-Object -FilePath $MetaOut -Append
  } catch {}
}

# MRU / config locations (KeePass 2.x + KeePassXC)
"--- KeePass MRU & config (if present) ---" | Tee-Object -FilePath $MetaOut -Append
try {
  Get-ItemProperty 'HKCU:\Software\KeePass\KeePass\MostRecentlyUsed\*' |
    Out-String | Tee-Object -FilePath $MetaOut -Append
} catch {}
try {
  $kpCfg = Join-Path $env:APPDATA 'KeePass\KeePass.config.xml'
  if (Test-Path $kpCfg) {
    "KeePass.config.xml: $kpCfg" | Tee-Object -FilePath $MetaOut -Append
  }
} catch {}
try {
  $kpxcIni = Join-Path $env:APPDATA 'KeePassXC\keepassxc.ini'
  if (Test-Path $kpxcIni) {
    "keepassxc.ini: $kpxcIni" | Tee-Object -FilePath $MetaOut -Append
  }
} catch {}

# Common side files (key files, configs, INIs)
Write-Host "[*] Sweeping for side files (.key, KeePass*.config.xml, KeePass.ini, keepassxc.ini) ..." -ForegroundColor Cyan
$side = foreach ($root in $Roots) {
  if ($Skip -contains $root) { continue }
  try {
    Get-ChildItem -Path $root -Recurse -Depth $depth -Force -ErrorAction SilentlyContinue |
      Where-Object {
        -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -and
        (
          $_.Name -match '\.key$'                         -or
          $_.Name -match 'KeePass\.config\.xml'           -or
          $_.Name -match 'KeePass\.ini'                   -or
          $_.Name -match 'keepassxc\.ini'
        )
      } |
      Select-Object FullName, Length, LastWriteTime
  } catch {}
}
$sideSorted = $side | Sort-Object LastWriteTime -Descending
$sideSorted | Export-Csv -NoTypeInformation -Path $SideOut -Encoding UTF8
$sideSorted | Out-String | Tee-Object -FilePath $MetaOut -Append

Write-Host "[+] Sidefile index saved to $SideOut" -ForegroundColor Green
Write-Host "[+] Meta saved to $MetaOut" -ForegroundColor Green
Write-Host "[*] Done." -ForegroundColor Cyan
