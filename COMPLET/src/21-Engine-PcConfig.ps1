# ==================================================================
# src\21-Engine-PcConfig.ps1  -  Moteur de configuration PC
#   Etape 1 : desactivation IPv6 + serveurs DNS sur une carte reseau.
#   Etape 2 : renommage du poste et jonction au domaine Active Directory.
#   Verifications prealables : etat de jonction AD (Get-PcDomainStatus)
#   et joignabilite des serveurs DNS (Test-PcDnsConnectivity).
#   Configuration systeme : etat des protections (Get-PcProtectionsState),
#   desactivation AUTOMATIQUE avant installation (Disable-PcInstallProtections,
#   best effort, ne bloque jamais) et reactivation manuelle (Enable-PcProtections).
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

# ================= VERIFICATIONS PREALABLES =================
function Get-PcDomainStatus {
    <#
        Lit l'etat de jonction Active Directory du poste (lecture seule).
        Retourne une hashtable @{ Joined; Domain; Name; Error }.
        En workgroup, Win32_ComputerSystem.Domain contient le nom du
        groupe de travail : on le normalise a chaine vide pour garder
        une lecture "domaine AD" fiable.
    #>
    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $joined = [bool]$cs.PartOfDomain
        $dom = "$($cs.Domain)".Trim()
        if (-not $joined) { $dom = '' }
        return @{ Joined = $joined; Domain = $dom; Name = "$($cs.Name)".Trim(); Error = '' }
    }
    catch {
        return @{ Joined = $false; Domain = ''; Name = $env:COMPUTERNAME; Error = "$($_.Exception.Message)" }
    }
}

function Test-PcDnsConnectivity {
    <#
        Teste la joignabilite de chaque serveur DNS en resolvant un nom
        de test. Un echec est relance sur la racine '.' : si la racine
        repond, le serveur est joignable mais le nom est introuvable.
        Retourne @{ Ok; Results = @( @{Server; Ok; Ms; Detail} ) }.
    #>
    param(
        [string[]]$Servers,
        [string]$TestName
    )
    if (-not $Servers) { $Servers = @($DnsPrimary, $DnsSecondary) | Where-Object { $_ } }
    $Servers = @($Servers | Where-Object { "$_".Trim() } | ForEach-Object { "$_".Trim() })
    if ($Servers.Count -eq 0) { return @{ Ok = $false; Results = @() } }
    if (-not $TestName) { $TestName = $DomainName }
    if (-not $TestName) { $TestName = 'microsoft.com' }
    $hasResolve = [bool](Get-Command Resolve-DnsName -ErrorAction SilentlyContinue)
    # Certains builds n'exposent pas -Timeout sur Resolve-DnsName : on le detecte une fois.
    $timeoutSplat = @{}
    if ($hasResolve -and (Get-Command Resolve-DnsName).Parameters.ContainsKey('Timeout')) {
        $timeoutSplat = @{ Timeout = 2 }
    }

    $allOk = $true
    $results = @()
    foreach ($srv in $Servers) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $ok = $false
        $detail = ''
        try {
            if ($hasResolve) {
                $null = Resolve-DnsName -Name $TestName -Server $srv -DnsOnly @timeoutSplat -ErrorAction Stop
            } else {
                # Repli .NET (resout via la configuration systeme, pas via $srv)
                $null = [System.Net.Dns]::GetHostAddresses($TestName)
            }
            $ok = $true
            $detail = "'$TestName' resolu"
        }
        catch {
            if ($hasResolve) {
                try {
                    # La racine repond -> serveur joignable, nom de test introuvable
                    $null = Resolve-DnsName -Name '.' -Server $srv -DnsOnly @timeoutSplat -ErrorAction Stop
                    $ok = $true
                    $detail = "joignable ('$TestName' introuvable)"
                }
                catch {
                    $ok = $false
                    $detail = 'serveur injoignable'
                }
            } else {
                $ok = $false
                $detail = "$($_.Exception.Message)"
            }
        }
        $sw.Stop()
        if (-not $ok) { $allOk = $false }
        $results += [pscustomobject]@{ Server = $srv; Ok = $ok; Ms = [int]$sw.ElapsedMilliseconds; Detail = $detail }
    }
    return @{ Ok = $allOk; Results = $results }
}

# ================= CONFIGURATION SYSTEME : PROTECTIONS =================
function Get-PcProtectionsState {
    <#
        Lecture seule de l'etat des protections : protection en arriere-plan
        Defender ($null si illisible, par exemple antivirus tiers) et profils
        pare-feu encore actifs. Retourne @{ DefenderOn; FirewallOn; Error }.
    #>
    $out = @{ DefenderOn = $null; FirewallOn = @(); Error = '' }
    try { $out.DefenderOn = [bool](Get-MpComputerStatus -ErrorAction Stop).RealTimeProtectionEnabled } catch { $out.DefenderOn = $null }
    try {
        $out.FirewallOn = @(Get-NetFirewallProfile -ErrorAction Stop | Where-Object { $_.Enabled } | ForEach-Object { $_.Name })
    } catch { $out.Error = "$($_.Exception.Message)" }
    return $out
}

function Disable-PcInstallProtections {
    <#
        Desactivation AUTOMATIQUE et de meilleure grace (best effort) avant
        une installation : protection en arriere-plan Defender + pare-feu
        Windows. Ne leve jamais d'exception : en cas d'echec (Tamper
        Protection, droits insuffisants), une ATTENTION est journalisee et
        l'installation se poursuit. Deja desactive = aucune commande.
    #>
    param([switch]$Simulate, [scriptblock]$Log)
    $say = {
        param($m, $l = 'INFO')
        if ($Log) { & $Log $m $l } else { Write-Out ("[{0}] {1}" -f $l, $m) $l }
    }.GetNewClosure()

    & $say "--- Protections : desactivation automatique pre-installation ---" 'INFO'

    # --- Protection en arriere-plan (Defender) ---
    try {
        $st = Get-PcProtectionsState
        if ($null -eq $st.DefenderOn) {
            & $say "Windows Defender illisible (antivirus tiers ?) : rien a desactiver ici." 'INFO'
        } elseif (-not $st.DefenderOn) {
            & $say "Protection en arriere-plan deja desactivee." 'INFO'
        } else {
            Invoke-PcStep -Label "Desactivation de la protection en arriere-plan" `
                          -Command "Set-MpPreference -DisableRealtimeMonitoring `$true" `
                          -Simulate:$Simulate -Log $Log `
                          -Action { Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction Stop } | Out-Null
            if ($Simulate) {
                & $say "Simulation : la protection en arriere-plan serait desactivee." 'ATTENTION'
            } else {
                $still = $true
                try { $still = [bool](Get-MpComputerStatus -ErrorAction Stop).RealTimeProtectionEnabled } catch {}
                if ($still) { & $say "Defender reste actif (Tamper Protection ?) : l'installation continue malgre tout." 'ATTENTION' }
                else { & $say "Protection en arriere-plan desactivee pour l'installation." 'OK' }
            }
        }

        # --- Pare-feu Windows ---
        if ($st.FirewallOn.Count -eq 0 -and -not $st.Error) {
            & $say "Pare-feu Windows deja desactive." 'INFO'
        } else {
            Invoke-PcStep -Label "Desactivation du pare-feu Windows (Domaine, Public, Prive)" `
                          -Command "Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False" `
                          -Simulate:$Simulate -Log $Log `
                          -Action {
                              try {
                                  Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False -ErrorAction Stop
                              }
                              catch {
                                  $null = & netsh advfirewall set allprofiles state off
                                  if ($LASTEXITCODE -ne 0) { throw "netsh advfirewall a echoue (code $LASTEXITCODE)." }
                              }
                          } | Out-Null
            if ($Simulate) {
                & $say "Simulation : le pare-feu Windows serait desactive." 'ATTENTION'
            } else {
                $stillOn = @('?')
                try { $stillOn = @(Get-NetFirewallProfile -ErrorAction Stop | Where-Object { $_.Enabled } | ForEach-Object { $_.Name }) } catch {}
                if ($stillOn.Count -eq 0) { & $say "Pare-feu Windows desactive pour l'installation." 'OK' }
                else { & $say ("Pare-feu encore actif sur : {0} : l'installation continue malgre tout." -f ($stillOn -join ', ')) 'ATTENTION' }
            }
        }
    }
    catch {
        & $say ("Protections : erreur inattendue ({0}) : l'installation continue." -f $_.Exception.Message) 'ATTENTION'
    }
    return $true
}

function Enable-PcProtections {
    <#
        Reactivation manuelle des protections apres le deploiement :
        protection en arriere-plan Defender + pare-feu Windows.
        Retourne @{ Defender; Firewall; Ok } (booleens = reactive reel).
    #>
    param([switch]$Simulate, [scriptblock]$Log)
    $say = {
        param($m, $l = 'INFO')
        if ($Log) { & $Log $m $l } else { Write-Out ("[{0}] {1}" -f $l, $m) $l }
    }.GetNewClosure()

    $res = @{ Defender = $false; Firewall = $false; Ok = $true }

    Invoke-PcStep -Label "Reactivation de la protection en arriere-plan" `
                  -Command "Set-MpPreference -DisableRealtimeMonitoring `$false" `
                  -Simulate:$Simulate -Log $Log `
                  -Action { Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop } | Out-Null
    if ($Simulate) {
        & $say "Simulation : protections laissees telles quelles." 'ATTENTION'
        return $res
    }
    try {
        $on = [bool](Get-MpComputerStatus -ErrorAction Stop).RealTimeProtectionEnabled
        if ($on) { & $say "Protection en arriere-plan reactivee." 'OK'; $res.Defender = $true }
        else { $res.Ok = $false; & $say "La protection en arriere-plan n'a pas pu etre reactivee (Tamper Protection ?)." 'ERREUR' }
    } catch {
        $res.Ok = $false
        & $say "Reactivation Defender non verifiable : service indisponible." 'ERREUR'
    }

    Invoke-PcStep -Label "Reactivation du pare-feu Windows (Domaine, Public, Prive)" `
                  -Command "Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True" `
                  -Simulate:$Simulate -Log $Log `
                  -Action {
                      try {
                          Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True -ErrorAction Stop
                      }
                      catch {
                          $null = & netsh advfirewall set allprofiles state on
                          if ($LASTEXITCODE -ne 0) { throw "netsh advfirewall a echoue (code $LASTEXITCODE)." }
                      }
                  } | Out-Null
    $stillOn = $null
    try { $stillOn = @(Get-NetFirewallProfile -ErrorAction Stop | Where-Object { -not $_.Enabled } | ForEach-Object { $_.Name }) } catch {}
    if ($null -eq $stillOn) {
        $res.Ok = $false
        & $say "Etat du pare-feu non verifiable apres reactivation." 'ERREUR'
    } elseif ($stillOn.Count -eq 0) {
        & $say "Pare-feu Windows reactive (Domaine, Public, Prive)." 'OK'
        $res.Firewall = $true
    } else {
        $res.Ok = $false
        & $say ("Pare-feu toujours inactif sur : {0}." -f ($stillOn -join ', ')) 'ERREUR'
    }
    return $res
}
