#Requires -Version 5.1
<#
    Assemble Install-Bentley-GUI.ps1 + les modules src\ en un script unique,
    puis le compile en UN SEUL executable (ps2exe) avec l'icone app.ico.
    Lancement : powershell -ExecutionPolicy Bypass -File .\Build-Exe.ps1
#>
$ErrorActionPreference = 'Stop'
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

$dir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$src    = Join-Path $dir 'Install-Bentley-GUI.ps1'
$out    = Join-Path $dir 'Install-Bentley-GUI.exe'
$ico    = Join-Path $dir 'app.ico'
$bundle = Join-Path $env:TEMP 'Install-Bentley-GUI.bundle.ps1'
$modDir = Join-Path $env:TEMP 'ps2exe_mod'

if (-not (Test-Path -LiteralPath $src)) { throw "Script principal introuvable : $src" }
if (-not (Test-Path -LiteralPath $ico)) { throw "Icone introuvable : $ico" }

# --- 1. ASSEMBLAGE -------------------------------------------------
# Chaque ligne '. (Join-Path $script:AppRoot 'src\X.ps1')' est remplacee par le
# contenu du module : le resultat est un script autonome, compile en un seul exe.
$pattern = "(?m)^\s*\.\s+\(Join-Path\s+\`$script:AppRoot\s+'([^']+)'\)"
$sb = New-Object System.Text.StringBuilder
$assembled = 0
$missing = @()

foreach ($line in [System.IO.File]::ReadAllLines($src)) {
    if ($line -match $pattern) {
        $rel = $Matches[1]
        $modulePath = Join-Path $dir $rel
        if (-not (Test-Path -LiteralPath $modulePath)) { $missing += $rel; continue }
        [void]$sb.AppendLine()
        [void]$sb.AppendLine("# ==================================================================")
        [void]$sb.AppendLine("# MODULE : $rel")
        [void]$sb.AppendLine("# ==================================================================")
        [void]$sb.AppendLine([System.IO.File]::ReadAllText($modulePath))
        $assembled++
    } else {
        [void]$sb.AppendLine($line)
    }
}

if ($missing.Count) { throw ("Module(s) introuvable(s) : " + ($missing -join ', ')) }
if ($assembled -eq 0) { throw "Aucun module assemble : verifiez les chargements de $src." }

$assembledText = $sb.ToString()
if ($assembledText -match $pattern) { throw "Assemblage incomplet : des chargements de modules subsistent." }
Write-Host "Assemblage : $assembled modules integres au script." -ForegroundColor Cyan
[System.IO.File]::WriteAllText($bundle, $assembledText, (New-Object System.Text.UTF8Encoding($true)))

if (-not (Test-Path $modDir)) {
    Write-Host "Telechargement de ps2exe..." -ForegroundColor Cyan
    $ProgressPreference = 'SilentlyContinue'
    $zip = Join-Path $env:TEMP 'ps2exe.zip'
    Invoke-WebRequest -Uri 'https://www.powershellgallery.com/api/v2/package/ps2exe/0.18.10' -OutFile $zip -UseBasicParsing
    Expand-Archive $zip $modDir -Force
}

Import-Module (Join-Path $modDir 'ps2exe.psd1') -Force

# --- 2. COMPILATION (ps2exe) : une seule sortie, icone app.ico embarquee ---
Invoke-ps2exe -inputFile  $bundle `
              -outputFile $out `
              -iconFile   $ico `
              -title      'Assistant Deploiement Bentley PowerDraft' `
              -product    'Bentley PowerDraft Deploy' `
              -company    'Sarytany' `
              -description 'Deploiement automatique de la configuration PowerDraft' `
              -version    '1.0.0.0' `
              -noConsole -STA -x86 -ErrorAction Stop

Remove-Item -LiteralPath $bundle -Force -ErrorAction SilentlyContinue

Write-Host "Compilation terminee : $out ($assembled modules)" -ForegroundColor Green