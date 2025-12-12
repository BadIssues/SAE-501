# HQWEBSRV - Serveur Web HQ

> **OS** : Windows Server 2022  
> **IP** : 217.4.160.2 (VLAN 30 - DMZ)  
> **Rôles** : IIS (Web), RDS (Remote Desktop Services)

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

## ✅ Vérifications

| Test | Action |
|------|--------|
| Site Web | `curl https://www.wsl2025.org` |
| Auth Site | Naviguer vers `https://authentication.wsl2025.org` avec user Sales |
| RD Web | Naviguer vers `https://217.4.160.2/RDWeb` |
| IIS Status | `Get-Website` |

---

## 📝 Notes

- **IP** : 217.4.160.2 (VLAN 30 - DMZ)
- **Gateway** : 217.4.160.254 (VIP HSRP EDGE1/EDGE2)
- Les certificats doivent être demandés à HQDCSRV (template WSFR_Services)
- L'accès à `authentication.wsl2025.org` est limité au groupe AD "Sales" (rola)
- RD Web Access permet l'accès aux applications Word/Excel via navigateur
