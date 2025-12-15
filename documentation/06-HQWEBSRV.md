# HQWEBSRV - Serveur Web HQ

> **OS** : Windows Server 2022  
> **IP** : 217.4.160.2 (VLAN 30 - DMZ)  
> **Rôles** : IIS (Web), RDS (Remote Desktop Services)

---

## 🎯 Contexte (Sujet)

Ce serveur héberge les services web et RDS accessibles depuis Internet :

| Service | Description |
|---------|-------------|
| **IIS Web** | Site `www.wsl2025.org` accessible en HTTP/HTTPS (redirection auto HTTP→HTTPS). IP publique 217.4.160.X. |
| **RDS** | RemoteApp pour Excel et Word, accessible via navigateur web pour tous les utilisateurs. |
| **Authentification** | Site `https://authentication.wsl2025.org` avec auth AD, accès réservé au groupe Sales. |
| **Certificat** | SSL émis par HQDCSRV (Sub CA WSFR-SUB-CA). |

---

## 📋 Prérequis

- [ ] Windows Server 2022 installé
- [ ] Joint au domaine hq.wsl2025.org
- [ ] Certificat SSL de HQDCSRV (Sub CA)
- [ ] Connectivité avec AD (via HQFWSRV)

---

## 1️⃣ Configuration de base

### Hostname et IP
```powershell
Rename-Computer -NewName "HQWEBSRV"

# Configuration IP (VLAN 30 - DMZ)
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 217.4.160.2 -PrefixLength 24 -DefaultGateway 217.4.160.254
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 10.4.10.1
```

### Joindre le domaine
```powershell
Add-Computer -DomainName "hq.wsl2025.org" -Credential (Get-Credential) -Restart
```

---

## 2️⃣ Installation IIS

```powershell
Install-WindowsFeature -Name Web-Server, Web-Mgmt-Tools, Web-Scripting-Tools -IncludeManagementTools
```

### Créer le site www.wsl2025.org
```powershell
# Créer le dossier
New-Item -Path "C:\inetpub\wwwroot\wsl2025" -ItemType Directory

# Page d'accueil
@"
<!DOCTYPE html>
<html>
<head>
    <title>WorldSkills Lyon 2025</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; margin-top: 50px; }
        h1 { color: #0066cc; }
    </style>
</head>
<body>
    <h1>Bienvenue sur WSL2025</h1>
    <p>Site officiel de WorldSkills Lyon 2025</p>
</body>
</html>
"@ | Out-File "C:\inetpub\wwwroot\wsl2025\index.html" -Encoding UTF8

# Créer le site IIS
Import-Module WebAdministration
New-Website -Name "www.wsl2025.org" -PhysicalPath "C:\inetpub\wwwroot\wsl2025" -HostHeader "www.wsl2025.org" -Port 80
```

### Configurer HTTPS
```powershell
# Importer le certificat (obtenu de HQDCSRV)
$cert = Import-PfxCertificate -FilePath "C:\Certs\www.wsl2025.org.pfx" -CertStoreLocation Cert:\LocalMachine\My -Password (ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force)

# Binding HTTPS
New-WebBinding -Name "www.wsl2025.org" -Protocol https -Port 443 -HostHeader "www.wsl2025.org"
$binding = Get-WebBinding -Name "www.wsl2025.org" -Protocol https
$binding.AddSslCertificate($cert.Thumbprint, "My")

# Redirection HTTP vers HTTPS (web.config)
@"
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <system.webServer>
        <httpRedirect enabled="true" destination="https://www.wsl2025.org" httpResponseStatus="Permanent" />
    </system.webServer>
</configuration>
"@ | Out-File "C:\inetpub\wwwroot\wsl2025\web.config" -Encoding UTF8
```

---

## 3️⃣ Site authentication.wsl2025.org

### Créer le site
```powershell
New-Item -Path "C:\inetpub\wwwroot\authentication" -ItemType Directory

@"
<!DOCTYPE html>
<html>
<head>
    <title>Authentication Portal - WSL2025</title>
</head>
<body>
    <h1>Portail d'authentification WSL2025</h1>
    <p>Bienvenue ! Vous êtes authentifié.</p>
    <p>Accès réservé au groupe Sales.</p>
</body>
</html>
"@ | Out-File "C:\inetpub\wwwroot\authentication\index.html" -Encoding UTF8

New-Website -Name "authentication.wsl2025.org" -PhysicalPath "C:\inetpub\wwwroot\authentication" -HostHeader "authentication.wsl2025.org" -Port 80
New-WebBinding -Name "authentication.wsl2025.org" -Protocol https -Port 443 -HostHeader "authentication.wsl2025.org"
```

### Configurer l'authentification Windows
```powershell
# Désactiver auth anonyme, activer Windows Auth
Set-WebConfigurationProperty -Filter "/system.webServer/security/authentication/anonymousAuthentication" -Name "enabled" -Value "False" -PSPath "IIS:\Sites\authentication.wsl2025.org"
Set-WebConfigurationProperty -Filter "/system.webServer/security/authentication/windowsAuthentication" -Name "enabled" -Value "True" -PSPath "IIS:\Sites\authentication.wsl2025.org"
```

### Restreindre au groupe Sales
```powershell
@"
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <system.web>
        <authorization>
            <allow roles="HQ\Sales" />
            <deny users="*" />
        </authorization>
    </system.web>
</configuration>
"@ | Out-File "C:\inetpub\wwwroot\authentication\web.config" -Encoding UTF8
```

---

## 4️⃣ Remote Desktop Services (RDS)

### Installer les rôles RDS
```powershell
Install-WindowsFeature -Name RDS-RD-Server, RDS-Web-Access, RDS-Connection-Broker -IncludeManagementTools
```

### Installer Microsoft Office
> Installer Office 365 ou Office 2021 manuellement pour les RemoteApp

### Configurer RDS
```powershell
Import-Module RemoteDesktop

# Créer une collection de sessions
New-RDSessionCollection -CollectionName "Office Apps" -SessionHost HQWEBSRV.hq.wsl2025.org -ConnectionBroker HQWEBSRV.hq.wsl2025.org

# Publier Word et Excel comme RemoteApp
New-RDRemoteApp -Alias "Word" -DisplayName "Microsoft Word" -FilePath "C:\Program Files\Microsoft Office\root\Office16\WINWORD.EXE" -CollectionName "Office Apps"
New-RDRemoteApp -Alias "Excel" -DisplayName "Microsoft Excel" -FilePath "C:\Program Files\Microsoft Office\root\Office16\EXCEL.EXE" -CollectionName "Office Apps"
```

### Configurer les certificats RDS
```powershell
Set-RDCertificate -Role RDWebAccess -ImportPath "C:\Certs\rds.pfx" -Password (ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force)
Set-RDCertificate -Role RDGateway -ImportPath "C:\Certs\rds.pfx" -Password (ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force)
Set-RDCertificate -Role RDRedirector -ImportPath "C:\Certs\rds.pfx" -Password (ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force)
Set-RDCertificate -Role RDPublishing -ImportPath "C:\Certs\rds.pfx" -Password (ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force)
```

### Accès RD Web
Le portail RD Web Access est accessible sur :
- `https://hqwebsrv.hq.wsl2025.org/RDWeb`
- `https://217.4.160.2/RDWeb`

---

## ✅ Vérification Finale

> **Instructions** : Exécuter ces commandes sur HQWEBSRV (PowerShell Admin) pour valider le bon fonctionnement.

### 1. IIS - Sites web actifs
```powershell
Get-Website | Select-Object Name, State, PhysicalPath
```
✅ Les sites doivent être en état `Started`

### 2. Test site www.wsl2025.org (depuis HQWEBSRV)
```powershell
Invoke-WebRequest -Uri "http://localhost" -UseBasicParsing | Select-Object StatusCode
```
✅ Doit retourner `StatusCode: 200` (ou 301 si redirection HTTPS)

### 3. Certificat SSL
```powershell
Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -like "*wsl2025*" }
```
✅ Doit afficher un certificat avec le subject contenant wsl2025

### 4. RDS - Rôles installés
```powershell
Get-WindowsFeature | Where-Object { $_.Name -like "RDS*" -and $_.Installed }
```
✅ Doit montrer RDS-RD-Server, RDS-Web-Access installés

### 5. RDS - RemoteApps publiées
```powershell
Get-RDRemoteApp -CollectionName "Office Apps" -ErrorAction SilentlyContinue
```
✅ Doit lister Word et Excel (si configurés)

### 6. Test depuis un navigateur externe
- `https://www.wsl2025.org` → Page d'accueil WSL2025
- `https://authentication.wsl2025.org` → Demande d'authentification AD
- `https://217.4.160.2/RDWeb` → Portail RD Web Access

### Tableau récapitulatif

| Test | Commande/Action | Résultat attendu |
|------|-----------------|------------------|
| IIS actif | `(Get-Website).State` | `Started` |
| Cert SSL | `Get-ChildItem Cert:\LocalMachine\My` | Certificat wsl2025 |
| RDS installé | `Get-WindowsFeature RDS*` | Installé |
| Site HTTP | `curl http://localhost` | Réponse 200/301 |
| RD Web | Navigateur `/RDWeb` | Page de connexion |
