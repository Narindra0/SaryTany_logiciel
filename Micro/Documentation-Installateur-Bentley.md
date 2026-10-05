# Documentation — Installateur automatisé Bentley Suite (v1.4.0.0)

## 1. Présentation

Ce programme automatise l'installation **séquentielle de 21 modules Bentley**
(MicroStation / PowerDraft) : prérequis MSI, correctifs MSP, gros installateurs EXE
et patch final MicroStation Update 11.

Fichiers livrés dans `Micro/` :

| Fichier | Rôle |
|---|---|
| `Install-BentleySuite.exe` | **Programme à utiliser** : double-clic, aucune installation requise (demande admin via UAC) |
| `Install-BentleySuite.ps1` | Code source PowerShell (à modifier pour personnaliser, puis recompiler) |
| `icon.jpg` / `icon.ico` | Logo (embarqué dans le programme ; `icon.ico` sert à la compilation) |
| Ce document | Mode d'emploi + maintenance |

## 2. Prérequis

- **Windows 10/11 64 bits**, compte autorisé à passer administrateur (UAC).
- Le **dossier source** contenant les **21 fichiers** ci-dessous (nommés `01-…` à `22-…`, pas de n°10) :

| N° | Module | Fichier réel | Mode |
|---|---|---|---|
| 01 | DgnIFilterSetUpx64 | `01-DgnIFilterSetUpx64.msi` | Auto |
| 02 | DgnIndexer | `02-DgnIndexer.msi` | Auto |
| 03 | DgnPreviewHandlerx64 | `03- DgnPreviewHandlerx64.msi` (avec espace !) | Auto |
| 04 | DgnThumbnailProviderx64 | `04-DgnThumbnailProviderx64.msi` | Auto |
| 05 | HDRPreviewExtension_x64 | `05-HDRPreviewExtension_x64.msi` | Auto |
| 06 | ItgDgnDbImporter 1.6 | `06-ItgDgnDbImporter_1.6_x64.msi` | Auto |
| 07 | ItgDgnDbImporter 2.0 | `07-ItgDgnDbImporter_2.0_x64.msi` | Auto |
| 08 | MetroStationx64 | `08-MetroStationx64.msi` | Auto |
| 09 | Pointools32Extx86 | `09-Pointools32Extx86.msi` | Auto |
| 11 | PowerDraftDocumentation | `11-PowerDraftDocumentationProductx64.msi` | Auto |
| 12 | PowerDraftx64 | `12-PowerDraftx64.msi` | Auto |
| **13** | **CONNECTION Client 10.00.12.006** | `13-Setup_CONNECTIONClientx64_10.00.12.006.exe` | **Manuel** |
| **14** | **PowerDraft 10.11.00.036** | `14-Setup_PowerDraftx64_10.11.00.036.exe` | **Manuel** |
| **15** | **CONNECT Advisor 10.01.00.103** | `15-Setup_CONNECTAdvisorx64_10.01.00.103.exe` | **Manuel** |
| 16 | Vba71 | `16-Vba71.msi` | Auto |
| 17 | Vba71_1033 | `17-Vba71_1033.MSI` | Auto |
| 18 | VBA71-KB2803801-x64 | `18-VBA71-KB2803801-x64.msp` | Auto |
| 19 | VBA71-KB2803801-x64_1033 | `19-VBA71-KB2803801-x64_1033.msp` | Auto |
| 20 | VBA71-KB3061498-x64 | `20-VBA71-KB3061498-x64.msp` | Auto |
| 21 | patch.x64 | `21-patch.x64.msp` | Auto |
| 22 | MicroStation Update 11 REV3 | `22-microstation…patch-REV3.exe` | Auto |

> La détection est **tolérante** : recherche par motif puis repli par **numéro**
> (`01*`, `06*`…), insensible à la casse et aux espaces parasites. C'est ce qui
> absorbe les coquilles historiques (`Dgnl…` vs `DgnIFilter…`, `Dblmporter` vs
> `DbImporter`).

## 3. Parcours utilisateur (3 étapes guidées)

Un **bandeau bleu** en haut de la fenêtre indique toujours l'étape en cours.

1. **Licence** — au lancement (après l'UAC), une fenêtre demande le **code
   d'activation : `ICECREAM`** (casse ignorée). Code faux → message d'erreur,
   nouvel essai. Bouton *« Je n'ai pas de code »* → ouvre la fiche **Contact**,
   puis le programme se ferme.
2. **Étape 1/3 — Dossier** : la fenêtre *Parcourir* s'ouvre **toute seule**.
   Choisissez le dossier source (ex. `D:\LIDAR\Bentley.MicroStation`). En cas
   d'annulation, le bandeau invite à cliquer sur `Parcourir`.
3. **Étape 2/3 — Vérification automatique** : les 21 fichiers sont contrôlés,
   la liste des modules sort du **voile gris** et affiche les fichiers détectés
   (`MANQUANT` si absent). Si incomplet → message + la liste reste grisée.
4. **Étape 3/3 — Carte 3 verte `DEMARRER >`** : cliquez dessus. La progression
   avance, chaque ligne passe : 🟡 *En cours...* → 🟢 *Succès* ou 🔴 *Échec*.
   - **Modules 13/14/15** : pause automatique (🟠 *Action requise*), l'installeur
     s'ouvre **en manuel**, puis cliquez `Continuer / Valider` et confirmez
     Oui (= Succès) / Non (= Échec).
   - `Annuler` interrompt proprement entre deux modules.
5. **Rapport final** : popup récapitulatif (succès / échecs) + détails dans le journal.

## 4. L'interface, zone par zone (thème clair, sobre)

- **Header** : logo diable + point vert + titre versionné, liens `A propos` / `Support` / `Quitter` à droite.
- **Bandeau d'étape** : consigne unique en bleu + **badge** d'état à droite (`EN ATTENTE` → `DOSSIER` → `CONTROLE` → `VERIFIE` → `EN COURS` → `TERMINE` / `ERREUR`).
- **3 cartes d'étapes** : `1. DOSSIER SOURCE` (cliquable : Parcourir, affiche le chemin), `2. VERIFICATION` (`21 modules (0/21)` → `21/21 Valides` en vert, recliquable pour re-vérifier), `3. INSTALLATION` (grisée `En attente` → verte `DEMARRER >` → `En cours...` → `Termine`).
- **Carte Progression** : `Progression globale` + `%` + bouton `Annuler` (actif pendant l'installation).
- **Liste Modules** : grille sombre (police Consolas), colonnes N. / Module / Fichier détecté / Mode / Statut. **Désactivée (grisée) tant que la vérification n'a pas réussi.**
- **Journal** : zone sombre horodatée `[HH:MM:SS][NIVEAU]`, copiée dans `%TEMP%\BentleyInstall_….log`. Boutons `Journal complet` (ouvre le .log) / `Effacer`.
  Chaque MSI/MSP génère en plus son log `msiexec` : `%TEMP%\Bentley_NN_….log`.
- **Barre basse** : `Continuer / Valider` (pauses manuelles 13/14/15, orange quand requis), rappel, version + auteur à droite.
- **Fiche Contact** : Narindra Ranjalahy — email cliquable (`mailto`), WhatsApp
  cliquable (`wa.me/261328814081`), boutons copier vers le presse-papiers.
- **Fiche À propos** : version, descriptif, auteur, copyright, accès au support.

## 5. Statuts et codes

| Statut | Couleur | Signification |
|---|---|---|
| En attente | blanc | pas encore traité |
| En cours… | jaune | installation lancée |
| Succès | vert | code 0 (ou 1641/3010 = succès + redémarrage requis) |
| Échec | rouge | code ≠ 0 → voir le journal + le log `msiexec` du module |
| Action requise | orange | module manuel 13/14/15 : à vous de jouer |

## 6. Personnalisation (dans `Install-BentleySuite.ps1`)

| Besoin | Où modifier |
|---|---|
| Code d'activation | `Install-BentleySuite.ps1:287` (`$LicenseCode`) — comparaison insensible à la casse ; mettez `-ceq` pour la rendre stricte |
| Coordonnées support | `Install-BentleySuite.ps1:45` (`$SupportMail`, `$SupportWaDisplay`, lien `wa.me`) |
| Version affichée | `Install-BentleySuite.ps1:48` (`$AppVersion`) |
| Arguments silencieux des EXE | `Install-BentleySuite.ps1:419` (`$DefaultSilentExeArgs`, défaut `/S`) — MSI/MSP restent en `/qn /norestart` |
| Liste des modules | `Install-BentleySuite.ps1:421` (bloc `$Modules` : `Num`, `Name`, `Pattern`, `Manual`) |
| Logo embarqué | entre `Install-BentleySuite.ps1:458` et `:460` (remplacé auto par `embed-logo.ps1`) |
| Vérification manuelle | `Install-BentleySuite.ps1:859` (`function Invoke-Verification`) |

> ⚠️ Écrivez le script **sans accents ni caractères spéciaux** (é, —, •, ▶…) :
> PowerShell 5.1 lit les `.ps1` sans BOM en ANSI et cela **casse la compilation**.
> Après chaque modification, relancez le contrôle de syntaxe avant de recompiler.

## 7. Recompiler l'EXE (après modification du `.ps1`)

Le module `ps2exe` est déjà installé sur ce poste. Dans PowerShell :

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\IT_ST\AppData\Local\Temp\opencode\build-exe.ps1"
```

(Contenu : `Invoke-ps2exe` avec `-noConsole -requireAdmin -x64 -STA`,
`-iconFile icon.ico`, métadonnées société/version — alignez `-version` avec
`$AppVersion`.) Puis contrôle :

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\IT_ST\AppData\Local\Temp\opencode\verify-exe.ps1"
```

## 8. Dépannage

| Symptôme | Cause probable / Action |
|---|---|
| UAC au lancement | **Normal** : l'installeur exige les droits admin |
| Alerte SmartScreen « éditeur inconnu » | **Normal** (EXE non signé) : *Informations complémentaires → Exécuter quand même* ; si fichier « bloqué » : clic droit → Propriétés → Débloquer |
| « Fichiers manquants (01, 06, 07) » | Ancienne version : mettez à jour vers ≥ v1.1 (motifs corrigés + repli par numéro) |
| Module en Échec | Ouvrez son log `%TEMP%\Bentley_ NN _….log` (ex. `1603` = échec MSI générique, `1618` = autre installation en cours) puis relancez |
| Fenêtre Parcourir non vue | Elle s'ouvre derrière ? L'icône diable clignote dans la barre des tâches |
| Antivirus qui supprime l'EXE | Faux positif classique des EXE ps2exe : restaurez + ajoutez une exclusion |
| Code `ICECREAM` refusé | Espaces avant/après ? Le programme les ignore déjà ; vérifiez la version du programme |

## 9. Limites assumées

- Le code d'activation est **lisible dans le `.ps1`** : c'est un verrou simple
  anti-utilisation occasionnelle, pas une protection inviolable. L'EXE compilé
  relève la barrière (chaînes extractibles avec des outils adaptés) sans
  l'éliminer. Pour un besoin fort : licence par machine (fichier signé).
- Installations **séquentielles** (~20–40 min au total) : c'est volontaire
  (les MSI se marchent dessus en parallèle).
- Les EXE Bentley en mode `/S` dépendent de chaque installeur : si un EXE
  ignore le mode silencieux, basculez son module en `Manual=$true`.

---
*Développé par **Narindra Ranjalahy** — ranjalahy.narindraa@gmail.com — WhatsApp 0328814081.*
