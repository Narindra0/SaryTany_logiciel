# ==================================================================
# src\10-Core.ps1  -  Socle de l'application
#   Preferences, analyse de la ligne de commande (exe ps2exe), arret
#   propre, sortie console, assemblies WinForms, elevation admin.
# Depend de : $Mode et compagnie (parametres de Install-Bentley-GUI.ps1),
#             $script:AppEntry (chemin du .ps1 racine).
# ==================================================================
$ErrorActionPreference = 'Stop'

# NOTE : l'executable compile par ps2exe n'exploite pas toujours le bloc param()
# (les arguments sont livres tels quels). On reparses donc la ligne de commande
# pour que l'exe accepte les memes options que le script.
$knownSwitches = @('SelfTest', 'AutoTest', 'NoDialogs', 'DryRun', 'RenderLicense')
$knownValues   = @('Mode', 'StartTab', 'RenderTo', 'AutoTestDelay', 'SourceConfig', 'ItStSource',
                   'DefaultPath', 'UsersRoot', 'AdapterName', 'DnsPrimary', 'DnsSecondary',
                   'ComputerName', 'DomainName', 'DomainUser', 'DomainPassword')

# NOTE : dans un executable compile avec ps2exe, 'exit' ne quitte que le scriptblock
# du script : le flux continuait ensuite vers la GUI. On termine donc explicitement.
function Stop-App {
    param([int]$Code = 0)
    if ($env:BENTLEY_DEBUG) { "STOP-APP code=$Code" | Add-Content -Path "$env:TEMP\bentley_debug.txt" -Encoding UTF8 }
    [Environment]::Exit($Code)
}

# NOTE : Write-Out peut FAIRE PLANTER ou BLOQUER un exe sans console.
# Write-Out n'ecrit que si une console est reellement attachee.
function Write-Out {
    param([string]$Text, [string]$Color = 'Gray', [string]$ForegroundColor = $null)
    if ($ForegroundColor) { $Color = $ForegroundColor }
    # 1. Console : sortie directe, insensible a la capture de pipeline ($null = ...)
    try {
        [Console]::Out.WriteLine($Text)
        return
    } catch { }
    # 2. Console attachee avec couleurs
    try {
        if ([Console]::WindowHeight -gt 0) { Microsoft.PowerShell.Utility\Write-Host $Text -ForegroundColor $Color; return }
    } catch { }
    # 3. Dernier recours
    Microsoft.PowerShell.Utility\Write-Host $Text
}

$rawArgs = [Environment]::GetCommandLineArgs()
if ($env:BENTLEY_DEBUG) {
    "RAWARGS: " + ($rawArgs -join ' | ') | Set-Content -Path "$env:TEMP\bentley_debug.txt" -Encoding UTF8
}
if ($rawArgs.Count -gt 1) {
    $tokens = @($rawArgs[1..($rawArgs.Count - 1)])
    $i = 0
    while ($i -lt $tokens.Count) {
        $token = "$($tokens[$i])"
        $i++
        if (-not $token.StartsWith('-')) { continue }
        $name = $token.TrimStart('-')
        if ($knownSwitches -contains $name) {
            Set-Variable -Name $name -Value $true -Scope Local
        } elseif ($knownValues -contains $name) {
            if ($i -lt $tokens.Count -and "$($tokens[$i])" -notlike '-*') {
                Set-Variable -Name $name -Value "$($tokens[$i])" -Scope Local
                $i++
            }
        }
    }
}
if ($env:BENTLEY_DEBUG) {
    "PARSED Mode=$Mode SelfTest=$SelfTest StartTab=$StartTab" | Add-Content -Path "$env:TEMP\bentley_debug.txt" -Encoding UTF8
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- AUTO-ELEVATION DES DROITS ADMINISTRATEUR ---
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    # Cible a relancer : le .ps1 racine si on tourne en script, l'executable sinon.
    $selfPath = $null
    if ($script:AppEntry -and ([System.IO.Path]::GetExtension($script:AppEntry) -ieq '.ps1') -and (Test-Path -LiteralPath $script:AppEntry)) {
        $selfPath = $script:AppEntry
    }
    if (-not $selfPath) {
        $exePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if ([System.IO.Path]::GetFileNameWithoutExtension($exePath) -eq 'Install-Bentley-GUI') { $selfPath = $exePath }
    }
    if ($selfPath -and (Test-Path -LiteralPath $selfPath)) {
        try {
            if ([System.IO.Path]::GetExtension($selfPath) -ieq '.exe') {
                Start-Process -FilePath $selfPath -Verb RunAs -ArgumentList @('-Mode', $Mode) | Out-Null
            } else {
                Start-Process PowerShell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$selfPath`"",'-Mode',$Mode) -Verb RunAs | Out-Null
            }
            Stop-App 0
        } catch { }
    }
    if ($Mode -eq 'GUI') {
        [System.Windows.Forms.MessageBox]::Show("Les droits administrateur sont necessaires pour installer la configuration.`r`nRelancez l'application en mode 'Executer en tant qu administrateur'.", "Droits requis", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
    } else {
        Write-Out "Droits administrateur requis." -ForegroundColor Red
    }
    Stop-App 1
}
