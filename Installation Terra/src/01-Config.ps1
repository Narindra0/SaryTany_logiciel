# ==============================================================================
# 01-Config.ps1 - Configuration, palette, etapes (design "Maquette v2")
# ==============================================================================

# --- Reglages persistants ---
$script:AppDataDir  = Join-Path $env:LOCALAPPDATA 'PowerDraftSetup'
$script:SettingsFile = Join-Path $script:AppDataDir 'settings.json'

$script:Cfg = [ordered]@{
    TerraRoot     = ''                                    # Dossier principal Terra
    SetupExe      = ''                                    # eng\setup.exe (determine par l'etape 2)
    SetupVersion  = 'PowerDraft CE'                       # Version a installer
    PtcSource     = ''                                    # eng\PTC_LAS.ptc
    TscanDir      = 'C:\terra64\tscan'                   # Dossier cible TerraScan
    PowerDraftExe = 'C:\Program Files\Bentley\PowerDraft\PowerDraft.exe'
    Silent        = $false
    ComputerId    = ''
}

$script:VersionChoices = @('PowerDraft CE', 'MicroStation CE')

# --- Palette (design v2) ---
$script:Hex = @{
    page      = '#DDE3E8'; pageInk = '#2B3138'; pageMuted = '#5F6B76'
    accent    = '#005078'; accentSoft = '#BED7E8'
    win       = '#F8F9FA'; line = '#DEE2E6'; ink = '#212529'; muted = '#6C757D'
    pendBg    = '#F1F3F5'; pendInk = '#495057'
    waitBg    = '#F1F3F5'; waitInk = '#495057'; # alias etat 'wait' (lookup +'Bg'/+'Ink')
    runBg     = '#FFF3CD'; runInk = '#856404'
    okBg      = '#D1E7DD'; okInk = '#0F5132'
    errBg     = '#F8D7DA'; errInk = '#842029'
    go        = '#00723F'; blue = '#005A80'; grey = '#5A5F66'; coal = '#343A40'
    tbBg      = '#E8EBEE'; tbInk = '#3A4046'
    logBg     = '#1E2024'; logInk = '#D4D8DC'; logTm = '#7C838B'
    info      = '#9DB7CC'; ok = '#6FD39B'; warn = '#F1C75B'; err = '#F0868F'
}

function Get-Col {
    param([string]$Hex)
    return [System.Drawing.ColorTranslator]::FromHtml($Hex)
}

# --- Les 6 etapes de la procedure (design v2) ---
#  Title / Desc : affiches sur la carte
#  Lines        : lignes loguees pendant l'execution
#  Ok / Er      : message de succes / message d'echec
$script:Steps = @(
    @{ Id=1; Title='Sécurité & antivirus'
       Desc='Vérifie Windows Security et restaure les fichiers bloqués'
       Lines=@('Lecture de l''état de la protection','Recherche des éléments bloqués')
       Ok='Protection vérifiée'
       Er='Un fichier est bloqué par Windows Security. Autorisez-le puis réessayez.' },
    @{ Id=2; Title='Dossier Terra'
       Desc='Trouve le sous-dossier eng et le fichier setup.exe'
       Lines=@('Analyse de l''arborescence','Dossier eng trouvé','setup.exe trouvé')
       Ok='setup.exe localisé'
       Er='setup.exe est introuvable. Vérifiez le dossier dans les réglages.' },
    @{ Id=3; Title='Initialisation de PowerDraft'
       Desc='Un premier lancement crée les dossiers de configuration'
       Lines=@('Lancement de PowerDraft','Création des dossiers','Fermeture de PowerDraft')
       Ok='Dossier 10.0.0 créé'
       Er='PowerDraft ne démarre pas. Vérifiez son chemin dans les réglages.' },
    @{ Id=4; Title='Installation'
       Desc='Installe la version choisie. Ne cliquez jamais sur Abort'
       Lines=@('Ouverture de setup.exe','Sélection de la version','Copie des fichiers','Attente du bouton Terminer')
       Ok='Installation terminée'
       Er='L''installeur s''est arrêté trop tôt. Fermez-le puis réessayez.' },
    @{ Id=5; Title='Collecte système'
       Desc='Lit le nom de l''ordinateur et le Computer ID'
       Lines=@('Lecture du nom de l''ordinateur','Lecture du Computer ID')
       Ok='Informations récupérées'
       Er='Computer ID illisible. Ouvrez Terra puis réessayez.' },
    @{ Id=6; Title='Configuration finale'
       Desc='Copie PTC_LAS.ptc vers C:\terra64\tscan et valide'
       Lines=@('Copie de PTC_LAS.ptc','Contrôle du fichier copié')
       Ok='Configuration validée'
       Er='Dossier cible protégé en écriture. Relancez en administrateur.' }
)

$script:StepCount = $script:Steps.Count

# --- Etat des etapes : @{ s='wait'|'run'|'ok'|'err'; m='message' } ---
$script:StepsState = @{}
for ($i = 1; $i -le $script:StepCount; $i++) {
    $script:StepsState[$i] = @{ s = 'wait'; m = '' }
}

$script:StepLabels = @{ wait = 'En attente'; run = 'En cours'; ok = 'Terminé'; err = 'Échec' }
$script:StepGlyphs = @{ run = [char]0x25CF; ok = [char]0x2713; err = [char]0x2717 }

# --- Elements d'interface (peuples par 05-UI.ps1) ---
$script:StepRows = @{}          # id -> hashtable { row, icon, detail }
$script:Running  = $false
$script:Abort    = $false
$script:PromptOk = $true
$script:LogLines = @()
$script:LogPainted = 0

# ==============================================================================
# Activation - controle d'acces avant lancement (code : empreinte SHA256)
# ==============================================================================
$script:DefaultActivationHash = '44947097d64e9c8bdf46b5397bb3aeef18bc72afd449037357ed1d060d2bc02f'
$script:ActivationFile = Join-Path $script:AppDataDir 'activation.dat'

function Get-ActivationHash {
    param([string]$Code)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Code)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-ExpectedHash {
    if (Test-Path $script:ActivationFile) {
        $stored = (Get-Content -Path $script:ActivationFile -Raw).Trim()
        if ($stored) { return $stored }
    }
    return $script:DefaultActivationHash
}

function Test-ActivationCode {
    param([string]$Code)
    if (-not $Code) { return $false }
    if ($env:POWERDRAFT_ACTIVATION -and ($Code -eq $env:POWERDRAFT_ACTIVATION)) { return $true }
    return ((Get-ActivationHash $Code) -eq (Get-ExpectedHash))
}

# ==============================================================================
# Persistance des reglages
# ==============================================================================
function Save-Settings {
    try {
        if (-not (Test-Path $script:AppDataDir)) {
            New-Item -ItemType Directory -Path $script:AppDataDir -Force | Out-Null
        }
        $script:Cfg | ConvertTo-Json | Set-Content -Path $script:SettingsFile -Encoding UTF8
        return $true
    } catch {
        return $false
    }
}

function Load-Settings {
    if (-not (Test-Path $script:SettingsFile)) { return }
    try {
        $json = Get-Content -Path $script:SettingsFile -Raw -Encoding UTF8
        if (-not $json) { return }
        $data = $json | ConvertFrom-Json
        foreach ($k in @($data.PSObject.Properties.Name)) {
            if ($script:Cfg.Contains($k)) { $script:Cfg[$k] = $data.$k }
        }
    } catch {
        Write-Verbose "Reglages illisibles : $script:SettingsFile"
    }
}