#Requires -Version 5.1
<#
    Assistant de deploiement Bentley PowerDraft (PC-002) - Sarytany
    ================================================================
    Point d'entree de l'application : declaration des parametres puis
    chargement ordonne des modules du dossier src\.

    Modes :
      -Mode GUI       : interface graphique (defaut, egalement utilise par l'exe)
      -Mode Deploy    : deploiement en ligne de commande, sans interface
      -Mode Configure : configuration reseau / domaine en ligne de commande
      -SelfTest       : recette automatique du deploiement automatique (RunOnce)
      -AutoTest       : recette automatique de l'interface (clique les boutons)

    Modules :
      src\10-Core.ps1               analyse de la ligne de commande, arret, sorties,
                                    assemblies, elevation administrateur
      src\20-Engine-Deployment.ps1  moteur de deploiement PowerDraft + RunOnce
      src\21-Engine-PcConfig.ps1    moteur de configuration reseau / domaine
      src\30-Modes.ps1              modes CLI (SelfTest, Deploy, Configure)
      src\40-Theme.ps1              palette, polices, icone, primitives de dessin
      src\50-Widgets.ps1            controles reutilisables, journal, statut, onglets
      src\55-License.ps1            verrou de licence (ecran d'activation)
      src\60-Shell.ps1              fenetre principale, barre de titre, navigation
      src\70-View-Deployment.ps1    vue "Deploiement Bentley" (cartes + actions)
      src\80-View-PcConfig.ps1      vue "Configuration PC" (cartes + actions)
      src\90-App.ps1                finalisation, rendu, autotest, boucle d'evenements

    Compilation : .\Build-Exe.ps1 assemble ces modules en un script unique puis le
    compile en UN SEUL executable : Install-Bentley-GUI.exe
#>
[CmdletBinding()]
param(
    [ValidateSet('GUI', 'Deploy', 'Configure')][string]$Mode = 'GUI',
    [string]$SourceConfig = 'C:\IT_Config\Bentley',
    [string]$ItStSource   = 'C:\Users\it_st\AppData\Local\Bentley\PowerDraft',
    [string]$DefaultPath  = 'C:\Users\Default\AppData\Local\Bentley\PowerDraft',
    [string]$UsersRoot    = 'C:\Users',
    [switch]$SelfTest,
    [switch]$AutoTest,
    [int]$AutoTestDelay = 700,
    [switch]$NoDialogs,
    [string]$RenderTo,
    [switch]$RenderLicense,
    [ValidateSet('Bentley', 'Pc')][string]$StartTab = 'Bentley',

    # --- Module independant : Configuration PC ---
    [string]$AdapterName,
    [string]$DnsPrimary   = '192.168.1.214',
    [string]$DnsSecondary = '8.8.8.8',
    [string]$ComputerName,
    [string]$DomainName   = 'sarytany.local',
    [string]$DomainUser,
    [string]$DomainPassword,
    [switch]$DryRun
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
. (Join-Path $script:AppRoot 'src\30-Modes.ps1')
. (Join-Path $script:AppRoot 'src\40-Theme.ps1')
. (Join-Path $script:AppRoot 'src\50-Widgets.ps1')
. (Join-Path $script:AppRoot 'src\55-License.ps1')
. (Join-Path $script:AppRoot 'src\60-Shell.ps1')
. (Join-Path $script:AppRoot 'src\70-View-Deployment.ps1')
. (Join-Path $script:AppRoot 'src\80-View-PcConfig.ps1')
. (Join-Path $script:AppRoot 'src\90-App.ps1')
