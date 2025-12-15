# REMCLT - Client Windows Remote

> **OS** : Windows 11  
> **IP** : DHCP (VLAN Remote - 10.4.100.0/25)  
> **Rôle** : Poste client simulant un employé du site distant

---

## 🎯 Contexte (Sujet)

Ce poste simule un employé du site Remote (MAN) :

| Fonction    | Description                                                                     |
| ----------- | ------------------------------------------------------------------------------- |
| **DHCP**    | Obtient son IP automatiquement de REMDCSRV/REMINFRASRV (plage 10.4.100.10-120). |
| **Domaine** | Membre du domaine `rem.wsl2025.org`.                                            |
| **Accès**   | Doit accéder aux ressources corporate (HQ et Remote) et à Internet via MAN.     |

---

## 📋 Prérequis

- [ ] Windows 11 installé
- [ ] Connecté au réseau Remote (via REMFW)
- [ ] REMDCSRV fonctionnel (DHCP + AD)

---

## 1️⃣ Configuration réseau

### Informations DHCP attendues

| Paramètre  | Valeur                                        |
| ---------- | --------------------------------------------- |
| IP         | 10.4.100.X (plage 10.4.100.10 - 10.4.100.120) |
| Masque     | 255.255.255.128 (/25)                         |
| Passerelle | 10.4.100.126 (REMFW)                          |
| DNS        | 10.4.100.1 (REMDCSRV)                         |
| Domaine    | rem.wsl2025.org                               |
| NTP        | 10.4.10.2 (HQINFRASRV via WAN)                |

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

| Lettre | Chemin                                            | Description |
| ------ | ------------------------------------------------- | ----------- |
| U:     | `\\rem.wsl2025.org\files\users\%username%`        | Home drive  |
| S:     | `\\rem.wsl2025.org\files\Department\%department%` | Département |

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

### 🔌 Comment se connecter à REMCLT

1. Ouvrir la console VMware du poste REMCLT
2. Se connecter avec un utilisateur du domaine : `REM\dpeltier` / `P@ssw0rd`
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
   Adresse IPv4. . . . . . . . . . . . . .: 10.4.100.15
```

✅ **C'est bon si** : L'IP commence par `10.4.100.`
❌ **Problème si** : IP en `169.254.x.x` → DHCP ne fonctionne pas

---

### Test 2 : Vérifier la jonction au domaine

**Étape 1** : Tape cette commande :
```powershell
systeminfo | findstr "Domaine"
```

**Étape 2** : Regarde le résultat :
```
Domaine:                       rem.wsl2025.org
```

✅ **C'est bon si** : Tu vois `rem.wsl2025.org`
❌ **Problème si** : `WORKGROUP` → Pas joint au domaine

---

### Test 3 : Ping vers les serveurs Remote

**Étape 1** : Tape cette commande :
```powershell
ping 10.4.100.1 -n 1
```

**Étape 2** : Regarde le résultat :
```
Réponse de 10.4.100.1 : octets=32 temps<1ms TTL=128
```

✅ **C'est bon si** : Tu vois une réponse
❌ **Problème si** : "Délai d'attente" → Problème réseau local

---

### Test 4 : Ping vers HQ (via le réseau MAN)

**Étape 1** : Tape cette commande :
```powershell
ping 10.4.10.1 -n 1
```

**Étape 2** : Regarde le résultat :
```
Réponse de 10.4.10.1 : octets=32 temps=XXms TTL=12X
```

✅ **C'est bon si** : Tu vois une réponse (le temps sera plus long car passe par le MAN)
❌ **Problème si** : "Délai d'attente" → Vérifier REMFW/WANRTR

---

### Test 5 : Accès Internet

**Étape 1** : Tape cette commande :
```powershell
ping google.com -n 1
```

**Étape 2** : Regarde le résultat :

✅ **C'est bon si** : Tu vois une réponse avec une IP Google
❌ **Problème si** : "Hôte introuvable" → DNS ou routage

---

### Test 6 : Accès au webmail

**Étape 1** : Ouvre Microsoft Edge

**Étape 2** : Tape dans la barre d'adresse : `https://webmail.wsl2025.org`

✅ **C'est bon si** : Tu vois la page de connexion Roundcube
❌ **Problème si** : "Page inaccessible"

---

### 📋 Résumé rapide PowerShell

```powershell
Write-Host "=== IP ===" -ForegroundColor Cyan
ipconfig | findstr "IPv4"

Write-Host "=== DOMAINE ===" -ForegroundColor Cyan
systeminfo | findstr "Domaine"

Write-Host "=== PING REMDCSRV ===" -ForegroundColor Cyan
ping 10.4.100.1 -n 1 | findstr "Réponse"

Write-Host "=== PING HQ ===" -ForegroundColor Cyan
ping 10.4.10.1 -n 1 | findstr "Réponse"

Write-Host "=== INTERNET ===" -ForegroundColor Cyan
ping google.com -n 1 | findstr "Réponse"
```
