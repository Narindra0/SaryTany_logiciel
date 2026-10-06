# ==================================================================
# src\23-Engine-SintegraLidar.ps1  -  Moteur integration SintegraLidar
#   Installe SintegraLidar : creation repertoire, permissions,
#   copie fichiers, import registre, PATH systeme, separateur
#   decimal, integration Bentley PowerDraft (fichier mvba).
#   Inclut le cryptage AES pour les valeurs sensibles.
#   Moteur testable : aucune dependance a l'interface graphique.
# Inspire du projet SintegraLidar (Install-SintegraLidar.ps1).
# Depend de : $SintegraSourceDir, $SintegraDestDir, $TrialMaxLaunches
# ==================================================================

# --- Cryptage AES pour valeurs sensibles ---
# Cle de 32 octets (256 bits) pour AES-256-CBC.
# Repare : la cle d'origine faisait 62 caracteres (Base64 invalide,
# longueur non multiple de 4) et plantait au chargement du module.
# 43 caracteres + '=' = 44 caracteres = exactement 32 octets.
$script:SintegraAesKey = [Convert]::FromBase64String("JFDHKJdhf23984hjsdfkjhSDKLJsfh2384hjsdfkjhS=")

function Encrypt-String {
    param([string]$PlainText)
    if (-not $PlainText) { return $null }
    $bytes = [Text.Encoding]::Unicode.GetBytes($PlainText)
    $aes = [System.Security.Cryptography.AES]::Create()
    $aes.Key = $script:SintegraAesKey
    $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
    $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
    $encryptor = $aes.CreateEncryptor()
    $encrypted = $encryptor.TransformFinalBlock($bytes, 0, $bytes.Length)
    return [Convert]::ToBase64String($encrypted)
}

function Decrypt-String {
    param([string]$CipherText)
    if (-not $CipherText) { return $null }
    try {
        $bytes = [Convert]::FromBase64String($CipherText)
        $aes = [System.Security.Cryptography.AES]::Create()
        $aes.Key = $script:SintegraAesKey
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        $decryptor = $aes.CreateDecryptor()
        $plain = $decryptor.TransformFinalBlock($bytes, 0, $bytes.Length)
        return [Text.Encoding]::Unicode.GetString($plain)
    } catch {
        return $null
    }
}

# --- Valeurs configurees (peuvent etre surchargees par parametres CLI) ---
if (-not $SintegraDestDir) {
    $SintegraDestDir = 'C:\SintegraLidar'
}

$script:SintegraAppName      = 'SintegraLidar'
$script:SintegraAppVersion   = '1.0.0'
$script:SintegraDevName      = 'Narindra Ranjalahy'
$script:SintegraContactEmail = 'ranjalahy.narindraa@gmail.com'
$script:SintegraContactPhone = '0328814081'

$script:SintegraRegFileName  = 'Las2Laz+IIQ+EXIF.reg'
$script:SintegraMvbaFileName = 'SintegraLidarConnect.mvba'
$script:BentleyDir           = 'C:\ProgramData\Bentley\PowerDraft'

$script:SintegraTrialLaunches = 0

# Etat partage avec l'interface
$script:SintegraCancelRequested = $false

# --- Protections anti-analyse (conservées depuis SintegraLidar) ---
function Test-AnalysisEnvironment {
    # Vérification du débogueur
    if ([System.Diagnostics.Debugger]::IsAttached) {
        return $true
    }
    # Verification des noms d'ordinateur suspects
    $suspiciousNames = @('DEBUG', 'ANALYSIS', 'PEKER', 'TEST', 'VMWARE', 'VIRTUAL', 'SANDBOX')
    if ($suspiciousNames -contains $env:COMPUTERNAME.ToUpper()) {
        return $true
    }
    # Verification des variables d'environnement d'analyse
    $analysisEnvVars = @('DEBUG', 'ANALYSIS_TOOL', 'PEID', 'ILDASM', 'DOTPEEK')
    foreach ($var in $analysisEnvVars) {
        if (${env:$var}) { return $true }
    }
    return $false
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Request-SintegraSourceDirectory {
    param([string]$Initial)
    if ($Initial -and (Test-Path -LiteralPath $Initial -PathType Container)) {
        return (Resolve-Path -LiteralPath $Initial).Path
    }
    # 1) Dialogue graphique
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = "Selectionnez le dossier source SintegraLidarCONNECT"
        $dlg.ShowNewFolderButton = $false
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK -and $dlg.SelectedPath) {
            return $dlg.SelectedPath
        }
    } catch {
        # Dialogue graphique indisponible - on continue avec la saisie manuelle
    }
    # 2) Retourner $null pour que l'appelant gere la saisie
    return $null
}

function Add-ToSystemPath {
    param([string]$DirToAdd)
    $machinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
    if (-not $machinePath) { $machinePath = "" }
    $entries = $machinePath -split ";" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
    $exists = $entries | Where-Object { $_.TrimEnd('\') -ieq $DirToAdd.TrimEnd('\') }
    if ($exists) {
        return $true
    }
    $newPath = ($machinePath.TrimEnd(';') + ";" + $DirToAdd).TrimStart(';')
    [Environment]::SetEnvironmentVariable("PATH", $newPath, "Machine")
    $env:Path = $env:Path.TrimEnd(';') + ";" + $DirToAdd
    # Notification WM_SETTINGCHANGE pour éviter le reboot
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
    } catch { }
    return $true
}

function Invoke-SintegraLidarInstall {
    <#
        Execute les 7 etapes d'installation SintegraLidar :
        1. Selection dossier source
        2. Creation + securisation destination
        3. Copie fichiers
        4. Import registre
        5. Ajout au PATH
        6. Separateur decimal = point
        7. Integration Bentley PowerDraft (mvba)
    #>
    param(
        [string]$SourceDir,
        [string]$DestDir = $SintegraDestDir,
        [int]$TrialLimit = $TrialMaxLaunches,
        [scriptblock]$OnProgress,
        [scriptblock]$Log
    )

    $say = {
        param($m, $l = 'INFO')
        if ($Log) { & $Log $m $l }
    }.GetNewClosure()
    $upd = {
        param($p, $s)
        if ($OnProgress) { & $OnProgress $p $s }
    }.GetNewClosure()

    # --- Etape 0 : trial counter ---
    $script:SintegraTrialLaunches++
    if ($script:SintegraTrialLaunches -gt $TrialLimit) {
        & $say ("Limite d'essais atteinte ($TrialLimit). Utilisez le mode Deploy ou Configure." ) 'ERREUR'
        throw "Limite d'essais atteinte ($TrialLimit)."
    }

    # --- Etape 1 : source ---
    & $upd 5 "Selection du dossier source..."
    if (-not $SourceDir) {
        $SourceDir = Request-SintegraSourceDirectory -Initial $SintegraSourceDir
        if (-not $SourceDir) {
            throw "Aucun dossier source specifie."
        }
    }
    if (-not (Test-Path -LiteralPath $SourceDir)) {
        throw "Dossier source introuvable : $SourceDir"
    }
    & $say "Source : $SourceDir" 'OK'

    # --- Etape 2 : destination + securite ---
    & $upd 15 "Creation et securisation de $DestDir..."
    if (-not (Test-Path -LiteralPath $DestDir)) {
        New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
    }
    # Tout le monde = Everyone (SID S-1-1-0, indépendant de la langue de l'OS)
    $icacls = Start-Process icacls.exe -ArgumentList "`"$DestDir`" /grant *S-1-1-0:(OI)(CI)F /T" -Wait -NoNewWindow -PassThru
    if ($icacls.ExitCode -ne 0) {
        & $say ("icacls a echoue (code $($icacls.ExitCode)). Continue...") 'ATTENTION'
    } else {
        & $say "Permissions Tout le monde = Autoriser tout appliquees." 'OK'
    }

    # --- Etape 3 : copie fichiers ---
    & $upd 35 "Copie des fichiers source..."
    $sourceItems = Get-ChildItem -LiteralPath $SourceDir -Force
    if ($sourceItems) {
        Copy-Item -LiteralPath (Join-Path $SourceDir '*') -Destination $DestDir -Recurse -Force
        & $say "Fichiers copies vers $DestDir" 'OK'
    } else {
        & $say "Le dossier source est vide." 'ATTENTION'
    }

    # --- Etape 4 : import registre ---
    & $upd 50 "Import du registre..."
    $regSource = Join-Path $SourceDir $script:SintegraRegFileName
    $regDest   = Join-Path $DestDir $script:SintegraRegFileName
    $regToImport = $null
    if (Test-Path -LiteralPath $regDest -PathType Leaf) { $regToImport = $regDest }
    elseif (Test-Path -LiteralPath $regSource -PathType Leaf) { $regToImport = $regSource }

    if (-not $regToImport) {
        & $say "Fichier $script:SintegraRegFileName introuvable. Etape ignoree." 'ATTENTION'
    } else {
        & $say "Import : $regToImport" 'INFO'
        $r = Start-Process reg.exe -ArgumentList "import `"$regToImport`"" -Wait -NoNewWindow -PassThru
        if ($r.ExitCode -ne 0) {
            & $say ("reg import a echoue (code $($r.ExitCode)).") 'ERREUR'
        } else {
            & $say "Registre importe avec succes." 'OK'
            # Suppression apres import reussi
            if (Test-Path -LiteralPath $regDest) {
                Remove-Item -LiteralPath $regDest -Force
                & $say "Fichier registre supprime : $regDest" 'OK'
            }
        }
    }

    # --- Etape 5 : PATH ---
    & $upd 60 "Ajout au PATH systeme..."
    $result = Add-ToSystemPath -DirToAdd $DestDir
    if ($result) {
        & $say "Ajout au PATH systeme : $DestDir" 'OK'
    }

    # --- Etape 6 : separateur decimal ---
    & $upd 75 "Configuration du separateur decimal..."
    $intlPath = "HKCU:\Control Panel\International"
    $currentDec = (Get-ItemProperty -Path $intlPath -Name sDecimal -ErrorAction SilentlyContinue).sDecimal
    $currentTho = (Get-ItemProperty -Path $intlPath -Name sThousand -ErrorAction SilentlyContinue).sThousand
    Set-ItemProperty -Path $intlPath -Name sDecimal -Value "."
    if ($currentTho -eq ".") {
        Set-ItemProperty -Path $intlPath -Name sThousand -Value " "
    }
    & $say "sDecimal defini a '.' (redemarrage peut etre necessaire)." 'OK'

    # --- Etape 7 : integration Bentley ---
    & $upd 90 "Integration Bentley PowerDraft..."
    $mvbaSource = Join-Path $SourceDir $script:SintegraMvbaFileName
    if (-not (Test-Path -LiteralPath $mvbaSource -PathType Leaf)) {
        $altSource = Join-Path $DestDir $script:SintegraMvbaFileName
        if (Test-Path -LiteralPath $altSource -PathType Leaf) { $mvbaSource = $altSource }
    }
    if (-not (Test-Path -LiteralPath $mvbaSource -PathType Leaf)) {
        & $say "Fichier $script:SintegraMvbaFileName introuvable. Etape ignoree." 'ATTENTION'
    } else {
        if (-not (Test-Path -LiteralPath $script:BentleyDir)) {
            New-Item -ItemType Directory -Path $script:BentleyDir -Force | Out-Null
        }
        Copy-Item -LiteralPath $mvbaSource -Destination (Join-Path $script:BentleyDir $script:SintegraMvbaFileName) -Force
        & $say "Copie vers $script:BentleyDir\$script:SintegraMvbaFileName" 'OK'
    }

    & $upd 100 "Termine"
    return [pscustomobject]@{
        Success     = $true
        DestDir     = $DestDir
        AppName     = $script:SintegraAppName
        AppVersion  = $script:SintegraAppVersion
        TrialNumber = $script:SintegraTrialLaunches
    }
}
