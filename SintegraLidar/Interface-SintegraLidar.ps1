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

# Licence code chiffré
$encryptedLicense = "sYFJ5c3RlYWs="
$ValidLicenseCode = Decrypt-String -CipherText $encryptedLicense

# Chemins de registre chiffrés
$encryptedRegPath = "SUtcRGVncm91cFBvbGljeQ="
$LicenseRegPath = Decrypt-String -CipherText $encryptedRegPath

$encryptedRegPathMachine = "TG9uZ2l0eVJlcG9ydFBvbGljeQ="
$LicenseRegPathMachine = Decrypt-String -CipherText $encryptedRegPathMachine

# Chemin destination chiffré
$encryptedDestDir = "LFdyaW5BcG9ydFBvaW50cg=="
$DestDir = Decrypt-String -CipherText $encryptedDestDir

# Nom/application chiffrés
$encryptedAppName = "U2luZGVyTGF5ZXJz"
$AppName = Decrypt-String -CipherText $encryptedAppName

$encryptedAppVersion = "VQxJTkVHIg=="
$AppVersion = Decrypt-String -CipherText $encryptedAppVersion

$encryptedDevName = "TGFuYW5kcmF6YWx5"
$DevName = Decrypt-String -CipherText $encryptedDevName

# Clé de licence trial
$encryptedTrialMax = "Mzim5MRhb="
$TrialMaxLaunches = [int]::Parse(Decrypt-String -CipherText $encryptedTrialMax)

# Logo/Base64 chiffré (laisser vide si non utilisé ou chiffré séparément)
$encryptedLogoBase64 = ""
$script:LogoBase64 = if ($encryptedLogoBase64) { Decrypt-String -CipherText $encryptedLogoBase64 } else { $null }

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

# Valeurs personnelles - utilisent les valeurs déchiffrées ci-dessus
# Pour personnaliser, modifiez les valeurs chiffrées en haut du fichier
$DevName      = $DecryptedDevName
$AppName      = $DecryptedAppName
$AppVersion   = $DecryptedAppVersion
$ContactEmail = "ranjalahy.narindraa@gmail.com"
$ContactPhone = "0328814081"
# Logo - rechiffrer avec Encrypt-String si modifié
$LogoBase64 = if ($encryptedLogoBase64) { $script:LogoBase64 = Decrypt-String -CipherText $encryptedLogoBase64 } else { $null }