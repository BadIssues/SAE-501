# VPNCLT - Client VPN

> **OS** : Windows 11  
> **IP Internet** : 8.8.4.3/29 (Gateway 8.8.4.6, DNS 8.8.4.1)  
> **IP VPN** : 10.4.22.X (attribuée par le serveur VPN)  
> **Rôle** : Client VPN simulant un télétravailleur accédant aux ressources corporate depuis Internet

---

## 📋 Exigences du sujet

| Paramètre | Valeur |
|-----------|--------|
| Protocole | OpenVPN |
| Serveur | vpn.wsl2025.org:4443 (= 191.4.157.33:4443) |
| Authentification | **Certificat + user/password AD** |
| Membre domaine | **hq.wsl2025.org** |
| Accès | Ressources HQ + Remote site |

---

## 📋 Prérequis

- [ ] Windows 11 installé
- [ ] HQINFRASRV opérationnel (serveur VPN sur port 4443)
- [ ] NAT configuré sur EDGE1/EDGE2 (191.4.157.33:4443 → 10.4.10.2:4443)
- [ ] Certificat client émis par HQDCSRV (Sub CA)
- [ ] Certificats Root CA et Sub CA installés

---

## 1️⃣ Configuration de base

### Configuration IP (côté Internet)
```powershell
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 8.8.4.3 -PrefixLength 29 -DefaultGateway 8.8.4.6
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 8.8.4.1
```

---

## 2️⃣ Joindre le domaine (AVANT de configurer le VPN)

> ⚠️ **IMPORTANT** : Le PC doit être joint au domaine AVANT de pouvoir utiliser le VPN !
> Pour ce faire, connecter temporairement VPNCLT au réseau local HQ (ou utiliser une autre méthode).

### Option A : Connexion temporaire au LAN HQ
1. Connecter VPNCLT au réseau VLAN 20 (Clients)
2. Obtenir une IP via DHCP
3. Joindre le domaine :

```powershell
Add-Computer -DomainName "hq.wsl2025.org" -Credential (Get-Credential) -Restart
```

### Option B : Joindre le domaine hors-ligne (djoin)
Sur HQDCSRV :
```powershell
djoin /provision /domain hq.wsl2025.org /machine VPNCLT /savefile C:\vpnclt-blob.txt
```

Sur VPNCLT :
```powershell
djoin /requestODJ /loadfile C:\vpnclt-blob.txt /windowspath %SystemRoot% /localos
Restart-Computer
```

---

## 3️⃣ Installation OpenVPN

### Télécharger et installer
1. Télécharger OpenVPN GUI depuis https://openvpn.net/community-downloads/
2. Installer avec les options par défaut
3. Autoriser l'installation du TAP adapter

---

## 4️⃣ Configuration OpenVPN Client

### Fichier de configuration
Créer le fichier `C:\Program Files\OpenVPN\config\wsl2025.ovpn` :

```
client
dev tun
proto udp
remote vpn.wsl2025.org 4443
remote 191.4.157.33 4443

resolv-retry infinite
nobind
persist-key
persist-tun

# Certificats
ca ca.crt
cert client.crt
key client.key
tls-auth ta.key 1

# Sécurité
cipher AES-256-GCM
auth SHA256
remote-cert-tls server

# Logs
verb 3

# Authentification utilisateur
auth-user-pass
```

### Fichiers nécessaires

> ⚠️ Les certificats doivent être émis par **HQDCSRV** (Sub CA WSFR-SUB-CA) !

#### Obtenir le certificat client depuis HQDCSRV

1. Sur VPNCLT, demander un certificat via MMC :
   - `Win+R` → `certlm.msc`
   - **Personnel** → Clic droit → **Toutes les tâches** → **Demander un nouveau certificat**
   - Sélectionner le template **WSFR_Services** ou **WSFR_Users**
   - Exporter le certificat avec la clé privée (format PFX)

2. Convertir le PFX en fichiers séparés :
```powershell
# Extraire le certificat
openssl pkcs12 -in vpnclient.pfx -clcerts -nokeys -out client.crt

# Extraire la clé privée
openssl pkcs12 -in vpnclient.pfx -nocerts -nodes -out client.key
```

#### Fichiers à placer dans `C:\Program Files\OpenVPN\config\`

| Fichier | Description | Source |
|---------|-------------|--------|
| `ca.crt` | Chaîne de certificats CA (Root + Sub) | HQINFRASRV ou HQDCSRV |
| `client.crt` | Certificat client | HQDCSRV (template WSFR_Services) |
| `client.key` | Clé privée client | Généré localement |
| `ta.key` | Clé TLS-Auth | HQINFRASRV (`/etc/openvpn/ta.key`) |

#### Récupérer les fichiers depuis HQINFRASRV

```powershell
# Depuis VPNCLT (après avoir joint le domaine et configuré le VPN basique)
scp root@10.4.10.2:/etc/openvpn/certs/ca-chain.crt "C:\Program Files\OpenVPN\config\ca.crt"
scp root@10.4.10.2:/etc/openvpn/ta.key "C:\Program Files\OpenVPN\config\ta.key"
```

---

## 5️⃣ Connexion VPN

### Via OpenVPN GUI
1. Clic droit sur l'icône OpenVPN dans la barre des tâches
2. Sélectionner "wsl2025" → "Connect"
3. Entrer les credentials AD :
   - Username : `vtim` (ou autre utilisateur AD)
   - Password : `P@ssw0rd`

### Via ligne de commande
```powershell
& "C:\Program Files\OpenVPN\bin\openvpn.exe" --config "C:\Program Files\OpenVPN\config\wsl2025.ovpn"
```

---

## 6️⃣ Vérifications post-connexion

### IP VPN obtenue
```powershell
ipconfig /all
# L'interface TAP doit avoir une IP dans 10.4.22.X (tunnel VPN)
```

### Tests de connectivité
```powershell
# Ping serveurs HQ via VPN
ping 10.4.10.1   # HQDCSRV
ping 10.4.10.2   # HQINFRASRV
ping 10.4.10.3   # HQMAILSRV

# Ping site Remote (via VPN + MAN)
ping 10.4.100.1  # REMDCSRV

# Test DNS interne
nslookup hqdcsrv.hq.wsl2025.org
nslookup www.wsl2025.org
```

---

## 7️⃣ Accès aux ressources corporate

### Partages réseau
```powershell
# Home drive
net use U: \\hq.wsl2025.org\users$\vtim

# Partages Samba
net use X: \\10.4.10.2\Public
```

### Email
- Webmail : https://webmail.wsl2025.org
- Outlook : configurer IMAP/SMTP vers hqmailsrv.wsl2025.org

### Sites web internes
```powershell
Start-Process "https://www.wsl2025.org"
Start-Process "https://authentication.wsl2025.org"  # Si membre du groupe Sales
```

### RDS (RemoteApp)
```powershell
Start-Process "https://hqwebsrv.hq.wsl2025.org/RDWeb"
```

---

## 8️⃣ Dépannage

### Vérifier les logs OpenVPN
```
C:\Program Files\OpenVPN\log\wsl2025.log
```

### Problèmes courants

| Problème | Solution |
|----------|----------|
| "TLS handshake failed" | Vérifier les certificats et ta.key |
| "AUTH_FAILED" | Vérifier username/password AD |
| "Connection refused" | Vérifier que le port 4443 est ouvert (NAT sur EDGE) |
| Pas de résolution DNS | Vérifier que le VPN pousse les options DNS |

### Forcer le trafic via VPN
Si nécessaire, ajouter dans le fichier .ovpn :
```
redirect-gateway def1
```

---

## ✅ Checklist de validation

| Test | Statut |
|------|--------|
| ⬜ OpenVPN installé | |
| ⬜ Certificats en place | |
| ⬜ Connexion VPN établie | |
| ⬜ IP VPN obtenue (10.4.22.X) | |
| ⬜ Ping vers HQDCSRV (10.4.10.1) | |
| ⬜ Ping vers REMDCSRV (10.4.100.1) | |
| ⬜ Résolution DNS interne | |
| ⬜ Accès partages réseau | |
| ⬜ Accès webmail | |
| ⬜ Accès www.wsl2025.org | |

---

## 📝 Notes

### Configuration réseau
| Paramètre | Valeur |
|-----------|--------|
| **IP Internet** | 8.8.4.3/29 |
| **Gateway Internet** | 8.8.4.6 |
| **DNS Internet** | 8.8.4.1 (DNSSRV) |
| **IP VPN** | 10.4.22.X (attribuée par le serveur VPN) |

### Configuration VPN (selon le sujet)
| Paramètre | Valeur |
|-----------|--------|
| Protocole | OpenVPN |
| Port | **4443/UDP** |
| Serveur | vpn.wsl2025.org (= 191.4.157.33) |
| Authentification | Certificat (HQDCSRV) + user/password AD |
| Accès | Ressources HQ + Remote site |

### Flux réseau VPN
```
VPNCLT (8.8.4.3)
    ↓ OpenVPN UDP:4443
vpn.wsl2025.org (191.4.157.33)
    ↓ NAT sur EDGE1/EDGE2
HQINFRASRV (10.4.10.2:4443)
    ↓ Tunnel établi
IP VPN attribuée (10.4.22.X)
    ↓ Routes poussées
Accès à 10.4.0.0/16 (HQ) + 10.4.100.0/24 (Remote)
```

### Checklist de fonctionnement
- [ ] Certificat client émis par HQDCSRV
- [ ] Certificats CA (Root + Sub) installés
- [ ] Fichier ta.key récupéré de HQINFRASRV
- [ ] NAT configuré sur EDGE (191.4.157.33:4443 → 10.4.10.2:4443)
- [ ] Enregistrement DNS vpn.wsl2025.org → 191.4.157.33 (sur DNSSRV et DCWSL)
- [ ] VPNCLT membre du domaine hq.wsl2025.org

