<#
==============================================================================
 PowerDraft / Terra - Assistant d'installation et de configuration
------------------------------------------------------------------------------
 Point d'entree du mode developpement : charge les modules de src/ puis
 affiche l'interface. Ce fichier sert aussi de tete au script unique
 genere dans build/ par build.ps1.

 developpement : .\main.ps1
 production     : .\..\dist\PowerDraft-Setup.exe
==============================================================================
#>

param()

# --- Prerequis Windows Forms ---
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# --- Version (injectee par build.ps1 en production) ---
$script:AppVersion = '1.0.0'

# --- Chargement ordonne des modules ---
$root = $PSScriptRoot
$modules = @(
    '01-Config.ps1'
    '02-Helpers.ps1'
    '03-Steps.ps1'
    '04-Orchestration.ps1'
    '05-UI.ps1'
)

foreach ($m in $modules) {
    $path = Join-Path $root $m
    if (-not (Test-Path $path)) {
        throw "Module introuvable : $path"
    }
    . $path
}

# --- Lancement (activation -> dossier Terra -> fenetre principale) ---
Start-Application