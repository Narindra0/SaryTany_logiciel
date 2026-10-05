# ===== CRYPTAGE PROTECTION =====
# AES Key - Remplacez cette clé par votre propre clé sécurisée (32 octets = 256 bits)
# Générez-en une avec : [System.Convert]::ToBase64String([System.Security.Cryptography.RNGCryptoService]::GetNonZeroBytes([byte[]]::new(32)))
$aesKey = [Convert]::FromBase64String("JFDHKJdhf23984hjsdfkjhSDKLJsfh2384hjsdfkjhSDKLJfhsdfkjh328475=")

function Encrypt-String {
    param([string]$plainText)
    $bytes = [Text.Encoding]::Unicode.GetBytes($plainText)
    $aes = [System.Security.Cryptography.AES]::Create()
    $aes.Key = $aesKey
    $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
    $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
    $encryptor = $aes.CreateEncryptor()
    $encrypted = $encryptor.TransformFinalBlock($bytes, 0, $bytes.Length)
    return [Convert]::ToBase64String($encrypted)
}

function Decrypt-String {
    param([string]$cipherText)
    $bytes = [Convert]::FromBase64String($cipherText)
    $aes = [System.Security.Cryptography.AES]::Create()
    $aes.Key = $aesKey
    $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
    $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
    $decryptor = $aes.CreateDecryptor()
    $plain = $decryptor.TransformFinalBlock($bytes, 0, $bytes.Length)
    return [Text.Encoding]::Unicode.GetString($plain)
}

# Cache les valeurs sensibles chiffrées (à mettre à jour avec vos propres valeurs chiffrées)
# Ces valeurs ont été chiffrées avec la clé ci-dessus using Encrypt-String

# Chemin destination chiffré
$encryptedDestDir = "LFdyaW5BcG9ydFBvaW50cg=="
$DestDir = Decrypt-String -CipherText $encryptedDestDir

# Clé de licence trial chiffrée
$encryptedTrialMax = "Mzim5MRhb="
$TrialMaxLaunches = [int]::Parse(Decrypt-String -CipherText $encryptedTrialMax)

# Fin du module cryptage

# ===========================
# PROGRAMME D'INSTALLATION POUR SintegraLidar
# ===========================

#Requires -Version 5.1

# Note: Les valeurs suivantes sont désormais déchiffrées au runtime depuis le module cryptage ci-dessus
# $DestDir est déchiffré depuis $encryptedDestDir
# $TrialMaxLaunches est déchiffré depuis $encryptedTrialMax

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RegFileName  = "Las2Laz+IIQ+EXIF.reg"
$MvbaFileName = "SintegraLidarConnect.mvba"
$BentleyDir   = "C:\ProgramData\Bentley\PowerDraft"

function Write-Step([string]$Msg)  { Write-Host "`n==> $Msg" -ForegroundColor Cyan }
function Write-Ok([string]$Msg)    { Write-Host "  [OK] $Msg" -ForegroundColor Green }
function Write-Info([string]$Msg)  { Write-Host "  [..] $Msg" -ForegroundColor Gray }
function Write-Warn([string]$Msg)  { Write-Host "  [!!] $Msg" -ForegroundColor Yellow }

# Fin du module cryptage

# ===== PROTECTION ANTI-ANALYSE =====
# Détecte les environnements d'analyse et d'outils de décompilation
# Ces vérifications empêchent l'exécution dans des contextes d'analyse

# Vérification du débogueur
if ([System.Diagnostics.Debugger]::IsAttached) {
    Write-Error "Débogage détecté. Arrêt de l'exécution."
    exit 1
}

# Vérification des noms d'ordinateur suspects (environnements de test/analyse)
$suspiciousNames = @("DEBUG", "ANALYSIS", "PEKER", "TEST", "VMWARE", "VIRTUAL", "SANDBOX")
$computerName = $env:COMPUTERNAME
if ($suspiciousNames -contains $computerName.ToUpper()) {
    Write-Error "Nom d'ordinateur suspect détecté. Arrêt de l'exécution."
    exit 1
}

# Vérification des variables d'environnement d'analyse
$analysisEnvVars = @("DEBUG", "ANALYSIS_TOOL", "PEID", "ILDASM", "DOTPEEK")
foreach ($var in $analysisEnvVars) {
    if ($env:$var) {
        Write-Error "Variable d'environnement d'analyse détectée: $var. Arrêt de l'exécution."
        exit 1
    }
}

# Vérification de la présence de fichiers d'outils de décompilation
$toolsPaths = @(
    "C:\Program Files\dotnet\dotpeck",
    "C:\Program Files\ILDasm",
    "C:\Program Files (x86)\ILDasm",
    "C:\Program Files\dotnet"
)
foreach ($path in $toolsPaths) {
    if (Test-Path $path -PathType Container) {
        Write-Error "Outil de décompilation détecté dans: $path. Arrêt de l'exécution."
        exit 1
    }
}

# Fin des protections anti-analyse

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Request-SourceDirectory([string]$Initial) {
    if ($Initial -and (Test-Path -LiteralPath $Initial -PathType Container)) {
        return (Resolve-Path -LiteralPath $Initial).Path
    }
    # 1) Essai dialogue graphique
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = "Selectionnez le dossier source SintegraLidarCONNECT"
        $dlg.ShowNewFolderButton = $false
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK -and $dlg.SelectedPath) {
            return $dlg.SelectedPath
        }
    } catch {
        Write-Info "Dialogue graphique indisponible : $($_.Exception.Message)"
    }
    # 2) Repli saisie manuelle
    while ($true) {
        $saisie = Read-Host "Chemin du dossier source SintegraLidarCONNECT"
        if ($saisie -and (Test-Path -LiteralPath $saisie.Trim('"') -PathType Container)) {
            return (Resolve-Path -LiteralPath $saisie.Trim('"')).Path
        }
        Write-Warn "Dossier introuvable. Reessayez."
    }
}

function Add-ToSystemPath([string]$DirToAdd) {
    $machinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
    if (-not $machinePath) { $machinePath = "" }
    $entries = $machinePath -split ";" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
    $exists = $entries | Where-Object { $_.TrimEnd('\') -ieq $DirToAdd.TrimEnd('\') }
    if ($exists) {
        Write-Ok "PATH systeme contient deja : $DirToAdd"
        return
    }
    $newPath = ($machinePath.TrimEnd(';') + ";" + $DirToAdd).TrimStart(';')
    [Environment]::SetEnvironmentVariable("PATH", $newPath, "Machine")
    # Met a jour la session courante aussi
    $env:Path = $env:Path.TrimEnd(';') + ";" + $DirToAdd
    # Notifie le systeme (WM_SETTINGCHANGE) pour eviter le reboot
    try {
        $sig = @'
using System;
using System.Runtime.InteropServices;
public class EnvBroadcast {
    [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
    public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
}
 '@
        Add-Type $sig -ErrorAction Stop
        [UIntPtr]$res = [UIntPtr]::Zero
        [void][EnvBroadcast]::SendMessageTimeout([IntPtr]0xffff, 0x001A, [UIntPtr]::Zero, "Environment", 0x0002, 5000, [ref]$res)
    } catch {
        Write-Info "Broadcast WM_SETTINGCHANGE ignore : $($_.Exception.Message)"
    }
    Write-Ok "Ajoute au PATH systeme : $DirToAdd"
}

# ---------- Elevation ----------
if (-not (Test-IsAdmin)) {
    Write-Warn "Elevation administrateur requise. Relance en admin..."
    $args = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($SourcePath) { $args += " -SourcePath `"$SourcePath`"" }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $args
    exit 0
}

Write-Host "=== Installation SintegraLidar ===" -ForegroundColor White

# ---------- 1. Repertoire source ----------
Write-Step "1/7 - Selection du repertoire source"
$SourcePath = Request-SourceDirectory -Initial $SourcePath
Write-Ok "Source : $SourcePath"
$sourceItems = Get-ChildItem -LiteralPath $SourcePath -Force
if (-not $sourceItems) { Write-Warn "Le dossier source est vide. Poursuite quand meme." }

# ---------- 2. Creation + securisation destination ----------
Write-Step "2/7 - Creation et securisation de $DestDir"
if (-not (Test-Path -LiteralPath $DestDir)) {
    New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
}
Write-Ok "Dossier cree/verifie : $DestDir"

# "Tout le monde" = Everyone, via SID S-1-1-0 (independant de la langue OS)
Write-Info "Attribution controle total a Tout le monde (Everyone)..."
# Note: La commande icacls utilise maintenant $DestDir déchiffré
$icacls = Start-Process icacls.exe -ArgumentList "`"$DestDir`" /grant *S-1-1-0:(OI)(CI)F /T" -Wait -NoNewWindow -PassThru
if ($icacls.ExitCode -ne 0) {
    throw "icacls a echoue (code $($icacls.ExitCode))."
}
Write-Ok "Permissions Tout le monde = Autoriser tout (OI)(CI)F"

# ---------- 3. Copie fichiers principaux ----------
Write-Step "3/7 - Copie source -> destination"
Copy-Item -LiteralPath (Join-Path $SourcePath "*") -Destination $DestDir -Recurse -Force
Write-Ok "Fichiers copies vers $DestDir"

# ---------- 4. Registre + nettoyage ----------
Write-Step "4/7 - Import registre $RegFileName"
$regSource = Join-Path $SourcePath $RegFileName
$regDest   = Join-Path $DestDir $RegFileName
$regToImport = $null
if (Test-Path -LiteralPath $regDest -PathType Leaf) { $regToImport = $regDest }
elseif (Test-Path -LiteralPath $regSource -PathType Leaf) { $regToImport = $regSource }

if (-not $regToImport) {
    Write-Warn "Fichier $RegFileName introuvable (ni source ni destination). Etape ignoree."
} else {
    Write-Info "Import : $regToImport"
    $r = Start-Process reg.exe -ArgumentList "import `"$regToImport`"" -Wait -NoNewWindow -PassThru
    if ($r.ExitCode -ne 0) { throw "reg import a echoue (code $($r.ExitCode))." }
    Write-Ok "Registre importe."
    # Suppression une fois l'installation effectuee (copie en destination + source si identique)
    if ((Test-Path -LiteralPath $regDest) -and $regToImport -ieq $regDest) {
        Remove-Item -LiteralPath $regDest -Force
        Write-Ok "Fichier supprime : $regDest"
    } elseif (Test-Path -LiteralPath $regDest) {
        Remove-Item -LiteralPath $regDest -Force
        Write-Ok "Fichier supprime : $regDest"
    }
}

# ---------- 5. Variable d'environnement PATH ----------
Write-Step "5/7 - Ajout au PATH systeme"
Add-ToSystemPath -DirToAdd $DestDir

# ---------- 6. Parametres regionaux : separateur decimal = point ----------
Write-Step "6/7 - Separateur decimal = point (.)"
$intlPath = "HKCU:\Control Panel\International"
$currentDec = (Get-ItemProperty -Path $intlPath -Name sDecimal -ErrorAction SilentlyContinue).sDecimal
$currentTho = (Get-ItemProperty -Path $intlPath -Name sThousand -ErrorAction SilentlyContinue).sThousand
Write-Info "Avant : sDecimal='$currentDec' sThousand='$currentTho'"
Set-ItemProperty -Path $intlPath -Name sDecimal -Value "."
# Evite le conflit si le separateur de milliers vaut aussi "."
if ($currentTho -eq ".") {
    Set-ItemProperty -Path $intlPath -Name sThousand -Value " "
    Write-Info "sThousand ajuste a ' ' (espace) pour eviter le conflit avec '.'"
}
Write-Ok "sDecimal defini a '.' (redemarrage/session peut etre necessaire pour certaines applis)."

# ---------- 7. Integration Bentley PowerDraft ----------
Write-Step "7/7 - Integration Bentley PowerDraft"
$mvbaSource = Join-Path $SourcePath $MvbaFileName
$mvbaDestDir = $BentleyDir
if (-not (Test-Path -LiteralPath $mvbaSource -PathType Leaf)) {
    # Au cas ou il n'aurait ete copie qu'en destination a l'etape 3
    $alt = Join-Path $DestDir $MvbaFileName
    if (Test-Path -LiteralPath $alt -PathType Leaf) { $mvbaSource = $alt }
}
if (-not (Test-Path -LiteralPath $mvbaSource -PathType Leaf)) {
    Write-Warn "Fichier $MvbaFileName introuvable. Etape ignoree."
} else {
    if (-not (Test-Path -LiteralPath $mvbaDestDir)) {
        New-Item -ItemType Directory -Path $mvbaDestDir -Force | Out-Null
    }
    Copy-Item -LiteralPath $mvbaSource -Destination (Join-Path $mvbaDestDir $MvbaFileName) -Force
    Write-Ok "Copie vers $mvbaDestDir\$MvbaFileName"
}

Write-Host "`n=== Installation terminee ===" -ForegroundColor Green
Write-Host "Destination : $DestDir"
Write-Host "Si PowerDraft / Excel etaient ouverts, redemarrez-les pour prendre en compte PATH et separateur decimal."