# REMCLT - Client Windows Remote

> **OS** : Windows 11  
> **IP** : DHCP (VLAN Remote - 10.4.100.0/25)  
> **Rôle** : Poste client simulant un employé du site distant

---

## 🎯 Contexte (Sujet)

Ce poste simule un employé du site Remote (MAN) :

| Fonction | Description |
|----------|-------------|
| **DHCP** | Obtient son IP automatiquement de REMDCSRV/REMINFRASRV (plage 10.4.100.10-120). |
| **Domaine** | Membre du domaine `rem.wsl2025.org`. |
| **Accès** | Doit accéder aux ressources corporate (HQ et Remote) et à Internet via MAN. |

---

## 📋 Prérequis

- [ ] Windows 11 installé
- [ ] Connecté au réseau Remote (via REMFW)
- [ ] REMDCSRV fonctionnel (DHCP + AD)

---

## 1️⃣ Configuration réseau

### Informations DHCP attendues

| Paramètre | Valeur |
|-----------|--------|
| IP | 10.4.100.X (plage 10.4.100.10 - 10.4.100.120) |
| Masque | 255.255.255.128 (/25) |
| Passerelle | 10.4.100.126 (REMFW) |
| DNS | 10.4.100.1 (REMDCSRV) |
| Domaine | rem.wsl2025.org |
| NTP | 10.4.10.2 (HQINFRASRV via WAN) |

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
3. Sélectionner **Domaine** : `rem.wsl2025.org`
4. Entrer les credentials : `REM\Administrator` / `P@ssw0rd`
5. Redémarrer

### Via PowerShell
```powershell
Add-Computer -DomainName "rem.wsl2025.org" -Credential (Get-Credential) -Restart
```

---

## 3️⃣ Tests de connectivité

### Réseau local Remote
```powershell
# Ping gateway
ping 10.4.100.126

# Ping serveurs locaux
ping 10.4.100.1   # REMDCSRV
ping 10.4.100.2   # REMINFRASRV
```

### Réseau HQ (via MAN)
```powershell
# Ping serveurs HQ
ping 10.4.10.1    # HQDCSRV
ping 10.4.10.2    # HQINFRASRV
ping 10.4.10.3    # HQMAILSRV

# Test DNS inter-sites
nslookup hqdcsrv.hq.wsl2025.org
nslookup www.wsl2025.org
```

### Internet
```powershell
ping 8.8.4.1      # DNSSRV
ping 8.8.8.8      # Google DNS

# Sites web
Start-Process "https://www.wsl2025.org"
Start-Process "https://www.worldskills.org"
```

---

## 4️⃣ Utilisateurs disponibles

```
Utilisateurs du site Remote :
- REM\estique (Warehouse)
- REM\rtaha (Direction)
- REM\dpeltier (IT)
```

---

## 5️⃣ Vérifications post-jonction

### Vérifier les GPO
```powershell
gpresult /r
gpresult /h C:\GPO-Report.html
```

### Lecteurs réseau mappés
| Lettre | Chemin | Description |
|--------|--------|-------------|
| U: | `\\rem.wsl2025.org\files\users\%username%` | Home drive |
| S: | `\\rem.wsl2025.org\files\Department\%department%` | Département |

```powershell
net use
```

---

## 6️⃣ Accès aux services

### Email (via HQ)
1. Configurer Outlook
2. Serveur IMAP : `hqmailsrv.wsl2025.org:993` (SSL)
3. Serveur SMTP : `hqmailsrv.wsl2025.org:465` (SSL)

### Webmail
```powershell
Start-Process "https://webmail.wsl2025.org"
```

### Site web corporate
```powershell
Start-Process "https://www.wsl2025.org"
```

---

## 7️⃣ Vérification des certificats

```powershell
certmgr.msc
# Vérifier :
# - WSFR-ROOT-CA dans les racines de confiance
# - WSFR-SUB-CA dans les intermédiaires
```

---

## ✅ Vérification Finale

> **Instructions** : Exécuter ces tests sur REMCLT après connexion avec un utilisateur du domaine.

### 1. DHCP - IP obtenue
```powershell
ipconfig | Select-String "IPv4"
```
✅ Doit afficher une IP dans la plage `10.4.100.X`

### 2. Domaine
```powershell
(Get-WmiObject Win32_ComputerSystem).Domain
```
✅ Doit afficher `rem.wsl2025.org`

### 3. Ping serveurs Remote
```powershell
Test-Connection 10.4.100.1 -Count 1  # REMDCSRV
Test-Connection 10.4.100.2 -Count 1  # REMINFRASRV
```
✅ Les deux doivent répondre

### 4. Ping serveurs HQ (via MAN)
```powershell
Test-Connection 10.4.10.1 -Count 1  # HQDCSRV
Test-Connection 10.4.10.4 -Count 1  # DCWSL
```
✅ Les deux doivent répondre

### 5. Accès Internet
```powershell
Test-NetConnection google.com -Port 443
```
✅ `TcpTestSucceeded` doit être `True`

### 6. Accès ressources web
```powershell
Test-NetConnection www.wsl2025.org -Port 443
Test-NetConnection webmail.wsl2025.org -Port 443
```
✅ Accessibles

### 7. Certificats CA
```powershell
Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.Subject -like "*WSFR*" }
```
✅ Doit afficher `WSFR-ROOT-CA`

### Tableau récapitulatif

| Test | Commande/Action | Résultat attendu |
|------|-----------------|------------------|
| IP DHCP | `ipconfig` | `10.4.100.X` |
| Domaine | `systeminfo \| find "Domaine"` | `rem.wsl2025.org` |
| Ping REMDCSRV | `ping 10.4.100.1` | Réponse |
| Ping HQDCSRV | `ping 10.4.10.1` | Réponse (via MAN) |
| Internet | `ping google.com` | Réponse |
| Webmail | Navigateur | Page Roundcube |

