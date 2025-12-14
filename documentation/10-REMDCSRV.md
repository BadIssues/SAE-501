# REMDCSRV - Contrôleur de Domaine Remote

> **OS** : Windows Server 2022  
> **IP** : 10.4.100.1/25  
> **Gateway** : 10.4.100.126 (REMFW)  
> **Rôles** : AD DS (Child Domain rem.wsl2025.org), DNS, DHCP, DFS  
> **Parent Domain** : wsl2025.org (DCWSL)

---

## 📋 Prérequis

- [ ] Windows Server 2022 installé
- [ ] Connectivité réseau avec DCWSL (10.4.10.4) via REMFW/WANRTR
- [ ] DCWSL (wsl2025.org) opérationnel
- [ ] HQDCSRV (hq.wsl2025.org) opérationnel avec PKI/ADCS
- [ ] Résolution DNS vers wsl2025.org fonctionnelle
- [ ] **ACL REMFW correctement configurée** (voir section Dépannage)

> ⚠️ **IMPORTANT - ACL REMFW** : Avant de commencer, vérifier que l'ACL `FIREWALL-INBOUND` sur REMFW autorise les **réponses UDP** (source port) pour DNS, Kerberos, LDAP, NTP et SMB. Sans cela, la promotion AD échouera ! Voir la section [Dépannage](#-dépannage) en fin de document.

---

## 1️⃣ Configuration de base

### 1.1 Renommer le serveur

```powershell
Rename-Computer -NewName "REMDCSRV" -Restart
```

### 1.2 Configuration IP statique

```powershell
# Désactiver DHCP et configurer IP statique
New-NetIPAddress -InterfaceAlias "Ethernet0" `
    -IPAddress 10.4.100.1 `
    -PrefixLength 25 `
    -DefaultGateway 10.4.100.126

# DNS pointe vers DCWSL (wsl2025.org) pour joindre le domaine
Set-DnsClientServerAddress -InterfaceAlias "Ethernet0" `
    -ServerAddresses 10.4.10.4
```

### 1.3 Vérifier la connectivité

```powershell
# Test ping vers DCWSL
Test-Connection -ComputerName 10.4.10.4

# Test résolution DNS
Resolve-DnsName wsl2025.org
Resolve-DnsName dcwsl.wsl2025.org
```

---

## 2️⃣ Installation des rôles

### 2.1 Installer tous les rôles nécessaires

```powershell
Install-WindowsFeature -Name `
    AD-Domain-Services, `
    DNS, `
    DHCP, `
    FS-DFS-Namespace, `
    FS-DFS-Replication, `
    FS-Resource-Manager, `
    RSAT-AD-Tools, `
    RSAT-DNS-Server, `
    RSAT-DHCP, `
    RSAT-DFS-Mgmt-Con `
    -IncludeManagementTools
```

---

## 3️⃣ Promotion Active Directory

### 3.1 Créer le Child Domain rem.wsl2025.org

> **Important** : REMDCSRV est un **child domain de wsl2025.org** (forest root = DCWSL), pas de hq.wsl2025.org

> ⚠️ **PROBLÈME FRÉQUENT - Échec de connexion au domaine parent**
>
> Si vous obtenez l'erreur _"Impossible de se connecter au domaine"_ ou _"Échec de la vérification des autorisations"_ :
>
> 1. **Vérifier la résolution DNS** : `nslookup wsl2025.org` doit répondre (10.4.10.4)
> 2. **Utiliser le FQDN complet** pour les credentials : `WSL2025.ORG\Administrateur` (pas juste `WSL2025\Administrateur`)
> 3. **Vérifier l'ACL REMFW** : Les réponses UDP doivent être autorisées (voir section Dépannage)
> 4. **Vider le cache DNS** : `Clear-DnsClientCache` puis réessayer

```powershell
# Credentials de l'administrateur du domaine wsl2025.org (DCWSL)
# IMPORTANT: Utiliser le FQDN complet WSL2025.ORG\Administrateur
$credential = Get-Credential -Message "Entrez les credentials de WSL2025.ORG\Administrateur"

# Promotion en tant que Child Domain
Install-ADDSDomain `
    -NewDomainName "rem" `
    -ParentDomainName "wsl2025.org" `
    -DomainType ChildDomain `
    -InstallDns:$true `
    -CreateDnsDelegation:$true `
    -DnsDelegationCredential $credential `
    -DatabasePath "C:\Windows\NTDS" `
    -LogPath "C:\Windows\NTDS" `
    -SysvolPath "C:\Windows\SYSVOL" `
    -Credential $credential `
    -SafeModeAdministratorPassword (ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force) `
    -Force

# Le serveur redémarre automatiquement
```

### 3.2 Vérifier la promotion (après redémarrage)

```powershell
# Vérifier le domaine
Get-ADDomain

# Vérifier que c'est un Global Catalog
Get-ADDomainController -Identity "REMDCSRV" | Select-Object Name, IsGlobalCatalog

# Si pas Global Catalog, l'activer
Set-ADDomainController -Identity "REMDCSRV" -IsGlobalCatalog $true
```

### 3.3 Mettre à jour le DNS client local

```powershell
# Après promotion, pointer vers soi-même en premier, puis DCWSL
Set-DnsClientServerAddress -InterfaceAlias "Ethernet0" `
    -ServerAddresses 127.0.0.1, 10.4.10.4
```

---

## 4️⃣ Configuration DNS

### 4.1 Configurer le Forwarder

> **Sujet** : "All others DNS requests are forwarded to wsl2025.org"

```powershell
# Supprimer les forwarders existants
Get-DnsServerForwarder | Remove-DnsServerForwarder -Force

# Ajouter le forwarder vers DCWSL (wsl2025.org)
Add-DnsServerForwarder -IPAddress 10.4.10.4

# Vérifier
Get-DnsServerForwarder
```

### 4.2 Vérifier les zones DNS

```powershell
# La zone rem.wsl2025.org est créée automatiquement avec AD DS
Get-DnsServerZone

# Vérifier les enregistrements
Get-DnsServerResourceRecord -ZoneName "rem.wsl2025.org"
```

### 4.3 Configurer DNSSEC avec certificat PKI

> **Sujet** : "DNSSec should be configured on this server with a certificate issued by HQDCSRV"

#### Étape 1 : Vérifier les certificats CA dans le magasin

```powershell
# Vérifier que les certificats Root CA et Sub CA sont présents
Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.Subject -like "*WSFR*" }
Get-ChildItem Cert:\LocalMachine\CA | Where-Object { $_.Subject -like "*WSFR*" }
```

Si les certificats ne sont pas présents, les importer depuis HQDCSRV :

```powershell
# Copier les certificats depuis un partage ou les exporter depuis HQDCSRV
# Import Root CA
Import-Certificate -FilePath "\\hqdcsrv.hq.wsl2025.org\CertEnroll\WSFR-ROOT-CA.crt" -CertStoreLocation Cert:\LocalMachine\Root

# Import Sub CA
Import-Certificate -FilePath "\\hqdcsrv.hq.wsl2025.org\CertEnroll\WSFR-SUB-CA.crt" -CertStoreLocation Cert:\LocalMachine\CA
```

#### Étape 2 : Demander un certificat DNSSEC depuis la PKI

```powershell
# Demander un certificat pour la signature DNSSEC
# Le template "DnsServerDnsSecZoneSigningKey" doit exister sur HQDCSRV
$template = "DnsServerDnsSecZoneSigningKey"
$enrollment = Get-Certificate -Template $template -CertStoreLocation Cert:\LocalMachine\My -DnsName "remdcsrv.rem.wsl2025.org"
$cert = $enrollment.Certificate
Write-Host "Certificat obtenu: $($cert.Thumbprint)"
```

> ⚠️ **Si le template n'existe pas** : Il faut d'abord créer un template DNSSEC sur HQDCSRV (voir documentation HQDCSRV section PKI).

#### Étape 3 : Signer la zone avec l'assistant graphique (recommandé)

L'assistant graphique permet de sélectionner le certificat PKI :

1. Ouvrir **DNS Manager** (`dnsmgmt.msc`)
2. Clic droit sur la zone `rem.wsl2025.org` → **DNSSEC** → **Sign the Zone...**
3. Choisir **"Customize zone signing parameters"**
4. **Key Signing Key (KSK)** :
   - Cliquer sur **Add**
   - Sélectionner **"Use an existing key"** ou générer une nouvelle clé
   - Cocher **"Enable automatic rollover"**
   - Pour utiliser le certificat PKI : sélectionner le certificat dans la liste
5. **Zone Signing Key (ZSK)** :
   - Configurer de la même manière
6. **Next Step Protocol (NSEC3)** : Garder les paramètres par défaut
7. **Trust Anchors** : Cocher "Enable the distribution of trust anchors"
8. Terminer l'assistant

#### Étape 4 : Signer via PowerShell (alternative)

```powershell
# Créer les paramètres KSK avec le certificat
$kskParams = New-DnsServerSigningKey -ZoneName "rem.wsl2025.org" `
    -KeyType KeySigningKey `
    -CryptoAlgorithm RsaSha256 `
    -KeyLength 2048 `
    -StoreKeysInAD $true `
    -KeyStorageProvider "Microsoft Software Key Storage Provider"

# Créer les paramètres ZSK
$zskParams = New-DnsServerSigningKey -ZoneName "rem.wsl2025.org" `
    -KeyType ZoneSigningKey `
    -CryptoAlgorithm RsaSha256 `
    -KeyLength 1024 `
    -StoreKeysInAD $true `
    -KeyStorageProvider "Microsoft Software Key Storage Provider"

# Signer la zone
Invoke-DnsServerZoneSign -ZoneName "rem.wsl2025.org" -Force
```

#### Étape 5 : Vérifier la signature DNSSEC

```powershell
# Vérifier que DNSSEC est activé
Get-DnsServerDnsSecZoneSetting -ZoneName "rem.wsl2025.org"

# Vérifier les clés
Get-DnsServerSigningKey -ZoneName "rem.wsl2025.org"

# Tester la résolution avec DNSSEC
Resolve-DnsName remdcsrv.rem.wsl2025.org -DnssecOk
```

> ✅ **Validation** : La commande `Get-DnsServerDnsSecZoneSetting` doit montrer `IsSigned: True`

---

## 5️⃣ Configuration DHCP

### 5.1 Autoriser le serveur DHCP dans AD

```powershell
Add-DhcpServerInDC -DnsName "remdcsrv.rem.wsl2025.org" -IPAddress 10.4.100.1

# Supprimer le warning de configuration
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\ServerManager\Roles\12" -Name "ConfigurationState" -Value 2
```

### 5.2 Créer le scope DHCP

> **Sujet** :
>
> - Subnet : 10.4.100.0
> - Gateway : à définir (10.4.100.126 = REMFW)
> - Name server : remdcsrv.rem.wsl2025.org
> - Domain : rem.wsl2025.org
> - NTP server : hqinfrasrv.hq.wsl2025.org (10.4.10.2)
> - Lease : 2 heures

```powershell
# Créer le scope pour les clients Remote
# Réseau 10.4.100.0/25 = 10.4.100.0 - 10.4.100.127
# Serveurs : .1 à .9 | Clients DHCP : .10 à .120 | Gateway : .126

Add-DhcpServerv4Scope -Name "Remote-Clients" `
    -StartRange 10.4.100.10 `
    -EndRange 10.4.100.120 `
    -SubnetMask 255.255.255.128 `
    -LeaseDuration 02:00:00 `
    -State Active

# Exclure les adresses réservées (serveurs)
Add-DhcpServerv4ExclusionRange -ScopeId 10.4.100.0 -StartRange 10.4.100.1 -EndRange 10.4.100.9
```

### 5.3 Configurer les options DHCP

```powershell
# Option 003 - Gateway/Router
Set-DhcpServerv4OptionValue -ScopeId 10.4.100.0 -OptionId 3 -Value 10.4.100.126

# Option 006 - DNS Server (remdcsrv.rem.wsl2025.org)
Set-DhcpServerv4OptionValue -ScopeId 10.4.100.0 -OptionId 6 -Value 10.4.100.1

# Option 015 - DNS Domain Name
Set-DhcpServerv4OptionValue -ScopeId 10.4.100.0 -OptionId 15 -Value "rem.wsl2025.org"

# Option 042 - NTP Server (hqinfrasrv.hq.wsl2025.org)
Set-DhcpServerv4OptionValue -ScopeId 10.4.100.0 -OptionId 42 -Value 10.4.10.2
```

### 5.4 Configurer Dynamic DNS

> **Sujet** : "Configure Dynamic DNS to create the associated record corresponding to the distributed IP address"

```powershell
# Activer la mise à jour DNS dynamique
Set-DhcpServerv4DnsSetting -ScopeId 10.4.100.0 `
    -DynamicUpdates Always `
    -DeleteDnsRROnLeaseExpiry $true `
    -UpdateDnsRRForOlderClients $true `
    -NameProtection $true

# Configurer les credentials pour la mise à jour DNS
$dnsCredential = Get-Credential -Message "Credentials pour mise à jour DNS (REM\Administrator)"
Set-DhcpServerDnsCredential -Credential $dnsCredential
```

### 5.5 Vérifier la configuration DHCP

```powershell
Get-DhcpServerv4Scope
Get-DhcpServerv4OptionValue -ScopeId 10.4.100.0
Get-DhcpServerv4DnsSetting -ScopeId 10.4.100.0
```

---

## 6️⃣ Structure Organisationnelle Active Directory

### 6.1 Créer les OUs

> **Sujet** : "The remote site is represented by one OU that contains: Workers, Computers, Groups"

```powershell
# OU principale Remote
New-ADOrganizationalUnit -Name "Remote" -Path "DC=rem,DC=wsl2025,DC=org" -ProtectedFromAccidentalDeletion $true

# Sous-OUs
New-ADOrganizationalUnit -Name "Workers" -Path "OU=Remote,DC=rem,DC=wsl2025,DC=org" -ProtectedFromAccidentalDeletion $true
New-ADOrganizationalUnit -Name "Computers" -Path "OU=Remote,DC=rem,DC=wsl2025,DC=org" -ProtectedFromAccidentalDeletion $true
New-ADOrganizationalUnit -Name "Groups" -Path "OU=Remote,DC=rem,DC=wsl2025,DC=org" -ProtectedFromAccidentalDeletion $true
```

### 6.2 Créer les groupes

```powershell
# Groupes de département (Global Security Groups)
New-ADGroup -Name "IT" -GroupScope Global -GroupCategory Security `
    -Path "OU=Groups,OU=Remote,DC=rem,DC=wsl2025,DC=org" `
    -Description "Groupe IT Remote"

New-ADGroup -Name "Direction" -GroupScope Global -GroupCategory Security `
    -Path "OU=Groups,OU=Remote,DC=rem,DC=wsl2025,DC=org" `
    -Description "Groupe Direction Remote"

New-ADGroup -Name "Warehouse" -GroupScope Global -GroupCategory Security `
    -Path "OU=Groups,OU=Remote,DC=rem,DC=wsl2025,DC=org" `
    -Description "Groupe Warehouse Remote"
```

### 6.3 Créer les utilisateurs Remote

> **Sujet** : Utilisateurs du site REM selon l'Appendix

```powershell
# Définition des utilisateurs Remote
$usersRemote = @(
    @{
        FirstName = "Ela"
        LastName = "STIQUE"
        Login = "estique"
        Department = "Warehouse"
        Email = "estique@wsl2025.org"
    },
    @{
        FirstName = "Rachid"
        LastName = "TAHA"
        Login = "rtaha"
        Department = "Direction"
        Email = "rtaha@wsl2025.org"
    },
    @{
        FirstName = "Denis"
        LastName = "PELTIER"
        Login = "dpeltier"
        Department = "IT"
        Email = "dpeltier@wsl2025.org"
    }
)

# Création des utilisateurs
foreach ($user in $usersRemote) {
    New-ADUser `
        -Name "$($user.FirstName) $($user.LastName)" `
        -GivenName $user.FirstName `
        -Surname $user.LastName `
        -SamAccountName $user.Login `
        -UserPrincipalName "$($user.Login)@rem.wsl2025.org" `
        -EmailAddress $user.Email `
        -Department $user.Department `
        -Path "OU=Workers,OU=Remote,DC=rem,DC=wsl2025,DC=org" `
        -AccountPassword (ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force) `
        -ChangePasswordAtLogon $false `
        -PasswordNeverExpires $true `
        -Enabled $true

    # Ajouter au groupe correspondant
    Add-ADGroupMember -Identity $user.Department -Members $user.Login

    Write-Host "Utilisateur $($user.Login) créé et ajouté au groupe $($user.Department)" -ForegroundColor Green
}
```

### 6.4 Vérifier les utilisateurs et groupes

```powershell
# Lister les utilisateurs
Get-ADUser -Filter * -SearchBase "OU=Workers,OU=Remote,DC=rem,DC=wsl2025,DC=org" | Select-Object Name, SamAccountName

# Lister les groupes et leurs membres
Get-ADGroup -Filter * -SearchBase "OU=Groups,OU=Remote,DC=rem,DC=wsl2025,DC=org" | ForEach-Object {
    Write-Host "`nGroupe: $($_.Name)" -ForegroundColor Cyan
    Get-ADGroupMember -Identity $_ | Select-Object Name
}
```

---

## 7️⃣ Configuration DFS

### 7.1 Créer les répertoires de partage

```powershell
# Créer la structure de dossiers
New-Item -Path "C:\shares" -ItemType Directory -Force
New-Item -Path "C:\shares\datausers" -ItemType Directory -Force
New-Item -Path "C:\shares\Department" -ItemType Directory -Force

# Créer les dossiers département
foreach ($dept in @("IT", "Direction", "Warehouse")) {
    New-Item -Path "C:\shares\Department\$dept" -ItemType Directory -Force
}
```

### 7.2 Créer les dossiers personnels utilisateurs

```powershell
foreach ($user in $usersRemote) {
    $userPath = "C:\shares\datausers\$($user.Login)"
    New-Item -Path $userPath -ItemType Directory -Force
}
```

### 7.3 Configurer les permissions NTFS - Home Drives

> **Sujet** :
>
> - "Administrators must have Full control access on all folders"
> - "Users can only access their personal folder"
> - "Users can only see their personal folder"

```powershell
# Permissions sur le dossier parent datausers
$aclParent = Get-Acl "C:\shares\datausers"
$aclParent.SetAccessRuleProtection($true, $false)  # Désactiver héritage

# Administrators = Full Control
$adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
$aclParent.AddAccessRule($adminRule)

# SYSTEM = Full Control
$systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "SYSTEM", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
$aclParent.AddAccessRule($systemRule)

# Authenticated Users = List folder (pour accéder à leur sous-dossier)
$authUsersRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "Authenticated Users", "ReadAndExecute", "None", "None", "Allow")
$aclParent.AddAccessRule($authUsersRule)

Set-Acl "C:\shares\datausers" $aclParent

# Permissions sur chaque dossier utilisateur
foreach ($user in $usersRemote) {
    $userPath = "C:\shares\datausers\$($user.Login)"
    $acl = Get-Acl $userPath
    $acl.SetAccessRuleProtection($true, $false)  # Désactiver héritage

    # Administrators = Full Control
    $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.AddAccessRule($adminRule)

    # SYSTEM = Full Control
    $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "SYSTEM", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.AddAccessRule($systemRule)

    # Utilisateur = Modify sur son dossier uniquement
    $userRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "REM\$($user.Login)", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.AddAccessRule($userRule)

    Set-Acl $userPath $acl
    Write-Host "Permissions configurées pour $($user.Login)" -ForegroundColor Green
}
```

### 7.4 Configurer les permissions NTFS - Department

> **Sujet** :
>
> - "Users can only access their department folder"
> - "Users can only see their department folder"

```powershell
# Permissions sur le dossier parent Department
$aclDept = Get-Acl "C:\shares\Department"
$aclDept.SetAccessRuleProtection($true, $false)

$adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
$aclDept.AddAccessRule($adminRule)

$systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "SYSTEM", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
$aclDept.AddAccessRule($systemRule)

$authUsersRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "Authenticated Users", "ReadAndExecute", "None", "None", "Allow")
$aclDept.AddAccessRule($authUsersRule)

Set-Acl "C:\shares\Department" $aclDept

# Permissions sur chaque dossier département
foreach ($dept in @("IT", "Direction", "Warehouse")) {
    $deptPath = "C:\shares\Department\$dept"
    $acl = Get-Acl $deptPath
    $acl.SetAccessRuleProtection($true, $false)

    # Administrators = Full Control
    $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.AddAccessRule($adminRule)

    # SYSTEM = Full Control
    $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "SYSTEM", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.AddAccessRule($systemRule)

    # Groupe département = Modify
    $groupRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "REM\$dept", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.AddAccessRule($groupRule)

    Set-Acl $deptPath $acl
    Write-Host "Permissions configurées pour département $dept" -ForegroundColor Green
}
```

### 7.5 Créer les partages SMB avec ABE

> **Sujet** : "Users can only see their personal folder" → Access-Based Enumeration

```powershell
# Partage users (Home drives)
# Share path: \\rem.wsl2025.org\users
New-SmbShare -Name "users" `
    -Path "C:\shares\datausers" `
    -FullAccess "Administrators" `
    -ChangeAccess "Authenticated Users" `
    -FolderEnumerationMode AccessBased `
    -Description "Home drives utilisateurs Remote"

# Partage Department
New-SmbShare -Name "Department" `
    -Path "C:\shares\Department" `
    -FullAccess "Administrators" `
    -ChangeAccess "Authenticated Users" `
    -FolderEnumerationMode AccessBased `
    -Description "Dossiers départements Remote"
```

### 7.6 Configurer les quotas (20 Mo)

> **Sujet** : "Limit the storage quota to 20Mb"

```powershell
# Créer le template de quota
New-FsrmQuotaTemplate -Name "UserQuota20MB" `
    -Size 20MB `
    -Description "Quota 20 Mo pour les utilisateurs" `
    -SoftLimit

# Appliquer le quota automatique sur datausers
New-FsrmAutoQuota -Path "C:\shares\datausers" -Template "UserQuota20MB"

# Vérifier
Get-FsrmAutoQuota -Path "C:\shares\datausers"
```

### 7.7 Créer la racine DFS Domaine

> **Sujet** : "Create a DFS Domain root with REMINFRASRV"

```powershell
# Créer le dossier racine DFS
New-Item -Path "C:\DFSRoots\files" -ItemType Directory -Force

# Partager le dossier racine
New-SmbShare -Name "files" -Path "C:\DFSRoots\files" -FullAccess "Everyone"

# Créer le namespace DFS (Domain-based)
New-DfsnRoot -TargetPath "\\REMDCSRV.rem.wsl2025.org\files" `
    -Type DomainV2 `
    -Path "\\rem.wsl2025.org\files"

# Ajouter les dossiers au namespace
New-DfsnFolder -Path "\\rem.wsl2025.org\files\users" `
    -TargetPath "\\REMDCSRV.rem.wsl2025.org\users"

New-DfsnFolder -Path "\\rem.wsl2025.org\files\Department" `
    -TargetPath "\\REMDCSRV.rem.wsl2025.org\Department"
```

### 7.8 Vérifier DFS

```powershell
Get-DfsnRoot -Path "\\rem.wsl2025.org\files"
Get-DfsnFolder -Path "\\rem.wsl2025.org\files\*"
```

---

## 8️⃣ Configuration des GPO

### 8.1 GPO - IT sont administrateurs locaux

> **Sujet** : "Members of IT group are local administrators"

```powershell
# Créer la GPO
$gpoITAdmin = New-GPO -Name "REM-IT-LocalAdmins"

# Lier à l'OU Remote
New-GPLink -Guid $gpoITAdmin.Id -Target "OU=Remote,DC=rem,DC=wsl2025,DC=org"

Write-Host @"
=== Configuration manuelle requise ===
1. Ouvrir GPMC (gpmc.msc)
2. Éditer la GPO 'REM-IT-LocalAdmins'
3. Aller à : Computer Configuration > Policies > Windows Settings > Security Settings > Restricted Groups
4. Clic droit > Add Group
5. Ajouter le groupe 'Administrators'
6. Dans 'Members of this group', ajouter 'REM\IT'
"@ -ForegroundColor Yellow
```

**Configuration manuelle GPMC :**

1. `gpmc.msc` → Éditer `REM-IT-LocalAdmins`
2. `Computer Configuration` → `Policies` → `Windows Settings` → `Security Settings` → `Restricted Groups`
3. Clic droit → `Add Group` → `Administrators`
4. `Members of this group` → Ajouter `REM\IT`

### 8.2 GPO - Bloquer le Panneau de configuration (sauf IT)

> **Sujet** : "Control Panel is blocked for everyone except for IT group members"

```powershell
# Créer la GPO
$gpoBlockCP = New-GPO -Name "REM-Block-ControlPanel"

# Lier à l'OU Workers (où sont les utilisateurs)
New-GPLink -Guid $gpoBlockCP.Id -Target "OU=Workers,OU=Remote,DC=rem,DC=wsl2025,DC=org"

# Configurer via registre (alternative PowerShell)
Set-GPRegistryValue -Guid $gpoBlockCP.Id `
    -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" `
    -ValueName "NoControlPanel" `
    -Type DWord `
    -Value 1

# Retirer le groupe IT du filtrage de sécurité
Set-GPPermission -Guid $gpoBlockCP.Id -TargetName "IT" -TargetType Group -PermissionLevel GpoApply -Replace
Set-GPPermission -Guid $gpoBlockCP.Id -TargetName "IT" -TargetType Group -PermissionLevel None

Write-Host "GPO Block Control Panel créée - Le groupe IT est exclu" -ForegroundColor Green
```

**Configuration manuelle alternative :**

1. `gpmc.msc` → Éditer `REM-Block-ControlPanel`
2. `User Configuration` → `Administrative Templates` → `Control Panel`
3. Activer `Prohibit access to Control Panel and PC settings`
4. Dans l'onglet `Delegation` → Retirer `Apply` pour le groupe `REM\IT`

### 8.3 GPO - Mappages lecteurs réseau

> **Sujet** : "Mapping shares Department" + "Home drives mounted with letter U: and S:"

```powershell
# Créer la GPO
$gpoDriveMap = New-GPO -Name "REM-DriveMappings"

# Lier à l'OU Remote
New-GPLink -Guid $gpoDriveMap.Id -Target "OU=Remote,DC=rem,DC=wsl2025,DC=org"

Write-Host @"
=== Configuration manuelle requise ===
1. Ouvrir GPMC (gpmc.msc)
2. Éditer la GPO 'REM-DriveMappings'
3. User Configuration > Preferences > Windows Settings > Drive Maps

LECTEUR U: (Home Drive)
- Action: Update
- Location: \\rem.wsl2025.org\users\%USERNAME%
- Letter: U
- Reconnect: Oui
- Label: Home

LECTEUR S: (Department)
- Action: Update
- Location: \\rem.wsl2025.org\files\Department
- Letter: S
- Reconnect: Oui
- Label: Department
- Item-level targeting: Groupe spécifique pour chaque département
"@ -ForegroundColor Yellow
```

### 8.4 GPO - Déployer les certificats CA

> **Sujet** : "Configure Root CA certificate on the Root CA magazine and the Sub CA on the Sub CA magazine"

```powershell
# Créer la GPO
$gpoCerts = New-GPO -Name "REM-Deploy-Certificates"

# Lier à l'OU Remote
New-GPLink -Guid $gpoCerts.Id -Target "OU=Remote,DC=rem,DC=wsl2025,DC=org"

Write-Host @"
=== Configuration manuelle requise ===
1. Exporter les certificats depuis DNSSRV (Root CA) et HQDCSRV (Sub CA)
   - WSFR-ROOT-CA.cer
   - WSFR-SUB-CA.cer

2. Ouvrir GPMC (gpmc.msc)
3. Éditer la GPO 'REM-Deploy-Certificates'
4. Computer Configuration > Policies > Windows Settings > Security Settings > Public Key Policies

5. Trusted Root Certification Authorities
   - Clic droit > Import > WSFR-ROOT-CA.cer

6. Intermediate Certification Authorities
   - Clic droit > Import > WSFR-SUB-CA.cer
"@ -ForegroundColor Yellow
```

### 8.5 Forcer la mise à jour des GPO

```powershell
# Sur le serveur
gpupdate /force

# Pour forcer sur tous les clients du domaine (optionnel)
Invoke-GPUpdate -Computer "REMCLT" -Force
```

---

## 9️⃣ Configuration NTP

### 9.1 Configurer le client NTP

> **Sujet** : "Use HQINFRASRV as time reference"

```powershell
# Configurer la source NTP (HQINFRASRV)
w32tm /config /manualpeerlist:"10.4.10.2" /syncfromflags:manual /reliable:no /update

# Redémarrer le service
Restart-Service w32time

# Forcer la synchronisation
w32tm /resync /force

# Vérifier
w32tm /query /status
w32tm /query /source
```

---

## 🔟 Vérifications finales

### 10.1 Tests Active Directory

```powershell
# Domaine
Get-ADDomain
Get-ADForest

# Global Catalog
Get-ADDomainController -Identity "REMDCSRV" | Select-Object Name, IsGlobalCatalog, IPv4Address

# Trust avec le parent
Get-ADTrust -Filter *

# Réplication
repadmin /replsummary
repadmin /showrepl
```

### 10.2 Tests DNS

```powershell
# Zone locale
Get-DnsServerZone
Resolve-DnsName remdcsrv.rem.wsl2025.org

# Résolution vers parent
Resolve-DnsName dcwsl.wsl2025.org
Resolve-DnsName hqdcsrv.hq.wsl2025.org

# DNSSEC
Get-DnsServerDnsSecZoneSetting -ZoneName "rem.wsl2025.org"
```

### 10.3 Tests DHCP

```powershell
# Scopes
Get-DhcpServerv4Scope

# Options
Get-DhcpServerv4OptionValue -ScopeId 10.4.100.0

# Dynamic DNS
Get-DhcpServerv4DnsSetting -ScopeId 10.4.100.0

# Autorisation AD
Get-DhcpServerInDC
```

### 10.4 Tests DFS

```powershell
# Namespace
Get-DfsnRoot -Path "\\rem.wsl2025.org\files"
Get-DfsnFolder -Path "\\rem.wsl2025.org\files\*"

# Accès
Test-Path "\\rem.wsl2025.org\users"
Test-Path "\\rem.wsl2025.org\files\Department"
```

### 10.5 Tests Partages

```powershell
# Lister les partages
Get-SmbShare

# Vérifier ABE
Get-SmbShare -Name "users" | Select-Object Name, FolderEnumerationMode
Get-SmbShare -Name "Department" | Select-Object Name, FolderEnumerationMode

# Quotas
Get-FsrmAutoQuota
```

### 10.6 Tests GPO

```powershell
# Lister les GPO
Get-GPO -All | Select-Object DisplayName, GpoStatus

# Vérifier les liens
Get-GPInheritance -Target "OU=Remote,DC=rem,DC=wsl2025,DC=org"

# Rapport GPO
Get-GPOReport -All -ReportType HTML -Path "C:\GPOReport.html"
```

---

## 📋 Checklist de validation

| Composant | Test                         | Commande                                           |
| --------- | ---------------------------- | -------------------------------------------------- |
| AD DS     | Child domain rem.wsl2025.org | `Get-ADDomain`                                     |
| AD DS     | Global Catalog activé        | `Get-ADDomainController -Identity REMDCSRV`        |
| AD DS     | Trust avec wsl2025.org       | `Get-ADTrust -Filter *`                            |
| DNS       | Zone rem.wsl2025.org         | `Get-DnsServerZone`                                |
| DNS       | Forwarder vers DCWSL         | `Get-DnsServerForwarder`                           |
| DNS       | DNSSEC activé                | `Get-DnsServerDnsSecZoneSetting`                   |
| DHCP      | Scope actif                  | `Get-DhcpServerv4Scope`                            |
| DHCP      | Options configurées          | `Get-DhcpServerv4OptionValue -ScopeId 10.4.100.0`  |
| DHCP      | Dynamic DNS                  | `Get-DhcpServerv4DnsSetting`                       |
| OUs       | Structure créée              | `Get-ADOrganizationalUnit -Filter *`               |
| Users     | 3 utilisateurs Remote        | `Get-ADUser -Filter * -SearchBase "OU=Workers..."` |
| Groups    | IT, Direction, Warehouse     | `Get-ADGroup -Filter * -SearchBase "OU=Groups..."` |
| DFS       | Namespace créé               | `Get-DfsnRoot`                                     |
| Shares    | ABE activé                   | `Get-SmbShare -Name users`                         |
| Quotas    | 20 Mo configuré              | `Get-FsrmAutoQuota`                                |
| GPO       | 4 GPO créées                 | `Get-GPO -All`                                     |
| NTP       | Sync avec HQINFRASRV         | `w32tm /query /source`                             |

---

## 📝 Notes importantes

1. **Ordre d'exécution** : Suivre les sections dans l'ordre (1 à 10)
2. **Redémarrage** : Le serveur redémarre après la promotion AD
3. **Credentials** : Utiliser les credentials de `WSL2025\Administrator` pour joindre le domaine
4. **DFS Replication** : Sera configuré après l'installation de REMINFRASRV
5. **Certificats** : Exporter depuis DNSSRV (Root CA) et HQDCSRV (Sub CA) avant de configurer la GPO
6. **GPO manuelles** : Certaines GPO nécessitent une configuration via GPMC (interface graphique)

---

## 🔗 Dépendances

| Machine     | Requis pour                          |
| ----------- | ------------------------------------ |
| DCWSL       | Joindre le domaine wsl2025.org       |
| HQDCSRV     | Certificats PKI, DNSSEC              |
| HQINFRASRV  | Source NTP                           |
| REMFW       | Connectivité réseau                  |
| REMINFRASRV | DFS Replication (à configurer après) |

---

## 🔧 Dépannage

### Problème : La promotion AD échoue avec "Impossible de se connecter au domaine"

**Symptômes :**

- Erreur : _"Échec de la vérification des autorisations des informations d'identification de l'utilisateur"_
- Erreur : _"Vous devez fournir un nom du domaine résolvable DNS"_
- `nslookup wsl2025.org` timeout puis répond

**Cause :** L'ACL `FIREWALL-INBOUND` sur REMFW bloque les **réponses UDP** (paquets avec port source 53, 88, 389, etc.)

**Solution :** Reconfigurer l'ACL sur REMFW pour autoriser les réponses UDP :

```cisco
enable
conf t

! Supprimer l'ancienne ACL
no ip access-list extended FIREWALL-INBOUND

! Recréer avec les règles de réponse UDP
ip access-list extended FIREWALL-INBOUND
 remark === Allow established connections ===
 permit tcp any any established
 remark === Allow SSH from HQ ===
 permit tcp 10.4.0.0 0.0.255.255 any eq 22
 remark === Allow DNS (requests and responses) ===
 permit udp any any eq domain
 permit udp any eq domain any
 permit tcp any any eq domain
 remark === Allow HTTPS ===
 permit tcp any any eq 443
 remark === Allow HTTP ===
 permit tcp any any eq 80
 remark === Allow ICMP ===
 permit icmp any any
 remark === Allow Microsoft Services (requests and responses) ===
 permit tcp any any eq 445
 permit udp any any eq 445
 permit udp any eq 445 any
 permit tcp any any range 135 139
 permit udp any any range 135 139
 permit udp any range 135 139 any
 remark === Allow Kerberos (requests and responses) ===
 permit tcp any any eq 88
 permit udp any any eq 88
 permit udp any eq 88 any
 remark === Allow LDAP (requests and responses) ===
 permit tcp any any eq 389
 permit udp any any eq 389
 permit udp any eq 389 any
 permit tcp any any eq 636
 remark === Allow NTP (requests and responses) ===
 permit udp any any eq ntp
 permit udp any eq ntp any
 remark === Allow OSPF ===
 permit ospf any any
 remark === Deny all other ===
 deny ip any any log

end
write memory
```

> ⚠️ **IMPORTANT - Ordre des règles ACL Cisco** : Les règles `permit` doivent être **AVANT** le `deny ip any any`. Les ACL Cisco sont traitées séquentiellement, donc toute règle après le `deny` est ignorée !

**Vérification :**

```cisco
show access-list FIREWALL-INBOUND
```

Le `deny ip any any log` doit être la **dernière** règle de la liste.

---

### Problème : DNS timeout mais finit par répondre

**Symptômes :**

- `nslookup wsl2025.org` affiche "DNS request timed out" puis répond après plusieurs secondes

**Cause :** Les premiers paquets UDP sont bloqués, mais les retries passent (comportement instable)

**Solution :** Vérifier que les règles `permit udp any eq domain any` (réponses DNS) sont bien présentes et **avant** le `deny`.

---

### Problème : Credentials refusés lors de la promotion

**Symptômes :**

- Erreur d'authentification même avec le bon mot de passe

**Solution :**

1. Utiliser le **FQDN complet** : `WSL2025.ORG\Administrateur` (pas `WSL2025\Administrateur`)
2. Ou utiliser le format UPN : `administrateur@wsl2025.org`

---

### Commandes de diagnostic utiles

```powershell
# Test résolution DNS
Resolve-DnsName wsl2025.org
Resolve-DnsName dcwsl.wsl2025.org
Resolve-DnsName _ldap._tcp.dc._msdcs.wsl2025.org -Type SRV

# Vider le cache DNS
Clear-DnsClientCache

# Test connectivité réseau
Test-Connection 10.4.10.4
Test-NetConnection 10.4.10.4 -Port 389

# Vérifier la config DNS client
Get-DnsClientServerAddress

# Test authentification AD
$cred = Get-Credential
Get-ADDomain -Server "wsl2025.org" -Credential $cred
```

```cisco
! Sur REMFW - Voir les paquets bloqués
show access-list FIREWALL-INBOUND

! Voir les logs en temps réel
terminal monitor
```
