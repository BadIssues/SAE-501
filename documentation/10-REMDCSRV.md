# REMDCSRV - Contrôleur de Domaine Remote

> **OS** : Windows Server 2022  
> **IP** : 10.4.100.1 (VLAN Remote)  
> **Rôles** : AD DS (Child Domain), DNS, DHCP, DFS

---

## 📋 Prérequis

- [ ] Windows Server 2022 installé
- [ ] Connectivité avec HQDCSRV (via REMFW/WANRTR)
- [ ] Résolution DNS vers hq.wsl2025.org fonctionnelle

---

## 1️⃣ Configuration de base

### Hostname et IP
```powershell
Rename-Computer -NewName "REMDCSRV" -Restart

# Configuration IP
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 10.4.100.1 -PrefixLength 25 -DefaultGateway 10.4.100.126
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 10.4.10.1, 127.0.0.1  # HQDCSRV puis local
```

---

## 2️⃣ Installation Active Directory

### Installer les rôles
```powershell
Install-WindowsFeature -Name AD-Domain-Services, DNS, DHCP, FS-DFS-Namespace, FS-DFS-Replication, RSAT-AD-Tools, RSAT-DNS-Server, RSAT-DHCP -IncludeManagementTools
```

### Joindre comme Child Domain
```powershell
# Option : Child de wsl2025.org (Forest Root)
Install-ADDSDomain `
    -NewDomainName "rem" `
    -ParentDomainName "wsl2025.org" `
    -DomainType "ChildDomain" `
    -InstallDns:$true `
    -Credential (Get-Credential) `
    -SafeModeAdministratorPassword (ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force) `
    -Force
```

---

## 3️⃣ Configuration DNS

### Zone rem.wsl2025.org
```powershell
# La zone est créée automatiquement avec AD DS

# Ajouter un forwarder vers wsl2025.org / HQDCSRV
Add-DnsServerForwarder -IPAddress 10.4.10.1

# Vérifier la réplication de zone si configurée
Get-DnsServerZone
```

### DNSSEC
```powershell
# Signer la zone avec certificat de HQDCSRV
Invoke-DnsServerZoneSign -ZoneName "rem.wsl2025.org" -SignWithDefault
```

---

## 4️⃣ Configuration DHCP

### Autoriser le serveur DHCP
```powershell
Add-DhcpServerInDC -DnsName "remdcsrv.rem.wsl2025.org" -IPAddress 10.4.100.1
```

### Créer le scope
```powershell
# Scope pour le site Remote
Add-DhcpServerv4Scope -Name "Remote-Clients" `
    -StartRange 10.4.100.10 `
    -EndRange 10.4.100.120 `
    -SubnetMask 255.255.255.128 `
    -LeaseDuration 02:00:00  # 2 heures

# Options du scope
Set-DhcpServerv4OptionValue -ScopeId 10.4.100.0 -Router 10.4.100.126
Set-DhcpServerv4OptionValue -ScopeId 10.4.100.0 -DnsServer 10.4.100.1
Set-DhcpServerv4OptionValue -ScopeId 10.4.100.0 -DnsDomain "rem.wsl2025.org"

# Option NTP
Set-DhcpServerv4OptionValue -ScopeId 10.4.100.0 -OptionId 42 -Value 10.4.10.2  # hqinfrasrv
```

### Dynamic DNS
```powershell
# Activer la mise à jour DNS dynamique
Set-DhcpServerv4DnsSetting -ScopeId 10.4.100.0 -DynamicUpdates "Always" -DeleteDnsRROnLeaseExpiry $true
```

---

## 5️⃣ Structure Organisationnelle AD

### Créer les OUs
```powershell
# OU Remote
New-ADOrganizationalUnit -Name "Remote" -Path "DC=rem,DC=wsl2025,DC=org"
New-ADOrganizationalUnit -Name "Workers" -Path "OU=Remote,DC=rem,DC=wsl2025,DC=org"
New-ADOrganizationalUnit -Name "Computers" -Path "OU=Remote,DC=rem,DC=wsl2025,DC=org"
New-ADOrganizationalUnit -Name "Groups" -Path "OU=Remote,DC=rem,DC=wsl2025,DC=org"
```

### Créer les utilisateurs Remote
```powershell
$usersRemote = @(
    @{Name="Ela STIQUE"; Login="estique"; Dept="Warehouse"; Email="estique@wsl2025.org"},
    @{Name="Rachid TAHA"; Login="rtaha"; Dept="Direction"; Email="rtaha@wsl2025.org"},
    @{Name="Denis PELTIER"; Login="dpeltier"; Dept="IT"; Email="dpeltier@wsl2025.org"}
)

foreach ($user in $usersRemote) {
    New-ADUser -Name $user.Name `
        -SamAccountName $user.Login `
        -UserPrincipalName "$($user.Login)@rem.wsl2025.org" `
        -EmailAddress $user.Email `
        -Path "OU=Workers,OU=Remote,DC=rem,DC=wsl2025,DC=org" `
        -AccountPassword (ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force) `
        -Enabled $true
}

# Créer les groupes
New-ADGroup -Name "IT" -GroupScope Global -Path "OU=Groups,OU=Remote,DC=rem,DC=wsl2025,DC=org"
New-ADGroup -Name "Direction" -GroupScope Global -Path "OU=Groups,OU=Remote,DC=rem,DC=wsl2025,DC=org"
New-ADGroup -Name "Warehouse" -GroupScope Global -Path "OU=Groups,OU=Remote,DC=rem,DC=wsl2025,DC=org"

# Ajouter aux groupes
Add-ADGroupMember -Identity "IT" -Members "dpeltier"
Add-ADGroupMember -Identity "Direction" -Members "rtaha"
Add-ADGroupMember -Identity "Warehouse" -Members "estique"
```

---

## 6️⃣ Configuration DFS

### Créer la racine DFS
```powershell
# Créer le namespace
New-DfsnRoot -TargetPath "\\remdcsrv.rem.wsl2025.org\DFSRoot" -Type DomainV2 -Path "\\rem.wsl2025.org\files"

# Créer les dossiers
New-Item -Path "C:\shares\datausers" -ItemType Directory
New-Item -Path "C:\shares\Department" -ItemType Directory
```

### Partage users
```powershell
New-SmbShare -Name "users$" -Path "C:\shares\datausers" -FullAccess "Administrators" -ChangeAccess "Authenticated Users"

# Quota 20 Mo
Install-WindowsFeature -Name FS-Resource-Manager
New-FsrmQuotaTemplate -Name "UserQuota" -Size 20MB
New-FsrmAutoQuota -Path "C:\shares\datausers" -Template "UserQuota"

# Ajouter au DFS
New-DfsnFolder -Path "\\rem.wsl2025.org\files\users" -TargetPath "\\remdcsrv.rem.wsl2025.org\users$"
```

### Partage Department
```powershell
# Créer les dossiers département
foreach ($dept in @("IT", "Direction", "Warehouse")) {
    New-Item -Path "C:\shares\Department\$dept" -ItemType Directory
}

New-SmbShare -Name "Department$" -Path "C:\shares\Department" -FullAccess "Administrators"
New-DfsnFolder -Path "\\rem.wsl2025.org\files\Department" -TargetPath "\\remdcsrv.rem.wsl2025.org\Department$"
```

---

## 7️⃣ GPO Site Remote

### IT sont admins locaux
```powershell
New-GPO -Name "REM-IT-LocalAdmins" | New-GPLink -Target "OU=Remote,DC=rem,DC=wsl2025,DC=org"
# Via GPMC : Computer Configuration > Policies > Windows Settings > Security Settings > Restricted Groups
# Ajouter "REM\IT" au groupe "Administrators"
```

### Bloquer panneau de configuration
```powershell
New-GPO -Name "REM-Block-ControlPanel" | New-GPLink -Target "OU=Workers,OU=Remote,DC=rem,DC=wsl2025,DC=org"
# User Configuration > Administrative Templates > Control Panel > Prohibit access
# Utiliser le filtrage de sécurité pour exclure le groupe IT
```

### Mappages réseau
```powershell
New-GPO -Name "REM-DriveMappings" | New-GPLink -Target "OU=Remote,DC=rem,DC=wsl2025,DC=org"
# User Configuration > Preferences > Windows Settings > Drive Maps
# S: -> \\rem.wsl2025.org\files\Department\%DEPARTMENT%
# U: -> \\rem.wsl2025.org\files\users\%USERNAME%
```

### Certificats CA
```powershell
New-GPO -Name "REM-Certificates" | New-GPLink -Target "OU=Remote,DC=rem,DC=wsl2025,DC=org"
# Computer Configuration > Policies > Windows Settings > Security Settings > Public Key Policies
# Importer WSFR-ROOT-CA et WSFR-SUB-CA
```

---

## ✅ Vérifications

| Test | Commande |
|------|----------|
| AD DS | `Get-ADDomain` |
| DNS | `Resolve-DnsName remdcsrv.rem.wsl2025.org` |
| DHCP | `Get-DhcpServerv4Scope` |
| DFS | `Get-DfsnRoot` |
| Réplication AD | `repadmin /replsummary` |
| Trust | `Get-ADTrust -Filter *` |

---

## 📝 Notes

- La réplication AD avec HQDCSRV doit fonctionner via REMFW
- Le Dynamic DNS crée automatiquement les enregistrements pour les clients DHCP
- Les utilisateurs Remote peuvent s'authentifier sur les deux sites
- Le DFS sera répliqué avec REMINFRASRV pour la tolérance de panne
