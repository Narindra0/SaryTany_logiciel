using System.Windows;

namespace SarytanyAssistant;

/// <summary>Petits helpers partages par les vues (equivalent Show-Dialog / Set-Status).</summary>
public static class Ui
{
    public static void Dialog(string text, string title, string icon = "info")
    {
        var img = icon switch
        {
            "error" => MessageBoxImage.Error,
            "warning" => MessageBoxImage.Warning,
            _ => MessageBoxImage.Information,
        };
        MessageBox.Show(text, title, MessageBoxButton.OK, img);
    }

    /// <summary>
    /// Met a jour la barre de statut. SUR-ALL-THREADS : les moteurs rappellent
    /// depuis leurs threads de fond ; on transite toujours par le Dispatcher de
    /// la fenetre principale (Window.GetWindow depuis un thread de fond = crash).
    /// </summary>
    public static void Status(string message)
    {
        var mw = App.MainWin;
        if (mw is null) return;
        try { mw.Dispatcher.BeginInvoke(() => mw.SetStatus(message)); }
        catch { }
    }

    /// <summary>Variante avec proprietaire (ignore si l'objet n'est pas la fenetre principale).</summary>
    public static void Status(Window? owner, string message)
    {
        var mw = owner as MainWindow ?? App.MainWin;
        if (mw is null) return;
        try { mw.Dispatcher.BeginInvoke(() => mw.SetStatus(message)); }
        catch { }
    }
}
