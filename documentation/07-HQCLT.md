# HQCLT - Client Windows HQ

> **OS** : Windows 11  
> **IP** : DHCP (VLAN 20 - Clients)  
> **Rôle** : Poste client simulant un employé du siège

---

## 🎯 Contexte (Sujet)

Ce poste simule un employé du siège HQ :

| Fonction | Description |
|----------|-------------|
| **DHCP** | Obtient son IP automatiquement de HQINFRASRV (plage 10.4.20.10-10.4.21.200). |
| **Domaine** | Membre du domaine `hq.wsl2025.org`. |
| **GPO** | Reçoit les GPO (certificats, Edge homepage, lecteurs réseau U:/S:/P:). |
| **Accès** | Doit pouvoir accéder aux ressources corporate et à Internet. |

---

## 📋 Prérequis

- [ ] Windows 11 installé
- [ ] Connecté au VLAN 20 (Clients)
- [ ] HQINFRASRV fonctionnel (DHCP)
- [ ] HQDCSRV fonctionnel (AD)

---

## 1️⃣ Configuration réseau

### Informations DHCP attendues

| Paramètre | Valeur |
|-----------|--------|
| IP | 10.4.20.X (plage 10.4.20.1 - 10.4.21.200) |
| Masque | 255.255.254.0 (/23) |
| Passerelle | 10.4.20.254 (VIP HSRP) |
| DNS | 10.4.10.1 (HQDCSRV) |
| Domaine | hq.wsl2025.org |
| NTP | 10.4.10.2 (HQINFRASRV) |

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
| Lettre | Chemin | Description |
|--------|--------|-------------|
| U: | `\\hq.wsl2025.org\users$\%username%` | Home drive |
| S: | `\\hq.wsl2025.org\Department$\%department%` | Département |
| P: | `\\hq.wsl2025.org\Public` | Public |

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

> **Instructions** : Exécuter ces tests sur HQCLT après connexion avec un utilisateur du domaine.

### 1. DHCP - IP obtenue
```powershell
ipconfig | Select-String "IPv4"
```
✅ Doit afficher une IP dans la plage `10.4.20.X` ou `10.4.21.X`

### 2. Domaine - Jonction vérifiée
```powershell
(Get-WmiObject Win32_ComputerSystem).Domain
```
✅ Doit afficher `hq.wsl2025.org`

### 3. GPO - Forcer l'application
```powershell
gpupdate /force
gpresult /r | Select-String "Objets"
```
✅ Doit lister les GPO appliquées

### 4. Lecteurs réseau
```powershell
Get-PSDrive | Where-Object { $_.Name -in @("U","S","P") }
```
✅ Les lecteurs U:, S:, P: doivent être présents

### 5. Certificats CA déployés
```powershell
Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.Subject -like "*WSFR*" }
```
✅ Doit afficher `WSFR-ROOT-CA`

### 6. Accès Internet
```powershell
Test-NetConnection -ComputerName google.com -Port 443
```
✅ `TcpTestSucceeded` doit être `True`

### 7. Accès ressources internes
```powershell
Test-NetConnection -ComputerName www.wsl2025.org -Port 443
Test-NetConnection -ComputerName webmail.wsl2025.org -Port 443
```
✅ Les deux doivent être accessibles

### 8. Edge - Page d'accueil (GPO)
- Ouvrir Microsoft Edge
- ✅ La page d'accueil doit être `www.wsl2025.org` ou l'intranet

### 9. Panneau de configuration (GPO)
- Se connecter avec `rola` (non-IT)
- Appuyer sur `Win+I`
- ✅ L'accès aux paramètres doit être bloqué

### Tableau récapitulatif

| Test | Commande/Action | Résultat attendu |
|------|-----------------|------------------|
| IP DHCP | `ipconfig` | `10.4.20.X` ou `10.4.21.X` |
| Domaine | `systeminfo \| find "Domaine"` | `hq.wsl2025.org` |
| Lecteur U: | `net use U:` | Connecté |
| Cert Root | `certmgr.msc` | WSFR-ROOT-CA présent |
| Internet | `ping google.com` | Réponse |
| Webmail | Navigateur | Page Roundcube |
