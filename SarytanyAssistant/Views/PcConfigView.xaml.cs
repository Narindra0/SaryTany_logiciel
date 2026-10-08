using System.Collections.ObjectModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using SarytanyAssistant.Engines;

namespace SarytanyAssistant.Views;

/// <summary>
/// Vue "Configuration PC" (port fidele de src\80-View-PcConfig.ps1) :
/// carte Reseau (carte, IPv6, DNS), carte Domaine AD (renommage + jonction),
/// carte unique "Verifications et protections" (lecture seule + reactivation
/// manuelle ; la desactivation est automatique avant chaque installation),
/// puis journal.
/// </summary>
public partial class PcConfigView : UserControl
{
    private readonly PcConfigEngine _engine = new();

    // Bross du journal (memoires partagees, Figure libre).
    private static readonly Brush LogOk      = new SolidColorBrush(Color.FromRgb(0x48, 0xCD, 0x94));
    private static readonly Brush LogError   = new SolidColorBrush(Color.FromRgb(0xFF, 0x7A, 0x7A));
    private static readonly Brush LogWarn    = new SolidColorBrush(Color.FromRgb(0xFF, 0xBE, 0x64));
    private static readonly Brush LogDefault = new SolidColorBrush(Color.FromRgb(0xB2, 0xBE, 0xCE));
    private static readonly Brush StGreen    = new SolidColorBrush(Color.FromRgb(0x10, 0xB9, 0x81));
    private static readonly Brush StAmber    = new SolidColorBrush(Color.FromRgb(0xF5, 0x9E, 0x0B));
    private static readonly Brush StRed      = new SolidColorBrush(Color.FromRgb(0xEF, 0x44, 0x44));
    private static readonly Brush StMuted    = new SolidColorBrush(Color.FromRgb(0x64, 0x74, 0x8B));

    private readonly ObservableCollection<RunViewControl.LogLine> _logs = new();

    public PcConfigView()
    {
        InitializeComponent();
        LogLines.ItemsSource = _logs;

        TxtDns1.Text = PcConfigEngine.DefaultDnsPrimary;
        TxtDns2.Text = PcConfigEngine.DefaultDnsSecondary;
        TxtComputer.Text = Environment.MachineName;
        TxtDomain.Text = PcConfigEngine.DefaultDomainName;

        SetButtonsEnabled(false);
        _ = InitAsync();
    }

    /// <summary>Initialisation en arriere-plan : cartes reseau + etat systeme.</summary>
    private async Task InitAsync()
    {
        try
        {
            await UpdateAdapterListAsync();
            await PreChecks();
            AppendLog($"Module pret. Carte detectee : {SelectedAdapterName ?? "aucune"}");
            if (ChkSim.IsChecked == true)
                AppendLog("Mode simulation actif : aucune modification ne sera appliquee.", "ATTENTION");
        }
        finally { SetButtonsEnabled(true); }
    }

    private MainWindow? Main => Window.GetWindow(this) as MainWindow;

    // ================= HELPERS DE LA VUE =================
    private void AppendLog(string message, string level = "INFO")
    {
        var brush = level switch
        {
            "OK" => LogOk,
            "ERREUR" => LogError,
            "ATTENTION" => LogWarn,
            _ => LogDefault,
        };
        Dispatcher.Invoke(() =>
        {
            _logs.Add(new RunViewControl.LogLine
            { Time = DateTime.Now.ToString("HH:mm:ss"), Text = message, Brush = brush });
            while (_logs.Count > 800) _logs.RemoveAt(0);
            LogScroll.ScrollToEnd();
            Ui.Status(Main, message);
        });
    }

    private LogHandler EngineLog =>
        new((m, l) => { AppendLog(m, l); });

    private void SetButtonsEnabled(bool enabled)
    {
        Dispatcher.Invoke(() =>
        {
            BtnApplyNet.IsEnabled = enabled;
            BtnJoin.IsEnabled = enabled;
            BtnRefreshAdapters.IsEnabled = enabled;
            BtnPreChecks.IsEnabled = enabled;
            BtnRestore.IsEnabled = enabled;
        });
    }

    // --- Liste et selection des cartes reseau ---
    private async Task UpdateAdapterListAsync()
    {
        List<PcAdapterInfo> adapters;
        try { adapters = await Task.Run(() => _engine.GetAdapters()); }
        catch (Exception ex)
        {
            AppendLog($"Lecture des cartes reseau impossible : {ex.Message}", "ATTENTION");
            return;
        }
        CmbAdapter.Items.Clear();
        foreach (var a in adapters)
            CmbAdapter.Items.Add(new ComboBoxItem { Content = $"{a.Name}  ({a.Status})  -  {a.Index}", Tag = a.Name });
        if (CmbAdapter.Items.Count > 0)
        {
            var target = 0;
            for (var i = 0; i < CmbAdapter.Items.Count; i++)
            {
                if (((ComboBoxItem)CmbAdapter.Items[i]).Content.ToString()!.Contains("Up")) { target = i; break; }
            }
            CmbAdapter.SelectedIndex = target;
        }
    }

    private string? SelectedAdapterName =>
        CmbAdapter.SelectedIndex >= 0 ? ((ComboBoxItem)CmbAdapter.Items[CmbAdapter.SelectedIndex]).Tag as string : null;

    // ================= CONTROLES PREALABLES (lecture seule) =================
    private async Task PreChecks()
    {
        var st = await Task.Run(() => _engine.GetDomainStatus());
        Dispatcher.Invoke(() =>
        {
            if (!string.IsNullOrEmpty(st.Error))
            {
                LblChkDomain.Text = $"Jonction AD : lecture impossible ({st.Error})";
                LblChkDomain.Foreground = StRed;
            }
            else if (st.Joined)
            {
                LblChkDomain.Text = $"Jonction AD : poste '{st.Name}' deja membre du domaine '{st.Domain}'";
                LblChkDomain.Foreground = StGreen;
            }
            else
            {
                LblChkDomain.Text = $"Jonction AD : poste '{st.Name}' non joint (workgroup)";
                LblChkDomain.Foreground = StAmber;
            }
        });
        if (!string.IsNullOrEmpty(st.Error))
            AppendLog($"Jonction AD : lecture impossible ({st.Error})", "ATTENTION");
        else if (st.Joined)
            AppendLog($"Jonction AD verifiee : '{st.Name}' membre de '{st.Domain}'.", "OK");
        else
            AppendLog($"Jonction AD : '{st.Name}' n'est pas membre d'un domaine.", "ATTENTION");

        // Lecture des champs SUR LE THREAD UI avant de passer en arriere-plan :
        // lire TextBox.Text dans Task.Run leve une exception cross-thread.
        string[] dnsServers = [TxtDns1.Text, TxtDns2.Text];
        string domainName = TxtDomain.Text;
        var dns = await Task.Run(() => _engine.TestDnsConnectivity(dnsServers, domainName));
        if (dns.Results.Count == 0)
        {
            Dispatcher.Invoke(() =>
            {
                LblChkDns.Text = "Connectivite DNS : aucun serveur indique";
                LblChkDns.Foreground = StAmber;
            });
            AppendLog("Controle DNS : aucun serveur indique.", "ATTENTION");
            return;
        }
        var parts = dns.Results.Select(r => $"{r.Server} : {r.Detail} ({r.Ms} ms)").ToArray();
        Dispatcher.Invoke(() =>
        {
            LblChkDns.Text = "DNS : " + string.Join("   |   ", parts);
            LblChkDns.Foreground = dns.Ok ? StGreen : StRed;
        });
        AppendLog(dns.Ok
            ? "Connectivite DNS verifiee : " + string.Join(" ; ", parts) + "."
            : "Connectivite DNS en echec : " + string.Join(" ; ", parts) + ".",
            dns.Ok ? "OK" : "ERREUR");

        // Ligne protections : pure information, pas de journal (evite le bruit).
        var prot = await Task.Run(() => _engine.GetProtectionsState());
        var dTxt = prot.DefenderOn is null ? "Defender : illisible (antivirus tiers ?)"
                 : prot.DefenderOn == true ? "Defender : actif" : "Defender : arrete";
        var fTxt = prot.FirewallOn.Count > 0 ? "Pare-feu : actif (" + string.Join(", ", prot.FirewallOn) + ")"
                 : "Pare-feu : arrete";
        var allOff = (prot.DefenderOn is null || prot.DefenderOn == false) && prot.FirewallOn.Count == 0;
        Dispatcher.Invoke(() =>
        {
            LblProtState.Text = $"Protections : {dTxt}   |   {fTxt}";
            LblProtState.Foreground = allOff ? StGreen : StAmber;
        });
    }

    private async void PreChecks_Click(object sender, RoutedEventArgs e) => await PreChecks();

    // ================= REACTIVATION MANUELLE =================
    private async void Restore_Click(object sender, RoutedEventArgs e)
    {
        SetButtonsEnabled(false);
        Ui.Status(Main, "Reactivation des protections en cours");
        var simulate = ChkSim.IsChecked == true;
        try
        {
            var r = await Task.Run(() => _engine.EnableProtections(simulate, EngineLog));
            await PreChecks();
            if (simulate) Ui.Status(Main, "Simulation de reactivation terminee");
            else if (r.Ok)
            {
                Ui.Status(Main, "Protections reactivees");
                Ui.Dialog("Defender et le pare-feu Windows sont reactivees.", "Protections systeme");
            }
            else
            {
                Ui.Status(Main, "Reactivation partielle");
                Ui.Dialog("Reactivation incomplete : voir le journal.", "Protections systeme", "warning");
            }
        }
        catch (Exception ex)
        {
            AppendLog($"Erreur : {ex.Message}", "ERREUR");
            Ui.Status(Main, "Echec de la reactivation");
            Ui.Dialog(ex.Message, "Erreur protections", "error");
        }
        finally { SetButtonsEnabled(true); }
    }

    private async void RefreshAdapters_Click(object sender, RoutedEventArgs e)
    {
        BtnRefreshAdapters.IsEnabled = false;
        try
        {
            await UpdateAdapterListAsync();
            AppendLog("Liste des cartes reseau actualisee.");
        }
        finally { BtnRefreshAdapters.IsEnabled = true; }
    }

    // ================= ACTION 1 : RESEAU (IPv6 + DNS) =================
    private async void ApplyNet_Click(object sender, RoutedEventArgs e)
    {
        var adapter = SelectedAdapterName;
        var simulate = ChkSim.IsChecked == true;
        SetButtonsEnabled(false);
        Ui.Status(Main, "Configuration reseau en cours");
        AppendLog("===============================================");
        AppendLog($"Configuration reseau - carte '{adapter}'{(simulate ? "  [MODE SIMULATION]" : "")}");
        AppendLog("===============================================");
        try
        {
            await PreChecks();   // controles prealables automatiques (jonction AD + DNS)
            var dns1 = TxtDns1.Text; var dns2 = TxtDns2.Text;
            var ipv6 = ChkIPv6.IsChecked == true; var validate = ChkValidate.IsChecked == true;
            await Task.Run(() => _engine.SetAdapterNetwork(adapter ?? "", dns1, dns2, ipv6, validate, simulate, EngineLog));
            if (simulate)
            {
                Ui.Status(Main, "Simulation reseau terminee");
                AppendLog("Aucune modification appliquee (mode simulation).", "ATTENTION");
            }
            else
            {
                Ui.Status(Main, "Reseau configure");
                AppendLog($"IPv6 desactive : {ipv6} | DNS : {dns1}, {dns2}", "OK");
            }
            Ui.Dialog($"Etape 1 - Configuration reseau\n\nCarte : {adapter}\nIPv6 desactive : {ipv6}\nDNS prefere : {dns1}\nDNS auxiliaire : {dns2}\n\n"
                + (simulate ? "Mode simulation : rien n'a ete applique." : "La configuration a ete appliquee."),
                "Configuration reseau");
        }
        catch (Exception ex)
        {
            AppendLog($"Erreur : {ex.Message}", "ERREUR");
            Ui.Status(Main, "Echec de la configuration reseau");
            Ui.Dialog(ex.Message, "Erreur reseau", "error");
        }
        finally { SetButtonsEnabled(true); }
    }

    // ================= ACTION 2 : RENOMMAGE + JONCTION AU DOMAINE =================
    private async void Join_Click(object sender, RoutedEventArgs e)
    {
        var simulate = ChkSim.IsChecked == true;
        SetButtonsEnabled(false);
        Ui.Status(Main, "Jonction au domaine en cours");
        AppendLog("===============================================");
        AppendLog($"Renommage et jonction au domaine{(simulate ? "  [MODE SIMULATION]" : "")}");
        AppendLog("===============================================");
        try
        {
            await PreChecks();   // controles prealables automatiques (jonction AD + DNS)
            // Protections : desactivation automatique avant jonction (best effort).
            await Task.Run(() => _engine.DisableInstallProtections(simulate, EngineLog));
            var computer = TxtComputer.Text; var domain = TxtDomain.Text;
            var user = TxtDomainUser.Text; var pwd = TxtDomainPwd.Password;
            await Task.Run(() => _engine.InvokeDomainJoin(computer, domain, user, pwd, simulate, EngineLog));
            if (simulate)
            {
                Ui.Status(Main, "Simulation domaine terminee");
                AppendLog("Aucune modification appliquee (mode simulation).", "ATTENTION");
            }
            else
            {
                Ui.Status(Main, "Poste joint au domaine");
                AppendLog($"{computer} est membre de {domain} - redemarrage requis (reporte).", "OK");
            }
            Ui.Dialog($"Etape 2 - Integration Active Directory\n\nNom du poste : {computer}\nDomaine : {domain}\nCompte : {user}\n\n"
                + (simulate ? "Mode simulation : rien n'a ete applique." : "Le poste est joint au domaine. Redemarrez le PC pour finaliser."),
                "Integration au domaine");
        }
        catch (Exception ex)
        {
            AppendLog($"Erreur : {ex.Message}", "ERREUR");
            Ui.Status(Main, "Echec de la jonction au domaine");
            Ui.Dialog(ex.Message, "Erreur domaine", "error");
        }
        finally { SetButtonsEnabled(true); }
    }
}
