# 📘 Guide Git - SAE501 ConfigReseau

> **Repository** : https://github.com/L4Curtis/sae501.git  
> **Branche principale** : `main`

---

## 🚀 Commandes rapides

### Voir l'état actuel

```powershell
git status
```

### Ajouter et commit

```powershell
# Ajouter tous les fichiers modifiés
git add .

# Ou ajouter des dossiers spécifiques
git add documentation/
git add verification/

# Commit avec message
git commit -m "description des changements"
```

### Push vers GitHub

```powershell
git push
```

### Tout en une commande (add + commit + push)

```powershell
git add . ; git commit -m "message" ; git push
```

---

## 📝 Exemples de commits typiques

### Après modification de documentation

```powershell
git add documentation/
git commit -m "docs(HQDCSRV): mise à jour section GPO"
git push
```

### Après modification de vérification

```powershell
git add verification/
git commit -m "docs(verification): ajout tests quotas"
git push
```

### Après modification de plusieurs fichiers

```powershell
git add documentation/ verification/
git commit -m "fix(partages): correction permissions SMB et NTFS"
git push
```

---

## 🔄 Récupérer les dernières modifications

### Depuis un autre PC

```powershell
git pull
```

### Si conflit (forcer la version distante)

```powershell
git fetch origin
git reset --hard origin/main
```

---

## 📊 Voir l'historique

### Derniers commits

```powershell
git log --oneline -10
```

### Voir les modifications d'un fichier

```powershell
git log --oneline documentation/04-HQDCSRV.md
```

### Voir les différences avant commit

```powershell
git diff
```

---

## 🏷️ Conventions de messages de commit

| Préfixe      | Utilisation                                |
| ------------ | ------------------------------------------ |
| `docs()`     | Modification de documentation              |
| `fix()`      | Correction d'erreur                        |
| `feat()`     | Nouvelle fonctionnalité                    |
| `refactor()` | Réorganisation sans changement fonctionnel |
| `test()`     | Ajout/modification de tests                |

### Exemples

```
docs(HQDCSRV): ajout section 7.8 permissions NTFS
fix(GPO): correction exclusion groupe IT
feat(verification): ajout guide DNSSRV
refactor(gpo): script création unique + config GUI
```

---

## 🛠️ Configuration initiale (si nouveau PC)

```powershell
# Configurer nom et email
git config --global user.name "Ton Nom"
git config --global user.email "ton.email@example.com"

# Cloner le repo
git clone https://github.com/L4Curtis/sae501.git
cd sae501
```

---

## ⚠️ Problèmes courants

### "LF will be replaced by CRLF"

C'est juste un warning, ignorable. Pour le désactiver :

```powershell
git config --global core.autocrlf true
```

### "Your branch is behind"

```powershell
git pull --rebase
git push
```

### Annuler le dernier commit (non pushé)

```powershell
git reset --soft HEAD~1
```

### Annuler toutes les modifications locales

```powershell
git checkout -- .
```

---

## 📁 Structure du projet

```
configreseau/
├── documentation/       # Guides de configuration
│   ├── 03-DCWSL.md
│   ├── 04-HQDCSRV.md
│   └── 13-DNSSRV.md
├── verification/        # Guides de vérification
│   ├── 00-INDEX.md
│   ├── 03-DCWSL-verification.md
│   ├── 04-HQDCSRV-verification.md
│   └── 13-DNSSRV-verification.md
├── sujet/              # Sujets de la SAE
└── jalons_rendu/       # Descriptions des jalons
```

---

## 🔗 Liens utiles

- **GitHub repo** : https://github.com/L4Curtis/sae501
- **GitHub Desktop** : https://desktop.github.com/ (alternative GUI)
