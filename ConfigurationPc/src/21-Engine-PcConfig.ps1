# ==================================================================
# src\21-Engine-PcConfig.ps1  -  Moteur de configuration PC
#   Etape 1 : desactivation IPv6 + serveurs DNS sur une carte reseau.
#   Etape 2 : renommage du poste et jonction au domaine Active Directory.
#   Module independant du deploiement Bentley (etat separes), avec
#   support du mode simulation (-DryRun) et d'un journal externe.
# Depend de : $DnsPrimary, $DnsSecondary, $DomainName (parametres)
# ==================================================================
function Get-PcAdapters {
    @(Get-NetAdapter -ErrorAction SilentlyContinue |
        Where-Object { $_.HardwareInterface } |
        Sort-Object Status, Name |
        ForEach-Object {
            [pscustomobject]@{
                Name  = $_.Name
                Status = "$($_.Status)"
                Index = $_.InterfaceIndex
                Desc  = $_.InterfaceDescription
            }
        })
}

function Invoke-PcStep {
    # Execute une commande de configuration, ou l'affiche seulement en mode simulation
    param([string]$Label, [string]$Command, [scriptblock]$Action, [switch]$Simulate, [scriptblock]$Log, [string]$Level = 'INFO')
    if ($Log) {
        if ($Simulate) { & $Log ("[SIMULATION] {0} -> {1}" -f $Label, $Command) 'ATTENTION' }
        else { & $Log ("{0} -> {1}" -f $Label, $Command) $Level }
    }
    if ($Simulate) { return $null }
    return (& $Action)
}

function Set-AdapterNetwork {
    <#
        Etape 1 : desactive IPv6 et configure les DNS d'une carte reseau.
    #>
    param(
        [string]$AdapterName,
        [string]$DnsPrimary   = '192.168.1.214',
        [string]$DnsSecondary = '8.8.8.8',
        [switch]$DisableIPv6 = $true,
        [switch]$ValidateUponExit = $true,
        [switch]$Simulate,
        [scriptblock]$Log
    )
    $say = {
        param($m, $l = 'INFO')
        if ($Log) { & $Log $m $l } else { Write-Out ("[{0}] {1}" -f $l, $m) $l }
    }.GetNewClosure()

    if (-not $AdapterName) { throw "Aucune carte reseau selectionnee." }
    $adapter = Get-NetAdapter -Name $AdapterName -ErrorAction SilentlyContinue
    if (-not $adapter -and -not $Simulate) { throw "Carte reseau introuvable : $AdapterName" }

    if ($DisableIPv6) {
        Invoke-PcStep -Label "Desactivation IPv6 sur '$AdapterName'" `
                      -Command "Disable-NetAdapterBinding -Name '$AdapterName' -ComponentID ms_tcpip6" `
                      -Simulate:$Simulate -Log $Log `
                      -Action { Disable-NetAdapterBinding -Name $AdapterName -ComponentID ms_tcpip6 -ErrorAction Stop } | Out-Null
        & $say "IPv6 desactive sur '$AdapterName'." 'OK'
    }

    Invoke-PcStep -Label "Serveurs DNS sur '$AdapterName'" `
                  -Command ("Set-DnsClientServerAddress -InterfaceAlias '{0}' -ServerAddresses {1}, {2}" -f $AdapterName, $DnsPrimary, $DnsSecondary) `
                  -Simulate:$Simulate -Log $Log `
                  -Action { Set-DnsClientServerAddress -InterfaceAlias $AdapterName -ServerAddresses @($DnsPrimary, $DnsSecondary) -ErrorAction Stop } | Out-Null
    & $say ("DNS configures : {0} (prefere), {1} (auxiliaire)." -f $DnsPrimary, $DnsSecondary) 'OK'

    if ($ValidateUponExit -and $adapter) {
        $guid = "$($adapter.InterfaceGuid)"
        if ($guid -notmatch '^\{') { $guid = "{$guid}" }
        $key = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$guid"
        Invoke-PcStep -Label "Option 'Valider les parametres en quittant'" `
                      -Command ("New-ItemProperty -Path '{0}' -Name ValidateSettingsUponExit -Value 1" -f $key) `
                      -Simulate:$Simulate -Log $Log `
                      -Action {
                          if (-not (Test-Path -LiteralPath $key)) { New-Item -Path $key -Force | Out-Null }
                          New-ItemProperty -Path $key -Name 'ValidateSettingsUponExit' -Value 1 -PropertyType DWord -Force | Out-Null
                      } | Out-Null
        & $say "Option 'Valider les parametres en quittant' activee." 'OK'
    }

    if (-not $Simulate) {
        $ipv6 = (Get-NetAdapterBinding -Name $AdapterName -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue).Enabled
        $dns  = (Get-DnsClientServerAddress -InterfaceAlias $AdapterName -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses
        & $say ("Controle : IPv6 actif = {0} ; DNS = {1}" -f $ipv6, ($dns -join ', ')) 'INFO'
    }
    return $true
}

function Invoke-PcDomainJoin {
    <#
        Etape 2 : renomme le poste et le joint au domaine Active Directory.
        Redemarrage volontairement non automatique (= "Redemarrer ulterieurement").
    #>
    param(
        [string]$ComputerName,
        [string]$DomainName = 'sarytany.local',
        [string]$DomainUser,
        [string]$DomainPassword,
        [switch]$Simulate,
        [scriptblock]$Log
    )
    $say = {
        param($m, $l = 'INFO')
        if ($Log) { & $Log $m $l } else { Write-Out ("[{0}] {1}" -f $l, $m) $l }
    }.GetNewClosure()

    if (-not $ComputerName) { throw "Le nom du poste est obligatoire." }
    if ($ComputerName -notmatch '^[A-Za-z0-9-]{1,15}$') { throw "Nom de poste invalide (15 caracteres max, lettres/chiffres/tiret) : $ComputerName" }
    if (-not $DomainName) { throw "Le nom de domaine est obligatoire." }
    if (-not $DomainUser) { throw "Le compte du domaine est obligatoire (ex. SARYTANY\administrateur)." }
    if (-not $DomainPassword) { throw "Le mot de passe du domaine est obligatoire." }

    $current = (Get-CimInstance Win32_ComputerSystem).Domain
    & $say ("Domaine actuel : {0}  |  poste : {1}" -f $current, $env:COMPUTERNAME) 'INFO'
    if ($current -eq $DomainName) { & $say "Le poste est deja membre de $DomainName (l'operation reste possible pour renommer)." 'ATTENTION' }

    $securePwd = ConvertTo-SecureString $DomainPassword -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential($DomainUser, $securePwd)
    $user = ($DomainUser -split '\\')[-1]

    Invoke-PcStep -Label "Renommage et jonction au domaine" `
                  -Command ("Add-Computer -DomainName {0} -NewName {1} -Credential {2} -Restart:`$false" -f $DomainName, $ComputerName, $user) `
                  -Simulate:$Simulate -Log $Log `
                  -Action { Add-Computer -DomainName $DomainName -NewName $ComputerName -Credential $cred -Restart:$false -Force -ErrorAction Stop } | Out-Null

    if ($Simulate) {
        & $say "Simulation : aucune modification n'a ete appliquee." 'ATTENTION'
        return $true
    }
    $cs = Get-CimInstance Win32_ComputerSystem
    & $say ("Controle : nom = {0} ; domaine = {1} ; membre = {2}" -f $cs.Name, $cs.Domain, $cs.PartOfDomain) 'OK'
    if ($cs.Domain -ne $DomainName) { throw "La jonction n'a pas abouti (domaine actuel : $($cs.Domain))." }
    & $say "Redemarrage requis pour finaliser (volontairement reporte)." 'ATTENTION'
    return $true
}
