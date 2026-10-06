# ==================================================================
# src\90-App.ps1  -  Finalisation et demarrage de l'application
#   Garde de fermeture (operation en cours), licence affichee dans le
#   bandeau de titre, messages initiaux dans les journaux, activation
#   de la vue de depart, rendu image (-RenderTo) et recette
#   automatique (-AutoTest), puis boucle d'evenements modale.
# Depend de : src\60-Shell.ps1 ($form, $script:LblLicense, Show-View),
#            src\70/71/72/73/80 (boutons et journaux par vue),
#            src\55-License.ps1 ($script:LicenseValidated / Codes).
# ==================================================================

# --- 1. Garde de fermeture : refuser si une operation est en cours ---
# Une operation est en cours si le bouton principal de la vue active
# est desactive (Set-UiStatus le desactive quand -Running $true).
$form.Add_FormClosing({
    param($s, $e)
    $busy = $false
    if ($btnRun        -and -not $btnRun.Enabled)        { $busy = $true }
    if ($btnSuiteStart -and -not $btnSuiteStart.Enabled) { $busy = $true }
    if ($btnSinStart   -and -not $btnSinStart.Enabled)   { $busy = $true }
    if ($btnTerraStart -and -not $btnTerraStart.Enabled) { $busy = $true }
    if ($btnApplyNet   -and -not $btnApplyNet.Enabled)   { $busy = $true }
    if ($btnJoin       -and -not $btnJoin.Enabled)       { $busy = $true }
    if ($busy) { $e.Cancel = $true }
})

# --- 2. Licence dans le bandeau de titre ---
if ($script:LicenseValidated -and $script:LicenseCodes.ContainsKey('ICECREAM')) {
    $script:LblLicense.Text = "Licence : $($script:LicenseCodes['ICECREAM'].Label)"
    $script:LblLicense.ForeColor = [System.Drawing.Color]::FromArgb(110, 231, 183)
} elseif ($script:LicenseValidated) {
    $script:LblLicense.Text = 'Licence : Bentley CONNECT'
    $script:LblLicense.ForeColor = [System.Drawing.Color]::FromArgb(110, 231, 183)
} else {
    $script:LblLicense.Text = 'Licence : verrouillee'
    $script:LblLicense.ForeColor = $script:C_Red
}

# --- 3. Messages de log initiaux dans TOUTES les vues ---
# Les vues ecrivent deja leur message de bienvenue ; celui-ci confirme
# le demarrage de l'assistant et l'etat de la licence.
$initMsg = 'Assistant Sarytany Neo-Carbon v2.0.0.0 - prete.'
$allLogs = @($textBoxLog, $textBoxSuiteLog, $textBoxSinLog, $textBoxTerraLog, $pcLog.Box)
foreach ($lb in $allLogs) { Write-UiLog -Box $lb -Message $initMsg }

if ($script:LicenseValidated) {
    $licMsg = "Licence validee ($($script:LicenseLevel)) - acces debloque."
    foreach ($lb in $allLogs) { Write-UiLog -Box $lb -Message $licMsg -Level 'OK' }
}

# --- 4. Vue de depart + libelle du pied de page ---
Show-View $StartView

# --- 5. Rendu de l'interface vers un fichier image (sans afficher) ---
if ($RenderTo) {
    $form.StartPosition = 'Manual'
    $form.Location      = New-Object System.Drawing.Point(-4000, -4000)
    # Vide la file des finaliseurs AVANT la premiere peinture complete :
    # la finalisation concurrente d'objets GDI+ (GraphicsPath, Region)
    # pendant le DrawToBitmap pouvait contenter le verrou GDI+ et bloquer
    # l'application de facon aleatoire.
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
    $form.Show()
    $form.Update()
    Start-Sleep -Milliseconds 400

    # DrawToBitmap livre la FENETRE (barre de titre OS incluse) : on capte
    # tout puis on recadre sur la zone cliente pour un rendu fidele.
    $fw = $form.Width; $fh = $form.Height
    $full = New-Object System.Drawing.Bitmap $fw, $fh
    $form.DrawToBitmap($full, (New-Object System.Drawing.Rectangle(0, 0, $fw, $fh)))
    $cx = [int](($fw - $form.ClientSize.Width) / 2)
    $cy = $fh - $form.ClientSize.Height - $cx
    $cropRect = New-Object System.Drawing.Rectangle($cx, $cy, $form.ClientSize.Width, $form.ClientSize.Height)
    $bmp = $full.Clone($cropRect, $full.PixelFormat)
    $bmp.Save($RenderTo, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose(); $full.Dispose()
    $form.Close()
    $form.Dispose()
    Write-Out "RENDER OK : $RenderTo"
    Stop-App 0
}

# --- 6. Recette automatique (developpement) ---
# Parcourt les 5 vues et declenche les actions principales.
# Les etapes Suite/Sintegra/Terra ne demarrent l'installation que si un
# dossier source valide a ete fourni via -SuiteSourceDir /
# -SintegraSourceDir / -TerraSourceDir ; sinon elles sont simplement sautees.
if ($AutoTest) {
    if ($env:BENTLEY_DEBUG) {
        "AUTOTEST demarre Delay=$AutoTestDelay" | Add-Content -Path "$env:TEMP\bentley_debug.txt" -Encoding UTF8
    }

    $script:stepCount = 0
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = $AutoTestDelay
    $timer.Add_Tick({
        $script:stepCount++
        switch ($script:stepCount) {
            # --- Vue Bentley (Deploiement) ---
            1 { $btnGpo.PerformClick() }
            2 { $btnRun.PerformClick() }

            # --- Vue Configuration PC (mode simulation) ---
            3 { Activate-Module -Which 'Pc'; $chkSim.Checked = $true }
            4 { $btnApplyNet.PerformClick() }
            5 { $btnJoin.PerformClick() }

            # --- Vue Bentley Suite ---
            6 { Activate-Module -Which 'Suite' }
            7 {
                if ($SuiteSourceDir -and (Test-Path -LiteralPath $SuiteSourceDir)) {
                    $btnSuiteStart.PerformClick()
                } else {
                    Write-Out "[AUTOTEST] -SuiteSourceDir non disponible, etape 7 sautee" -ForegroundColor DarkGray
                }
            }

            # --- Vue SintegraLidar ---
            8 { Activate-Module -Which 'Sintegra' }
            9 {
                if ($SintegraSourceDir -and (Test-Path -LiteralPath $SintegraSourceDir)) {
                    $btnSinStart.PerformClick()
                } else {
                    Write-Out "[AUTOTEST] -SintegraSourceDir non disponible, etape 9 sautee" -ForegroundColor DarkGray
                }
            }

            # --- Vue Installation Terra ---
            10 { Activate-Module -Which 'Terra' }
            11 {
                if ($TerraSourceDir -and (Test-Path -LiteralPath $TerraSourceDir)) {
                    $btnTerraStart.PerformClick()
                } else {
                    Write-Out "[AUTOTEST] -TerraSourceDir non disponible, etape 11 sautee" -ForegroundColor DarkGray
                }
            }

            # --- Fin ---
            12 { $timer.Stop(); $form.Close() }
        }
    })
    $timer.Start()
    [void]$form.ShowDialog()
    $timer.Stop()
    $timer.Dispose()

    Write-Out "AUTOTEST termine - etapes declenchees : $($script:stepCount)" -ForegroundColor Cyan
    Write-Out 'AUTOTEST journal Bentley PowerDraft   :' -ForegroundColor DarkGray
    Write-Out $textBoxLog.Text -ForegroundColor DarkGray
    Write-Out 'AUTOTEST journal Bentley Suite       :' -ForegroundColor DarkGray
    Write-Out $textBoxSuiteLog.Text -ForegroundColor DarkGray
    Write-Out 'AUTOTEST journal SintegraLidar       :' -ForegroundColor DarkGray
    Write-Out $textBoxSinLog.Text -ForegroundColor DarkGray
    Write-Out 'AUTOTEST journal Installation Terra  :' -ForegroundColor DarkGray
    Write-Out $textBoxTerraLog.Text -ForegroundColor DarkGray
    Write-Out 'AUTOTEST journal Configuration PC    :' -ForegroundColor DarkGray
    Write-Out $pcLog.Box.Text -ForegroundColor DarkGray
    Stop-App 0
}

# --- 7. Boucle d'evenements modale ---
[void]$form.ShowDialog()
