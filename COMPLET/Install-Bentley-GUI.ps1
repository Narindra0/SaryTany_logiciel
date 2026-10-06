#Requires -Version 5.1
<#\
    Assistant deploiement Sarytany - Sarytany Unified Deployment Assistant
    ====================================================================
    Version unifiee : Configuration PC + Deploiement Bentley PowerDraft
    + Installation Bentley Suite + Integration SintegraLidar
    + Installation Terra (PowerDraft / TerraScan).

    Point d'entree : declaration des parametres puis chargement ordonne
    des modules du dossier src\.

    Modes :
      -Mode GUI       : interface graphique (defaut, egalement utilise par l'exe)
      -Mode Deploy    : deploiement profil PowerDraft en ligne de commande
      -Mode Configure : configuration reseau / domaine en ligne de commande
      -Mode Suite     : installation de la Bentley Suite (21 modules)
      -Mode Sintegra  : integration SintegraLidar
      -SelfTest       : recette automatique du deploiement automatique (RunOnce)

    Modules :
      src\10-Core.ps1               analyse CLI, arret, assemblies, elevation admin
      src\20-Engine-Deployment.ps1  moteur deploiement profil PowerDraft + RunOnce
      src\21-Engine-PcConfig.ps1    moteur configuration reseau / domaine
      src\22-Engine-BentleySuite.ps1 moteur installation Bentley Suite (21 modules)
      src\23-Engine-SintegraLidar.ps1 moteur integration SintegraLidar (7 etapes)
      src\24-Engine-Terra.ps1         moteur installation Terra PowerDraft (6 etapes)
      src\30-Modes.ps1              modes CLI (SelfTest, Deploy, Configure, Suite, Sintegra)
      src\40-Theme.ps1              palette, polices, icone, primitives de dessin
      src\50-Widgets.ps1            controles reutilisables + gabarit "run" (etapes/journal/actions)
      src\55-License.ps1            verrou de licence (ecran d'activation)
      src\60-Shell.ps1              fenetre, bandeau de titre + licence, sidebar dockee, pied de page
      src\70-View-Deployment.ps1    vue "Deploiement Bentley" (cartes + actions)
      src\71-View-BentleySuite.ps1  vue "Installation Bentley Suite" (modules + installer)
      src\72-View-SintegraLidar.ps1 vue "Integration SintegraLidar" (7 etapes)
      src\73-View-Terra.ps1         vue "Installation Terra" (6 etapes + reglages)
      src\80-View-PcConfig.ps1      vue "Configuration PC" (cartes + actions)
      src\90-App.ps1                finalisation, rendu, autotest, boucle d'evenements

    Compilation : .\Build-Exe.ps1 assemble ces modules en un script unique puis le
    compile en UN SEUL executable : Install-Bentley-GUI.exe
#>
[CmdletBinding()]
param(
    [ValidateSet('GUI', 'Deploy', 'Configure', 'Suite', 'Sintegra')][string]$Mode = 'GUI',
    [string]$SourceConfig = 'C:\\IT_Config\\Bentley',
    [string]$ItStSource   = 'C:\\Users\\it_st\\AppData\\Local\\Bentley\\PowerDraft',
    [string]$DefaultPath  = 'C:\\Users\\Default\\AppData\\Local\\Bentley\\PowerDraft',
    [string]$UsersRoot    = 'C:\\Users',
    [switch]$SelfTest,
    [switch]$AutoTest,
    [int]$AutoTestDelay = 700,
    [switch]$NoDialogs,
    [string]$RenderTo,
    [switch]$RenderLicense,
    [ValidateSet('Pc', 'Bentley', 'Suite', 'Sintegra', 'Terra')][string]$StartView = 'Pc',

    # --- Module independant : Configuration PC ---
    [string]$AdapterName,
    [string]$DnsPrimary   = '192.168.1.214',
    [string]$DnsSecondary = '8.8.8.8',
    [string]$ComputerName,
    [string]$DomainName   = 'sarytany.local',
    [string]$DomainUser,
    [string]$DomainPassword,
    [switch]$DryRun,

    # --- Module independant : Bentley Suite ---
    [string]$SuiteSourceDir,

    # --- Module independant : SintegraLidar ---
    [string]$SintegraSourceDir,
    [string]$SintegraDestDir,
    [int]$TrialMaxLaunches = 3,

    # --- Module independant : Installation Terra ---
    [string]$TerraSourceDir
)

# Racine du projet : sert aux modules a retrouver app.ico.
$script:AppRoot = "$PSScriptRoot"
if (-not $script:AppRoot) { $script:AppRoot = "$((Get-Location).Path)" }

# Chemin du .ps1 racine (nul dans l'executable) : necessaire a l'auto-elevation.
$script:AppEntry = "$PSCommandPath"

# Chargement des modules. Ces lignes doivent rester ecrites exactement ainsi :
# Build-Exe.ps1 les reconnait pour assembler l'executable en un seul fichier.
. (Join-Path $script:AppRoot 'src\10-Core.ps1')
. (Join-Path $script:AppRoot 'src\20-Engine-Deployment.ps1')
. (Join-Path $script:AppRoot 'src\21-Engine-PcConfig.ps1')
. (Join-Path $script:AppRoot 'src\22-Engine-BentleySuite.ps1')
. (Join-Path $script:AppRoot 'src\23-Engine-SintegraLidar.ps1')
. (Join-Path $script:AppRoot 'src\24-Engine-Terra.ps1')
. (Join-Path $script:AppRoot 'src\30-Modes.ps1')
. (Join-Path $script:AppRoot 'src\40-Theme.ps1')
. (Join-Path $script:AppRoot 'src\50-Widgets.ps1')
. (Join-Path $script:AppRoot 'src\55-License.ps1')
. (Join-Path $script:AppRoot 'src\60-Shell.ps1')
. (Join-Path $script:AppRoot 'src\70-View-Deployment.ps1')
. (Join-Path $script:AppRoot 'src\71-View-BentleySuite.ps1')
. (Join-Path $script:AppRoot 'src\72-View-SintegraLidar.ps1')
. (Join-Path $script:AppRoot 'src\73-View-Terra.ps1')
. (Join-Path $script:AppRoot 'src\80-View-PcConfig.ps1')
. (Join-Path $script:AppRoot 'src\90-App.ps1')
