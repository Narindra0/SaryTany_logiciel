using System;
using System.Diagnostics;
using System.Globalization;
using System.Linq;
using System.Management;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.Win32;

namespace SarytanyAssistant.Engines;

/// <summary>
/// Carte reseau physique (port du [pscustomobject] renvoye par Get-PcAdapters).
/// Guid = GUID d'interface (utile pour les cles registre Tcpip / Tcpip6).
/// </summary>
public sealed class PcAdapterInfo
{
    public string Name { get; init; } = string.Empty;
    public string Status { get; init; } = string.Empty;
    public int Index { get; init; }
    public string Description { get; init; } = string.Empty;
    public string Guid { get; init; } = string.Empty;
    public string MacAddress { get; init; } = string.Empty;
}

/// <summary>Port de la hashtable @{ Joined; Domain; Name; Error } de Get-PcDomainStatus.</summary>
public sealed class PcDomainStatus
{
    public bool Joined { get; init; }
    public string Domain { get; init; } = string.Empty;
    public string Name { get; init; } = string.Empty;
    public string Error { get; init; } = string.Empty;
}

/// <summary>Port de @{ Server; Ok; Ms; Detail } (un resultat par serveur DNS teste).</summary>
public sealed class DnsProbeResult
{
    public string Server { get; init; } = string.Empty;
    public bool Ok { get; init; }
    public int Ms { get; init; }
    public string Detail { get; init; } = string.Empty;
}

/// <summary>Port de @{ Ok; Results = @(...) } de Test-PcDnsConnectivity.</summary>
public sealed class PcDnsTestResult
{
    public bool Ok { get; init; }
    public List<DnsProbeResult> Results { get; init; } = new();
}

/// <summary>Port de @{ DefenderOn; FirewallOn; Error } de Get-PcProtectionsState.</summary>
public sealed class PcProtectionsState
{
    /// <summary>null = illisible (antivirus tiers, service Defender indisponible).</summary>
    public bool? DefenderOn { get; set; }
    public List<string> FirewallOn { get; set; } = new();
    public string Error { get; set; } = string.Empty;
}

/// <summary>Port de @{ Defender; Firewall; Ok } de Enable-PcProtections.</summary>
public sealed class PcProtectionsResult
{
    public bool Defender { get; set; }
    public bool Firewall { get; set; }
    public bool Ok { get; set; } = true;
}

/// <summary>
/// Port C# de src\21-Engine-PcConfig.ps1 (moteur de configuration PC) :
///  - Etape 1 : desactivation IPv6 + serveurs DNS sur une carte reseau.
///  - Etape 2 : renommage du poste et jonction au domaine Active Directory.
///  - Verifications prealables : etat de jonction AD (GetDomainStatus) et
///    joignabilite des serveurs DNS (TestDnsConnectivity).
///  - Protections : etat (GetProtectionsState), desactivation automatique
///    pre-installation (DisableInstallProtections, best effort, ne bloque
///    jamais) et reactivation manuelle (EnableProtections).
/// Le moteur ne touche jamais l'interface : il journalise via LogHandler
/// (levels INFO / OK / ERREUR / ATTENTION) comme le script PowerShell.
/// simulate = -DryRun : journalise la commande qui SERAIT lancee, ne modifie rien.
/// </summary>
public class PcConfigEngine : IEngine
{
    // Valeurs par defaut identiques au script PowerShell.
    public const string DefaultDnsPrimary = "192.168.1.214";
    public const string DefaultDnsSecondary = "8.8.8.8";
    public const string DefaultDomainName = "sarytany.local";

    private const string TcpIpInterfacesKey =
        @"SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces";
    private const string TcpIp6InterfacesKey =
        @"SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\Interfaces";
    private const string FirewallPolicyKey =
        @"SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy";
    private const string DefenderPolicyKey =
        @"SOFTWARE\Policies\Microsoft\Windows Defender";

    private static readonly Regex ComputerNamePattern =
        new("^[A-Za-z0-9-]{1,15}$", RegexOptions.Compiled);

    // Cle du registre pare-feu -> nom expose par Get-NetFirewallProfile.
    private static readonly (string RegKey, string ProfileName)[] FirewallProfiles =
    {
        ("DomainProfile", "Domain"),
        ("StandardProfile", "Private"),
        ("PublicProfile", "Public"),
    };

    // ================= OUTILS INTERNES =================

    /// <summary>Execute une commande de configuration, ou l'affiche seulement en mode simulation.</summary>
    private static object? InvokePcStep(
        string label,
        string command,
        Func<object?> action,
        bool simulate,
        LogHandler? log,
        string level = "INFO")
    {
        if (log != null)
        {
            if (simulate)
                log($"[SIMULATION] {label} -> {command}", "ATTENTION");
            else
                log($"{label} -> {command}", level);
        }
        if (simulate) return null;
        return action();
    }

    private static void Say(LogHandler? log, string message, string level = "INFO")
    {
        log?.Invoke(message, level);
    }

    private static string F(string format, params object[] args)
        => string.Format(CultureInfo.InvariantCulture, format, args);

    /// <summary>Rend un booleen comme l'interpolation PowerShell (null -> chaine vide).</summary>
    private static string PsBool(bool? value)
    {
        if (!value.HasValue) return string.Empty;
        return value.Value ? "True" : "False";
    }

    private static string EnsureBraces(string guid)
    {
        if (string.IsNullOrEmpty(guid)) return guid;
        return guid.StartsWith('{') ? guid : "{" + guid + "}";
    }

    private static string StripBraces(string guid)
    {
        guid = guid.Trim();
        if (guid.Length >= 2 && guid[0] == '{' && guid[^1] == '}')
            return guid[1..^1];
        return guid;
    }

    private static long ToLong(object? value, long fallback)
    {
        try { return value == null ? fallback : Convert.ToInt64(value, CultureInfo.InvariantCulture); }
        catch { return fallback; }
    }

    /// <summary>
    /// Lance un processus (netsh), capture stdout/stderr et retourne le code de retour.
    /// Equivalent de &amp; netsh ... + $LASTEXITCODE du script PowerShell.
    /// </summary>
    private static (int ExitCode, string Output) RunProcess(string fileName, string arguments)
    {
        var psi = new ProcessStartInfo
        {
            FileName = fileName,
            Arguments = arguments,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        using var process = Process.Start(psi)
            ?? throw new InvalidOperationException($"Impossible de demarrer {fileName}.");

        var output = new StringBuilder();
        var error = new StringBuilder();
        process.OutputDataReceived += (_, e) => { if (e.Data != null) output.AppendLine(e.Data); };
        process.ErrorDataReceived += (_, e) => { if (e.Data != null) error.AppendLine(e.Data); };
        process.BeginOutputReadLine();
        process.BeginErrorReadLine();
        process.WaitForExit();
        return (process.ExitCode, output.Length > 0 || error.Length == 0
            ? output.ToString()
            : error.ToString());
    }

    private static void RunNetsh(string arguments, string errorLabel)
    {
        (int code, string _) = RunProcess("netsh.exe", arguments);
        if (code != 0)
            throw new InvalidOperationException(F("{0} a echoue (code {1}).", errorLabel, code));
    }

    // ================= LISTE DES CARTES RESEAU (Get-PcAdapters) =================

    private sealed class WmiAdapterInfo
    {
        public string Guid { get; set; } = string.Empty;
        public bool? NetEnabled { get; set; }
        public long ConfigManagerErrorCode { get; set; }
        public int Index { get; set; }
    }

    /// <summary>Win32_NetworkAdapter (cartes physiques seulement), indexe par nom de connexion.</summary>
    private static Dictionary<string, WmiAdapterInfo> QueryPhysicalAdapters()
    {
        var map = new Dictionary<string, WmiAdapterInfo>(StringComparer.OrdinalIgnoreCase);
        try
        {
            using var searcher = new ManagementObjectSearcher(
                "SELECT Name, NetConnectionID, Guid, NetEnabled, ConfigManagerErrorCode, Index FROM Win32_NetworkAdapter WHERE PhysicalAdapter = TRUE");
            foreach (ManagementObject mo in searcher.Get())
            {
                // Win32_NetworkAdapter.Name = description du pilote ; la cle de
                // correspondence avec NetworkInterface.Name (Get-NetAdapter) est
                // NetConnectionID ("Ethernet", "Wi-Fi").
                string name = mo["NetConnectionID"]?.ToString() ?? string.Empty;
                if (string.IsNullOrEmpty(name))
                    name = mo["Name"]?.ToString() ?? string.Empty;
                if (string.IsNullOrEmpty(name)) continue;
                map[name] = new WmiAdapterInfo
                {
                    Guid = StripBraces(mo["Guid"]?.ToString() ?? string.Empty),
                    NetEnabled = mo["NetEnabled"] is bool b ? b : null,
                    ConfigManagerErrorCode = ToLong(mo["ConfigManagerErrorCode"], 0),
                    Index = (int)ToLong(mo["Index"], 0),
                };
            }
        }
        catch
        {
            // WMI indisponible : repli sur NetworkInterface seul (filtre par type).
        }
        return map;
    }

    private static string DescribeStatus(NetworkInterface nic, WmiAdapterInfo? info)
    {
        if (info != null && info.NetEnabled == false) return "Disabled";
        if (info != null && info.ConfigManagerErrorCode != 0) return "Disabled";
        return nic.OperationalStatus switch
        {
            OperationalStatus.Up => "Up",
            OperationalStatus.Down => "Disconnected",
            OperationalStatus.Dormant => "Warning",
            OperationalStatus.Testing => "Warning",
            OperationalStatus.NotPresent => "Disconnected",
            _ => nic.OperationalStatus.ToString(),
        };
    }

    /// <summary>
    /// Port de Get-PcAdapters : uniquement les cartes materielles (physiques),
    /// triees par Status puis Name.
    /// </summary>
    public List<PcAdapterInfo> GetAdapters()
    {
        var wmi = QueryPhysicalAdapters();
        var result = new List<PcAdapterInfo>();

        foreach (NetworkInterface nic in NetworkInterface.GetAllNetworkInterfaces())
        {
            if (string.IsNullOrEmpty(nic.Name)) continue;
            if (nic.NetworkInterfaceType is NetworkInterfaceType.Loopback or NetworkInterfaceType.Tunnel)
                continue;

            wmi.TryGetValue(nic.Name, out WmiAdapterInfo? info);
            // Quand WMI repond, sa liste de cartes physiques fait autorite
            // (equivalent du filtre HardwareInterface de Get-NetAdapter).
            if (wmi.Count > 0 && info == null) continue;

            string mac = string.Empty;
            try { mac = nic.GetPhysicalAddress().ToString(); } catch { /* non bloquant */ }

            result.Add(new PcAdapterInfo
            {
                Name = nic.Name,
                Status = DescribeStatus(nic, info),
                Index = info?.Index ?? 0,   // WMI fait autorite ; 0 si WMI indisponible
                Description = string.IsNullOrEmpty(nic.Description) ? nic.Name : nic.Description,
                Guid = info?.Guid ?? string.Empty,
                MacAddress = mac,
            });
        }

        return result
            .OrderBy(a => a.Status, StringComparer.Ordinal)
            .ThenBy(a => a.Name, StringComparer.Ordinal)
            .ToList();
    }

    private PcAdapterInfo? FindAdapter(string adapterName)
    {
        foreach (PcAdapterInfo adapter in GetAdapters())
        {
            if (string.Equals(adapter.Name, adapterName, StringComparison.OrdinalIgnoreCase))
                return adapter;
        }
        return null;
    }

    // ================= ETAPE 1 : IPv6 + DNS (Set-AdapterNetwork) =================

    /// <summary>
    /// Etape 1 : desactive IPv6 et configure les DNS d'une carte reseau.
    /// En mode simulation, seules les commandes sont journalisees.
    /// </summary>
    public bool SetAdapterNetwork(
        string adapterName,
        string dnsPrimary = DefaultDnsPrimary,
        string dnsSecondary = DefaultDnsSecondary,
        bool disableIPv6 = true,
        bool validateUponExit = true,
        bool simulate = false,
        LogHandler? log = null)
    {
        if (string.IsNullOrEmpty(adapterName))
            throw new InvalidOperationException("Aucune carte reseau selectionnee.");

        PcAdapterInfo? adapter = FindAdapter(adapterName);
        if (adapter == null && !simulate)
            throw new InvalidOperationException($"Carte reseau introuvable : {adapterName}");

        if (disableIPv6)
        {
            InvokePcStep(
                $"Desactivation IPv6 sur '{adapterName}'",
                $"Disable-NetAdapterBinding -Name '{adapterName}' -ComponentID ms_tcpip6",
                () =>
                {
                    DisableAdapterIPv6(adapterName, adapter?.Guid);
                    return null;
                },
                simulate, log);
            Say(log, $"IPv6 desactive sur '{adapterName}'.", "OK");
        }

        InvokePcStep(
            $"Serveurs DNS sur '{adapterName}'",
            F("Set-DnsClientServerAddress -InterfaceAlias '{0}' -ServerAddresses {1}, {2}",
                adapterName, dnsPrimary, dnsSecondary),
            () =>
            {
                SetDnsServers(adapterName, adapter?.Guid ?? string.Empty, dnsPrimary, dnsSecondary);
                return null;
            },
            simulate, log);
        Say(log, F("DNS configures : {0} (prefere), {1} (auxiliaire).", dnsPrimary, dnsSecondary), "OK");

        if (validateUponExit && adapter != null)
        {
            string guid = EnsureBraces(adapter.Guid);
            if (string.IsNullOrEmpty(guid))
            {
                Say(log, $"GUID d'interface introuvable pour '{adapterName}' : option de validation non appliquee.", "ATTENTION");
            }
            else
            {
                string key = $@"HKLM:\{TcpIpInterfacesKey}\{guid}";
                InvokePcStep(
                    "Option 'Valider les parametres en quittant'",
                    F("New-ItemProperty -Path '{0}' -Name ValidateSettingsUponExit -Value 1", key),
                    () =>
                    {
                        using RegistryKey ifaceKey = OpenOrCreateInterfacesKey(TcpIpInterfacesKey, guid);
                        ifaceKey.SetValue("ValidateSettingsUponExit", 1, RegistryValueKind.DWord);
                        return null;
                    },
                    simulate, log);
                Say(log, "Option 'Valider les parametres en quittant' activee.", "OK");
            }
        }

        if (!simulate)
        {
            bool? ipv6 = IsIPv6Enabled(adapterName, adapter?.Guid);
            List<string> dns = GetDnsServerAddresses(adapterName);
            Say(log, F("Controle : IPv6 actif = {0} ; DNS = {1}",
                PsBool(ipv6), string.Join(", ", dns)), "INFO");
        }
        return true;
    }

    /// <summary>Ouvre (ou cree) HKLM\...\&lt;parentKey&gt;\{guid} en ecriture.</summary>
    private static RegistryKey OpenOrCreateInterfacesKey(string parentKey, string guid)
    {
        RegistryKey machine = Registry.LocalMachine;
        RegistryKey? key = machine.CreateSubKey(parentKey + "\\" + guid);
        return key ?? throw new InvalidOperationException($@"Cle registre inaccessible : HKLM:\{parentKey}\{guid}");
    }

    /// <summary>
    /// Desactive la liaison IPv6 d'une carte. Disable-NetAdapterBinding passe par une
    /// API non exposee : on tente d'abord la liaison WMI (MSFT_NetAdapterBindingSettingData),
    /// puis on replie sur la cle registre par interface DisabledComponents = 0xFF
    /// (KB929852), qui desactive IPv6 uniquement sur cette carte.
    /// </summary>
    private static void DisableAdapterIPv6(string adapterName, string? interfaceGuid)
    {
        if (TrySetNetAdapterBindingEnabled(adapterName, "ms_tcpip6", false)) return;

        string guid = EnsureBraces(interfaceGuid ?? string.Empty);
        if (string.IsNullOrEmpty(guid))
            throw new InvalidOperationException(
                $"Impossible de desactiver IPv6 : GUID d'interface introuvable pour '{adapterName}'.");

        using RegistryKey key = OpenOrCreateInterfacesKey(TcpIp6InterfacesKey, guid);
        key.SetValue("DisabledComponents", 0xFF, RegistryValueKind.DWord);
    }

    /// <summary>
    /// Acces a la classe de liaisons d'une carte (equivalent Get-NetAdapterBinding).
    /// Les objets sont materialises pour que le searcher puisse etre libere.
    /// </summary>
    private static List<ManagementObject> QueryNetAdapterBindings(string adapterName, string componentId)
    {
        var list = new List<ManagementObject>();
        var scope = new ManagementScope(@"root\StandardCimv2");
        scope.Connect();
        string wql = F("SELECT * FROM MSFT_NetAdapterBindingSettingData WHERE ComponentID = '{0}' "
                       + "AND (Name = '{1}' OR InterfaceDescription = '{1}')",
            componentId, adapterName.Replace("'", "''"));
        using var searcher = new ManagementObjectSearcher(scope, new ObjectQuery(wql));
        foreach (ManagementObject mo in searcher.Get())
            list.Add(new ManagementObject(mo.Path));
        return list;
    }

    private static bool TrySetNetAdapterBindingEnabled(string adapterName, string componentId, bool enabled)
    {
        try
        {
            List<ManagementObject> bindings = QueryNetAdapterBindings(adapterName, componentId);
            bool touched = false;
            foreach (ManagementObject mo in bindings)
            {
                try
                {
                    mo["Enabled"] = enabled;
                    mo.Put();
                    touched = true;
                }
                catch
                {
                    // classe non modifiable sur ce build : le repli registre prend le relais
                }
                finally
                {
                    mo.Dispose();
                }
            }
            return touched;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>Etat reel de la liaison IPv6 : WMI d'abord, registre ensuite.</summary>
    private static bool? IsIPv6Enabled(string adapterName, string? interfaceGuid)
    {
        try
        {
            List<ManagementObject> bindings = QueryNetAdapterBindings(adapterName, "ms_tcpip6");
            foreach (ManagementObject mo in bindings)
            {
                try
                {
                    if (mo["Enabled"] is bool b) return b;
                }
                finally
                {
                    mo.Dispose();
                }
            }
        }
        catch
        {
            // WMI indisponible : repli registre
        }

        try
        {
            string guid = EnsureBraces(interfaceGuid ?? string.Empty);
            if (string.IsNullOrEmpty(guid)) return null;
            using RegistryKey? key = Registry.LocalMachine.OpenSubKey($@"{TcpIp6InterfacesKey}\{guid}");
            if (key == null) return null;
            long value = ToLong(key.GetValue("DisabledComponents"), -1);
            // 0 = actif, 0xFF = desactive ; les masques intermediaires laissent IPv6 partiellement actif.
            return value != 0xFF;
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// Ecrit les serveurs DNS de la carte. Chemin principal : WMI
    /// Win32_NetworkAdapterConfiguration.SetDNSServerSearchOrder (ce que fait
    /// Set-DnsClientServerAddress) ; repli : netsh interface ipv4.
    /// </summary>
    private static void SetDnsServers(string adapterName, string interfaceGuid, string primary, string secondary)
    {
        var servers = new[] { primary, secondary };
        try
        {
            if (TrySetDnsViaWmi(adapterName, interfaceGuid, servers)) return;
        }
        catch
        {
            // repli netsh ci-dessous
        }

        string name = adapterName.Replace("\"", string.Empty);
        RunNetsh(F("interface ipv4 set dnsservers name=\"{0}\" static {1} validate=no register=primary", name, primary),
            "netsh interface ipv4 set dnsservers");
        RunNetsh(F("interface ipv4 add dnsservers name=\"{0}\" address={1} index=2 validate=no", name, secondary),
            "netsh interface ipv4 add dnsservers");
    }

    private static bool TrySetDnsViaWmi(string adapterName, string interfaceGuid, string[] servers)
    {
        string guid = StripBraces(EnsureBraces(interfaceGuid));
        foreach (ManagementObject candidate in EnumerateIpEnabledConfigurations())
        {
            using ManagementObject mo = candidate;
            string settingId = StripBraces(mo["SettingID"]?.ToString() ?? string.Empty);
            string description = mo["Description"]?.ToString() ?? string.Empty;
            bool matches =
                (guid.Length > 0 && string.Equals(settingId, guid, StringComparison.OrdinalIgnoreCase))
                || string.Equals(description, adapterName, StringComparison.OrdinalIgnoreCase);
            if (!matches) continue;

            using ManagementBaseObject inParams = mo.GetMethodParameters("SetDNSServerSearchOrder");
            inParams["DNSServerSearchOrder"] = servers;
            ManagementBaseObject outParams = mo.InvokeMethod("SetDNSServerSearchOrder", inParams, null);
            long rc = ToLong(outParams?["ReturnValue"], 0);
            if (rc != 0)
                throw new InvalidOperationException(F("SetDNSServerSearchOrder a echoue (code WMI {0}).", rc));
            return true;
        }
        return false;
    }

    private static List<ManagementObject> EnumerateIpEnabledConfigurations()
    {
        var list = new List<ManagementObject>();
        using var searcher = new ManagementObjectSearcher(
            "SELECT SettingID, Description, DNSServerSearchOrder FROM Win32_NetworkAdapterConfiguration WHERE IPEnabled = TRUE");
        foreach (ManagementObject mo in searcher.Get())
            list.Add(new ManagementObject(mo.Path));
        return list;
    }

    private static List<string> GetDnsServerAddresses(string adapterName)
    {
        var addresses = new List<string>();
        try
        {
            foreach (NetworkInterface nic in NetworkInterface.GetAllNetworkInterfaces())
            {
                if (!string.Equals(nic.Name, adapterName, StringComparison.OrdinalIgnoreCase)) continue;
                foreach (IPAddress dns in nic.GetIPProperties().DnsAddresses
                             .Where(a => a.AddressFamily == AddressFamily.InterNetwork))
                    addresses.Add(dns.ToString());
                break;
            }
        }
        catch
        {
            try
            {
                foreach (ManagementObject candidate in EnumerateIpEnabledConfigurations())
                {
                    using ManagementObject mo = candidate;
                    if (!string.Equals(mo["Description"]?.ToString(), adapterName, StringComparison.OrdinalIgnoreCase))
                        continue;
                    if (mo["DNSServerSearchOrder"] is string[] arr) addresses.AddRange(arr);
                    break;
                }
            }
            catch { /* le controle n'est jamais bloquant */ }
        }
        return addresses;
    }

    // ================= ETAPE 2 : JOINTURE DOMAINE (Invoke-PcDomainJoin) =================

    /// <summary>
    /// Etape 2 : renomme le poste et le joint au domaine Active Directory.
    /// Redemarrage volontairement non automatique (= "Redemarrer ulterieurement").
    /// Add-Computer etant indisponible hors PowerShell, on reproduit son mecanisme
    /// WMI (Win32_ComputerSystem) avec les noms de parametres reels et les flags
    /// corrects : voir RenameAndJoin avant toute modification.
    /// </summary>
    public bool InvokeDomainJoin(
        string computerName,
        string domainName = DefaultDomainName,
        string? domainUser = null,
        string? domainPassword = null,
        bool simulate = false,
        LogHandler? log = null)
    {
        if (string.IsNullOrEmpty(computerName))
            throw new InvalidOperationException("Le nom du poste est obligatoire.");
        if (!ComputerNamePattern.IsMatch(computerName))
            throw new InvalidOperationException(
                $"Nom de poste invalide (15 caracteres max, lettres/chiffres/tiret) : {computerName}");
        if (string.IsNullOrEmpty(domainName))
            throw new InvalidOperationException("Le nom de domaine est obligatoire.");
        if (string.IsNullOrEmpty(domainUser))
            throw new InvalidOperationException(@"Le compte du domaine est obligatoire (ex. SARYTANY\administrateur).");
        if (string.IsNullOrEmpty(domainPassword))
            throw new InvalidOperationException("Le mot de passe du domaine est obligatoire.");

        string current = ReadCurrentDomain();
        Say(log, F("Domaine actuel : {0}  |  poste : {1}", current, Environment.MachineName), "INFO");
        if (string.Equals(current, domainName, StringComparison.OrdinalIgnoreCase))
            Say(log, $"Le poste est deja membre de {domainName} (l'operation reste possible pour renommer).", "ATTENTION");

        string[] userParts = domainUser.Split('\\', StringSplitOptions.RemoveEmptyEntries);
        string user = userParts.Length > 0 ? userParts[^1] : domainUser;

        InvokePcStep(
            "Renommage et jonction au domaine",
            F("Add-Computer -DomainName {0} -NewName {1} -Credential {2} -Restart:$false",
                domainName, computerName, user),
            () =>
            {
                RenameAndJoin(computerName, domainName, domainUser, domainPassword);
                return null;
            },
            simulate, log);

        if (simulate)
        {
            Say(log, "Simulation : aucune modification n'a ete appliquee.", "ATTENTION");
            return true;
        }

        using ManagementObject cs = QueryComputerSystem();
        string newName = (cs["Name"]?.ToString() ?? string.Empty).Trim();
        string newDomain = (cs["Domain"]?.ToString() ?? string.Empty).Trim();
        bool partOfDomain = cs["PartOfDomain"] is bool b && b;
        string pending = PendingComputerName();
        Say(log, F("Controle : nom = {0} ; nom en attente = {1} ; domaine = {2} ; membre = {3}",
            newName, pending, newDomain, PsBool(partOfDomain)), "OK");
        if (!string.Equals(newDomain, domainName, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException($"La jonction n'a pas abouti (domaine actuel : {newDomain}).");
        bool nameOk = string.Equals(newName, computerName, StringComparison.OrdinalIgnoreCase)
                   || string.Equals(pending, computerName, StringComparison.OrdinalIgnoreCase);
        if (!nameOk)
            throw new InvalidOperationException(
                F("La jonction a abouti mais le renommage n'a pas ete enregistre (nom en attente : {0}).", pending));
        Say(log, "Redemarrage requis pour finaliser renommage et/ou canal securise (volontairement reporte).", "ATTENTION");
        return true;
    }

    private static string ReadCurrentDomain()
    {
        using ManagementObject cs = QueryComputerSystem();
        return (cs["Domain"]?.ToString() ?? string.Empty).Trim();
    }

    private static ManagementObject QueryComputerSystem()
    {
        using var searcher = new ManagementObjectSearcher("SELECT * FROM Win32_ComputerSystem");
        foreach (ManagementObject mo in searcher.Get())
            return new ManagementObject(mo.Path);
        throw new InvalidOperationException("Win32_ComputerSystem illisible.");
    }

    /// <summary>
    /// Jonction + renommage via WMI (Win32_ComputerSystem.JoinDomainOrWorkgroup
    /// puis Rename). CAUSE RACINEE LE 2026-10-07 : les noms de parametres reels
    /// de ces methodes WMI different de la doc MSDN ("Account"/"JoinOptions"
    /// n'existent pas ; les noms reels sont UserName/FJoinOptions). Un nom
    /// inconnu est IGNOREE silencieusement : la jointure partait sans credentials
    /// ni flags et echouait en "Le serveur RPC n'est pas disponible" (1722). Ne
    /// jamais renommer ces cles. Test de reference : compte invalide -> 1326 propre.
    /// FJoinOptions = 0x1|0x2|0x20 (JOIN_DOMAIN | ACCT_CREATE | JOIN_IF_JOINED) :
    /// permet la re-jonction d'un poste deja membre (rearm du canal de confiance).
    /// ORDRE OBLIGATOIRE (bug constate 2026-10-08 sur ST-UC-LIDAR-023 : poste joint
    /// mais nom jamais change) : la JONCTION D'ABORD, le RENOMMAGE ENSUITE. Un
    /// renommage WMI reste "en attente" jusqu'au redemarrage ; si la jointure
    /// passe apres, elle reinitialise le nom actif et perd le renommage.
    /// L'AD est d'abord creee sous le nom courant ; au redemarrage le membre
    /// renomme son propre objet computer automatiquement (canal securise).
    /// Retour WMI : 0 = succes, 1 = "redemarrage requis" (= succes differe, PAS
    /// une erreur) pour Rename comme pour JoinDomainOrWorkgroup.
    /// La voie netapi32 NetJoinDomain a ete testee puis SUPPRIMEE : sur ce build
    /// Windows l'export lui-meme declenche un AccessViolation chez tous les
    /// appelants (PowerShell 5.1 inclus). Ne pas la reintroduire.
    /// </summary>
    private static void RenameAndJoin(string computerName, string domainName, string domainUser, string domainPassword)
    {
        // 1) JONCTION (ou re-jonction) en premier.
        using ManagementObject cs = QueryComputerSystem();
        using ManagementBaseObject joinParams = cs.GetMethodParameters("JoinDomainOrWorkgroup");
        joinParams["UserName"] = domainUser;
        joinParams["Password"] = domainPassword;
        joinParams["Name"] = domainName;
        joinParams["FJoinOptions"] = 0x1 | 0x2 | 0x20; // JOIN_DOMAIN | ACCT_CREATE | JOIN_IF_JOINED
        ManagementBaseObject joinResult = cs.InvokeMethod("JoinDomainOrWorkgroup", joinParams, null);
        long joinRc = ToLong(joinResult?["ReturnValue"], -1);
        if (joinRc != 0 && joinRc != 1)
            throw new InvalidOperationException(
                F("La jonction au domaine a echoue (code {0} : {1}). Verifiez que le DNS du poste resout le controleur de domaine et que le compte dispose des droits de jointure.",
                    joinRc, Win32Text((int)joinRc)));

        // 2) RENOMMAGE en dernier : c'est lui qui doit survivre jusqu'au redemarrage.
        string active = Environment.MachineName;
        string pending = PendingComputerName();
        bool conforme = string.Equals(active, computerName, StringComparison.OrdinalIgnoreCase)
                     || string.Equals(pending, computerName, StringComparison.OrdinalIgnoreCase);
        if (!conforme)
        {
            // Relecture apres jonction pour repartir d'un objet a jour (membre).
            using ManagementObject cs2 = QueryComputerSystem();
            using ManagementBaseObject inParams = cs2.GetMethodParameters("Rename");
            inParams["Name"] = computerName;
            inParams["UserName"] = domainUser;
            inParams["Password"] = domainPassword;
            ManagementBaseObject outParams = cs2.InvokeMethod("Rename", inParams, null);
            long rc = ToLong(outParams?["ReturnValue"], -1);
            if (rc != 0 && rc != 1)
                throw new InvalidOperationException(
                    F("Le renommage du poste a echoue (code {0} : {1}).", rc, Win32Text((int)rc)));
        }
    }

    /// <summary>Nom de poste "en attente" (applique au prochain redemarrage).</summary>
    private static string PendingComputerName()
    {
        try
        {
            using RegistryKey? key = Registry.LocalMachine.OpenSubKey(
                @"SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName");
            return (key?.GetValue("ComputerName") as string)?.Trim() ?? string.Empty;
        }
        catch { return string.Empty; }
    }

    private static string Win32Text(int code) =>
        new System.ComponentModel.Win32Exception(code).Message;

    // ================= VERIFICATIONS PREALABLES =================

    /// <summary>
    /// Lit l'etat de jonction Active Directory du poste (lecture seule).
    /// En workgroup, Win32_ComputerSystem.Domain contient le nom du groupe de
    /// travail : on le normalise a chaine vide pour garder une lecture
    /// "domaine AD" fiable.
    /// </summary>
    public PcDomainStatus GetDomainStatus()
    {
        try
        {
            using ManagementObject cs = QueryComputerSystem();
            bool joined = cs["PartOfDomain"] is bool b && b;
            string dom = (cs["Domain"]?.ToString() ?? string.Empty).Trim();
            if (!joined) dom = string.Empty;
            return new PcDomainStatus
            {
                Joined = joined,
                Domain = dom,
                Name = (cs["Name"]?.ToString() ?? string.Empty).Trim(),
                Error = string.Empty,
            };
        }
        catch (Exception ex)
        {
            return new PcDomainStatus
            {
                Joined = false,
                Domain = string.Empty,
                Name = Environment.MachineName,
                Error = ex.Message,
            };
        }
    }

    private enum DnsProbeOutcome
    {
        Resolved,
        NoAnswer,
        NoResponse,
    }

    /// <summary>
    /// Teste la joignabilite de chaque serveur DNS en resolvant un nom de test.
    /// Un echec est relance sur la racine '.' : si la racine repond, le serveur
    /// est joignable mais le nom est introuvable.
    /// </summary>
    public PcDnsTestResult TestDnsConnectivity(string[]? servers = null, string? testName = null)
    {
        string[] source = servers is { Length: > 0 }
            ? servers
            : new[] { DefaultDnsPrimary, DefaultDnsSecondary };

        var list = new List<string>();
        foreach (string srv in source)
        {
            string trimmed = (srv ?? string.Empty).Trim();
            if (trimmed.Length > 0) list.Add(trimmed);
        }
        if (list.Count == 0) return new PcDnsTestResult { Ok = false };

        if (string.IsNullOrEmpty(testName)) testName = DefaultDomainName;
        if (string.IsNullOrEmpty(testName)) testName = "microsoft.com";

        bool allOk = true;
        var results = new List<DnsProbeResult>();
        foreach (string srv in list)
        {
            var sw = Stopwatch.StartNew();
            bool ok;
            string detail;
            try
            {
                if (IPAddress.TryParse(srv, out IPAddress? ip) && ip != null && ip.AddressFamily == AddressFamily.InterNetwork)
                {
                    DnsProbeOutcome outcome = QueryDnsServer(ip, testName);
                    if (outcome == DnsProbeOutcome.Resolved)
                    {
                        ok = true;
                        detail = $"'{testName}' resolu";
                    }
                    else
                    {
                        try
                        {
                            // La racine repond -> serveur joignable, nom de test introuvable
                            DnsProbeOutcome root = QueryDnsServer(ip, ".");
                            if (root != DnsProbeOutcome.NoResponse)
                            {
                                ok = true;
                                detail = $"joignable ('{testName}' introuvable)";
                            }
                            else
                            {
                                ok = false;
                                detail = "serveur injoignable";
                            }
                        }
                        catch
                        {
                            ok = false;
                            detail = "serveur injoignable";
                        }
                    }
                }
                else
                {
                    // Repli .NET (resout via la configuration systeme, pas via le serveur)
                    (ok, detail) = ResolveViaSystem(testName);
                }
            }
            catch (Exception ex)
            {
                ok = false;
                detail = ex.Message;
            }
            sw.Stop();
            if (!ok) allOk = false;
            results.Add(new DnsProbeResult
            {
                Server = srv,
                Ok = ok,
                Ms = (int)sw.ElapsedMilliseconds,
                Detail = detail,
            });
        }
        return new PcDnsTestResult { Ok = allOk, Results = results };
    }

    private static (bool Ok, string Detail) ResolveViaSystem(string name)
    {
        try
        {
            _ = Dns.GetHostAddresses(name);
            return (true, $"'{name}' resolu");
        }
        catch (Exception ex)
        {
            return (false, ex.Message);
        }
    }

    /// <summary>
    /// Requete DNS A envoyee directement au serveur (equivalent Resolve-DnsName
    /// -Name ... -Server ... -DnsOnly -Timeout 2), sans dependance externe.
    /// </summary>
    private static DnsProbeOutcome QueryDnsServer(IPAddress server, string qname)
    {
        const int timeoutMs = 2000;
        byte[] query = BuildDnsQuery(qname);
        try
        {
            using var udp = new UdpClient(AddressFamily.InterNetwork);
            udp.Client.SendTimeout = timeoutMs;
            udp.Client.ReceiveTimeout = timeoutMs;
            udp.Connect(server, 53);
            udp.Send(query, query.Length);
            IPEndPoint? remote = null;
            byte[] response = udp.Receive(ref remote);
            if (response.Length < 12) return DnsProbeOutcome.NoResponse;

            int rcode = response[3] & 0x0F;
            int answers = (response[6] << 8) | response[7];
            if (rcode == 0 && answers > 0) return DnsProbeOutcome.Resolved;
            // Reponse recue mais aucune donnee utile : le serveur est joignable.
            return DnsProbeOutcome.NoAnswer;
        }
        catch (SocketException ex) when (ex.SocketErrorCode is SocketError.TimedOut or SocketError.ConnectionRefused)
        {
            return DnsProbeOutcome.NoResponse;
        }
        catch
        {
            return DnsProbeOutcome.NoResponse;
        }
    }

    private static byte[] BuildDnsQuery(string qname)
    {
        var buffer = new List<byte>(64);
        var id = (ushort)Random.Shared.Next(ushort.MinValue, ushort.MaxValue);
        buffer.Add((byte)(id >> 8));
        buffer.Add((byte)(id & 0xFF));
        buffer.Add(0x01); // flags : recursion souhaitee
        buffer.Add(0x00);
        buffer.Add(0x00); buffer.Add(0x01); // QDCOUNT = 1
        buffer.Add(0x00); buffer.Add(0x00); // ANCOUNT
        buffer.Add(0x00); buffer.Add(0x00); // NSCOUNT
        buffer.Add(0x00); buffer.Add(0x00); // ARCOUNT

        foreach (string label in qname.TrimEnd('.').Split('.', StringSplitOptions.RemoveEmptyEntries))
        {
            byte[] bytes = Encoding.ASCII.GetBytes(label);
            if (bytes.Length > 63) bytes = bytes[..63];
            buffer.Add((byte)bytes.Length);
            buffer.AddRange(bytes);
        }
        buffer.Add(0x00); // fin du nom ('.' -> question portant sur la racine)
        buffer.Add(0x00); buffer.Add(0x01); // QTYPE = A
        buffer.Add(0x00); buffer.Add(0x01); // QCLASS = IN
        return buffer.ToArray();
    }

    // ================= CONFIGURATION SYSTEME : PROTECTIONS =================

    /// <summary>
    /// Lecture seule de l'etat des protections : protection en arriere-plan
    /// Defender (null = illisible, par exemple antivirus tiers) et profils
    /// pare-feu encore actifs.
    /// </summary>
    public PcProtectionsState GetProtectionsState()
    {
        var state = new PcProtectionsState();
        try { state.DefenderOn = ReadDefenderRealTimeProtection(); }
        catch { state.DefenderOn = null; }

        try { state.FirewallOn = ReadFirewallProfiles(enabledOnly: true); }
        catch (Exception ex) { state.Error = ex.Message; }
        return state;
    }

    /// <summary>Port de (Get-MpComputerStatus).RealTimeProtectionEnabled.</summary>
    private static bool ReadDefenderRealTimeProtection()
    {
        var scope = new ManagementScope(@"root\Microsoft\Windows\WindowsDefender");
        scope.Connect();
        using var searcher = new ManagementObjectSearcher(scope,
            new ObjectQuery("SELECT RealTimeProtectionEnabled FROM MSFT_MpComputerStatus"));
        foreach (ManagementObject mo in searcher.Get())
            return mo["RealTimeProtectionEnabled"] is bool b && b;
        throw new InvalidOperationException("MSFT_MpComputerStatus introuvable.");
    }

    /// <summary>
    /// Port de Get-NetFirewallProfile : lit la valeur EnableFirewall de chaque profil
    /// (registre FirewallPolicy), ce qui evite la sortie localisee de netsh.
    /// </summary>
    private static List<string> ReadFirewallProfiles(bool enabledOnly)
    {
        var names = new List<string>();
        int readCount = 0;
        foreach ((string registryKey, string profileName) in FirewallProfiles)
        {
            using RegistryKey? profile = Registry.LocalMachine.OpenSubKey($@"{FirewallPolicyKey}\{registryKey}");
            if (profile == null) continue;
            readCount++;
            bool enabled = ToLong(profile.GetValue("EnableFirewall"), 0) != 0;
            if (enabled == enabledOnly) names.Add(profileName);
        }
        if (readCount == 0)
            throw new InvalidOperationException("Profils pare-feu illisibles dans le registre.");
        return names;
    }

    /// <summary>
    /// Port de Set-MpPreference -DisableRealtimeMonitoring : ecrit la valeur de
    /// strategie DisableRealtimeMonitoring (1 = desactive, 0 = actif) dans
    /// HKLM\SOFTWARE\Policies\Microsoft\Windows Defender, la cle que modifie le cmdlet.
    /// </summary>
    private static void SetRealtimeMonitoringPreference(bool disable)
    {
        RegistryKey machine = Registry.LocalMachine;
        using RegistryKey key = machine.CreateSubKey(DefenderPolicyKey)
            ?? throw new InvalidOperationException($@"Cle registre inaccessible : HKLM:\{DefenderPolicyKey}");
        key.SetValue("DisableRealtimeMonitoring", disable ? 1 : 0, RegistryValueKind.DWord);
    }

    /// <summary>Port de Set-NetFirewallProfile -Enabled (repli netsh du script, ici chemin unique).</summary>
    private static void SetAllFirewallProfilesEnabled(bool enabled)
    {
        (int code, string _) = RunProcess("netsh.exe",
            F("advfirewall set allprofiles state {0}", enabled ? "on" : "off"));
        if (code != 0)
            throw new InvalidOperationException(F("netsh advfirewall a echoue (code {0}).", code));
    }

    /// <summary>
    /// Desactivation AUTOMATIQUE et de meilleure grace (best effort) avant une
    /// installation : protection en arriere-plan Defender + pare-feu Windows.
    /// Ne leve jamais d'exception : en cas d'echec (Tamper Protection, droits
    /// insuffisants), une ATTENTION est journalisee et l'installation se poursuit.
    /// Deja desactive = aucune commande.
    /// </summary>
    public bool DisableInstallProtections(bool simulate = false, LogHandler? log = null)
    {
        Say(log, "--- Protections : desactivation automatique pre-installation ---", "INFO");

        try
        {
            PcProtectionsState st = GetProtectionsState();

            // --- Protection en arriere-plan (Defender) ---
            if (st.DefenderOn == null)
            {
                Say(log, "Windows Defender illisible (antivirus tiers ?) : rien a desactiver ici.", "INFO");
            }
            else if (st.DefenderOn == false)
            {
                Say(log, "Protection en arriere-plan deja desactivee.", "INFO");
            }
            else
            {
                InvokePcStep(
                    "Desactivation de la protection en arriere-plan",
                    "Set-MpPreference -DisableRealtimeMonitoring $true",
                    () =>
                    {
                        SetRealtimeMonitoringPreference(true);
                        return null;
                    },
                    simulate, log);
                if (simulate)
                {
                    Say(log, "Simulation : la protection en arriere-plan serait desactivee.", "ATTENTION");
                }
                else
                {
                    bool still = true;
                    try { still = ReadDefenderRealTimeProtection(); }
                    catch { /* statut inconnu : on considere que Defender est encore actif */ }
                    if (still)
                        Say(log, "Defender reste actif (Tamper Protection ?) : l'installation continue malgre tout.", "ATTENTION");
                    else
                        Say(log, "Protection en arriere-plan desactivee pour l'installation.", "OK");
                }
            }

            // --- Pare-feu Windows ---
            if (st.FirewallOn.Count == 0 && string.IsNullOrEmpty(st.Error))
            {
                Say(log, "Pare-feu Windows deja desactive.", "INFO");
            }
            else
            {
                InvokePcStep(
                    "Desactivation du pare-feu Windows (Domaine, Public, Prive)",
                    "Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False",
                    () =>
                    {
                        SetAllFirewallProfilesEnabled(false);
                        return null;
                    },
                    simulate, log);
                if (simulate)
                {
                    Say(log, "Simulation : le pare-feu Windows serait desactive.", "ATTENTION");
                }
                else
                {
                    List<string> stillOn;
                    try { stillOn = ReadFirewallProfiles(enabledOnly: true); }
                    catch { stillOn = new List<string> { "?" }; }
                    if (stillOn.Count == 0)
                        Say(log, "Pare-feu Windows desactive pour l'installation.", "OK");
                    else
                        Say(log, F("Pare-feu encore actif sur : {0} : l'installation continue malgre tout.",
                            string.Join(", ", stillOn)), "ATTENTION");
                }
            }
        }
        catch (Exception ex)
        {
            Say(log, F("Protections : erreur inattendue ({0}) : l'installation continue.", ex.Message), "ATTENTION");
        }
        return true;
    }

    /// <summary>
    /// Reactivation manuelle des protections apres le deploiement : protection en
    /// arriere-plan Defender + pare-feu Windows. Les booleens du resultat indiquent
    /// ce qui a reellement ete reactive.
    /// </summary>
    public PcProtectionsResult EnableProtections(bool simulate = false, LogHandler? log = null)
    {
        var res = new PcProtectionsResult { Defender = false, Firewall = false, Ok = true };

        InvokePcStep(
            "Reactivation de la protection en arriere-plan",
            "Set-MpPreference -DisableRealtimeMonitoring $false",
            () =>
            {
                SetRealtimeMonitoringPreference(false);
                return null;
            },
            simulate, log);
        if (simulate)
        {
            Say(log, "Simulation : protections laissees telles quelles.", "ATTENTION");
            return res;
        }
        try
        {
            bool on = ReadDefenderRealTimeProtection();
            if (on)
            {
                Say(log, "Protection en arriere-plan reactivee.", "OK");
                res.Defender = true;
            }
            else
            {
                res.Ok = false;
                Say(log, "La protection en arriere-plan n'a pas pu etre reactivee (Tamper Protection ?).", "ERREUR");
            }
        }
        catch
        {
            res.Ok = false;
            Say(log, "Reactivation Defender non verifiable : service indisponible.", "ERREUR");
        }

        InvokePcStep(
            "Reactivation du pare-feu Windows (Domaine, Public, Prive)",
            "Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True",
            () =>
            {
                SetAllFirewallProfilesEnabled(true);
                return null;
            },
            simulate, log);

        List<string>? stillOff = null;
        try { stillOff = ReadFirewallProfiles(enabledOnly: false); }
        catch { /* etat non verifiable */ }
        if (stillOff == null)
        {
            res.Ok = false;
            Say(log, "Etat du pare-feu non verifiable apres reactivation.", "ERREUR");
        }
        else if (stillOff.Count == 0)
        {
            Say(log, "Pare-feu Windows reactive (Domaine, Public, Prive).", "OK");
            res.Firewall = true;
        }
        else
        {
            res.Ok = false;
            Say(log, F("Pare-feu toujours inactif sur : {0}.", string.Join(", ", stillOff)), "ERREUR");
        }
        return res;
    }
}
