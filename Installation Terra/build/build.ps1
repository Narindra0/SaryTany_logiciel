<#
==============================================================================
 build.ps1 - Genere un fichier .exe unique a partir de src/
------------------------------------------------------------------------------
 Etapes :
   1. Verification/installation du module ps2exe
   2. Concatenation des modules src/ dans un script unique build/
   3. Compilation en .exe avec ps2exe (-noConsole -STA)
   4. Nettoyage de l'intermediaire

 Resultat : dist\PowerDraft-Setup.exe

 Usage : powershell -ExecutionPolicy Bypass -File .\build.ps1
==============================================================================
#>

param(
    [string]$Version = '1.0.0',
    [switch]$KeepIntermediate
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $PSCommandPath          # ...\build
$root      = Split-Path -Parent $scriptDir              # ...\azafady
$srcDir    = Join-Path $root 'src'
$buildDir  = $scriptDir
$distDir   = Join-Path $root 'dist'

$exeName    = 'PowerDraft-Setup'
$combined   = Join-Path $buildDir "$exeName.combined.ps1"
$outputExe  = Join-Path $distDir "$exeName.exe"

function Write-Section {
    param([string]$Text)
    Write-Host ''
    Write-Host "== $Text" -ForegroundColor Cyan
}

Write-Host ''
Write-Host ' PowerDraft / Terra - Build' -ForegroundColor Green
Write-Host " Version : $Version"

# ------------------------------------------------------------------------------
Write-Section 'Verification de ps2exe'

$ps2exe = Get-Module -ListAvailable -Name ps2exe | Select-Object -First 1
if (-not $ps2exe) {
    Write-Host ' ps2exe absent - installation...' -ForegroundColor Yellow
    try {
        Install-Module ps2exe -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        Write-Host ' ps2exe installe.' -ForegroundColor Green
    } catch {
        Write-Host " Echec de l'installation automatique : $_" -ForegroundColor Red
        Write-Host ' Installez manuellement : Install-Module ps2exe -Scope CurrentUser' -ForegroundColor Yellow
        exit 1
    }
} else {
    Write-Host " Detecte : $($ps2exe.Version)" -ForegroundColor Green
}

# ------------------------------------------------------------------------------
Write-Section 'Concatenation des modules'

$modules = @(
    '01-Config.ps1'
    '02-Helpers.ps1'
    '03-Steps.ps1'
    '04-Orchestration.ps1'
    '05-UI.ps1'
)

foreach ($m in $modules) {
    $p = Join-Path $srcDir $m
    if (-not (Test-Path $p)) {
        Write-Host " Module manquant : $m" -ForegroundColor Red
        exit 1
    }
}

$sb = New-Object System.Text.StringBuilder

[void]$sb.AppendLine('# ==============================================================================')
[void]$sb.AppendLine("# $exeName v$Version - genere automatiquement par build.ps1")
[void]$sb.AppendLine("# Source : src/01-Config.ps1 .. 05-UI.ps1")
[void]$sb.AppendLine('# Ne pas modifier : rebuilt a chaque compilation.')
[void]$sb.AppendLine('# ==============================================================================')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('Add-Type -AssemblyName System.Windows.Forms')
[void]$sb.AppendLine('Add-Type -AssemblyName System.Drawing')
[void]$sb.AppendLine('[System.Windows.Forms.Application]::EnableVisualStyles()')
[void]$sb.AppendLine('')
[void]$sb.AppendLine("`$script:AppVersion = '$Version'")
[void]$sb.AppendLine('')

foreach ($m in $modules) {
    [void]$sb.AppendLine("# ---- $m " + ('-' * (68 - $m.Length)))
    $body = Get-Content -Path (Join-Path $srcDir $m) -Raw -Encoding UTF8
    [void]$sb.AppendLine($body.TrimEnd())
    [void]$sb.AppendLine('')
}

[void]$sb.AppendLine('# ---- Lancement ' + ('-' * 58))
[void]$sb.AppendLine('Start-Application')

# BOM UTF-8 requis : PowerShell 5.1 ParseFile lit en ANSI les fichiers sans BOM,
# ce qui corrompt les accents et casse la syntaxe. ps2exe (ReadAllText) detecte le BOM.
[System.IO.File]::WriteAllText($combined, $sb.ToString(), (New-Object System.Text.UTF8Encoding $true))
Write-Host " Script genere : $combined" -ForegroundColor Green
Write-Host (' Taille : {0:N0} octets' -f (Get-Item $combined).Length)

# ------------------------------------------------------------------------------
Write-Section 'Verification de la syntaxe du script combine'

$parseErrors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile(
    $combined, [ref]$null, [ref]$parseErrors)

if ($parseErrors -and $parseErrors.Count -gt 0) {
    Write-Host ' Erreurs de syntaxe detectees :' -ForegroundColor Red
    $parseErrors | ForEach-Object {
        Write-Host "   ligne $($_.Extent.StartLineNumber) : $($_.Message)" -ForegroundColor Red
    }
    exit 1
}
Write-Host ' Syntaxe valide.' -ForegroundColor Green

# ------------------------------------------------------------------------------
Write-Section 'Compilation en .exe'

if (-not (Test-Path $distDir)) {
    New-Item -ItemType Directory -Path $distDir -Force | Out-Null
}
if (Test-Path $outputExe) { Remove-Item $outputExe -Force }

$ps2exeParams = @{
    InputFile       = $combined
    OutputFile      = $outputExe
    Title           = 'PowerDraft / Terra - Installation et configuration'
    Product         = 'Assistant PowerDraft Terra'
    Company         = 'Internal IT'
    Description     = "Installation et configuration de Bentley PowerDraft et des modules Terra (v$Version)"
    Version         = $Version
    NoConsole       = $true
    STA             = $true
    winFormsDPIAware= $true
    x64             = $true
}

try {
    Import-Module ps2exe -Force -ErrorAction Stop
    if (-not (Get-Command Invoke-ps2exe -ErrorAction SilentlyContinue)) {
        throw 'Commande Invoke-ps2exe indisponible apres import.'
    }
    Invoke-ps2exe @ps2exeParams -ErrorAction Stop
} catch {
    Write-Host " Echec de la compilation : $_" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $outputExe)) {
    Write-Host " L'executable n'a pas ete produit." -ForegroundColor Red
    exit 1
}

Write-Host " Executable : $outputExe" -ForegroundColor Green
Write-Host (' Taille : {0:N0} octets' -f (Get-Item $outputExe).Length) -ForegroundColor Green

# ------------------------------------------------------------------------------
if (-not $KeepIntermediate) {
    Remove-Item $combined -Force
    Write-Host ' Intermediaire supprime.' -ForegroundColor DarkGray
} else {
    Write-Host " Intermediaire conserve : $combined" -ForegroundColor DarkGray
}

Write-Host ''
Write-Host ' Build termine.' -ForegroundColor Green
Write-Host ''
