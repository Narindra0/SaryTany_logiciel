# ==================================================================
# src\90-App.ps1  -  Finalisation et demarrage
#   Etat initial de l'interface, rendu image (-RenderTo), recette
#   automatique (-AutoTest) puis boucle d'evenements de la fenetre.
# Depend de : toutes les vues (70 et 80) et le shell (60).
# ==================================================================

$form.Add_FormClosing({ param($s, $e) if ($btnRun.Enabled -eq $false) { $e.Cancel = $true } })

if ($script:LicenseValidated) { Write-Log "Licence validee - acces debloque." 'OK' }
Write-Log "Assistant pret. Aucune action n'a encore ete effectuee."
Set-State -Running $false -Status "Pret" -Detail "Choisissez une action pour commencer." -Percent 0 -PillText 'EN ATTENTE' -PillColor $script:C_Muted

# --- Rendu de l'interface vers un fichier image (sans afficher de fenetre) ---
if ($RenderTo) {
    # Affichage hors ecran (necessaire pour creer les handles des controles) puis rendu.
    $form.StartPosition = 'Manual'
    $form.Location = New-Object System.Drawing.Point(-4000, -4000)
    $form.Show()
    $form.Update()
    Start-Sleep -Milliseconds 400

    $bmp = New-Object System.Drawing.Bitmap $form.ClientSize.Width, $form.ClientSize.Height
    $form.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $bmp.Width, $bmp.Height)))
    $bmp.Save($RenderTo, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    $form.Close()
    $form.Dispose()
    Write-Out "RENDER OK : $RenderTo"
    Stop-App 0
}

# --- Recette automatique (developpement) ---
if ($AutoTest) {
    $script:stepCount = 0
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = $AutoTestDelay
    $timer.Add_Tick({
        $script:stepCount++
        switch ($script:stepCount) {
            1 { $btnGpo.PerformClick() }
            2 { $btnRun.PerformClick() }
            3 { Activate-Module -Which 'Pc'; $chkSim.Checked = $true }
            4 { $btnApplyNet.PerformClick() }
            5 { $btnJoin.PerformClick() }
            6 { $timer.Stop(); $form.Close() }
        }
    })
    $timer.Start()
    [void]$form.ShowDialog()
    $timer.Stop()
    Write-Out "AUTOTEST termine - etapes declenchees : $($script:stepCount)" -ForegroundColor Cyan
    Write-Out "AUTOTEST journal Bentley :`r`n$($textBoxLog.Text)" -ForegroundColor DarkGray
    Write-Out "AUTOTEST journal Configuration PC :`r`n$($pcLog.Box.Text)" -ForegroundColor DarkGray
    Stop-App 0
}

[void]$form.ShowDialog()
