# REMCLT - Client Windows Remote

> **OS** : Windows 11  
> **IP** : DHCP (VLAN Remote - 10.4.100.0/25)  
> **Rôle** : Poste client simulant un employé du site distant

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

## ✅ Checklist de validation

| Test | Statut |
|------|--------|
| ⬜ IP obtenue par DHCP (10.4.100.X) | |
| ⬜ Jonction au domaine rem.wsl2025.org | |
| ⬜ Connexion utilisateur AD (estique, rtaha, dpeltier) | |
| ⬜ GPO appliquées | |
| ⬜ Lecteurs réseau mappés (U:, S:) | |
| ⬜ Ping vers serveurs Remote | |
| ⬜ Ping vers serveurs HQ | |
| ⬜ Accès Internet | |
| ⬜ Accès www.wsl2025.org | |
| ⬜ Accès webmail.wsl2025.org | |
| ⬜ Certificats CA installés | |
| ⬜ Panneau de config bloqué (sauf IT) | |

---

## 📝 Notes

- L'utilisateur `dpeltier` fait partie du groupe IT (droits admin locaux)
- Le trafic vers Internet passe par REMFW → WANRTR → EDGE routers
- Le trafic vers HQ passe par REMFW → WANRTR (VRF MAN) → EDGE routers
- La latence peut être plus élevée que pour les clients HQ

