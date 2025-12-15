# HQCLT - Client Windows HQ

> **OS** : Windows 11  
> **IP** : DHCP (VLAN 20 - Clients)  
> **Rôle** : Poste client simulant un employé du siège

---

## 🎯 Contexte (Sujet)

Ce poste simule un employé du siège HQ :

| Fonction    | Description                                                                  |
| ----------- | ---------------------------------------------------------------------------- |
| **DHCP**    | Obtient son IP automatiquement de HQINFRASRV (plage 10.4.20.10-10.4.21.200). |
| **Domaine** | Membre du domaine `hq.wsl2025.org`.                                          |
| **GPO**     | Reçoit les GPO (certificats, Edge homepage, lecteurs réseau U:/S:/P:).       |
| **Accès**   | Doit pouvoir accéder aux ressources corporate et à Internet.                 |

---

## 📋 Prérequis

- [ ] Windows 11 installé
- [ ] Connecté au VLAN 20 (Clients)
- [ ] HQINFRASRV fonctionnel (DHCP)
- [ ] HQDCSRV fonctionnel (AD)

---

## 1️⃣ Configuration réseau

### Informations DHCP attendues

| Paramètre  | Valeur                                    |
| ---------- | ----------------------------------------- |
| IP         | 10.4.20.X (plage 10.4.20.1 - 10.4.21.200) |
| Masque     | 255.255.254.0 (/23)                       |
| Passerelle | 10.4.20.254 (VIP HSRP)                    |
| DNS        | 10.4.10.1 (HQDCSRV)                       |
| Domaine    | hq.wsl2025.org                            |
| NTP        | 10.4.10.2 (HQINFRASRV)                    |

### Vérifier DHCP

```powershell
ipconfig /all
ipconfig /release
ipconfig /renew
```

---

## 2️⃣ Joindre le domaine

### Via GUI

1. **Paramètres** → **Système** → **À propos** → **Paramètres avancés**
2. **Nom de l'ordinateur** → **Modifier**
3. Sélectionner **Domaine** : `hq.wsl2025.org`
4. Entrer les credentials : `HQ\Administrator` / `P@ssw0rd`
5. Redémarrer

### Via PowerShell

```powershell
Add-Computer -DomainName "hq.wsl2025.org" -Credential (Get-Credential) -Restart
```

---

## 3️⃣ Tests de connectivité

### Réseau interne

```powershell
# Ping gateway
ping 10.4.20.254

# Ping serveurs
ping 10.4.10.1   # HQDCSRV
ping 10.4.10.2   # HQINFRASRV
ping 10.4.10.3   # HQMAILSRV

# Test DNS
nslookup www.wsl2025.org
nslookup hqdcsrv.hq.wsl2025.org
```

### Internet

```powershell
ping 8.8.4.1    # DNSSRV
ping 8.8.8.8    # Google DNS

# Sites web
Start-Process "https://www.wsl2025.org"
Start-Process "https://www.worldskills.org"
```

---

## 4️⃣ Vérifications post-jonction

### Connexion utilisateur

```
Utilisateurs disponibles :
- HQ\vtim (IT)
- HQ\npresso (Direction)
- HQ\jticipe (Factory)
- HQ\rola (Sales)
```

### Vérifier les GPO

```powershell
gpresult /r
gpresult /h C:\GPO-Report.html
```

### Lecteurs réseau mappés

| Lettre | Chemin                                      | Description |
| ------ | ------------------------------------------- | ----------- |
| U:     | `\\hq.wsl2025.org\users$\%username%`        | Home drive  |
| S:     | `\\hq.wsl2025.org\Department$\%department%` | Département |
| P:     | `\\hq.wsl2025.org\Public`                   | Public      |

```powershell
net use
```

---

## 5️⃣ Accès aux services

### Partages Samba (HQINFRASRV)

```powershell
# Accès au partage public
net use X: \\10.4.10.2\Public

# Accès au partage privé
net use Y: \\10.4.10.2\Private /user:tom P@ssw0rd
```

### Email

1. Configurer Outlook ou client mail
2. Serveur IMAP : `hqmailsrv.wsl2025.org:993` (SSL)
3. Serveur SMTP : `hqmailsrv.wsl2025.org:465` (SSL)

### Webmail

```powershell
Start-Process "https://webmail.wsl2025.org"
```

### RDS (RemoteApp)

```powershell
Start-Process "https://hqwebsrv.hq.wsl2025.org/RDWeb"
# Ou via IP : https://217.4.160.2/RDWeb
```

### Site authentication (Sales uniquement)

```powershell
Start-Process "https://authentication.wsl2025.org"
# Seul l'utilisateur rola (Sales) peut y accéder
```

---

## 6️⃣ Vérification des certificats

```powershell
# Ouvrir le gestionnaire de certificats
certmgr.msc

# Vérifier dans :
# - Autorités de certification racines de confiance → WSFR-ROOT-CA
# - Autorités de certification intermédiaires → WSFR-SUB-CA
```

---

## ✅ Vérification Finale

### 🔌 Comment se connecter à HQCLT

1. Ouvrir la console VMware ou se connecter physiquement au poste
2. Se connecter avec un utilisateur du domaine : `HQ\vtim` / `P@ssw0rd`
3. Attendre que le bureau Windows 11 s'affiche
4. Clic droit sur le bouton Windows → **Terminal** ou **PowerShell**

---

### Test 1 : Vérifier l'IP obtenue par DHCP

**Étape 1** : Tape cette commande :
```powershell
ipconfig | findstr "IPv4"
```

**Étape 2** : Regarde le résultat :
```
   Adresse IPv4. . . . . . . . . . . . . .: 10.4.20.15
```

✅ **C'est bon si** : L'IP commence par `10.4.20.` ou `10.4.21.`
❌ **Problème si** : IP en `169.254.x.x` → DHCP ne fonctionne pas

---

### Test 2 : Vérifier la jonction au domaine

**Étape 1** : Tape cette commande :
```powershell
systeminfo | findstr "Domaine"
```

**Étape 2** : Regarde le résultat :
```
Domaine:                       hq.wsl2025.org
```

✅ **C'est bon si** : Tu vois `hq.wsl2025.org`
❌ **Problème si** : Tu vois `WORKGROUP` → Pas joint au domaine

---

### Test 3 : Vérifier les lecteurs réseau

**Étape 1** : Ouvre l'Explorateur de fichiers (touche Windows + E)

**Étape 2** : Regarde dans le panneau de gauche sous "Ce PC"

✅ **C'est bon si** : Tu vois les lecteurs :
- `U:` (Home drive de l'utilisateur)
- `S:` (Partage Department)
- `P:` (Partage Public)

❌ **Problème si** : Les lecteurs n'apparaissent pas → GPO non appliquée

**Alternative en PowerShell** :
```powershell
net use
```
Tu dois voir les 3 lecteurs listés.

---

### Test 4 : Vérifier les certificats CA

**Étape 1** : Appuie sur Windows + R, tape `certmgr.msc`, appuie sur Entrée

**Étape 2** : Dans la fenêtre qui s'ouvre :
1. Clique sur **Autorités de certification racines de confiance**
2. Clique sur **Certificats**
3. Cherche dans la liste `WSFR-ROOT-CA`

✅ **C'est bon si** : Tu trouves `WSFR-ROOT-CA` dans la liste
❌ **Problème si** : Pas présent → GPO certificats non appliquée

---

### Test 5 : Vérifier l'accès Internet

**Étape 1** : Tape cette commande :
```powershell
ping google.com -n 2
```

**Étape 2** : Regarde le résultat :
```
Réponse de 142.250.X.X : octets=32 temps=XXms TTL=XX
```

✅ **C'est bon si** : Tu vois des réponses avec des temps en ms
❌ **Problème si** : "Délai d'attente de la demande dépassé" → Pas d'accès Internet

---

### Test 6 : Vérifier l'accès au webmail

**Étape 1** : Ouvre Microsoft Edge (ou Firefox)

**Étape 2** : Tape dans la barre d'adresse : `https://webmail.wsl2025.org`

**Étape 3** : Regarde ce qui s'affiche

✅ **C'est bon si** : Tu vois la page de connexion Roundcube
❌ **Problème si** : "Page inaccessible" → Problème réseau ou NAT

---

### Test 7 : Vérifier Edge page d'accueil (GPO)

**Étape 1** : Ferme complètement Edge s'il est ouvert

**Étape 2** : Ouvre Edge (icône dans la barre des tâches)

**Étape 3** : Regarde quelle page s'ouvre automatiquement

✅ **C'est bon si** : La page `www.wsl2025.org` s'ouvre automatiquement
❌ **Problème si** : Page Microsoft par défaut → GPO Edge non appliquée

---

### Test 8 : Vérifier le blocage du panneau de config (GPO)

> ⚠️ Ce test doit être fait avec un utilisateur NON-IT (ex: `HQ\rola`)

**Étape 1** : Déconnecte-toi et reconnecte-toi avec `HQ\rola` / `P@ssw0rd`

**Étape 2** : Appuie sur Windows + I (pour ouvrir les Paramètres)

✅ **C'est bon si** : Message "Cette opération a été annulée..." ou fenêtre qui ne s'ouvre pas
❌ **Problème si** : Les paramètres s'ouvrent normalement → GPO non appliquée

---

### 📋 Résumé rapide PowerShell

```powershell
Write-Host "=== IP ===" -ForegroundColor Cyan
ipconfig | findstr "IPv4"

Write-Host "=== DOMAINE ===" -ForegroundColor Cyan
systeminfo | findstr "Domaine"

Write-Host "=== LECTEURS ===" -ForegroundColor Cyan
net use | findstr ":"

Write-Host "=== INTERNET ===" -ForegroundColor Cyan
ping google.com -n 1 | findstr "Réponse"

Write-Host "=== CERT CA ===" -ForegroundColor Cyan
Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.Subject -like "*WSFR*" } | Select-Object Subject
```
