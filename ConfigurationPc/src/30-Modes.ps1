# ==================================================================
# src\30-Modes.ps1  -  Modes non graphiques
#   -SelfTest       : recette automatique du deploiement automatique
#   -Mode Deploy    : deploiement Bentley en ligne de commande
#   -Mode Configure : configuration reseau / domaine en ligne de commande
#   Chacun se termine par Stop-App : aucune interface n'est construite.
# Depend de : les moteurs des modules 20 et 21.
# ==================================================================

# --- MODE SELFTEST ---
if ($env:BENTLEY_DEBUG) { "AVANT SELFTEST SelfTest=$SelfTest Mode=$Mode" | Add-Content -Path "$env:TEMP\bentley_debug.txt" -Encoding UTF8 }
if ($SelfTest) {
    if ($env:BENTLEY_DEBUG) { "DANS SELFTEST" | Add-Content -Path "$env:TEMP\bentley_debug.txt" -Encoding UTF8 }
    $tmpDir = Join-Path $env:TEMP ('BentleySelfTest_' + [guid]::NewGuid().ToString('N').Substring(0,8))
    $tmpKey = 'HKCU:\Software\BentleySelfTest\RunOnce'
    $stCode = 1

    # Ecriture directe dans le journal de debug (Write-Out peut bloquer sans console)
    $logNowhere = { param($m, $l) }

    try {
        New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
        $g = Install-AutoDeploy -LogonDir $tmpDir -RunOnceKey $tmpKey -SourcePath $SourceConfig -Log $logNowhere
        $err = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($g.ScriptPath, [ref]$null, [ref]$err)
        if ($err) { throw "Le script genere contient des erreurs : $($err[0].Message)" }
        $stCode = 0
    }
    catch {
        if ($env:BENTLEY_DEBUG) { "SELFTEST ECHEC : $($_.Exception.Message)" | Add-Content -Path "$env:TEMP\bentley_debug.txt" -Encoding UTF8 }
        $stCode = 1
    }
    finally {
        Remove-Item $tmpKey -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Stop-App $stCode
}

# --- MODE DEPLOY ---
if ($Mode -eq 'Deploy') {
    $r = Invoke-BentleyDeployment
    Write-Out ("`nRESULTAT : {0}/{1} profil(s) mis a jour, {2} echec(s), {3} fichiers de reference." -f $r.Updated, $r.Targets, $r.Failed.Count, $r.Files) -ForegroundColor $(if ($r.Success) { 'Green' } else { 'Yellow' })
    if ($r.Failed.Count) { Write-Out ("Echecs : " + ($r.Failed -join ', ')) -ForegroundColor Red }
    if ($r.Success) { Stop-App 0 } else { Stop-App 1 }
}

# --- MODE CONFIGURE (ligne de commande, sans interface) ---
if ($Mode -eq 'Configure') {
    $log = {
        param($m, $l)
        $c = switch ($l) { 'OK' { 'Green' } 'ERREUR' { 'Red' } 'ATTENTION' { 'Yellow' } default { 'Gray' } }
        Write-Out ("[{0}] {1}" -f $l, $m) -ForegroundColor $c
    }
    try {
        if ($AdapterName) {
            Set-AdapterNetwork -AdapterName $AdapterName -DnsPrimary $DnsPrimary -DnsSecondary $DnsSecondary -Simulate:$DryRun -Log $log | Out-Null
        }
        if ($ComputerName) {
            Invoke-PcDomainJoin -ComputerName $ComputerName -DomainName $DomainName -DomainUser $DomainUser -DomainPassword $DomainPassword -Simulate:$DryRun -Log $log | Out-Null
        }
        Write-Out "`nCONFIGURATION PC : termine." -ForegroundColor Green
        Stop-App 0
    }
    catch {
        Write-Out ("`nCONFIGURATION PC : ECHEC - {0}" -f $_.Exception.Message) -ForegroundColor Red
        Stop-App 1
    }
}
