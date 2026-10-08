using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

namespace SarytanyAssistant.Views;

/// <summary>
/// Gabarit "run" partage (port de New-RunView dans src\50-Widgets.ps1) :
/// carte statut + liste d'etapes colorees + journal sombre + barre d'actions.
/// Hierarchie volontaire : une seule couleur forte (bleu primaire), secondaires
/// grises, ambre reserve a l'etat "reprise manuelle attendue".
/// Les moteurs s'appellent en tache de fond (Task) ; les callbacks reviennent
/// sur le thread UI via Dispatcher.
/// </summary>
public partial class RunViewControl : UserControl
{
    public sealed class StepRow : INotifyPropertyChanged
    {
        private string _status = "EN ATTENTE";
        private string _description = "";
        private Brush _rowBrush = new SolidColorBrush(Color.FromRgb(0x64, 0x74, 0x8B));
        public required string Label { get; init; }
        public required string Description
        {
            get => _description;
            set { _description = value; OnChanged(nameof(Description)); }
        }
        public string Status
        {
            get => _status;
            set { _status = value; OnChanged(nameof(Status)); }
        }
        public Brush RowBrush
        {
            get => _rowBrush;
            set { _rowBrush = value; OnChanged(nameof(RowBrush)); }
        }
        public event PropertyChangedEventHandler? PropertyChanged;
        private void OnChanged(string p) => PropertyChanged?.Invoke(this, new(p));
    }

    public sealed class LogLine
    {
        public required string Time { get; init; }
        public required string Text { get; init; }
        public required Brush Brush { get; init; }
    }

    // Evenements de la barre d'actions, consommes par les vues.
    public event Action? GoClicked;
    public event Action? ExtraClicked;
    public event Action? ResumeClicked;
    public event Action? CancelClicked;

    /// <summary>Double-clic sur une ligne d'etape (index de la ligne) : import de secours.</summary>
    public event Action<int>? RowDoubleClicked;

    private readonly ObservableCollection<StepRow> _rows = new();
    private readonly ObservableCollection<LogLine> _logs = new();

    private static readonly Brush BgMuted  = new SolidColorBrush(Color.FromRgb(0x64, 0x74, 0x8B));
    private static readonly Brush BgAccent = new SolidColorBrush(Color.FromRgb(0x00, 0x72, 0xD2));
    private static readonly Brush BgGreen  = new SolidColorBrush(Color.FromRgb(0x10, 0xB9, 0x81));
    private static readonly Brush BgAmber  = new SolidColorBrush(Color.FromRgb(0xF5, 0x9E, 0x0B));
    private static readonly Brush BgRed    = new SolidColorBrush(Color.FromRgb(0xEF, 0x44, 0x44));
    private static readonly Brush BgText   = new SolidColorBrush(Color.FromRgb(0x0F, 0x17, 0x2A));

    private static readonly Brush LogOk        = new SolidColorBrush(Color.FromRgb(0x48, 0xCD, 0x94));
    private static readonly Brush LogError     = new SolidColorBrush(Color.FromRgb(0xFF, 0x7A, 0x7A));
    private static readonly Brush LogWarn      = new SolidColorBrush(Color.FromRgb(0xFF, 0xBE, 0x64));
    private static readonly Brush LogDefault   = new SolidColorBrush(Color.FromRgb(0xB2, 0xBE, 0xCE));

    public Button GoButton => BtnGo;
    public Button ExtraButton => BtnExtra;
    public Button ResumeButton => BtnResume;
    public Button CancelButton => BtnCancel;

    /// <summary>Nombre de lignes d'etape du gabarit.</summary>
    public int StepCount => _rows.Count;

    /// <summary>
    /// Condition de readiness du bouton "Demarrer" (spec Suite : active uniquement
    /// quand tous les emplacements et prerequis sont complets). Null = toujours actif.
    /// </summary>
    public Func<bool>? GoEnabledPredicate { get; set; }

    public RunViewControl()
    {
        InitializeComponent();
        StepList.ItemsSource = _rows;
        LogLines.ItemsSource = _logs;
        // Double-clic = import de secours (vue Suite). Double filet de securite :
        //  1) PreviewMouseLeftButtonDown avec ClickCount==2 : evenement tunnel emis
        //     par le noyau WPF sur tout vrai double-clic, jamais absorbe par les
        //     ListViewItem Focusable=False (bug constate 2026-10-08 : l'ancien
        //     MouseDoubleClick "bulle" etait avale et le selecteur ne s'ouvrait pas) ;
        //  2) PreviewMouseDoubleClick en secours. Un anti-rebond (500 ms) empeche
        //     l'ouverture de deux dialogues quand les deux voies declenchent.
        // La ligne est resolue depuis l'origine reelle (arbre visuel), donc sans
        // dependre de SelectedItem.
        StepList.PreviewMouseLeftButtonDown += StepList_PreviewMouseDown;
        StepList.PreviewMouseDoubleClick += OnStepListDoubleClicked;
    }

    private DateTime _lastDblUtc = DateTime.MinValue;

    private void StepList_PreviewMouseDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ClickCount != 2) return;
        _lastDblUtc = DateTime.UtcNow;
        TryFireRowDoubleClick(e.OriginalSource as DependencyObject);
    }

    private void OnStepListDoubleClicked(object sender, MouseButtonEventArgs e)
    {
        e.Handled = true;   // evite la double activation par l'evenement bulle
        // Deja traite par la voie "down" (anti-rebond) : ne rien faire.
        if ((DateTime.UtcNow - _lastDblUtc).TotalMilliseconds < 500) return;
        TryFireRowDoubleClick(e.OriginalSource as DependencyObject);
    }

    private void TryFireRowDoubleClick(DependencyObject? origin)
    {
        StepRow? row = ResolveRow(origin) ?? StepList.SelectedItem as StepRow;
        if (row is null) return;
        RowDoubleClicked?.Invoke(_rows.IndexOf(row));
    }

    private StepRow? ResolveRow(DependencyObject? origin)
    {
        while (origin is not null)
        {
            if (origin is FrameworkElement { DataContext: StepRow row }) return row;
            origin = origin is Visual or System.Windows.Media.Media3D.Visual3D
                ? VisualTreeHelper.GetParent(origin)
                : LogicalTreeHelper.GetParent(origin);
        }
        return null;
    }

    /// <summary>Reevalue l'etat actif du bouton Demarrer quand la readiness change.</summary>
    public void RefreshGoEnabled()
    {
        Dispatcher.Invoke(() => BtnGo.IsEnabled = GoEnabledPredicate?.Invoke() ?? true);
    }

    /// <summary>Configure le gabarit : etapes, libelles, boutons visibles.</summary>
    public void Configure(string readyText, IReadOnlyList<(string Label, string Description)> steps,
                         string goText, string? extraText = null, bool showResume = false)
    {
        LblStatusDetail.Text = readyText;
        BtnGo.Content = goText;
        foreach (var (label, desc) in steps)
            _rows.Add(new StepRow { Label = label, Description = desc });
        StepList.Height = Math.Min(26 * _rows.Count + 10, 300);
        if (extraText is not null) BtnExtra.Content = extraText;
        else BtnExtra.Visibility = Visibility.Collapsed;
        if (!showResume) BtnResume.Visibility = Visibility.Collapsed;
    }

    // ================= JOURNAL =================
    public void Log(string message, string level = "INFO")
    {
        var brush = level switch
        {
            "OK" => LogOk,
            "ERREUR" => LogError,
            "ATTENTION" => LogWarn,
            _ => LogDefault,
        };
        // Les moteurs appellent depuis un thread de fond : on revient sur l'UI.
        Dispatcher.Invoke(() =>
        {
            _logs.Add(new LogLine { Time = DateTime.Now.ToString("HH:mm:ss"), Text = message, Brush = brush });
            while (_logs.Count > 800) _logs.RemoveAt(0);   // garde-fou memoire
            LogScroll.ScrollToEnd();
        });
    }

    public void ClearLog() { _logs.Clear(); }

    private void ClearLog_Click(object sender, RoutedEventArgs e) => _logs.Clear();

    // ================= ETAT GLOBAL =================
    /// <summary>Met a jour carte statut + boutons (contrat Set-UiStatus).</summary>
    public void SetUiStatus(bool running, string status, string detail = "", int percent = -1,
                            string pillText = "EN ATTENTE", string pillKind = "muted", string barKind = "accent")
    {
        Dispatcher.Invoke(() =>
        {
            BtnGo.IsEnabled = !running && (GoEnabledPredicate?.Invoke() ?? true);
            if (BtnExtra.Visibility == Visibility.Visible) BtnExtra.IsEnabled = !running;
            BtnCancel.IsEnabled = running;
            // BtnResume garde son etat propre (pilote par la vue Suite).

            LblStatusTitle.Text = status;
            if (!string.IsNullOrEmpty(detail)) LblStatusDetail.Text = detail;

            PillText.Text = pillText;
            PillBg.Background = pillKind switch
            {
                "green" => BgGreen, "red" => BgRed, "amber" => BgAmber,
                "accent" => BgAccent, _ => BgMuted,
            };
            PillText.Foreground = pillKind == "amber" ? BgText : Brushes.White;

            if (percent >= 0)
                Progress.Value = Math.Clamp(percent, 0, 100);

            Progress.Foreground = barKind switch
            {
                "green" => BgGreen, "red" => BgRed, "amber" => BgAmber, _ => BgAccent,
            };
        });
    }

    // ================= LIGNES D'ETAPES =================
    /// <summary>EN ATTENTE discret, EN COURS bleu, OK vert, ERREUR rouge.</summary>
    public void SetRow(int index, string state)
    {
        Dispatcher.Invoke(() =>
        {
            if (index < 0 || index >= _rows.Count) return;
            var row = _rows[index];
            row.Status = state;
            row.RowBrush = state switch
            {
                "OK" => BgGreen,
                "ERREUR" => BgRed,
                "EN COURS" => BgAccent,
                "MANUEL" => BgAmber,
                // Etats de readiness de la vue Suite (avant installation).
                "MANQUANT" => BgRed,
                "IMPORTE" => BgAmber,
                _ => BgMuted,
            };
        });
    }

    public void ResetRows()
    {
        foreach (var r in _rows) { r.Status = "EN ATTENTE"; r.RowBrush = BgMuted; }
    }

    /// <summary>Met a jour la description d'une ligne (ex. "IMPORTE : fichier.msi").</summary>
    public void UpdateRowDescription(int index, string description)
    {
        Dispatcher.Invoke(() =>
        {
            if (index >= 0 && index < _rows.Count) _rows[index].Description = description;
        });
    }

    /// <summary>Lignes 'EN COURS' -> 'ERREUR' (comportement des vues PS d'origine).</summary>
    public void MarkRunningRowsAsError(int count) => MarkRunningRowsAsError(count, "ERREUR");

    /// <summary>Lignes 'EN COURS' -> etat donne ('ARRET' pour une annulation).</summary>
    public void MarkRunningRowsAsError(int count, string state)
    {
        Dispatcher.Invoke(() =>
        {
            for (var i = 0; i < Math.Min(count, _rows.Count); i++)
                if (_rows[i].Status == "EN COURS") SetRow(i, state);
        });
    }

    /// <summary>Reprise manuelle : ambre quand attendue, gris sinon.</summary>
    public void SetResumeHighlight(bool on)
    {
        Dispatcher.Invoke(() =>
        {
            BtnResume.Style = (Style)FindResource(on ? "WarnButton" : "SecondaryButton");
        });
    }

    // ================= BARRE D'ACTIONS =================
    private void BtnGo_Click(object sender, RoutedEventArgs e) => GoClicked?.Invoke();
    private void BtnExtra_Click(object sender, RoutedEventArgs e) => ExtraClicked?.Invoke();
    private void BtnResume_Click(object sender, RoutedEventArgs e) => ResumeClicked?.Invoke();
    private void BtnCancel_Click(object sender, RoutedEventArgs e) => CancelClicked?.Invoke();
}
