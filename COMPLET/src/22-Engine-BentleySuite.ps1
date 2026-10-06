# ==================================================================
# src\22-Engine-BentleySuite.ps1  -  Moteur installation Bentley Suite
#   Installe les 21 modules Bentley de facon sequentielle, detecte
#   les fichiers par motif, gere les modules manuels (pause/resume),
#   le progres, l'annulation et le rapport final.
#   Moteur testable : aucune dependance a l'interface graphique.
# Inspire du projet Micro (Install-BentleySuite).
# Depend de : $SuiteSourceDir (parametre)
# ==================================================================

# --- Definition des 21 modules Bentley (Micro) ---
# Num : ordre d'installation, Pattern : motif de detection du fichier,
#       Mode : 'MSI' | 'MSP' | 'EXE', Manual : $true = pause pour interaction.
$script:BentleyModules = @(
    @{ Num = 01; Name = 'DgnIFilterSetUpx64';       Pattern = 'DgnIFilterSetUpx64';              Mode = 'MSI';   Manual = $false },
    @{ Num = 02; Name = 'DgnIndexer';                Pattern = 'DgnIndexer';                    Mode = 'MSI';   Manual = $false },
    @{ Num = 03; Name = 'DgnPreviewHandlerx64';       Pattern = 'DgnPreviewHandlerx64';           Mode = 'MSI';   Manual = $false },
    @{ Num = 04; Name = 'DgnThumbnailProviderx64';   Pattern = 'DgnThumbnailProviderx64';        Mode = 'MSI';   Manual = $false },
    @{ Num = 05; Name = 'HDRPreviewExtension_x64';   Pattern = 'HDRPreviewExtension_x64';        Mode = 'MSI';   Manual = $false },
    @{ Num = 06; Name = 'ItgDgnDbImporter 1.6';      Pattern = 'ItgDgnDbImporter.*1\.6.*x64';    Mode = 'MSI';   Manual = $false },
    @{ Num = 07; Name = 'ItgDgnDbImporter 2.0';      Pattern = 'ItgDgnDbImporter.*2\.0.*x64';    Mode = 'MSI';   Manual = $false },
    @{ Num = 08; Name = 'MetroStationx64';             Pattern = 'MetroStationx64';              Mode = 'MSI';   Manual = $false },
    @{ Num = 09; Name = 'Pointools32Extx86';          Pattern = 'Pointools32Extx86';            Mode = 'MSI';   Manual = $false },
    @{ Num = 11; Name = 'PowerDraftDocumentation';    Pattern = 'PowerDraftDocumentation';         Mode = 'MSI';   Manual = $false },
    @{ Num = 12; Name = 'PowerDraftx64';              Pattern = 'PowerDraftx64';                Mode = 'MSI';   Manual = $false },
    @{ Num = 13; Name = 'CONNECTION Client';          Pattern = 'Setup_CONNECTIONClient';         Mode = 'EXE';   Manual = $true  },
    @{ Num = 14; Name = 'PowerDraft 10.11';           Pattern = 'Setup_PowerDraftx64_10.11';       Mode = 'EXE';   Manual = $true  },
    @{ Num = 15; Name = 'CONNECT Advisor';            Pattern = 'Setup_CONNECTAdvisor';            Mode = 'EXE';   Manual = $true  },
    @{ Num = 16; Name = 'Vba71';                      Pattern = 'Vba71';                          Mode = 'MSI';   Manual = $false },
    @{ Num = 17; Name = 'Vba71_1033';                 Pattern = 'Vba71_1033';                     Mode = 'MSI';   Manual = $false },
    @{ Num = 18; Name = 'VBA71-KB2803498-x64';        Pattern = 'VBA71-KB2803498-x64';            Mode = 'MSP';   Manual = $false },
    @{ Num = 19; Name = 'VBA71-KB2803498-x64_1033';   Pattern = 'VBA71-KB2803498-x64_1033';       Mode = 'MSP';   Manual = $false },
    @{ Num = 20; Name = 'VBA71-KB3061498-x64';        Pattern = 'VBA71-KB3061498-x64';            Mode = 'MSP';   Manual = $false },
    @{ Num = 21; Name = 'patch.x64';                  Pattern = 'patch\.x64';                   Mode = 'MSP';   Manual = $false },
    @{ Num = 22; Name = 'MicroStation Update 11';      Pattern = 'microstation.*patch-REV3';       Mode = 'EXE';   Manual = $false }
)

# Arguments silencieux par défaut pour les EXE
$script:DefaultSilentExeArgs = '/S'

# Etat partage avec l'interface : mis a true par le bouton "Annuler"
$script:SuiteCancelRequested = $false

# Compteur de lancements en mode trial (SintegraLidar)
$script:SintegraTrialLaunches = 0

function Test-BentleyModulesExist {
    <#
        Verifie que tous les fichiers de modules Bentley sont presents
        dans le dossier source. Renvoie un hashtable de resultats.
    #>
    param([string]$SourceDir)
    $results = @{}
    if (-not (Test-Path -LiteralPath $SourceDir)) { return $results }
    $files = Get-ChildItem -LiteralPath $SourceDir -File -Force -ErrorAction SilentlyContinue
    foreach ($mod in $script:BentleyModules) {
        $found = $files | Where-Object { $_.Name -imatch $mod.Pattern }
        if ($found) {
            $results[$mod.Num] = $found | Select-Object -First 1
        } else {
            $results[$mod.Num] = $null
        }
    }
    return $results
}

function Invoke-BentleySuiteInstall {
    <#
        Installe les modules Bentley de facon sequentielle.
        Pour les modules manuels (13/14/15), pause jusqu'a ce que l'appelant
        relance avec -ContinueManual.
        -OnProgress : callback (pct, status, moduleIndex, module)
        -Log : callback (message, level)
        -ResumeFrom : numero du module pour reprendre apres une pause manuelle
    #>
    param(
        [string]$SourceDir = $SuiteSourceDir,
        [int]$ResumeFrom = 0,
        [scriptblock]$OnProgress,
        [scriptblock]$Log
    )

    $say = {
        param($m, $l = 'INFO')
        if ($Log) { & $Log $m $l }
    }.GetNewClosure()
    $upd = {
        param($p, $s, $idx, $mod)
        if ($OnProgress) { & $OnProgress $p $s $idx $mod }
    }.GetNewClosure()

    if (-not $SourceDir) {
        throw "Aucun dossier source specifie pour l'installation Bentley Suite."
    }
    if (-not (Test-Path -LiteralPath $SourceDir)) {
        throw "Dossier source introuvable : $SourceDir"
    }

    $total = $script:BentleyModules.Count
    $foundFiles = Test-BentleyModulesExist -SourceDir $SourceDir
    $missing = @()
    foreach ($mod in $script:BentleyModules) {
        if (-not $foundFiles[$mod.Num]) { $missing += $mod.Num }
    }
    if ($missing.Count) {
        & $say ("Modules manquants : " + ($missing -join ', ')) 'ATTENTION'
    }

    $success = 0
    $failed  = @()
    $skipped = @()

    & $upd 0 "Demarrage de l'installation Bentley Suite..." -1 $null

    $i = 0
    foreach ($mod in $script:BentleyModules) {
        if ($script:SuiteCancelRequested) {
            & $say "Installation annulee par l'utilisateur." 'ATTENTION'
            break
        }
        if ($ResumeFrom -gt 0 -and $mod.Num -lt $ResumeFrom) { continue }

        $i++
        $idx = $i - 1
        $pct = [int](($i / $total) * 100)

        $f = $foundFiles[$mod.Num]
        if (-not $f) {
            & $say ("Module {0:D2} - {1} : MANQUANT (ignore)" -f $mod.Num, $mod.Name) 'ERREUR'
            $failed += $mod.Name
            & $upd $pct ("Module {0:D2} manquant" -f $mod.Num) $idx $mod
            continue
        }

        & $upd $pct ("Installation module {0:D2} - {1}" -f $mod.Num, $mod.Name) $idx $mod
        & $say ("Installation module {0:D2} - {1} : {2}" -f $mod.Num, $mod.Name, $f.Name) 'INFO'

        try {
            $exitCode = $null
            switch ($mod.Mode) {
                'MSI' {
                    # msiexec /i <file> /qn /norestart
                    $psi = New-Object System.Diagnostics.ProcessStartInfo
                    $psi.FileName = 'msiexec.exe'
                    $psi.Arguments = "/i `"$($f.FullName)`" /qn /norestart /log `"$env:TEMP\Bentley_$(($mod.Num).ToString('D2'))_$($mod.Name -replace '\s','_').log`" "
                    $psi.UseShellExecute = $false
                    $psi.RedirectStandardOutput = $true
                    $psi.RedirectStandardError = $true
                    $psi.CreateNoWindow = $true
                    $proc = [System.Diagnostics.Process]::Start($psi)
                    $proc.WaitForExit()
                    $exitCode = $proc.ExitCode
                    # Codes 0, 1641 (success + reboot), 3010 (success + reboot required) = succès
                    if ($exitCode -in @(0, 1641, 3010)) {
                        & $say ("Module {0:D2} - {1} : SUCCES (code {2})" -f $mod.Num, $mod.Name, $exitCode) 'OK'
                        $success++
                    } else {
                        & $say ("Module {0:D2} - {1} : ECHEC (code {2})" -f $mod.Num, $mod.Name, $exitCode) 'ERREUR'
                        $failed += $mod.Name
                    }
                }
                'MSP' {
                    # msiexec /p <file> /qn /norestart
                    $psi = New-Object System.Diagnostics.ProcessStartInfo
                    $psi.FileName = 'msiexec.exe'
                    $psi.Arguments = "/p `"$($f.FullName)`" /qn /norestart /log `"$env:TEMP\Bentley_$(($mod.Num).ToString('D2'))_$($mod.Name -replace '\s','_').log`" "
                    $psi.UseShellExecute = $false
                    $psi.RedirectStandardOutput = $true
                    $psi.RedirectStandardError = $true
                    $psi.CreateNoWindow = $true
                    $proc = [System.Diagnostics.Process]::Start($psi)
                    $proc.WaitForExit()
                    $exitCode = $proc.ExitCode
                    if ($exitCode -in @(0, 1641, 3010)) {
                        & $say ("Module {0:D2} - {1} : SUCCES (code {2})" -f $mod.Num, $mod.Name, $exitCode) 'OK'
                        $success++
                    } else {
                        & $say ("Module {0:D2} - {1} : ECHEC (code {2})" -f $mod.Num, $mod.Name, $exitCode) 'ERREUR'
                        $failed += $mod.Name
                    }
                }
                'EXE' {
                    if ($mod.Manual) {
                        # Marquer que l'installation manuelle est requise ; l'appelant
                        # doit inviter l'utilisateur a installer manuellement, puis
                        # relancer avec -ResumeFrom
                        & $say ("Module {0:D2} - {1} : ACTION REQUISE - installation manuelle" -f $mod.Num, $mod.Name) 'ATTENTION'
                        $skipped += $mod.Name
                        & $upd $pct ("Module {0:D2} : action requise" -f $mod.Num) $idx $mod
                        # On ne bloque pas ici - on marque pour resume
                        continue
                    }
                    # EXE silencieux
                    $psi = New-Object System.Diagnostics.ProcessStartInfo
                    $psi.FileName = $f.FullName
                    $psi.Arguments = $script:DefaultSilentExeArgs
                    $psi.UseShellExecute = $true
                    $psi.Verb = 'runas'
                    $proc = [System.Diagnostics.Process]::Start($psi)
                    $proc.WaitForExit()
                    $exitCode = $proc.ExitCode
                    if ($exitCode -eq 0 -or $exitCode -eq 3010) {
                        & $say ("Module {0:D2} - {1} : SUCCES (code {2})" -f $mod.Num, $mod.Name, $exitCode) 'OK'
                        $success++
                    } else {
                        & $say ("Module {0:D2} - {1} : ECHEC (code {2})" -f $mod.Num, $mod.Name, $exitCode) 'ERREUR'
                        $failed += $mod.Name
                    }
                }
            }
        }
        catch {
            & $say ("Module {0:D2} - {1} : ERREUR EXCEPTION - {2}" -f $mod.Num, $mod.Name, $_.Exception.Message) 'ERREUR'
            $failed += $mod.Name
        }
    }

    & $upd 100 "Termine" -1 $null
    return [pscustomobject]@{
        Success      = $failed.Count -eq 0
        TotalModules = $total
        Installed    = $success
        Failed       = $failed
        Skipped      = $skipped
        Cancelled    = $script:SuiteCancelRequested
    }
}
