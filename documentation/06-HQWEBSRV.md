# HQWEBSRV - Serveur Web HQ

> **OS** : Windows Server 2022  
> **IP** : 217.4.160.2 (VLAN 30 - DMZ)  
> **Rôles** : IIS (Web), RDS (Remote Desktop Services)

---

## 🎯 Contexte (Sujet)

Ce serveur héberge les services web et RDS accessibles depuis Internet :

| Service              | Description                                                                                             |
| -------------------- | ------------------------------------------------------------------------------------------------------- |
| **IIS Web**          | Site `www.wsl2025.org` accessible en HTTP/HTTPS (redirection auto HTTP→HTTPS). IP publique 217.4.160.X. |
| **RDS**              | RemoteApp pour Excel et Word, accessible via navigateur web pour tous les utilisateurs.                 |
| **Authentification** | Site `https://authentication.wsl2025.org` avec auth AD, accès réservé au groupe Sales.                  |
| **Certificat**       | SSL émis par HQDCSRV (Sub CA WSFR-SUB-CA).                                                              |

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

### 🔌 Comment se connecter à HQWEBSRV

1. Ouvrir la console VMware ou Bureau à distance (RDP) vers `217.4.160.2`
2. Se connecter avec `HQ\Administrateur` / `P@ssw0rd`
3. Clic droit sur le bouton Windows → **Windows PowerShell (Admin)**

---

### Test 1 : Vérifier les sites IIS

**Étape 1** : Tape cette commande :
```powershell
Get-Website | Format-Table Name, State -AutoSize
```

**Étape 2** : Regarde le résultat :
```
Name                  State
----                  -----
Default Web Site      Started
www.wsl2025.org       Started
authentication        Started
```

✅ **C'est bon si** : Tous les sites sont en état `Started`
❌ **Problème si** : Un site est `Stopped` → Démarrer avec `Start-Website "nom"`

---

### Test 2 : Vérifier le certificat SSL

**Étape 1** : Tape cette commande :
```powershell
Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -like "*wsl2025*" } | Format-List Subject, NotAfter
```

**Étape 2** : Regarde le résultat :
```
Subject  : CN=www.wsl2025.org
NotAfter : 01/01/2026 00:00:00
```

✅ **C'est bon si** : Tu vois un certificat avec `wsl2025` dans le Subject et une date valide
❌ **Problème si** : Rien ne s'affiche → Certificat manquant

---

### Test 3 : Tester le site localement

**Étape 1** : Tape cette commande :
```powershell
Invoke-WebRequest -Uri "http://localhost" -UseBasicParsing -MaximumRedirection 0 -ErrorAction SilentlyContinue | Select-Object StatusCode
```

**Étape 2** : Regarde le résultat :
```
StatusCode
----------
       200
```
(ou 301/302 si redirection HTTPS configurée)

✅ **C'est bon si** : StatusCode est 200, 301 ou 302
❌ **Problème si** : Erreur → IIS ne répond pas

---

### Test 4 : Vérifier RDS installé

**Étape 1** : Tape cette commande :
```powershell
Get-WindowsFeature RDS* | Where-Object Installed | Format-Table Name, Installed -AutoSize
```

**Étape 2** : Regarde le résultat :
```
Name              Installed
----              ---------
RDS-RD-Server          True
RDS-Web-Access         True
```

✅ **C'est bon si** : Tu vois au moins `RDS-RD-Server` et `RDS-Web-Access`
❌ **Problème si** : Rien de listé → RDS pas installé

---

### Test 5 : Tester depuis un autre PC (HQCLT ou INETCLT)

**Étape 1** : Ouvre un navigateur sur un autre PC

**Étape 2** : Tape chaque URL et vérifie :

| URL | Ce que tu dois voir |
|-----|---------------------|
| `https://www.wsl2025.org` | Page d'accueil WSL2025 |
| `https://authentication.wsl2025.org` | Popup demandant login/mot de passe |
| `https://217.4.160.2/RDWeb` | Page de connexion RD Web Access |

✅ **C'est bon si** : Chaque page s'affiche correctement
❌ **Problème si** : "Page inaccessible" → Vérifier NAT/Firewall

---

### 📋 Résumé rapide PowerShell

```powershell
Write-Host "=== SITES IIS ===" -ForegroundColor Cyan
Get-Website | Format-Table Name, State -AutoSize

Write-Host "=== CERTIFICAT ===" -ForegroundColor Cyan
Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -like "*wsl2025*" } | Select-Object Subject

Write-Host "=== RDS ===" -ForegroundColor Cyan
Get-WindowsFeature RDS* | Where-Object Installed | Select-Object Name

Write-Host "=== TEST LOCAL ===" -ForegroundColor Cyan
(Invoke-WebRequest -Uri "http://localhost" -UseBasicParsing -MaximumRedirection 0 -ErrorAction SilentlyContinue).StatusCode
```
