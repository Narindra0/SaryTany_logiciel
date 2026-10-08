using System.Windows;
using System.Windows.Controls;
using SarytanyAssistant.Views;

namespace SarytanyAssistant;

/// <summary>
/// Coque principale (port de src\60-Shell.ps1) : bandeau titre + licence,
/// sidebar 5 vues, contenu, pied de page avec etat horodate.
/// Les vues sont creees a la premiere activation (lazy) : le demarrage
/// reste instantane et aucune lecture systeme n'est faite a l'avance.
/// </summary>
public partial class MainWindow : Window
{
    private readonly Dictionary<RadioButton, (string Key, string Title, Func<UserControl> Factory)> _views = new();
    private readonly Dictionary<RadioButton, UserControl> _instances = new();
    private bool _ready;

    public MainWindow(string licenseLabel, string? startView = null)
    {
        InitializeComponent();
        LblLicense.Text = licenseLabel;

        // Les vues sont creees paresseusement : le constructeur ne doit pas
        // declencher de lecture systeme avant l'affichage.
        _views[NavPc]       = ("Pc",       "Configuration PC",    () => new PcConfigView());
        _views[NavBentley]  = ("Bentley",  "Deploiement Bentley", () => new DeploymentView());
        _views[NavSuite]    = ("Suite",    "Installation Suite",  () => new SuiteView());
        _views[NavSintegra] = ("Sintegra", "SintegraLidar",       () => new SintegraView());
        _views[NavTerra]    = ("Terra",    "Installation Terra",  () => new TerraView());

        _ready = true;
        var initial = _views.Keys.FirstOrDefault(rb => _views[rb].Key.Equals(startView, StringComparison.OrdinalIgnoreCase))
                      ?? NavPc;
        initial.IsChecked = true;
        ShowView(initial);
    }

    private void Nav_Checked(object sender, RoutedEventArgs e)
    {
        if (!_ready || sender is not RadioButton rb) return;
        ShowView(rb);
    }

    private UserControl Instance(RadioButton rb)
    {
        if (!_instances.TryGetValue(rb, out var view))
        {
            view = _views[rb].Factory();
            ContentHost.Children.Add(view);
            _instances[rb] = view;
        }
        return view;
    }

    private void ShowView(RadioButton rb)
    {
        var (key, title, _) = _views[rb];
        var active = Instance(rb);
        foreach (var view in _instances.Values)
            view.Visibility = view == active ? Visibility.Visible : Visibility.Collapsed;
        LblViewName.Text = $"Vue : {title}";
    }

    /// <summary>Etat horodate du pied de page (equivalent Set-Status).</summary>
    public void SetStatus(string message)
    {
        // Double filet : appel possible depuis un thread de fond.
        if (!Dispatcher.CheckAccess())
        {
            Dispatcher.BeginInvoke(() => SetStatus(message));
            return;
        }
        LblStatus.Text = $"{DateTime.Now:HH:mm:ss}  {message}";
    }
}
