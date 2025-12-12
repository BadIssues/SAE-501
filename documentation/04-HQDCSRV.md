# HQDCSRV - Contrôleur de Domaine HQ

> **OS** : Windows Server 2022  
> **IP** : 10.4.10.1 (VLAN 10 - Servers)  
> **Rôles** : AD DS, DNS, ADCS (Sub CA), File Server, GPO

---

## 📋 Prérequis

- [ ] Windows Server 2022 installé
- [ ] 3 disques supplémentaires de 1 Go (RAID-5)
- [ ] DCWSL opérationnel (10.4.10.4)
- [ ] DNSSRV opérationnel (pour la Root CA) - 8.8.4.1

---

## 1️⃣ Configuration de base

### Hostname et IP
```powershell
# Renommer le serveur
Rename-Computer -NewName "HQDCSRV" -Restart

# Configuration IP statique
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 10.4.10.1 -PrefixLength 24 -DefaultGateway 10.4.10.254
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 10.4.10.4, 127.0.0.1
```

---

## 2️⃣ Installation Active Directory

### Installer les rôles
```powershell
Install-WindowsFeature -Name AD-Domain-Services, DNS, RSAT-AD-Tools, RSAT-DNS-Server -IncludeManagementTools
```

### Child Domain de wsl2025.org
```powershell
# Joindre comme domaine enfant de wsl2025.org (DCWSL)
Install-ADDSDomain `
    -NewDomainName "hq" `
    -ParentDomainName "wsl2025.org" `
    -DomainType "ChildDomain" `
    -InstallDns:$true `
    -Credential (Get-Credential -Message "Entrez les credentials de WSL2025\Administrator") `
    -SafeModeAdministratorPassword (ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force) `
    -Force
```

---

## 3️⃣ Configuration DNS

### Enregistrements DNS zone hq.wsl2025.org
```powershell
# Zone hq.wsl2025.org (créée automatiquement)
Add-DnsServerResourceRecordA -ZoneName "hq.wsl2025.org" -Name "hqdcsrv" -IPv4Address "10.4.10.1"
Add-DnsServerResourceRecordCName -ZoneName "hq.wsl2025.org" -Name "hqwebsrv" -HostNameAlias "hqfwsrv.wsl2025.org"
Add-DnsServerResourceRecordCName -ZoneName "hq.wsl2025.org" -Name "pki" -HostNameAlias "hqdcsrv.hq.wsl2025.org"

# Forwarder conditionnel vers wsl2025.org
Add-DnsServerConditionalForwarderZone -Name "wsl2025.org" -MasterServers 10.4.10.4
```

### DNSSEC
```powershell
# Signer la zone
Invoke-DnsServerZoneSign -ZoneName "hq.wsl2025.org" -SignWithDefault
```

---

## 4️⃣ Structure Organisationnelle AD

### Créer les OUs
```powershell
# OU principales
New-ADOrganizationalUnit -Name "HQ" -Path "DC=hq,DC=wsl2025,DC=org"
New-ADOrganizationalUnit -Name "Users" -Path "OU=HQ,DC=hq,DC=wsl2025,DC=org"
New-ADOrganizationalUnit -Name "Computers" -Path "OU=HQ,DC=hq,DC=wsl2025,DC=org"
New-ADOrganizationalUnit -Name "Groups" -Path "OU=HQ,DC=hq,DC=wsl2025,DC=org"

# OUs par département
New-ADOrganizationalUnit -Name "IT" -Path "OU=Users,OU=HQ,DC=hq,DC=wsl2025,DC=org"
New-ADOrganizationalUnit -Name "Direction" -Path "OU=Users,OU=HQ,DC=hq,DC=wsl2025,DC=org"
New-ADOrganizationalUnit -Name "Factory" -Path "OU=Users,OU=HQ,DC=hq,DC=wsl2025,DC=org"
New-ADOrganizationalUnit -Name "Sales" -Path "OU=Users,OU=HQ,DC=hq,DC=wsl2025,DC=org"

# OU pour provisioning automatique
New-ADOrganizationalUnit -Name "AUTO" -Path "OU=Users,DC=hq,DC=wsl2025,DC=org"

# Shadow groups
New-ADOrganizationalUnit -Name "Shadow groups" -Path "DC=hq,DC=wsl2025,DC=org"
```

### Créer les utilisateurs HQ
```powershell
$users = @(
    @{Name="Vincent TIM"; Login="vtim"; Dept="IT"; Email="vtim@wsl2025.org"},
    @{Name="Ness PRESSO"; Login="npresso"; Dept="Direction"; Email="npresso@wsl2025.org"},
    @{Name="Jean TICIPE"; Login="jticipe"; Dept="Factory"; Email="jticipe@wsl2025.org"},
    @{Name="Rick OLA"; Login="rola"; Dept="Sales"; Email="rola@wsl2025.org"}
)

foreach ($user in $users) {
    New-ADUser -Name $user.Name `
        -SamAccountName $user.Login `
        -UserPrincipalName "$($user.Login)@hq.wsl2025.org" `
        -EmailAddress $user.Email `
        -Path "OU=$($user.Dept),OU=Users,OU=HQ,DC=hq,DC=wsl2025,DC=org" `
        -AccountPassword (ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force) `
        -Enabled $true `
        -ChangePasswordAtLogon $false
}

# Créer les groupes
New-ADGroup -Name "IT" -GroupScope Global -Path "OU=Groups,OU=HQ,DC=hq,DC=wsl2025,DC=org"
New-ADGroup -Name "Direction" -GroupScope Global -Path "OU=Groups,OU=HQ,DC=hq,DC=wsl2025,DC=org"
New-ADGroup -Name "Factory" -GroupScope Global -Path "OU=Groups,OU=HQ,DC=hq,DC=wsl2025,DC=org"
New-ADGroup -Name "Sales" -GroupScope Global -Path "OU=Groups,OU=HQ,DC=hq,DC=wsl2025,DC=org"

# Ajouter aux groupes
Add-ADGroupMember -Identity "IT" -Members "vtim"
Add-ADGroupMember -Identity "Direction" -Members "npresso"
Add-ADGroupMember -Identity "Factory" -Members "jticipe"
Add-ADGroupMember -Identity "Sales" -Members "rola"
```

### Provisionner 1000 utilisateurs
```powershell
# Créer les groupes
New-ADGroup -Name "FirstGroup" -GroupScope Global -Path "OU=Groups,DC=hq,DC=wsl2025,DC=org"
New-ADGroup -Name "LastGroup" -GroupScope Global -Path "OU=Groups,DC=hq,DC=wsl2025,DC=org"

# Créer 1000 utilisateurs
for ($i = 1; $i -le 1000; $i++) {
    $username = "wslusr{0:D3}" -f $i
    New-ADUser -Name $username `
        -SamAccountName $username `
        -UserPrincipalName "$username@hq.wsl2025.org" `
        -Path "OU=AUTO,OU=Users,DC=hq,DC=wsl2025,DC=org" `
        -AccountPassword (ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force) `
        -Enabled $true
    
    if ($i -le 500) {
        Add-ADGroupMember -Identity "FirstGroup" -Members $username
    } else {
        Add-ADGroupMember -Identity "LastGroup" -Members $username
    }
}
```

### Shadow Group automatique
```powershell
# Créer le groupe shadow
New-ADGroup -Name "OU_Shadow" -GroupScope Global -Path "OU=Shadow groups,DC=hq,DC=wsl2025,DC=org"

# Script pour sync automatique
New-Item -Path "C:\Scripts" -ItemType Directory -Force
@'
$users = Get-ADUser -SearchBase "OU=HQ,DC=hq,DC=wsl2025,DC=org" -Filter *
$shadowGroup = Get-ADGroup "OU_Shadow"
foreach ($user in $users) {
    if (-not (Get-ADGroupMember -Identity $shadowGroup | Where-Object {$_.SamAccountName -eq $user.SamAccountName})) {
        Add-ADGroupMember -Identity $shadowGroup -Members $user
    }
}
'@ | Out-File C:\Scripts\ShadowGroup.ps1

# Tâche planifiée chaque minute
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-File C:\Scripts\ShadowGroup.ps1"
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName "ShadowGroupSync" -Action $action -Trigger $trigger -User "SYSTEM"
```

---

## 5️⃣ ADCS - Autorité de Certification Subordonnée

### Installer ADCS
```powershell
Install-WindowsFeature -Name ADCS-Cert-Authority, ADCS-Web-Enrollment -IncludeManagementTools
```

### Générer la demande de certificat
```powershell
$inf = @"
[NewRequest]
Subject = "CN=WSFR-SUB-CA"
KeyLength = 2048
Exportable = TRUE
MachineKeySet = TRUE
SMIME = FALSE
RequestType = PKCS10
KeyUsage = 0xa0
ProviderName = "Microsoft Strong Cryptographic Provider"
ProviderType = 1
[RequestAttributes]
CertificateTemplate = SubCA
"@
$inf | Out-File C:\SubCA.inf
certreq -new C:\SubCA.inf C:\SubCA.req
```

> **Envoyer `C:\SubCA.req` à DNSSRV (8.8.4.1) pour signature, puis installer le certificat retourné.**

### Configurer ADCS
```powershell
Install-AdcsCertificationAuthority `
    -CAType EnterpriseSubordinateCA `
    -CACommonName "WSFR-SUB-CA" `
    -CertFile "C:\SubCA.cer" `
    -Force
```

### Configuration CRL
```powershell
certutil -setreg CA\CRLPeriodUnits 1
certutil -setreg CA\CRLPeriod "Days"
certutil -setreg CA\CRLDeltaPeriodUnits 1
certutil -setreg CA\CRLDeltaPeriod "Minutes"
certutil -setreg CA\CRLOverlapUnits 12
certutil -setreg CA\CRLOverlapPeriod "Hours"

New-Item -Path "C:\inetpub\PKI" -ItemType Directory
```

---

## 6️⃣ Stockage RAID-5

```powershell
# Identifier les disques
Get-PhysicalDisk | Where-Object CanPool -eq $true

# Créer le pool
$disks = Get-PhysicalDisk | Where-Object CanPool -eq $true
New-StoragePool -FriendlyName "DataPool" -StorageSubSystemFriendlyName "Windows Storage*" -PhysicalDisks $disks

# Créer le disque virtuel RAID-5 (Parity)
New-VirtualDisk -StoragePoolFriendlyName "DataPool" -FriendlyName "DataDisk" -ResiliencySettingName "Parity" -UseMaximumSize

# Initialiser et formater en ReFS
Get-VirtualDisk -FriendlyName "DataDisk" | Get-Disk | Initialize-Disk -PartitionStyle GPT
Get-VirtualDisk -FriendlyName "DataDisk" | Get-Disk | New-Partition -UseMaximumSize -DriveLetter D
Format-Volume -DriveLetter D -FileSystem ReFS -NewFileSystemLabel "DATA"

# Activer la déduplication
Install-WindowsFeature -Name FS-Data-Deduplication
Enable-DedupVolume -Volume "D:"
```

---

## 7️⃣ Partages de fichiers

### Créer les dossiers
```powershell
New-Item -Path "D:\shares\datausers" -ItemType Directory
New-Item -Path "D:\shares\Department" -ItemType Directory
New-Item -Path "D:\shares\Public" -ItemType Directory

foreach ($dept in @("IT", "Direction", "Factory", "Sales")) {
    New-Item -Path "D:\shares\Department\$dept" -ItemType Directory
    New-Item -Path "D:\shares\Public\$dept" -ItemType Directory
}
```

### Partage Home Drives
```powershell
New-SmbShare -Name "users$" -Path "D:\shares\datausers" -FullAccess "Administrators" -ChangeAccess "Authenticated Users"

# Quota 20 Mo
Install-WindowsFeature -Name FS-Resource-Manager
New-FsrmQuotaTemplate -Name "UserQuota" -Size 20MB -SoftLimit
New-FsrmAutoQuota -Path "D:\shares\datausers" -Template "UserQuota"

# Bloquer les exécutables
New-FsrmFileGroup -Name "Executables" -IncludePattern @("*.exe", "*.com", "*.bat", "*.cmd", "*.msi")
New-FsrmFileScreen -Path "D:\shares\datausers" -IncludeGroup "Executables"
```

---

## 8️⃣ GPO

```powershell
# Certificats Root et Sub CA
New-GPO -Name "Certificates" | New-GPLink -Target "DC=hq,DC=wsl2025,DC=org"

# Edge Homepage
New-GPO -Name "Edge-Homepage" | New-GPLink -Target "DC=hq,DC=wsl2025,DC=org"

# Bloquer panneau de configuration
New-GPO -Name "Block-ControlPanel" | New-GPLink -Target "OU=Users,OU=HQ,DC=hq,DC=wsl2025,DC=org"

# Logo entreprise
New-GPO -Name "Enterprise-Logo" | New-GPLink -Target "DC=hq,DC=wsl2025,DC=org"
```

---

## ✅ Vérifications

| Test | Commande |
|------|----------|
| AD DS | `Get-ADDomain` |
| DNS | `Resolve-DnsName hqdcsrv.hq.wsl2025.org` |
| ADCS | `certutil -ping` |
| Partages | `Get-SmbShare` |
| GPO | `gpresult /r` |
| Trust | `Get-ADTrust -Filter *` |

---

## 📝 Notes

- **IP** : 10.4.10.1
- Le certificat Sub CA doit être signé par la Root CA sur DNSSRV (8.8.4.1)
- Configurer l'auto-enrollment des certificats via GPO
- Tester les mappages de lecteurs (U:, S:, P:) sur les clients
