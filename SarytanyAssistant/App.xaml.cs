using System.IO;
using System.Windows;
using System.Windows.Threading;

namespace SarytanyAssistant;

public partial class App : Application
{
    /// <summary>
    /// Fenetre principale, accessible depuis n'importe quel thread (statique pure).
    /// Les moteurs appellent leurs callbacks depuis des threads de fond : ils ne
    /// doivent JAMAIS toucher un UIElement directement, toujours transiter par ici
    /// + Dispatcher (sinon exception cross-thread = fermeture silencieuse de l'app).
    /// </summary>
    public static MainWindow? MainWin { get; private set; }

    private static string ErrorLogFile => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "SarytanyAssistant", "erreurs.log");

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // FILET DE SECURITE GLOBAL : plus aucune fermeture silencieuse.
        // Toute exception qui fuite est journalisee dans %LOCALAPPDATA%\SarytanyAssistant\erreurs.log
        // et affichee a l'utilisateur ; l'application survit aux erreurs non prevues.
        DispatcherUnhandledException += OnDispatcherUnhandledException;
        AppDomain.CurrentDomain.UnhandledException += OnDomainUnhandledException;
        TaskScheduler.UnobservedTaskException += OnUnobservedTaskException;

        // Options de verification (equivalent -RenderTo/-NoDialogs du PS) :
        //   -StartView Pc|Bentley|Suite|Sintegra|Terra  : vue affichee au demarrage
        //   -NoLicense                                   : passe la fenetre de licence
        var args = e.Args;
        string? startView = null;
        for (var i = 0; i < args.Length - 1; i++)
            if (string.Equals(args[i], "-StartView", StringComparison.OrdinalIgnoreCase))
                startView = args[i + 1];

        var licenseLabel = "Bentley CONNECT";
        if (!args.Contains("-NoLicense", StringComparer.OrdinalIgnoreCase))
        {
            // La fenetre de licence est la premiere fenetre : elle devient
            // Application.MainWindow et sa fermeture declencherait l'arret
            // (mode OnMainWindowClose). On suspend l'arret pendant le dialogue.
            ShutdownMode = ShutdownMode.OnExplicitShutdown;
            var license = new LicenseWindow();
            if (license.ShowDialog() != true)
            {
                Shutdown(0);
                return;
            }
            licenseLabel = license.LicenseLabel;
        }

        var main = new MainWindow(licenseLabel, startView);
        MainWindow = main;
        MainWin = main;
        main.Show();
        ShutdownMode = ShutdownMode.OnMainWindowClose;

        // Auto-test cache (-DblSelfTest) : declenche le gestionnaire de double-clic
        // sur la premiere ligne rendue (verification du cablage import de secours).
        if (args.Contains("-DblSelfTest", StringComparer.OrdinalIgnoreCase))
        {
            var t = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2) };
            t.Tick += (_, _) =>
            {
                t.Stop();
                try { SelfTest.RaiseRowDoubleClick(main); }
                catch (Exception ex) { LogError("DblSelfTest", ex); }
            };
            t.Start();
        }
    }

    private void OnDispatcherUnhandledException(object sender, DispatcherUnhandledExceptionEventArgs e)
    {
        LogError("UI", e.Exception);
        try
        {
            MessageBox.Show(
                "Une erreur inattendue est survenue. Le programme reste ouvert, "
              + "mais l'operation en cours a ete interrompue.\n\n"
              + e.Exception.Message
              + "\n\nDetail ecrit dans : " + ErrorLogFile,
                "Assistant Sarytany - erreur", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        catch { }
        e.Handled = true;   // empeche la fermeture silencieuse de l'application
    }

    private static void OnDomainUnhandledException(object? sender, UnhandledExceptionEventArgs e)
        => LogError("Domaine", e.ExceptionObject as Exception);

    private static void OnUnobservedTaskException(object? sender, UnobservedTaskExceptionEventArgs e)
    {
        LogError("Tache", e.Exception);
        e.SetObserved();
    }

    /// <summary>Journalise une exception dans le fichier d'erreurs (jamais bloquant).</summary>
    public static void LogError(string source, Exception? ex)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(ErrorLogFile)!);
            File.AppendAllText(ErrorLogFile,
                $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] ({source}) {ex?.GetType().Name}: {ex?.Message}\n"
              + ex?.StackTrace + "\n\n");
        }
        catch { }
    }
}
