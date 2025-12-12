# VPNCLT - Client VPN

> **OS** : Windows 11  
> **IP** : 8.8.4.3 (Internet) + IP VPN dynamique  
> **Rôle** : Client VPN simulant un télétravailleur

---

## 📋 Prérequis

- [ ] Windows 11 installé
- [ ] Joint au domaine hq.wsl2025.org
- [ ] HQINFRASRV opérationnel (serveur VPN)
- [ ] Certificats CA installés

---

## 1️⃣ Configuration de base

### Configuration IP (côté Internet)
```powershell
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 8.8.4.3 -PrefixLength 29 -DefaultGateway 8.8.4.6
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 8.8.4.1
```

---

## 2️⃣ Joindre le domaine (avant VPN)

> **Note** : Joindre le domaine en étant connecté au réseau local HQ d'abord, ou via VPN.

```powershell
Add-Computer -DomainName "hq.wsl2025.org" -Credential (Get-Credential) -Restart
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
Placer dans `C:\Program Files\OpenVPN\config\` :
- `ca.crt` - Certificat CA (de HQDCSRV ou HQINFRASRV)
- `client.crt` - Certificat client (signé par SubCA)
- `client.key` - Clé privée client
- `ta.key` - Clé TLS-Auth (de HQINFRASRV)

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

- **IP Internet** : 8.8.4.3
- **IP VPN** : 10.4.22.X (attribuée par DHCP du serveur VPN)
- Le VPN utilise le port **4443/UDP**
- L'authentification combine certificat + username/password AD
- Via VPN, l'accès aux ressources HQ et Remote est possible
- Le NAT est configuré sur EDGE1 (191.4.157.33:4443 → 10.4.10.2:4443)

