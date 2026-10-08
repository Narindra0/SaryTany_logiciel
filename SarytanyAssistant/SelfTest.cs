using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using SarytanyAssistant.Views;

namespace SarytanyAssistant;

/// <summary>
/// Auto-test de cablage du double-clic (argument cache -DblSelfTest) : resout la
/// premiere ligne d'etape rendue dans le VRAI arbre visuel de la vue courante,
/// puis invoque le gestionnaire de double-clic du gabarit. Verifie ainsi la
/// chaine complete ResolveRow -> RowDoubleClicked -> import Suite -> selecteur
/// de fichiers, sans dependre de l'injection souris (peu fiable a distance
/// quand l'operateur se sert de la machine).
/// </summary>
internal static class SelfTest
{
    public static void RaiseRowDoubleClick(DependencyObject root)
    {
        var stepList = FindByName(root, "StepList") as ListView
            ?? throw new InvalidOperationException("StepList introuvable (vue sans gabarit run ?)");
        var origin = FindRowElement(stepList)
            ?? throw new InvalidOperationException("Aucune ligne d'etape rendue dans StepList.");
        var run = FindAncestor<RunViewControl>(origin)
            ?? throw new InvalidOperationException("RunViewControl ancetre introuvable.");
        var mi = typeof(RunViewControl).GetMethod("TryFireRowDoubleClick",
            System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance)
            ?? throw new InvalidOperationException("TryFireRowDoubleClick introuvable.");
        mi.Invoke(run, new object?[] { origin });
    }

    private static DependencyObject? FindByName(DependencyObject root, string name)
    {
        if (root is FrameworkElement fe && fe.Name == name) return root;
        int n = VisualTreeHelper.GetChildrenCount(root);
        for (int i = 0; i < n; i++)
        {
            var hit = FindByName(VisualTreeHelper.GetChild(root, i), name);
            if (hit is not null) return hit;
        }
        return null;
    }

    private static FrameworkElement? FindRowElement(DependencyObject root)
    {
        if (root is FrameworkElement fe && fe.DataContext?.GetType().Name == "StepRow") return fe;
        int n = VisualTreeHelper.GetChildrenCount(root);
        for (int i = 0; i < n; i++)
        {
            var hit = FindRowElement(VisualTreeHelper.GetChild(root, i));
            if (hit is not null) return hit;
        }
        return null;
    }

    private static T? FindAncestor<T>(DependencyObject? node) where T : DependencyObject
    {
        while (node is not null)
        {
            if (node is T hit) return hit;
            node = VisualTreeHelper.GetParent(node);
        }
        return null;
    }
}
