# HQDCSRV - Contrôleur de Domaine HQ

> **OS** : Windows Server 2022  
> **IP** : 10.4.10.1/27 (VLAN 10 - Servers)  
> **Rôles** : AD DS, DNS, ADCS (Sub CA), File Server, FSRM, IIS, GPO

---

## 📋 Prérequis

- [ ] Windows Server 2022 installé
- [ ] 3 disques supplémentaires de 1 Go (pour RAID-5)
- [ ] DCWSL opérationnel (10.4.10.4) - Forêt wsl2025.org créée
- [ ] DNSSRV opérationnel (8.8.4.1) - Root CA configurée
- [ ] Connectivité réseau vers DCWSL et DNSSRV

---

## 1️⃣ Configuration de base

### 1.1 Renommer le serveur

```powershell
Rename-Computer -NewName "HQDCSRV" -Restart
```

### 1.2 Configuration IP statique

```powershell
# Identifier l'interface réseau
Get-NetAdapter

# Configuration IP statique
New-NetIPAddress -InterfaceAlias "Ethernet0" -IPAddress 10.4.10.1 -PrefixLength 27 -DefaultGateway 10.4.10.30
Set-DnsClientServerAddress -InterfaceAlias "Ethernet0" -ServerAddresses 10.4.10.4, 127.0.0.1
```

### 1.3 Configuration du fuseau horaire

```powershell
Set-TimeZone -Id "Romance Standard Time"
```

---

## 2️⃣ Installation Active Directory (Child Domain)

### 2.1 Installer les rôles AD DS et DNS

```powershell
Install-WindowsFeature -Name AD-Domain-Services, DNS, RSAT-AD-Tools, RSAT-DNS-Server -IncludeManagementTools
```

### 2.2 Promouvoir en Child Domain de wsl2025.org

```powershell
# Credentials de l'administrateur du domaine parent
$cred = Get-Credential -Message "Entrez les credentials de WSL2025\Administrator"

# Installation du domaine enfant hq.wsl2025.org
Install-ADDSDomain `
    -NewDomainName "hq" `
    -ParentDomainName "wsl2025.org" `
    -DomainType ChildDomain `
    -InstallDns:$true `
    -CreateDnsDelegation:$true `
    -Credential $cred `
    -DatabasePath "C:\Windows\NTDS" `
    -LogPath "C:\Windows\NTDS" `
    -SysvolPath "C:\Windows\SYSVOL" `
    -SafeModeAdministratorPassword (ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force) `
    -Force
```

> ⚠️ Le serveur redémarre automatiquement après l'installation.

---

## 3️⃣ Configuration DNS

### 3.1 Vérifier la zone DNS hq.wsl2025.org

```powershell
# La zone est créée automatiquement lors de la promotion AD
Get-DnsServerZone
```

### 3.2 Créer les enregistrements DNS requis

```powershell
# Enregistrement A pour hqdcsrv
Add-DnsServerResourceRecordA -ZoneName "hq.wsl2025.org" -Name "hqdcsrv" -IPv4Address "10.4.10.1"

# CNAME hqwebsrv pointe vers le firewall (dans zone parent)
Add-DnsServerResourceRecordCName -ZoneName "hq.wsl2025.org" -Name "hqwebsrv" -HostNameAlias "hqfwsrv.wsl2025.org"

# CNAME pki pointe vers hqdcsrv
Add-DnsServerResourceRecordCName -ZoneName "hq.wsl2025.org" -Name "pki" -HostNameAlias "hqdcsrv.hq.wsl2025.org"
```

### 3.3 Configurer le forwarder

```powershell
# Forwarder vers DNSSRV pour les requêtes externes
Set-DnsServerForwarder -IPAddress 8.8.4.1
```

### 3.4 Activer DNSSEC

```powershell
# Signer la zone hq.wsl2025.org
Invoke-DnsServerZoneSign -ZoneName "hq.wsl2025.org" -SignWithDefault -Force
```

---

## 4️⃣ Structure Organisationnelle Active Directory

### 4.1 Créer les OUs principales

```powershell
# OU principale HQ
New-ADOrganizationalUnit -Name "HQ" -Path "DC=hq,DC=wsl2025,DC=org" -ProtectedFromAccidentalDeletion $true

# Sous-OUs de HQ
New-ADOrganizationalUnit -Name "Users" -Path "OU=HQ,DC=hq,DC=wsl2025,DC=org"
New-ADOrganizationalUnit -Name "Computers" -Path "OU=HQ,DC=hq,DC=wsl2025,DC=org"
New-ADOrganizationalUnit -Name "Groups" -Path "OU=HQ,DC=hq,DC=wsl2025,DC=org"

# OUs par département (dans Users)
New-ADOrganizationalUnit -Name "IT" -Path "OU=Users,OU=HQ,DC=hq,DC=wsl2025,DC=org"
New-ADOrganizationalUnit -Name "Direction" -Path "OU=Users,OU=HQ,DC=hq,DC=wsl2025,DC=org"
New-ADOrganizationalUnit -Name "Factory" -Path "OU=Users,OU=HQ,DC=hq,DC=wsl2025,DC=org"
New-ADOrganizationalUnit -Name "Sales" -Path "OU=Users,OU=HQ,DC=hq,DC=wsl2025,DC=org"

# OU AUTO pour le provisioning (dans Users de HQ)
New-ADOrganizationalUnit -Name "AUTO" -Path "OU=Users,OU=HQ,DC=hq,DC=wsl2025,DC=org"

# OU Shadow Groups à la racine
New-ADOrganizationalUnit -Name "Shadow groups" -Path "DC=hq,DC=wsl2025,DC=org"

# OU Groups à la racine (pour FirstGroup et LastGroup)
New-ADOrganizationalUnit -Name "Groups" -Path "DC=hq,DC=wsl2025,DC=org"
```

### 4.2 Créer les groupes de sécurité

```powershell
# Groupes dans OU=Groups,OU=HQ (pour les départements)
New-ADGroup -Name "IT" -GroupScope Global -GroupCategory Security -Path "OU=Groups,OU=HQ,DC=hq,DC=wsl2025,DC=org"
New-ADGroup -Name "Direction" -GroupScope Global -GroupCategory Security -Path "OU=Groups,OU=HQ,DC=hq,DC=wsl2025,DC=org"
New-ADGroup -Name "Factory" -GroupScope Global -GroupCategory Security -Path "OU=Groups,OU=HQ,DC=hq,DC=wsl2025,DC=org"
New-ADGroup -Name "Sales" -GroupScope Global -GroupCategory Security -Path "OU=Groups,OU=HQ,DC=hq,DC=wsl2025,DC=org"

# Groupes à la racine pour le provisioning
New-ADGroup -Name "FirstGroup" -GroupScope Global -GroupCategory Security -Path "OU=Groups,DC=hq,DC=wsl2025,DC=org"
New-ADGroup -Name "LastGroup" -GroupScope Global -GroupCategory Security -Path "OU=Groups,DC=hq,DC=wsl2025,DC=org"

# Shadow Group
New-ADGroup -Name "OU_Shadow" -GroupScope Global -GroupCategory Security -Path "OU=Shadow groups,DC=hq,DC=wsl2025,DC=org"
```

### 4.3 Créer les utilisateurs HQ

```powershell
$users = @(
    @{Name="Vincent TIM"; First="Vincent"; Last="TIM"; Login="vtim"; Dept="IT"; Email="vtim@wsl2025.org"},
    @{Name="Ness PRESSO"; First="Ness"; Last="PRESSO"; Login="npresso"; Dept="Direction"; Email="npresso@wsl2025.org"},
    @{Name="Jean TICIPE"; First="Jean"; Last="TICIPE"; Login="jticipe"; Dept="Factory"; Email="jticipe@wsl2025.org"},
    @{Name="Rick OLA"; First="Rick"; Last="OLA"; Login="rola"; Dept="Sales"; Email="rola@wsl2025.org"}
)

foreach ($user in $users) {
    New-ADUser -Name $user.Name `
        -GivenName $user.First `
        -Surname $user.Last `
        -SamAccountName $user.Login `
        -UserPrincipalName "$($user.Login)@hq.wsl2025.org" `
        -EmailAddress $user.Email `
        -Path "OU=$($user.Dept),OU=Users,OU=HQ,DC=hq,DC=wsl2025,DC=org" `
        -AccountPassword (ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force) `
        -Enabled $true `
        -ChangePasswordAtLogon $false `
        -PasswordNeverExpires $true

    # Ajouter au groupe du département
    Add-ADGroupMember -Identity $user.Dept -Members $user.Login
}
```

### 4.4 Provisionner les 1000 utilisateurs

```powershell
# Créer 1000 utilisateurs wslusr001 à wslusr1000
for ($i = 1; $i -le 1000; $i++) {
    $username = "wslusr{0:D3}" -f $i

    New-ADUser -Name $username `
        -SamAccountName $username `
        -UserPrincipalName "$username@hq.wsl2025.org" `
        -Path "OU=AUTO,OU=Users,OU=HQ,DC=hq,DC=wsl2025,DC=org" `
        -AccountPassword (ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force) `
        -Enabled $true `
        -ChangePasswordAtLogon $false

    # 500 premiers dans FirstGroup, 500 derniers dans LastGroup
    if ($i -le 500) {
        Add-ADGroupMember -Identity "FirstGroup" -Members $username
    } else {
        Add-ADGroupMember -Identity "LastGroup" -Members $username
    }

    # Afficher la progression
    if ($i % 100 -eq 0) { Write-Host "Créé $i utilisateurs..." }
}
Write-Host "Provisioning terminé : 1000 utilisateurs créés"
```

### 4.5 Shadow Group - Synchronisation automatique

```powershell
# Créer le dossier pour les scripts
New-Item -Path "C:\Scripts" -ItemType Directory -Force

# Script de synchronisation du Shadow Group
$shadowScript = @'
# ShadowGroup.ps1 - Synchronise les utilisateurs de OU=HQ vers OU_Shadow
Import-Module ActiveDirectory

$ouPath = "OU=HQ,DC=hq,DC=wsl2025,DC=org"
$shadowGroup = "OU_Shadow"

# Récupérer tous les utilisateurs de l'OU HQ (récursif)
$users = Get-ADUser -SearchBase $ouPath -Filter * -SearchScope Subtree

# Récupérer les membres actuels du shadow group
$currentMembers = Get-ADGroupMember -Identity $shadowGroup | Select-Object -ExpandProperty SamAccountName

foreach ($user in $users) {
    if ($user.SamAccountName -notin $currentMembers) {
        try {
            Add-ADGroupMember -Identity $shadowGroup -Members $user.SamAccountName
            Write-Host "Ajouté: $($user.SamAccountName)"
        } catch {
            Write-Warning "Erreur pour $($user.SamAccountName): $_"
        }
    }
}
'@
$shadowScript | Out-File -FilePath "C:\Scripts\ShadowGroup.ps1" -Encoding UTF8

# Créer la tâche planifiée (exécution chaque minute)
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File C:\Scripts\ShadowGroup.ps1"
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 1) -RepetitionDuration (New-TimeSpan -Days 9999)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

Register-ScheduledTask -TaskName "ShadowGroupSync" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Synchronise les utilisateurs HQ vers OU_Shadow"

# Exécuter immédiatement
Start-ScheduledTask -TaskName "ShadowGroupSync"
```

---

## 5️⃣ ADCS - Autorité de Certification Subordonnée

### 5.1 Installer ADCS et IIS

```powershell
Install-WindowsFeature -Name ADCS-Cert-Authority, ADCS-Web-Enrollment, Web-Server, Web-Mgmt-Tools -IncludeManagementTools
```

### 5.2 Générer la demande de certificat pour la Sub CA

```powershell
# Créer le fichier INF pour la demande
$inf = @"
[Version]
Signature = "`$Windows NT$"

[NewRequest]
Subject = "CN=WSFR-SUB-CA,OU=Worldskills France Lyon 2025,O=Worldskills France,L=Lyon,S=Auvergne Rhone-Alpes,C=FR"
KeyLength = 2048
KeySpec = 1
KeyUsage = 0xa0
MachineKeySet = TRUE
RequestType = PKCS10
ProviderName = "Microsoft RSA SChannel Cryptographic Provider"
ProviderType = 12
SMIME = FALSE
Exportable = TRUE

[RequestAttributes]
CertificateTemplate = SubCA
"@
$inf | Out-File -FilePath "C:\SubCA.inf" -Encoding ASCII

# Générer la demande de certificat
certreq -new C:\SubCA.inf C:\SubCA.req

Write-Host "Fichier C:\SubCA.req généré. Envoyez-le à DNSSRV (8.8.4.1) pour signature."
```

### 5.3 Signer le certificat sur DNSSRV (Root CA)

> **Sur DNSSRV (8.8.4.1)** : Transférer le fichier `C:\SubCA.req` et exécuter :

```bash
# Sur DNSSRV (Linux avec OpenSSL)
openssl ca -config /etc/ssl/openssl.cnf -extensions v3_ca -days 3650 -notext -md sha256 -in SubCA.req -out SubCA.cer
```

### 5.4 Installer le certificat et configurer ADCS

```powershell
# Après réception du certificat signé (SubCA.cer), l'installer
# Récupérer également le certificat Root CA (WSFR-ROOT-CA.cer)

# Installer le certificat Root CA dans le magasin racine
Import-Certificate -FilePath "C:\WSFR-ROOT-CA.cer" -CertStoreLocation Cert:\LocalMachine\Root

# Configurer ADCS comme Enterprise Subordinate CA
Install-AdcsCertificationAuthority `
    -CAType EnterpriseSubordinateCA `
    -CACommonName "WSFR-SUB-CA" `
    -CertFile "C:\SubCA.cer" `
    -CertificateID "WSFR-SUB-CA" `
    -Force
```

### 5.5 Configurer les paramètres CRL

```powershell
# CRL publication : tous les jours
certutil -setreg CA\CRLPeriodUnits 1
certutil -setreg CA\CRLPeriod "Days"

# Delta CRL : chaque minute
certutil -setreg CA\CRLDeltaPeriodUnits 1
certutil -setreg CA\CRLDeltaPeriod "Minutes"

# Delta CRL Overlap : 12 heures
certutil -setreg CA\CRLOverlapUnits 12
certutil -setreg CA\CRLOverlapPeriod "Hours"

# Redémarrer le service
Restart-Service certsvc
```

### 5.6 Créer le dossier PKI et configurer IIS

```powershell
# Créer le dossier pour les CRL
New-Item -Path "C:\inetpub\PKI" -ItemType Directory -Force

# Configurer les permissions
$acl = Get-Acl "C:\inetpub\PKI"
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule("IIS_IUSRS", "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")
$acl.AddAccessRule($rule)
Set-Acl "C:\inetpub\PKI" $acl

# Créer le site IIS pour PKI
Import-Module WebAdministration

# Supprimer le binding existant sur le port 80 si nécessaire
Remove-IISSite -Name "Default Web Site" -Confirm:$false -ErrorAction SilentlyContinue

# Créer le nouveau site PKI
New-IISSite -Name "PKI" -PhysicalPath "C:\inetpub\PKI" -BindingInformation "*:80:"

# Permettre le double escaping pour les fichiers .crl
Set-WebConfigurationProperty -PSPath "IIS:\Sites\PKI" -Filter "system.webServer/security/requestFiltering" -Name "allowDoubleEscaping" -Value $true

# Démarrer le site
Start-IISSite -Name "PKI"
```

### 5.7 Configurer la publication automatique des CRL

```powershell
# Configurer l'AIA et CDP pour publier dans C:\inetpub\PKI
$crlPath = "C:\inetpub\PKI"
$httpUrl = "http://pki.hq.wsl2025.org"

# Ajouter le CDP (CRL Distribution Point)
certutil -setreg CA\CRLPublicationURLs "1:$crlPath\%3%8%9.crl\n2:$httpUrl/%3%8%9.crl"

# Ajouter l'AIA (Authority Information Access)
certutil -setreg CA\CACertPublicationURLs "1:$crlPath\%1_%3%4.crt\n2:$httpUrl/%1_%3%4.crt"

# Redémarrer le service
Restart-Service certsvc

# Publier la CRL immédiatement
certutil -crl
```

### 5.8 Créer les templates de certificats

#### Template WSFR_Services (On-demand pour services)

```powershell
# Dupliquer le template "Web Server" pour créer WSFR_Services
$configContext = ([ADSI]"LDAP://RootDSE").configurationNamingContext
$templateContainer = "CN=Certificate Templates,CN=Public Key Services,CN=Services,$configContext"

# Exporter le template existant et le modifier (via GUI ou ADCS PowerShell)
# Alternative : utiliser la console certtmpl.msc

Write-Host "Ouvrir certtmpl.msc et créer manuellement les templates suivants :"
Write-Host "1. WSFR_Services - Dupliquer 'Web Server', activer 'Supply in request'"
Write-Host "2. WSFR_Machines - Dupliquer 'Computer', activer autoenrollment"
Write-Host "3. WSFR_Users - Dupliquer 'User', activer autoenrollment"
```

#### Configuration manuelle des templates (certtmpl.msc)

> **Étapes manuelles dans certtmpl.msc :**
>
> **WSFR_Services :**
>
> 1. Clic droit sur "Web Server" → Duplicate Template
> 2. General : Nom = "WSFR_Services"
> 3. Request Handling : Allow private key to be exported
> 4. Subject Name : Supply in the request
> 5. Security : Authenticated Users → Enroll
>
> **WSFR_Machines :**
>
> 1. Clic droit sur "Computer" → Duplicate Template
> 2. General : Nom = "WSFR_Machines"
> 3. Security : Domain Computers → Enroll + Autoenroll
>
> **WSFR_Users :**
>
> 1. Clic droit sur "User" → Duplicate Template
> 2. General : Nom = "WSFR_Users"
> 3. Security : Domain Users → Enroll + Autoenroll

### 5.9 Publier les templates

```powershell
# Publier les templates sur la CA (après création manuelle)
Add-CATemplate -Name "WSFR_Services" -Force
Add-CATemplate -Name "WSFR_Machines" -Force
Add-CATemplate -Name "WSFR_Users" -Force

# Vérifier les templates publiés
Get-CATemplate
```

---

## 6️⃣ Stockage RAID-5

### 6.1 Identifier les disques disponibles

```powershell
# Lister les disques physiques disponibles pour le pool
Get-PhysicalDisk | Where-Object CanPool -eq $true | Format-Table FriendlyName, Size, MediaType
```

### 6.2 Créer le pool de stockage

```powershell
# Récupérer les disques poolables
$disks = Get-PhysicalDisk | Where-Object CanPool -eq $true

# Créer le pool de stockage
New-StoragePool -FriendlyName "DataPool" `
    -StorageSubSystemFriendlyName "Windows Storage*" `
    -PhysicalDisks $disks
```

### 6.3 Créer le disque virtuel RAID-5 (Parity)

```powershell
# Créer le disque virtuel avec résilience Parity (RAID-5)
New-VirtualDisk -StoragePoolFriendlyName "DataPool" `
    -FriendlyName "DataDisk" `
    -ResiliencySettingName "Parity" `
    -UseMaximumSize
```

### 6.4 Initialiser et formater en NTFS

```powershell
# Récupérer le disque virtuel et l'initialiser
$vdisk = Get-VirtualDisk -FriendlyName "DataDisk"
$disk = $vdisk | Get-Disk

# Initialiser le disque
Initialize-Disk -Number $disk.Number -PartitionStyle GPT

# Créer la partition
New-Partition -DiskNumber $disk.Number -UseMaximumSize -DriveLetter D

# Formater en NTFS (PAS ReFS - conformément au sujet)
Format-Volume -DriveLetter D -FileSystem NTFS -NewFileSystemLabel "DATA" -Confirm:$false
```

### 6.5 Activer la déduplication

```powershell
# Installer la fonctionnalité de déduplication
Install-WindowsFeature -Name FS-Data-Deduplication

# Activer la déduplication sur le volume D:
Enable-DedupVolume -Volume "D:" -UsageType Default

# Configurer les paramètres de déduplication
Set-DedupVolume -Volume "D:" -MinimumFileAgeDays 0
```

---

## 7️⃣ Serveur de fichiers et partages

### 7.1 Installer FSRM

```powershell
Install-WindowsFeature -Name FS-Resource-Manager -IncludeManagementTools
```

### 7.2 Créer la structure des dossiers

```powershell
# Dossiers principaux
New-Item -Path "D:\shares" -ItemType Directory -Force
New-Item -Path "D:\shares\datausers" -ItemType Directory -Force
New-Item -Path "D:\shares\Department" -ItemType Directory -Force
New-Item -Path "D:\shares\Public" -ItemType Directory -Force

# Dossiers par département
$departments = @("IT", "Direction", "Factory", "Sales")
foreach ($dept in $departments) {
    New-Item -Path "D:\shares\Department\$dept" -ItemType Directory -Force
    New-Item -Path "D:\shares\Public\$dept" -ItemType Directory -Force
}
```

### 7.3 Partage Home Drives (users$)

```powershell
# Créer le partage caché pour les home drives
New-SmbShare -Name "users$" `
    -Path "D:\shares\datausers" `
    -FullAccess "HQ\Domain Admins" `
    -ChangeAccess "HQ\Authenticated Users" `
    -FolderEnumerationMode AccessBased  # ABE activé

# Configurer les permissions NTFS
$acl = Get-Acl "D:\shares\datausers"
$acl.SetAccessRuleProtection($true, $false)  # Désactiver l'héritage

# Administrateurs - Full Control
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule("HQ\Domain Admins", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
$acl.AddAccessRule($rule)

# CREATOR OWNER - pour les sous-dossiers utilisateurs
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule("CREATOR OWNER", "FullControl", "ContainerInherit,ObjectInherit", "InheritOnly", "Allow")
$acl.AddAccessRule($rule)

# Utilisateurs authentifiés - CreateFolders uniquement sur ce dossier
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule("HQ\Authenticated Users", "CreateDirectories", "None", "None", "Allow")
$acl.AddAccessRule($rule)

Set-Acl "D:\shares\datausers" $acl
```

### 7.4 Quota 20 Mo pour les home drives

```powershell
# Créer le template de quota (20 Mo soft limit)
New-FsrmQuotaTemplate -Name "UserQuota20MB" `
    -Size 20MB `
    -SoftLimit `
    -Description "Quota utilisateur 20 Mo"

# Appliquer l'auto-quota sur le dossier
New-FsrmAutoQuota -Path "D:\shares\datausers" -Template "UserQuota20MB"
```

### 7.5 Bloquer les fichiers exécutables

```powershell
# Créer le groupe de fichiers pour les exécutables
New-FsrmFileGroup -Name "Executables" -IncludePattern @("*.exe", "*.com", "*.bat", "*.cmd", "*.msi", "*.vbs", "*.ps1", "*.scr")

# Créer le file screen
New-FsrmFileScreen -Path "D:\shares\datausers" -IncludeGroup "Executables" -Active
```

### 7.6 Partage Department

```powershell
# Créer le partage Department
New-SmbShare -Name "Department$" `
    -Path "D:\shares\Department" `
    -FullAccess "HQ\Domain Admins" `
    -FolderEnumerationMode AccessBased

# Configurer les permissions par département
foreach ($dept in $departments) {
    $deptPath = "D:\shares\Department\$dept"
    $acl = Get-Acl $deptPath
    $acl.SetAccessRuleProtection($true, $false)

    # Administrateurs
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule("HQ\Domain Admins", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.AddAccessRule($rule)

    # Groupe du département - Modify
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule("HQ\$dept", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.AddAccessRule($rule)

    Set-Acl $deptPath $acl
}
```

### 7.7 Partage Public

```powershell
# Créer le partage Public
New-SmbShare -Name "Public$" `
    -Path "D:\shares\Public" `
    -FullAccess "HQ\Domain Admins" `
    -ReadAccess "HQ\Domain Users" `
    -FolderEnumerationMode AccessBased

# Configurer les permissions par département
foreach ($dept in $departments) {
    $deptPath = "D:\shares\Public\$dept"
    $acl = Get-Acl $deptPath
    $acl.SetAccessRuleProtection($true, $false)

    # Administrateurs
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule("HQ\Domain Admins", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.AddAccessRule($rule)

    # Groupe du département - Modify
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule("HQ\$dept", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.AddAccessRule($rule)

    # Autres utilisateurs - Read only
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule("HQ\Domain Users", "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.AddAccessRule($rule)

    Set-Acl $deptPath $acl
}
```

---

## 8️⃣ GPO (Group Policy Objects)

### 8.1 GPO - Certificats Root CA et Sub CA

```powershell
# Créer la GPO pour les certificats
$gpo = New-GPO -Name "Deploy-Certificates" -Comment "Déploie les certificats Root CA et Sub CA"
$gpo | New-GPLink -Target "DC=hq,DC=wsl2025,DC=org"

Write-Host "Configurer manuellement dans GPMC :"
Write-Host "Computer Configuration > Policies > Windows Settings > Security Settings > Public Key Policies"
Write-Host "- Trusted Root CA : Importer WSFR-ROOT-CA.cer"
Write-Host "- Intermediate CA : Importer WSFR-SUB-CA.cer"
```

### 8.2 GPO - Autoenrollment des certificats

```powershell
# Créer la GPO pour l'auto-enrollment
$gpo = New-GPO -Name "Certificate-Autoenrollment" -Comment "Active l'auto-enrollment des certificats"
$gpo | New-GPLink -Target "DC=hq,DC=wsl2025,DC=org"

# Configurer l'auto-enrollment via registre
Set-GPRegistryValue -Name "Certificate-Autoenrollment" `
    -Key "HKLM\SOFTWARE\Policies\Microsoft\Cryptography\AutoEnrollment" `
    -ValueName "AEPolicy" `
    -Type DWord `
    -Value 7

Set-GPRegistryValue -Name "Certificate-Autoenrollment" `
    -Key "HKCU\SOFTWARE\Policies\Microsoft\Cryptography\AutoEnrollment" `
    -ValueName "AEPolicy" `
    -Type DWord `
    -Value 7
```

### 8.3 GPO - Edge Homepage (Intranet)

```powershell
# Créer la GPO pour Edge
$gpo = New-GPO -Name "Edge-Homepage-Intranet" -Comment "Configure la page d'accueil Edge sur l'intranet"
$gpo | New-GPLink -Target "DC=hq,DC=wsl2025,DC=org"

# Configurer la page d'accueil
Set-GPRegistryValue -Name "Edge-Homepage-Intranet" `
    -Key "HKLM\SOFTWARE\Policies\Microsoft\Edge" `
    -ValueName "HomepageLocation" `
    -Type String `
    -Value "https://www.wsl2025.org"

# Activer le bouton Accueil
Set-GPRegistryValue -Name "Edge-Homepage-Intranet" `
    -Key "HKLM\SOFTWARE\Policies\Microsoft\Edge" `
    -ValueName "ShowHomeButton" `
    -Type DWord `
    -Value 1

# Empêcher la modification
Set-GPRegistryValue -Name "Edge-Homepage-Intranet" `
    -Key "HKLM\SOFTWARE\Policies\Microsoft\Edge" `
    -ValueName "HomepageIsNewTabPage" `
    -Type DWord `
    -Value 0

# Configurer RestoreOnStartup pour ouvrir la homepage
Set-GPRegistryValue -Name "Edge-Homepage-Intranet" `
    -Key "HKLM\SOFTWARE\Policies\Microsoft\Edge" `
    -ValueName "RestoreOnStartup" `
    -Type DWord `
    -Value 4

Set-GPRegistryValue -Name "Edge-Homepage-Intranet" `
    -Key "HKLM\SOFTWARE\Policies\Microsoft\Edge\RestoreOnStartupURLs" `
    -ValueName "1" `
    -Type String `
    -Value "https://www.wsl2025.org"
```

### 8.4 GPO - Bloquer le Panneau de configuration

```powershell
# Créer la GPO pour bloquer le panneau de config
$gpo = New-GPO -Name "Block-ControlPanel" -Comment "Bloque l'accès au panneau de configuration sauf pour les admins"
$gpo | New-GPLink -Target "OU=Users,OU=HQ,DC=hq,DC=wsl2025,DC=org"

# Bloquer le panneau de configuration
Set-GPRegistryValue -Name "Block-ControlPanel" `
    -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" `
    -ValueName "NoControlPanel" `
    -Type DWord `
    -Value 1

# Filtrer la GPO pour exclure le groupe IT (admins)
$gpo = Get-GPO -Name "Block-ControlPanel"
Set-GPPermission -Name "Block-ControlPanel" -TargetName "IT" -TargetType Group -PermissionLevel GpoApply -Replace
Set-GPPermission -Name "Block-ControlPanel" -TargetName "IT" -TargetType Group -PermissionLevel None

# Alternative : Deny Apply pour le groupe IT
$gpo = Get-GPO -Name "Block-ControlPanel"
# Dans GPMC, ajouter "IT" avec "Deny Apply Group Policy"
```

### 8.5 GPO - Logo entreprise

```powershell
# Créer la GPO pour le logo
$gpo = New-GPO -Name "Enterprise-Logo" -Comment "Affiche le logo entreprise"
$gpo | New-GPLink -Target "DC=hq,DC=wsl2025,DC=org"

# Créer le dossier pour le logo sur NETLOGON
$logoPath = "\\hq.wsl2025.org\NETLOGON\Logo"
New-Item -Path "C:\Windows\SYSVOL\domain\scripts\Logo" -ItemType Directory -Force

Write-Host "Placer le logo dans : C:\Windows\SYSVOL\domain\scripts\Logo\logo.bmp"
Write-Host "Configurer dans GPMC > User Configuration > Policies > Administrative Templates > Control Panel > Personalization"
```

### 8.6 GPO - Mappage des lecteurs réseau

```powershell
# Créer la GPO pour le mappage des lecteurs
$gpo = New-GPO -Name "Drive-Mappings" -Comment "Configure les lecteurs réseau U:, S:, P:"
$gpo | New-GPLink -Target "OU=Users,OU=HQ,DC=hq,DC=wsl2025,DC=org"

# Script de mappage (à placer dans NETLOGON)
$driveScript = @'
@echo off
REM Mappage des lecteurs réseau

REM U: - Home Drive personnel
net use U: /delete /y 2>nul
net use U: \\hq.wsl2025.org\users$\%USERNAME% /persistent:yes

REM S: - Dossier Département
net use S: /delete /y 2>nul
net use S: \\HQDCSRV\Department$ /persistent:yes

REM P: - Dossier Public
net use P: /delete /y 2>nul
net use P: \\HQDCSRV\Public$ /persistent:yes
'@
$driveScript | Out-File -FilePath "C:\Windows\SYSVOL\domain\scripts\MapDrives.bat" -Encoding ASCII

Write-Host "Configurer le script de logon dans GPMC :"
Write-Host "User Configuration > Policies > Windows Settings > Scripts > Logon"
Write-Host "Ajouter : MapDrives.bat"
```

### 8.7 GPO - Configurer les Home Folders utilisateurs

```powershell
# Configurer le home folder pour chaque utilisateur
$users = Get-ADUser -Filter * -SearchBase "OU=HQ,DC=hq,DC=wsl2025,DC=org" -SearchScope Subtree

foreach ($user in $users) {
    $homeFolder = "\\hq.wsl2025.org\users$\$($user.SamAccountName)"
    $localPath = "D:\shares\datausers\$($user.SamAccountName)"

    # Créer le dossier local s'il n'existe pas
    if (-not (Test-Path $localPath)) {
        New-Item -Path $localPath -ItemType Directory -Force

        # Configurer les permissions
        $acl = Get-Acl $localPath
        $acl.SetAccessRuleProtection($true, $false)

        # Administrateurs
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule("HQ\Domain Admins", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
        $acl.AddAccessRule($rule)

        # Utilisateur propriétaire
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($user.SamAccountName, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
        $acl.AddAccessRule($rule)

        Set-Acl $localPath $acl
    }

    # Configurer le profil AD
    Set-ADUser -Identity $user -HomeDirectory $homeFolder -HomeDrive "U:"
}
```

---

## 9️⃣ Configuration NTP

```powershell
# Configurer le serveur NTP (synchronisation avec HQINFRASRV)
w32tm /config /manualpeerlist:"hqinfrasrv.wsl2025.org" /syncfromflags:manual /reliable:yes /update

# Redémarrer le service
Restart-Service w32time

# Forcer la synchronisation
w32tm /resync
```

---

## ✅ Vérifications finales

### Tests Active Directory

```powershell
# Vérifier le domaine
Get-ADDomain

# Vérifier la forêt
Get-ADForest

# Vérifier le trust avec le parent
Get-ADTrust -Filter *

# Lister les OUs
Get-ADOrganizationalUnit -Filter * | Format-Table Name, DistinguishedName

# Compter les utilisateurs
(Get-ADUser -Filter * -SearchBase "DC=hq,DC=wsl2025,DC=org").Count
```

### Tests DNS

```powershell
# Tester la résolution DNS
Resolve-DnsName hqdcsrv.hq.wsl2025.org
Resolve-DnsName pki.hq.wsl2025.org
Resolve-DnsName hqwebsrv.hq.wsl2025.org

# Vérifier DNSSEC
Resolve-DnsName hq.wsl2025.org -DnssecOk
```

### Tests ADCS

```powershell
# Vérifier la CA
certutil -ping

# Lister les templates
Get-CATemplate

# Vérifier les CRL
certutil -URL http://pki.hq.wsl2025.org/WSFR-SUB-CA.crl
```

### Tests Stockage

```powershell
# Vérifier le volume RAID-5
Get-VirtualDisk
Get-Volume -DriveLetter D

# Vérifier la déduplication
Get-DedupStatus -Volume D:
```

### Tests Partages

```powershell
# Lister les partages
Get-SmbShare

# Tester l'accès
Test-Path "\\hq.wsl2025.org\users$"
Get-SmbShareAccess -Name "users$"
```

### Tests GPO

```powershell
# Lister les GPO
Get-GPO -All

# Générer un rapport
gpresult /r
```

---

## 📝 Récapitulatif des services

| Service  | Port | URL/Accès                      |
| -------- | ---- | ------------------------------ |
| DNS      | 53   | hqdcsrv.hq.wsl2025.org         |
| LDAP     | 389  | ldap://hqdcsrv.hq.wsl2025.org  |
| LDAPS    | 636  | ldaps://hqdcsrv.hq.wsl2025.org |
| Kerberos | 88   | hqdcsrv.hq.wsl2025.org         |
| PKI/CRL  | 80   | http://pki.hq.wsl2025.org      |
| SMB      | 445  | \\hq.wsl2025.org\*             |

---

## 📋 Checklist finale

- [ ] Serveur renommé HQDCSRV
- [ ] IP statique configurée (10.4.10.1/27)
- [ ] Child domain hq.wsl2025.org créé
- [ ] Zone DNS hq.wsl2025.org configurée avec DNSSEC
- [ ] Enregistrements DNS créés (hqdcsrv, hqwebsrv, pki)
- [ ] OUs créées (HQ, Users, Computers, Groups, Shadow groups)
- [ ] 4 utilisateurs HQ créés
- [ ] 1000 utilisateurs provisionnés (wslusr001-wslusr1000)
- [ ] Shadow Group avec synchronisation automatique
- [ ] ADCS Enterprise Subordinate CA configurée
- [ ] Templates de certificats créés (WSFR_Services, WSFR_Machines, WSFR_Users)
- [ ] Site IIS PKI configuré
- [ ] RAID-5 avec 3 disques (NTFS, DATA)
- [ ] Déduplication activée
- [ ] Partages créés (users$, Department$, Public$)
- [ ] ABE activé sur les partages
- [ ] Quota 20 Mo et blocage exécutables
- [ ] GPO certificats déployée
- [ ] GPO Edge homepage configurée
- [ ] GPO Block Control Panel active
- [ ] GPO mappage lecteurs (U:, S:, P:)
- [ ] NTP synchronisé avec HQINFRASRV
