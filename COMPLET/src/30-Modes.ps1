# ==================================================================
# src\30-Modes.ps1  -  Modes non graphiques
#   -SelfTest           : recette automatique du RunOnce
#   -Mode Deploy        : deploiement Bentley en ligne de commande
#   -Mode Configure     : configuration reseau / domaine en ligne de commande
#   -Mode Suite         : installation Bentley Suite en ligne de commande
#   -Mode Sintegra      : integration SintegraLidar en ligne de commande
#   Chacun se termine par Stop-App : aucune interface n'est construite.
# Depend de : les moteurs des modules 20, 21, 22, 23.
# ==================================================================

# --- MODE SELFTEST ---
if ($env:BENTLEY_DEBUG) { "AVANT SELFTEST SelfTest=$SelfTest Mode=$Mode" | Add-Content -Path "$env:TEMP\bentley_debug.txt" -Encoding UTF8 }
if ($SelfTest) {
    if ($env:BENTLEY_DEBUG) { "DANS SELFTEST" | Add-Content -Path "$env:TEMP\bentley_debug.txt" -Encoding UTF8 }
    $tmpDir = Join-Path $env:TEMP ('BentleySelfTest_' + [guid]::NewGuid().ToString('N').Substring(0,8))
    $tmpKey = 'HKCU:\Software\BentleySelfTest\RunOnce'
    $stCode = 1

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
    $log = {
        param($m, $l)
        $c = switch ($l) { 'OK' { 'Green' } 'ERREUR' { 'Red' } 'ATTENTION' { 'Yellow' } default { 'Gray' } }
        Write-Out ("[{0}] {1}" -f $l, $m) -ForegroundColor $c
    }
    $r = Invoke-BentleyDeployment -Log $log
    Write-Out ("`nRESULTAT : {0}/{1} profil(s) mis a jour, {2} echec(s), {3} fichiers de reference." -f $r.Updated, $r.Targets, $r.Failed.Count, $r.Files) -ForegroundColor $(if ($r.Success) { 'Green' } else { 'Yellow' })
    if ($r.Failed.Count) { Write-Out ("Echecs : " + ($r.Failed -join ', ')) -ForegroundColor Red }
    if ($r.Success) { Stop-App 0 } else { Stop-App 1 }
}

# --- MODE CONFIGURE ---
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

# --- MODE SUITE (Bentley Suite installer, ligne de commande) ---
if ($Mode -eq 'Suite') {
    $log = {
        param($m, $l)
        $c = switch ($l) { 'OK' { 'Green' } 'ERREUR' { 'Red' } 'ATTENTION' { 'Yellow' } default { 'Gray' } }
        Write-Out ("[{0}] {1}" -f $l, $m) -ForegroundColor $c
    }
    try {
        if (-not $SuiteSourceDir) {
            $dir = Request-SintegraSourceDirectory -Initial $SuiteSourceDir
            if (-not $dir) { throw "Aucun dossier source specifie." }
            $SuiteSourceDir = $dir
        }
        $r = Invoke-BentleySuiteInstall -SourceDir $SuiteSourceDir -Log $log
        Write-Out ("`nINSTALLATION BENTLEY SUITE : {0}/{1} modules, {2} echec(s), {3} manuel(s)." -f $r.Installed, $r.TotalModules, $r.Failed.Count, $r.Skipped.Count) -ForegroundColor $(if ($r.Success) { 'Green' } else { 'Yellow' })
        if ($r.Failed.Count) { Write-Out ("Echecs : " + ($r.Failed -join ', ')) -ForegroundColor Red }
        if ($r.Skipped.Count) { Write-Out ("Manuels a finaliser : " + ($r.Skipped -join ', ')) -ForegroundColor Yellow }
        if ($r.Success) { Stop-App 0 } else { Stop-App 1 }
    }
    catch {
        Write-Out ("`nINSTALLATION BENTLEY SUITE : ECHEC - {0}" -f $_.Exception.Message) -ForegroundColor Red
        Stop-App 1
    }
}

# --- MODE SINTEGRA (integration SintegraLidar, ligne de commande) ---
if ($Mode -eq 'Sintegra') {
    $log = {
        param($m, $l)
        $c = switch ($l) { 'OK' { 'Green' } 'ERREUR' { 'Red' } 'ATTENTION' { 'Yellow' } default { 'Gray' } }
        Write-Out ("[{0}] {1}" -f $l, $m) -ForegroundColor $c
    }
    try {
        if (-not $SintegraSourceDir) {
            $dir = Request-SintegraSourceDirectory -Initial $SintegraSourceDir
            if (-not $dir) { throw "Aucun dossier source specifie." }
            $SintegraSourceDir = $dir
        }
        $r = Invoke-SintegraLidarInstall -SourceDir $SintegraSourceDir -DestDir $SintegraDestDir -TrialLimit $TrialMaxLaunches -Log $log
        Write-Out "`nINTEGRATION SINTEGRA LIDAR : terminee." -ForegroundColor Green
        Write-Out ("Destination : {0}" -f $r.DestDir) -ForegroundColor Cyan
        Write-Out ("Essai : {0}/{1}" -f $r.TrialNumber, $TrialMaxLaunches) -ForegroundColor Cyan
        Stop-App 0
    }
    catch {
        Write-Out ("`nINTEGRATION SINTEGRA LIDAR : ECHEC - {0}" -f $_.Exception.Message) -ForegroundColor Red
        Stop-App 1
    }
}
