# HQDCSRV - Contrôleur de Domaine HQ

> **OS** : Windows Server 2022  
> **IP** : 10.4.10.1/24 (VLAN 10 - Servers)  
> **Gateway** : 10.4.10.254 (VIP HSRP)  
> **Rôles** : AD DS, DNS, ADCS (Sub CA), File Server, FSRM, IIS, GPO

---

## 📋 Prérequis

- [ ] Windows Server 2022 installé
- [ ] 3 disques supplémentaires de 1 Go (pour RAID-5)
- [ ] **Carte réseau "Portail Captif" désactivée** (si présente)

> ⚠️ **IMPORTANT - Carte Portail Captif** : Si une carte réseau "Portail Captif" est activée sur le serveur, **la désactiver** avant de commencer la configuration. Cette carte peut causer des problèmes de routage et bloquer les communications (NTP, DNS, AD, etc.).
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
# Gateway = VIP HSRP des Core Switches (CORESW1/CORESW2)
New-NetIPAddress -InterfaceAlias "Ethernet0" -IPAddress 10.4.10.1 -PrefixLength 24 -DefaultGateway 10.4.10.254
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
# IMPORTANT : Utiliser le FQDN du domaine + nom français "Administrateur"
$cred = Get-Credential -UserName "WSL2025.ORG\Administrateur" -Message "Mot de passe du domaine wsl2025.org"

# Vérifier que les credentials fonctionnent (optionnel)
Get-ADDomain -Server 10.4.10.4 -Credential $cred

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

> ⚠️ **Note** : Sur Windows Server en français, le compte admin s'appelle "**Administrateur**" (pas "Administrator"). Utiliser le format `WSL2025.ORG\Administrateur`.

> ⚠️ Le serveur redémarre automatiquement après l'installation.

### 2.3 ✅ Vérification AD

```powershell
# Vérifier le domaine
Get-ADDomain

# Vérifier la forêt
Get-ADForest

# Vérifier le trust avec le parent
Get-ADTrust -Filter *

# Résultat attendu :
# Name           : hq.wsl2025.org
# Forest         : wsl2025.org
# ParentDomain   : wsl2025.org
```

---

## 3️⃣ Configuration DNS

### 3.1 Vérifier la zone DNS hq.wsl2025.org

```powershell
# La zone est créée automatiquement lors de la promotion AD
Get-DnsServerZone

# Résultat attendu : zone "hq.wsl2025.org" de type Primary, DsIntegrated = True
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

### 3.5 ✅ Vérification DNS

```powershell
# Vérifier les enregistrements créés
Get-DnsServerResourceRecord -ZoneName "hq.wsl2025.org" | Format-Table RecordType, HostName, RecordData

# Tester la résolution
Resolve-DnsName hqdcsrv.hq.wsl2025.org
Resolve-DnsName pki.hq.wsl2025.org

# Tester le forwarder (résolution externe)
Resolve-DnsName google.com
```

### 3.4 Activer DNSSEC

> ⚠️ **Prérequis** : La zone parente `wsl2025.org` sur DCWSL doit être signée en premier.

```powershell
# 1. Vérifier l'état actuel de la zone
Get-DnsServerZone -Name "hq.wsl2025.org" | Select-Object ZoneName, IsSigned, KeyMasterServer

# 2. Définir ce serveur comme Key Master (si nécessaire)
# D'abord récupérer le FQDN du serveur
$serverFQDN = [System.Net.Dns]::GetHostEntry($env:COMPUTERNAME).HostName
Write-Host "FQDN du serveur: $serverFQDN"

# 3. Créer les clés de signature manuellement
Add-DnsServerSigningKey -ZoneName "hq.wsl2025.org" -Type KeySigningKey -CryptoAlgorithm RsaSha256 -KeyLength 2048
Add-DnsServerSigningKey -ZoneName "hq.wsl2025.org" -Type ZoneSigningKey -CryptoAlgorithm RsaSha256 -KeyLength 1024

# 4. Signer la zone
Invoke-DnsServerZoneSign -ZoneName "hq.wsl2025.org" -Force
```

#### 🖥️ Alternative via interface graphique (si erreur PowerShell)

Si les commandes PowerShell échouent avec "Access Denied" :

1. Ouvrir **DNS Manager** (dnsmgmt.msc)
2. Clic droit sur la zone `hq.wsl2025.org`
3. **DNSSEC** → **Sign the Zone...**
4. Suivre l'assistant avec les paramètres par défaut

#### ✅ Vérification DNSSEC

```powershell
# Vérifier que la zone est signée
Get-DnsServerZone -Name "hq.wsl2025.org" | Select-Object ZoneName, IsSigned
# Résultat attendu : IsSigned = True

# Vérifier les clés de signature
Get-DnsServerSigningKey -ZoneName "hq.wsl2025.org"

# Tester la résolution avec DNSSEC
Resolve-DnsName hqdcsrv.hq.wsl2025.org -DnssecOk
```

> ⚠️ **Note** : DNSSEC n'est pas critique pour le fonctionnement de base. Si ça bloque, tu peux continuer et y revenir plus tard.

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

#### ✅ Vérification OUs

```powershell
# Lister toutes les OUs créées
Get-ADOrganizationalUnit -Filter * | Select-Object Name, DistinguishedName | Format-Table -AutoSize
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

#### ✅ Vérification Utilisateurs et Groupes

```powershell
# Compter le nombre total d'utilisateurs
(Get-ADUser -Filter * -SearchBase "DC=hq,DC=wsl2025,DC=org").Count

# Vérifier les 4 utilisateurs HQ
Get-ADUser -Filter * -SearchBase "OU=Users,OU=HQ,DC=hq,DC=wsl2025,DC=org" -SearchScope Subtree |
    Where-Object {$_.SamAccountName -notlike "wslusr*"} |
    Select-Object Name, SamAccountName

# Vérifier les groupes
Get-ADGroup -Filter * -SearchBase "DC=hq,DC=wsl2025,DC=org" | Select-Object Name

# Vérifier le nombre de membres dans FirstGroup et LastGroup
(Get-ADGroupMember -Identity "FirstGroup").Count  # Doit être 500
(Get-ADGroupMember -Identity "LastGroup").Count   # Doit être 500
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

> ⚠️ **IMPORTANT** : Pour configurer une Enterprise CA, vous DEVEZ être connecté avec le compte **`WSL2025\Administrateur`** (Enterprise Admin du domaine racine), pas `HQ\Administrateur` !

### 5.1 Installer ADCS et IIS

```powershell
Install-WindowsFeature -Name ADCS-Cert-Authority, ADCS-Web-Enrollment, Web-Server, Web-Mgmt-Tools -IncludeManagementTools
```

### 5.2 Configurer ADCS via l'assistant graphique (recommandé)

> La configuration via GUI est plus stable que PowerShell pour ADCS.

1. Ouvrir **Server Manager**
2. Cliquer sur le **drapeau jaune ⚠️** en haut à droite
3. Cliquer sur **"Configurer les services de certificats Active Directory"**
4. **Informations d'identification** : Utiliser `WSL2025\Administrateur`
5. **Services de rôle** : Cocher ✅ Autorité de certification + ✅ Inscription via le Web
6. **Type d'installation** : **Autorité de certification d'entreprise** (pas autonome !)
7. **Type d'AC** : **AC secondaire** (Subordinate CA)
8. **Clé privée** : Créer une nouvelle clé privée
9. **Chiffrement** : RSA 2048 + SHA256
10. **Nom de l'AC** : `WSFR-SUB-CA`
11. **Demande de certificat** : **Enregistrer dans un fichier** (génère le `.req`)
12. Terminer l'assistant

Le fichier généré sera : `C:\HQDCSRV.hq.wsl2025.org_WSFR-SUB-CA.req`

### 5.3 Signer le certificat sur DNSSRV (Root CA)

#### Étape 1 : Transférer le .req vers DNSSRV

Depuis **HQDCSRV** (PowerShell) :

```powershell
# Envoyer le fichier .req généré par l'assistant
scp "C:\HQDCSRV.hq.wsl2025.org_WSFR-SUB-CA.req" root@8.8.4.1:/etc/ssl/CA/requests/SubCA.req
```

#### Étape 2 : Sur DNSSRV, modifier la politique OpenSSL (si erreur "countryName missing")

```bash
nano /etc/ssl/CA/openssl.cnf

# Modifier la ligne "policy = policy_strict" en :
# policy = policy_anything

# Ajouter cette section si elle n'existe pas :
# [ policy_anything ]
# countryName             = optional
# stateOrProvinceName     = optional
# localityName            = optional
# organizationName        = optional
# organizationalUnitName  = optional
# commonName              = supplied
# emailAddress            = optional
```

#### Étape 3 : Sur DNSSRV, vérifier les extensions CDP/AIA dans openssl.cnf

> ⚠️ **IMPORTANT** : Le certificat Sub CA doit contenir les URLs de CRL pour que la vérification de révocation fonctionne !

```bash
# Vérifier que la section [v3_intermediate_ca] contient les extensions CDP/AIA
grep -A10 "v3_intermediate_ca" /etc/ssl/CA/openssl.cnf
```

Tu dois voir ces lignes dans `[ v3_intermediate_ca ]` :

```ini
crlDistributionPoints = URI:http://pki.hq.wsl2025.org/WSFR-ROOT-CA.crl
authorityInfoAccess = caIssuers;URI:http://pki.hq.wsl2025.org/WSFR-ROOT-CA.crt
```

Si elles n'y sont pas, les ajouter :

```bash
nano /etc/ssl/CA/openssl.cnf
# Ajouter les 2 lignes dans la section [ v3_intermediate_ca ]
```

#### Étape 4 : Sur DNSSRV, signer le certificat

```bash
cd /etc/ssl/CA

# Signer la demande (mot de passe Root CA requis)
openssl ca -config openssl.cnf \
    -extensions v3_intermediate_ca \
    -days 3650 -notext -md sha256 \
    -in requests/SubCA.req \
    -out certs/SubCA.crt

# Confirmer avec 'y' deux fois

# Vérifier que les extensions CDP/AIA sont présentes dans le certificat signé
openssl x509 -in certs/SubCA.crt -text -noout | grep -A2 "CRL Distribution"
openssl x509 -in certs/SubCA.crt -text -noout | grep -A2 "Authority Information"
```

> ✅ Tu dois voir les URLs `http://pki.hq.wsl2025.org/...` dans la sortie.

#### Étape 5 : Générer la CRL du Root CA

```bash
# Générer la CRL (nécessaire pour la vérification de révocation)
openssl ca -config openssl.cnf -gencrl -out crl/ca.crl
```

#### Étape 6 : Récupérer les certificats et CRL sur HQDCSRV

Depuis **HQDCSRV** (PowerShell) :

```powershell
# Certificat Sub CA signé
scp root@8.8.4.1:/etc/ssl/CA/certs/SubCA.crt C:\SubCA.cer

# Certificat Root CA
scp root@8.8.4.1:/etc/ssl/CA/certs/ca.crt C:\WSFR-ROOT-CA.cer

# CRL du Root CA (OBLIGATOIRE pour la vérification de révocation)
scp root@8.8.4.1:/etc/ssl/CA/crl/ca.crl C:\inetpub\PKI\WSFR-ROOT-CA.crl
```

> ⚠️ La CRL du Root CA doit être accessible sur `http://pki.hq.wsl2025.org/WSFR-ROOT-CA.crl` sinon les clients auront l'erreur `CRYPT_E_NO_REVOCATION_CHECK`.

### 5.4 Installer les certificats

> ⚠️ Toujours utiliser le compte **`WSL2025\Administrateur`** !

```powershell
# 1. Installer le certificat Root CA dans le magasin racine
Import-Certificate -FilePath "C:\WSFR-ROOT-CA.cer" -CertStoreLocation Cert:\LocalMachine\Root
```

#### Installation via GUI (recommandé)

1. Ouvrir **certsrv.msc** (Autorité de certification)
2. Il va demander si on veut installer le certificat → Cliquer **Oui**
3. Sélectionner le fichier `C:\SubCA.cer`
4. Le service devrait démarrer automatiquement

#### Ou via PowerShell

```powershell
certutil -installcert C:\SubCA.cer
Start-Service certsvc
```

#### ✅ Vérification

```powershell
# Vérifier que le service est démarré
Get-Service certsvc

# Vérifier que la CA répond
certutil -ping

# Vérifier le certificat installé
certutil -ca.cert

# IMPORTANT : Vérifier que les extensions CDP/AIA sont présentes
certutil -ca.cert | Select-String "pki.hq.wsl2025.org"
```

> ✅ Tu dois voir les URLs `http://pki.hq.wsl2025.org/WSFR-ROOT-CA.crl` et `.crt` dans la sortie.
> Si rien ne s'affiche, le certificat Sub CA n'a pas les bonnes extensions → refaire la signature sur DNSSRV.

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

# Configurer les permissions NTFS (IIS_IUSRS + IUSR pour l'accès anonyme)
$acl = Get-Acl "C:\inetpub\PKI"
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule("IIS_IUSRS", "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")
$acl.AddAccessRule($rule)
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule("IUSR", "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")
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

# Activer le Directory Browsing (IMPORTANT pour lister les fichiers CRL)
Set-WebConfigurationProperty -PSPath "IIS:\Sites\PKI" -Filter "system.webServer/directoryBrowse" -Name "enabled" -Value $true

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

### 5.8 Vérifier l'accès aux CRL

```powershell
# Vérifier que les fichiers sont présents
Get-ChildItem C:\inetpub\PKI

# Tester l'accès HTTP (depuis HQDCSRV ou HQCLT)
Invoke-WebRequest -Uri "http://pki.hq.wsl2025.org/WSFR-ROOT-CA.crl" -UseBasicParsing
Invoke-WebRequest -Uri "http://pki.hq.wsl2025.org/WSFR-SUB-CA.crl" -UseBasicParsing
```

> ✅ Les deux requêtes doivent retourner un StatusCode 200.

#### Troubleshooting : Erreur CRYPT_E_NO_REVOCATION_CHECK

Si les clients ont cette erreur lors de l'émission de certificats :

1. **Vérifier que la CRL du Root CA est dans `C:\inetpub\PKI\WSFR-ROOT-CA.crl`**
2. **Vérifier que le certificat Sub CA contient les extensions CDP/AIA** :
   ```powershell
   certutil -ca.cert | Select-String "pki.hq.wsl2025.org"
   ```
3. **Si les extensions sont absentes** → Refaire la signature sur DNSSRV (voir section 5.3)

#### ✅ Vérification ADCS

```powershell
# Vérifier que la CA est fonctionnelle
certutil -ping

# Vérifier la configuration de la CA
certutil -getreg CA\CRLPeriod
certutil -getreg CA\CRLDeltaPeriod

# Vérifier le site IIS PKI
Get-IISSite -Name "PKI"

# Tester l'accès HTTP (depuis un autre poste)
# Invoke-WebRequest -Uri "http://pki.hq.wsl2025.org" -UseBasicParsing
```

### 5.9 Créer les templates de certificats

> ⚠️ **Prérequis** : Si `certtmpl.msc` échoue avec une erreur DNS, configurer d'abord le forwarder DNS :
>
> ```powershell
> Set-DnsServerForwarder -IPAddress 10.4.10.4
> Clear-DnsClientCache
> ```

#### Ouvrir la console des templates

```powershell
certtmpl.msc
```

#### Template 1 : WSFR_Services (On-demand pour services web, VPN, etc.)

| Étape | Action                                                                                       |
| ----- | -------------------------------------------------------------------------------------------- |
| 1     | Clic droit sur **"Serveur Web"** (ou "Web Server") → **Dupliquer le modèle**                 |
| 2     | Onglet **Général** : Nom complet = `WSFR_Services`                                           |
| 3     | Onglet **Traitement de la demande** : ✅ Cocher **Autoriser l'exportation de la clé privée** |
| 4     | Onglet **Nom du sujet** : Sélectionner ⚪ **Fourni dans la demande**                         |
| 5     | Onglet **Sécurité** : **Utilisateurs authentifiés** → ✅ **Inscrire**                        |
| 6     | Cliquer **OK**                                                                               |

#### Template 2 : WSFR_Machines (Autoenrollment ordinateurs)

| Étape | Action                                                                                                 |
| ----- | ------------------------------------------------------------------------------------------------------ |
| 1     | Clic droit sur **"Ordinateur"** (ou "Computer") → **Dupliquer le modèle**                              |
| 2     | Onglet **Général** : Nom complet = `WSFR_Machines`                                                     |
| 3     | Onglet **Sécurité** : Ajouter **Ordinateurs du domaine** (cliquer Types d'objets → cocher Ordinateurs) |
| 4     | Pour **Ordinateurs du domaine** : ✅ **Lecture** + ✅ **Inscrire** + ✅ **Inscription automatique**    |
| 5     | Cliquer **OK**                                                                                         |

> ⚠️ **Important** : Si vous avez des domaines enfants (HQ), ajoutez aussi **HQ\Ordinateurs du domaine** avec les mêmes permissions.

#### Template 3 : WSFR_Users (Autoenrollment utilisateurs)

| Étape | Action                                                                                               |
| ----- | ---------------------------------------------------------------------------------------------------- |
| 1     | Clic droit sur **"Utilisateur"** (ou "User") → **Dupliquer le modèle**                               |
| 2     | Onglet **Général** : Nom complet = `WSFR_Users`                                                      |
| 3     | Onglet **Sécurité** : **Utilisateurs du domaine** → ✅ **Inscrire** + ✅ **Inscription automatique** |
| 4     | Cliquer **OK**                                                                                       |

#### ✅ Vérification

Les 3 templates doivent apparaître dans la liste de `certtmpl.msc` :

- WSFR_Services
- WSFR_Machines
- WSFR_Users

### 5.10 Publier les templates sur la CA

#### Méthode GUI (recommandée)

1. Ouvrir la console de la CA :

```powershell
certsrv.msc
```

2. Dans l'arborescence, déplier **WSFR-SUB-CA**
3. Clic droit sur **"Modèles de certificats"** → **Nouveau** → **Modèle de certificat à délivrer**
4. Sélectionner **WSFR_Services** → **OK**
5. Répéter pour **WSFR_Machines** et **WSFR_Users**

#### Méthode PowerShell

```powershell
# Publier les templates sur la CA (après création manuelle)
Add-CATemplate -Name "WSFR_Services" -Force
Add-CATemplate -Name "WSFR_Machines" -Force
Add-CATemplate -Name "WSFR_Users" -Force
```

#### ✅ Vérification

```powershell
# Vérifier les templates publiés sur la CA
Get-CATemplate

# Résultat attendu : WSFR_Services, WSFR_Machines, WSFR_Users dans la liste
```

---

## 6️⃣ Stockage RAID-5

### 6.0 Prérequis : Ajouter les disques sur ESXi

> ⚠️ **Avant de commencer** : Ajouter 3 disques virtuels de 1 Go à la VM depuis ESXi/vSphere.

1. Sur **ESXi** : Clic droit sur la VM → **Edit Settings**
2. **Add New Device** → **Hard Disk** → **1 Go**
3. Répéter 3 fois pour avoir 3 disques de 1 Go
4. Redémarrer la VM si nécessaire

### 6.1 Ouvrir la Gestion des disques

```powershell
diskmgmt.msc
```

### 6.2 Mettre les disques en ligne et les initialiser

1. Clic droit sur chaque disque "Hors connexion" (à gauche) → **En ligne**
2. Si "Lecture seule" : Clic droit → **Propriétés** → Décocher lecture seule
   - Ou en PowerShell : `Set-Disk -Number X -IsReadOnly $false`
3. Clic droit sur chaque disque → **Initialiser le disque**
4. Sélectionner les 3 disques → **GPT (GUID Partition Table)** → **OK**

### 6.3 Créer le volume RAID-5

> 💡 **Note** : Pas besoin de convertir en disques dynamiques manuellement ! L'assistant le fait automatiquement.

1. Clic droit sur l'espace **Non alloué** d'un des disques
2. Sélectionner **Nouveau volume RAID-5...**
3. **Suivant**
4. Ajouter les 3 disques dans la liste (utiliser le bouton **Ajouter >>**)
5. Vérifier que l'espace est identique sur les 3 disques
6. **Suivant**
7. Lettre de lecteur : **D:** (si le DVD occupe D:, le déplacer d'abord sur Z: via clic droit → Modifier la lettre)
8. **Suivant**
9. Système de fichiers : **NTFS**
10. Nom du volume : `DATA`
11. ✅ Cocher **Effectuer un formatage rapide**
12. **Suivant** → **Terminer**

> ⚠️ **Avertissement "Disques dynamiques"** : Un message apparaît indiquant que les disques seront convertis en disques dynamiques. Cela signifie :
>
> - Ces disques ne pourront plus être utilisés pour démarrer un autre OS (dual-boot)
> - Le disque système (C:) n'est PAS affecté
> - C'est normal et sans risque pour des disques de données → **Cliquer sur "Oui"**

> ⏳ Le volume mettra quelques minutes à se synchroniser (resync). Tu peux continuer pendant ce temps.

### 6.4 Vérification RAID-5

Dans la Gestion des disques, tu dois voir :

- **Disque 1, 2, 3** : Dynamique, En ligne
- **Volume D:** : RAID-5, NTFS, ~2 Go (1/3 perdu pour la parité)

### 6.5 Activer la déduplication

#### Étape 1 : Installer la fonctionnalité (obligatoire)

```powershell
Install-WindowsFeature -Name FS-Data-Deduplication -IncludeManagementTools
```

> ⚠️ **Sans cette étape**, l'option "Configurer la déduplication" sera **grisée** dans Server Manager !

#### Étape 2 : Activer la déduplication

**Méthode PowerShell :**

```powershell
# Activer la déduplication sur le volume D:
Enable-DedupVolume -Volume "D:" -UsageType Default

# Configurer les paramètres de déduplication (0 jours = immédiat)
Set-DedupVolume -Volume "D:" -MinimumFileAgeDays 0
```

**Méthode GUI :**

1. Dans **Server Manager** → **Services de fichiers et de stockage** → **Volumes**
2. Clic droit sur le volume **D:** → **Configurer la déduplication des données...**
3. **Déduplication des données** : Sélectionner **Serveur de fichiers à usage général**
4. **Dédupliquer les fichiers datant de plus de (jours)** : `0`
5. **OK**

#### ✅ Vérification finale RAID-5 et Déduplication

```powershell
# Vérifier le volume D:
Get-Volume -DriveLetter D

# Vérifier la déduplication
Get-DedupStatus -Volume "D:"

# Vérifier l'espace disponible
Get-PSDrive D
```

Dans **Gestion des disques** (`diskmgmt.msc`) :

- Volume D: doit apparaître comme **RAID-5**, **Sain**, **NTFS**

---

## 7️⃣ Serveur de fichiers et partages

### 7.0 Variables communes (EXÉCUTER EN PREMIER !)

> ⚠️ **IMPORTANT** : Exécute ce bloc AU DÉBUT de ta session PowerShell avant les autres sections !

```powershell
# Variables utilisées dans toute la section 7
$domainNetBIOS = (Get-ADDomain).NetBIOSName  # Retourne "HQ"
$departments = @("IT", "Direction", "Factory", "Sales")

# SID des groupes (plus fiable que les noms localisés)
$domainAdminsSID = (Get-ADGroup "Admins du domaine").SID
$domainUsersSID = (Get-ADGroup "Utilisateurs du domaine").SID
$authUsersSID = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-11")  # Authenticated Users
$creatorOwnerSID = New-Object System.Security.Principal.SecurityIdentifier("S-1-3-0")  # Creator Owner

# Vérification
Write-Host "Domaine: $domainNetBIOS" -ForegroundColor Cyan
Write-Host "Départements: $($departments -join ', ')" -ForegroundColor Cyan
Write-Host "SID Domain Admins: $domainAdminsSID" -ForegroundColor Cyan
```

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
foreach ($dept in $departments) {
    New-Item -Path "D:\shares\Department\$dept" -ItemType Directory -Force
    New-Item -Path "D:\shares\Public\$dept" -ItemType Directory -Force
}
```

### 7.3 Partage Home Drives (users$)

> ⚠️ **Prérequis** : Avoir exécuté la section **7.0** pour définir les variables et SID

```powershell
# Créer le partage caché pour les home drives
New-SmbShare -Name "users$" `
    -Path "D:\shares\datausers" `
    -FullAccess "$domainNetBIOS\Admins du domaine" `
    -ChangeAccess "Utilisateurs authentifiés" `
    -FolderEnumerationMode AccessBased -ErrorAction SilentlyContinue

# Configurer les permissions NTFS avec SID (plus fiable)
$acl = Get-Acl "D:\shares\datausers"
$acl.SetAccessRuleProtection($true, $false)  # Désactiver l'héritage

# Administrateurs du domaine - Full Control (via SID)
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule($domainAdminsSID, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
$acl.AddAccessRule($rule)

# CREATOR OWNER - pour les sous-dossiers utilisateurs (via SID)
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule($creatorOwnerSID, "FullControl", "ContainerInherit,ObjectInherit", "InheritOnly", "Allow")
$acl.AddAccessRule($rule)

# Utilisateurs authentifiés - CreateFolders uniquement (via SID)
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule($authUsersSID, "CreateDirectories", "None", "None", "Allow")
$acl.AddAccessRule($rule)

Set-Acl "D:\shares\datausers" $acl
Write-Host "OK: Partage users$ configuré" -ForegroundColor Green
```

### 7.4 Quota 20 Mo pour les home drives (GUI)

> ⚠️ **Important** : Le sujet demande de "Limit" (limiter) le quota, donc on utilise un **HardLimit** (blocage strict), pas un SoftLimit (avertissement).

#### Étape 1 : Ouvrir le Gestionnaire de ressources du serveur de fichiers

1. **Win+R** → `fsrm.msc` → Entrée
2. Ou via **Gestionnaire de serveur** → Outils → **Gestionnaire de ressources du serveur de fichiers**

#### Étape 2 : Créer un modèle de quota

1. Dans le panneau gauche : **Gestion de quota** → **Modèles de quotas**
2. Clic droit → **Créer un modèle de quota...**
3. Configurer :
   - **Nom du modèle** : `UserQuota20MB`
   - **Description** : `Quota utilisateur 20 Mo - STRICT`
   - **Limite d'espace** : `20` Mo
   - ✅ **Limite inconditionnelle** (HardLimit - bloque l'écriture)
   - ❌ Ne PAS cocher "Limite conditionnelle" (SoftLimit)
4. Optionnel : Configurer des **seuils de notification** (ex: avertissement à 85%, 95%)
5. Cliquer **OK**

#### Étape 3 : Appliquer un quota automatique sur les home drives

1. Dans le panneau gauche : **Gestion de quota** → **Quotas automatiques**
2. Clic droit → **Créer un quota automatique...**
3. Configurer :
   - **Chemin du quota automatique** : `D:\shares\datausers`
   - **Dériver les propriétés de ce modèle de quota** : Sélectionner `UserQuota20MB`
4. Cliquer **Créer**

> ✅ Le quota sera automatiquement appliqué à chaque sous-dossier utilisateur existant et futur !

#### Vérification

```powershell
# Vérifier le template
Get-FsrmQuotaTemplate -Name "UserQuota20MB" | Select-Object Name, Size, SoftLimit
# Attendu : SoftLimit = False (HardLimit)

# Vérifier l'auto-quota
Get-FsrmAutoQuota -Path "D:\shares\datausers"

# Vérifier les quotas appliqués
Get-FsrmQuota -Path "D:\shares\datausers\*" | Format-Table Path, @{N='SizeMB';E={$_.Size/1MB}}, @{N='UsedMB';E={$_.Usage/1MB}}
```

> ⚠️ **IMPORTANT** : Le quota automatique ne s'applique qu'aux **nouveaux** sous-dossiers !
> Pour les dossiers utilisateurs **existants**, exécuter :
>
> ```powershell
> # Appliquer le quota à TOUS les sous-dossiers existants
> Get-ChildItem "D:\shares\datausers" -Directory | ForEach-Object {
>     New-FsrmQuota -Path $_.FullName -Template "UserQuota20MB" -ErrorAction SilentlyContinue
>     Write-Host "Quota créé: $($_.FullName)" -ForegroundColor Green
> }
> ```

---

### 7.5 Bloquer les fichiers exécutables (GUI)

#### Étape 1 : Créer un groupe de fichiers (si nécessaire)

1. Dans `fsrm.msc` : **Gestion du filtrage de fichiers** → **Groupes de fichiers**
2. Vérifier si **"Fichiers exécutables"** existe déjà (groupe par défaut Windows)
3. Si non, clic droit → **Créer un groupe de fichiers...**
   - **Nom** : `Executables`
   - **Fichiers à inclure** : `*.exe`, `*.com`, `*.bat`, `*.cmd`, `*.msi`, `*.vbs`, `*.ps1`, `*.scr`
   - Cliquer **OK**

#### Étape 2 : Créer un filtre de fichiers

1. Dans le panneau gauche : **Gestion du filtrage de fichiers** → **Filtres de fichiers**
2. Clic droit → **Créer un filtre de fichiers...**
3. Configurer :
   - **Chemin du filtre de fichiers** : `D:\shares\datausers`
   - ✅ **Filtrage actif** (bloque les fichiers)
   - Sélectionner le groupe : **Fichiers exécutables** (ou `Executables`)
4. Cliquer **Créer**

#### Vérification

```powershell
Get-FsrmFileScreen -Path "D:\shares\datausers"
Get-FsrmFileGroup -Name "Fichiers exécutables"
```

---

### 7.4b / 7.5b Alternative PowerShell (si GUI non disponible)

```powershell
# === QUOTA 20 Mo ===
# Créer le template de quota (HardLimit par défaut)
New-FsrmQuotaTemplate -Name "UserQuota20MB" -Size 20MB -Description "Quota utilisateur 20 Mo - STRICT"

# Appliquer l'auto-quota
New-FsrmAutoQuota -Path "D:\shares\datausers" -Template "UserQuota20MB"

# === BLOCAGE EXECUTABLES ===
# Créer le groupe de fichiers
New-FsrmFileGroup -Name "Executables" -IncludePattern @("*.exe", "*.com", "*.bat", "*.cmd", "*.msi", "*.vbs", "*.ps1", "*.scr")

# Créer le filtre de fichiers
New-FsrmFileScreen -Path "D:\shares\datausers" -IncludeGroup "Executables" -Active
```

### 7.6 Partage Department

> ⚠️ **Prérequis** : Avoir exécuté la section **7.0** pour définir les variables et SID
>
> **Selon le sujet** : Chaque utilisateur a RW sur son département SEULEMENT, ne voit que son dossier.

```powershell
# Créer le partage Department (ignorer si existe déjà)
# IMPORTANT : Les utilisateurs du domaine doivent avoir accès SMB pour que le mappage fonctionne
New-SmbShare -Name "Department$" `
    -Path "D:\shares\Department" `
    -FullAccess "$domainNetBIOS\Admins du domaine" `
    -ChangeAccess "$domainNetBIOS\Utilisateurs du domaine" `
    -FolderEnumerationMode AccessBased -ErrorAction SilentlyContinue

# Configurer les permissions par département avec SID
foreach ($dept in $departments) {
    $deptPath = "D:\shares\Department\$dept"

    if (Test-Path $deptPath) {
        # Récupérer le SID du groupe de département
        $deptGroupSID = (Get-ADGroup $dept).SID

        $acl = Get-Acl $deptPath
        $acl.SetAccessRuleProtection($true, $false)

        # Administrateurs du domaine (via SID)
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($domainAdminsSID, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
        $acl.AddAccessRule($rule)

        # Groupe du département - Modify (via SID)
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($deptGroupSID, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
        $acl.AddAccessRule($rule)

        Set-Acl $deptPath $acl
        Write-Host "OK: $deptPath" -ForegroundColor Green
    }
}
```

### 7.7 Partage Public

> ⚠️ **Prérequis** : Avoir exécuté la section **7.0** pour définir les variables et SID
>
> **Selon le sujet** : RW sur son département, R sur les autres départements.

```powershell
# Créer le partage Public (ignorer si existe déjà)
# IMPORTANT : Les utilisateurs du domaine doivent avoir accès SMB Change pour RW sur leur dossier
New-SmbShare -Name "Public$" `
    -Path "D:\shares\Public" `
    -FullAccess "$domainNetBIOS\Admins du domaine" `
    -ChangeAccess "$domainNetBIOS\Utilisateurs du domaine" `
    -FolderEnumerationMode AccessBased -ErrorAction SilentlyContinue

# Configurer les permissions par département avec SID
foreach ($dept in $departments) {
    $deptPath = "D:\shares\Public\$dept"

    if (Test-Path $deptPath) {
        # Récupérer le SID du groupe de département
        $deptGroupSID = (Get-ADGroup $dept).SID

        $acl = Get-Acl $deptPath
        $acl.SetAccessRuleProtection($true, $false)

        # Administrateurs du domaine (via SID)
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($domainAdminsSID, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
        $acl.AddAccessRule($rule)

        # Groupe du département - Modify (via SID)
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($deptGroupSID, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
        $acl.AddAccessRule($rule)

        # Utilisateurs du domaine - Read only (via SID)
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($domainUsersSID, "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")
        $acl.AddAccessRule($rule)

        Set-Acl $deptPath $acl
        Write-Host "OK: $deptPath" -ForegroundColor Green
    }
}
```

### 7.8 Permissions NTFS sur les dossiers racines

> ⚠️ **IMPORTANT** : Sans ces permissions, les utilisateurs ne pourront pas naviguer dans les dossiers racines !

```powershell
# Permissions NTFS sur le dossier racine Department
$deptPath = "D:\shares\Department"
$acl = Get-Acl $deptPath

# Ajouter Utilisateurs du domaine avec Read + ListDirectory sur le dossier racine
$domainUsers = New-Object System.Security.Principal.NTAccount("HQ", "Utilisateurs du domaine")
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule($domainUsers, "ReadAndExecute,ListDirectory", "ContainerInherit,ObjectInherit", "None", "Allow")
$acl.AddAccessRule($rule)
Set-Acl $deptPath $acl
Write-Host "OK - $deptPath" -ForegroundColor Green

# Permissions NTFS sur le dossier racine Public
$publicPath = "D:\shares\Public"
$acl = Get-Acl $publicPath

# Ajouter Utilisateurs du domaine avec Read + ListDirectory sur le dossier racine
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule($domainUsers, "ReadAndExecute,ListDirectory", "ContainerInherit,ObjectInherit", "None", "Allow")
$acl.AddAccessRule($rule)
Set-Acl $publicPath $acl
Write-Host "OK - $publicPath" -ForegroundColor Green
```

#### ✅ Vérification Partages

```powershell
# Lister tous les partages SMB
Get-SmbShare | Format-Table Name, Path, Description

# Vérifier les permissions SMB sur les partages
Get-SmbShareAccess -Name "users$"
Get-SmbShareAccess -Name "Department$"
Get-SmbShareAccess -Name "Public$"

# Vérifier les permissions NTFS sur les dossiers racines
(Get-Acl "D:\shares\Department").Access | Format-Table IdentityReference, FileSystemRights
(Get-Acl "D:\shares\Public").Access | Format-Table IdentityReference, FileSystemRights
```

#### 🔧 Correction si les lecteurs S: et P: ne se montent pas

Si les utilisateurs ont l'erreur "Accès refusé" sur les partages :

```powershell
# 1. Ajouter les permissions SMB manquantes
Grant-SmbShareAccess -Name "Department$" -AccountName "HQ\Utilisateurs du domaine" -AccessRight Change -Force
Grant-SmbShareAccess -Name "Public$" -AccountName "HQ\Utilisateurs du domaine" -AccessRight Change -Force

# 2. Ajouter les permissions NTFS sur les dossiers racines
$domainUsers = New-Object System.Security.Principal.NTAccount("HQ", "Utilisateurs du domaine")

$acl = Get-Acl "D:\shares\Department"
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule($domainUsers, "ReadAndExecute,ListDirectory", "ContainerInherit,ObjectInherit", "None", "Allow")
$acl.AddAccessRule($rule)
Set-Acl "D:\shares\Department" $acl

$acl = Get-Acl "D:\shares\Public"
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule($domainUsers, "ReadAndExecute,ListDirectory", "ContainerInherit,ObjectInherit", "None", "Allow")
$acl.AddAccessRule($rule)
Set-Acl "D:\shares\Public" $acl

# 3. Vérifier
Get-SmbShareAccess -Name "Department$"
Get-SmbShareAccess -Name "Public$"

# Vérifier les quotas FSRM
Get-FsrmQuota -Path "D:\shares\datausers\*"

# Vérifier le file screen (blocage exécutables)
Get-FsrmFileScreen -Path "D:\shares\datausers"

# Tester l'accès aux partages (depuis ce serveur)
Test-Path "\\hq.wsl2025.org\users$"
```

---

## 8️⃣ GPO (Group Policy Objects)

### 8.0 Création de toutes les GPO (Script PowerShell)

> ⚠️ **Ce script crée les GPO et les lie. La configuration se fait ensuite en GUI.**

```powershell
# ============================================
# CRÉATION DES GPO - À exécuter sur HQDCSRV
# ============================================

Write-Host "=== CRÉATION DES GPO ===" -ForegroundColor Cyan

# 1. Deploy-Certificates
$gpo = New-GPO -Name "Deploy-Certificates" -Comment "Déploie les certificats Root CA et Sub CA"
$gpo | New-GPLink -Target "DC=hq,DC=wsl2025,DC=org"
Write-Host "OK - Deploy-Certificates" -ForegroundColor Green

# 2. Certificate-Autoenrollment
$gpo = New-GPO -Name "Certificate-Autoenrollment" -Comment "Active l'auto-enrollment des certificats"
$gpo | New-GPLink -Target "DC=hq,DC=wsl2025,DC=org"
Write-Host "OK - Certificate-Autoenrollment" -ForegroundColor Green

# 3. Edge-Homepage-Intranet
$gpo = New-GPO -Name "Edge-Homepage-Intranet" -Comment "Configure la page d'accueil Edge sur l'intranet"
$gpo | New-GPLink -Target "DC=hq,DC=wsl2025,DC=org"
Write-Host "OK - Edge-Homepage-Intranet" -ForegroundColor Green

# 4. Block-ControlPanel (lié aux Users uniquement)
$gpo = New-GPO -Name "Block-ControlPanel" -Comment "Bloque l'accès au panneau de configuration sauf IT"
$gpo | New-GPLink -Target "OU=Users,OU=HQ,DC=hq,DC=wsl2025,DC=org"
Write-Host "OK - Block-ControlPanel" -ForegroundColor Green

# 5. Enterprise-Logo
$gpo = New-GPO -Name "Enterprise-Logo" -Comment "Affiche le logo entreprise sur l'écran de verrouillage"
$gpo | New-GPLink -Target "DC=hq,DC=wsl2025,DC=org"
Write-Host "OK - Enterprise-Logo" -ForegroundColor Green

# 6. Drive-Mappings (lié aux Users uniquement)
$gpo = New-GPO -Name "Drive-Mappings" -Comment "Configure les lecteurs réseau U:, S:, P:"
$gpo | New-GPLink -Target "OU=Users,OU=HQ,DC=hq,DC=wsl2025,DC=org"
Write-Host "OK - Drive-Mappings" -ForegroundColor Green

# Créer le dossier Logo sur NETLOGON
New-Item -Path "C:\Windows\SYSVOL\domain\scripts\Logo" -ItemType Directory -Force | Out-Null

# Créer le script de mappage des lecteurs
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
Write-Host "OK - Script MapDrives.bat créé" -ForegroundColor Green

Write-Host "`n=== GPO CRÉÉES ===" -ForegroundColor Cyan
Get-GPO -All | Select-Object DisplayName, GpoStatus | Format-Table

Write-Host "`n⚠️  CONFIGURER CHAQUE GPO EN GUI (voir documentation)" -ForegroundColor Yellow
```

---

### 8.1 GPO Deploy-Certificates (GUI)

> Déploie les certificats Root CA et Sub CA sur tous les ordinateurs du domaine.

1. Ouvrir **`gpmc.msc`** (Win+R → gpmc.msc)

2. **Forêt: wsl2025.org** → **Domaines** → **hq.wsl2025.org** → **Objets de stratégie de groupe**

3. Clic droit sur **Deploy-Certificates** → **Modifier**

4. Naviguer vers :

   ```
   Configuration ordinateur → Stratégies → Paramètres Windows
   → Paramètres de sécurité → Stratégies de clé publique
   ```

5. **Importer le Root CA** :

   - Clic droit sur **Autorités de certification racines de confiance** → **Importer...**
   - Parcourir → `C:\WSFR-ROOT-CA.cer` → **Suivant** → **Terminer**

6. **Importer le Sub CA** :

   - Clic droit sur **Autorités de certification intermédiaires** → **Importer...**
   - Parcourir → `C:\SubCA.cer` → **Suivant** → **Terminer**

7. Fermer l'éditeur

---

### 8.2 GPO Certificate-Autoenrollment (GUI)

> Active l'inscription automatique des certificats machines et utilisateurs.

1. Dans **gpmc.msc**, clic droit sur **Certificate-Autoenrollment** → **Modifier**

2. **Configuration ORDINATEUR** :

   ```
   Configuration ordinateur → Stratégies → Paramètres Windows
   → Paramètres de sécurité → Stratégies de clé publique
   ```

   - Double-clic sur **Client des services de certificats - Inscription automatique**
   - **Modèle de configuration** : **Activé**
   - ✅ Cocher **Renouveler les certificats expirés...**
   - ✅ Cocher **Mettre à jour les certificats qui utilisent des modèles...**
   - **OK**

3. **Configuration UTILISATEUR** (répéter) :

   ```
   Configuration utilisateur → Stratégies → Paramètres Windows
   → Paramètres de sécurité → Stratégies de clé publique
   ```

   - Double-clic sur **Client des services de certificats - Inscription automatique**
   - Mêmes paramètres que ci-dessus
   - **OK**

4. Fermer l'éditeur

---

### 8.3 GPO Edge-Homepage-Intranet (GUI)

> Configure la page d'accueil de Microsoft Edge pour tous les utilisateurs.

1. Dans **gpmc.msc**, clic droit sur **Edge-Homepage-Intranet** → **Modifier**

2. Naviguer vers :

   ```
   Configuration ordinateur → Stratégies → Modèles d'administration
   → Microsoft Edge → Démarrage, page d'accueil et page Nouvel onglet
   ```

3. **Configurer l'URL de la page d'accueil** :

   - Double-clic sur **Configurer l'URL de la page d'accueil**
   - **Activé**
   - URL : `http://hqmailsrv.wsl2025.org` (ou votre URL intranet)
   - **OK**

4. **Afficher le bouton Accueil** :

   - Double-clic sur **Afficher le bouton Accueil sur la barre d'outils**
   - **Activé**
   - **OK**

5. **Configurer l'action au démarrage** :

   - Double-clic sur **Action à effectuer au démarrage**
   - **Activé**
   - Choisir : **Ouvrir une liste d'URL**
   - **OK**

6. **Configurer les URL de démarrage** :

   - Double-clic sur **URL à ouvrir au démarrage**
   - **Activé**
   - Cliquer **Afficher...** → Ajouter `http://hqmailsrv.wsl2025.org`
   - **OK**

7. Fermer l'éditeur

---

### 8.4 GPO Block-ControlPanel (GUI)

> Bloque l'accès au panneau de configuration pour tous les utilisateurs SAUF le groupe IT.

1. Dans **gpmc.msc**, clic droit sur **Block-ControlPanel** → **Modifier**

2. Naviguer vers :

   ```
   Configuration utilisateur → Stratégies → Modèles d'administration
   → Panneau de configuration
   ```

3. Double-clic sur **Interdire l'accès au Panneau de configuration et à l'application Paramètres du PC**

   - **Activé**
   - **OK**

4. Fermer l'éditeur

#### Exclure le groupe IT (IMPORTANT)

5. Dans **gpmc.msc**, clic sur **Block-ControlPanel** (dans Objets de stratégie de groupe)

6. Dans le panneau de droite, onglet **Délégation**

7. Cliquer sur **Avancé...** (en bas)

8. Cliquer **Ajouter...** → Taper `IT` → **OK**

9. Sélectionner le groupe **IT** dans la liste

10. Dans les permissions, cocher **Refuser** pour :

    - ✅ **Appliquer la stratégie de groupe** → **REFUSER**

11. Cliquer **OK** → **Oui** pour confirmer le Deny

---

### 8.5 GPO Enterprise-Logo (GUI)

> Affiche le logo entreprise sur l'écran de verrouillage.

#### Prérequis : Copier l'image du logo

1. Copier votre image de logo (format `.jpg` ou `.png`, résolution 1920x1080 recommandée) vers :
   ```
   C:\Windows\SYSVOL\domain\scripts\Logo\logo.jpg
   ```

#### Configuration

2. Dans **gpmc.msc**, clic droit sur **Enterprise-Logo** → **Modifier**

3. Naviguer vers :

   ```
   Configuration ordinateur → Stratégies → Modèles d'administration
   → Panneau de configuration → Personnalisation
   ```

4. Double-clic sur **Forcer une image d'écran de verrouillage par défaut**

   - **Activé**
   - Chemin : `\\hq.wsl2025.org\NETLOGON\Logo\logo.jpg`
   - **OK**

5. Fermer l'éditeur

---

### 8.6 GPO Drive-Mappings (GUI)

> Configure les lecteurs réseau U:, S:, P: via un script de connexion.

1. Dans **gpmc.msc**, clic droit sur **Drive-Mappings** → **Modifier**

2. Naviguer vers :

   ```
   Configuration utilisateur → Stratégies → Paramètres Windows
   → Scripts (ouverture/fermeture de session)
   ```

3. Double-clic sur **Ouverture de session**

4. Cliquer **Ajouter...**

5. Cliquer **Parcourir...** → Aller dans `\\hq.wsl2025.org\NETLOGON\` → Sélectionner `MapDrives.bat`

6. **OK** → **OK**

7. Fermer l'éditeur

---

### 8.7 Configurer les Home Folders utilisateurs

> Configure le dossier personnel (U:) pour chaque utilisateur dans Active Directory.

```powershell
# Récupérer le SID des Domain Admins
$domainAdminsSID = (Get-ADGroup "Admins du domaine").SID

# Configurer le home folder pour chaque utilisateur
$users = Get-ADUser -Filter * -SearchBase "OU=HQ,DC=hq,DC=wsl2025,DC=org" -SearchScope Subtree

$count = 0
foreach ($user in $users) {
    $homeFolder = "\\hq.wsl2025.org\users$\$($user.SamAccountName)"
    $localPath = "D:\shares\datausers\$($user.SamAccountName)"

    # Créer le dossier local s'il n'existe pas
    if (-not (Test-Path $localPath)) {
        New-Item -Path $localPath -ItemType Directory -Force | Out-Null

        # Configurer les permissions avec SID
        $acl = Get-Acl $localPath
        $acl.SetAccessRuleProtection($true, $false)

        # Administrateurs du domaine (via SID)
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($domainAdminsSID, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
        $acl.AddAccessRule($rule)

        # Utilisateur propriétaire (via SID)
        $userSID = $user.SID
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($userSID, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
        $acl.AddAccessRule($rule)

        Set-Acl $localPath $acl
    }

    # Configurer le profil AD
    Set-ADUser -Identity $user -HomeDirectory $homeFolder -HomeDrive "U:"

    $count++
    if ($count % 100 -eq 0) { Write-Host "Traité $count utilisateurs..." }
}
Write-Host "Terminé : $count utilisateurs configurés" -ForegroundColor Green
```

---

### 8.8 Vérification des GPO

```powershell
# Lister toutes les GPO
Get-GPO -All | Select-Object DisplayName, GpoStatus | Format-Table

# Vérifier les liens
Get-GPO -Name "Deploy-Certificates" | Get-GPOReport -ReportType HTML -Path "C:\GPO-Report.html"
```

**Attendu** : 6 GPO avec statut `AllSettingsEnabled`

| GPO                        | Liée à                                 |
| -------------------------- | -------------------------------------- |
| Deploy-Certificates        | DC=hq,DC=wsl2025,DC=org                |
| Certificate-Autoenrollment | DC=hq,DC=wsl2025,DC=org                |
| Edge-Homepage-Intranet     | DC=hq,DC=wsl2025,DC=org                |
| Block-ControlPanel         | OU=Users,OU=HQ,DC=hq,DC=wsl2025,DC=org |
| Enterprise-Logo            | DC=hq,DC=wsl2025,DC=org                |
| Drive-Mappings             | OU=Users,OU=HQ,DC=hq,DC=wsl2025,DC=org |

---

## 9️⃣ Configuration NTP

> ⚠️ **Sujet** : "Use HQINFRASRV as time reference. Use authentication to secure NTP communication."

### 9.1 Prérequis sur HQINFRASRV

HQINFRASRV doit être configuré comme serveur NTP avec un stratum valide. Sur HQINFRASRV, vérifier `/etc/ntpsec/ntp.conf` :

```bash
# Horloge locale avec stratum 10 (pour lab sans Internet)
server 127.127.1.0
fudge 127.127.1.0 stratum 10

# Autoriser le LAN
restrict 10.4.0.0 mask 255.255.0.0 nomodify notrap
```

Vérifier que ntpsec fonctionne :

```bash
systemctl status ntpsec
ntpq -p
# Doit afficher *LOCAL(0) avec stratum 10
```

### 9.2 Configurer NTP sur HQDCSRV

```powershell
# 1. Désactiver le provider Hyper-V/VMware (si VM)
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\VMICTimeProvider" -Name "Enabled" -Value 0

# 2. Configurer le serveur NTP avec HQINFRASRV
# Flag 0x8 = UseAsFallbackOnly + Client mode
w32tm /config /manualpeerlist:"hqinfrasrv.wsl2025.org,0x8" /syncfromflags:manual /update

# 3. Redémarrer le service
Restart-Service w32time

# 4. Forcer la synchronisation
w32tm /resync /force
```

### 9.3 Vérification NTP

```powershell
# Vérifier la source NTP
w32tm /query /source
# Attendu : hqinfrasrv.wsl2025.org,0x8

# Vérifier le statut de synchronisation
w32tm /query /status

# Vérifier les peers
w32tm /query /peers

# Tester la connexion au serveur NTP
w32tm /stripchart /computer:hqinfrasrv.wsl2025.org /samples:3
```

**Attendu** :

- Source : `hqinfrasrv.wsl2025.org,0x8`
- Stratum : 11 (HQINFRASRV stratum 10 + 1)
- État : Synchronisé

> 💡 **Note** : L'authentification NTP est gérée par la restriction réseau sur HQINFRASRV (`restrict 10.4.0.0 mask 255.255.0.0`). Seuls les clients du réseau interne peuvent se synchroniser.

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

### Tests sur un client (HQCLT)

> **Prérequis** : HQCLT doit être joint au domaine `hq.wsl2025.org`

```powershell
# 1. Forcer l'application des GPO
gpupdate /force

# 2. Vérifier les certificats Root/Sub CA déployés
Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.Subject -like "*WSFR*" }
Get-ChildItem Cert:\LocalMachine\CA | Where-Object { $_.Subject -like "*WSFR*" }

# 3. Forcer l'inscription des certificats machine
certutil -pulse

# 4. Vérifier le certificat machine
Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Issuer -like "*WSFR-SUB-CA*" }

# 5. Vérifier les lecteurs réseau (après connexion utilisateur)
Get-PSDrive | Where-Object { $_.Name -in @("U", "S", "P") }
```

#### Vérification GUI sur HQCLT

| Test                 | Action                              | Résultat attendu                |
| -------------------- | ----------------------------------- | ------------------------------- |
| **Certificats Root** | `certlm.msc` → Racines de confiance | WSFR-ROOT-CA visible            |
| **Certificats Sub**  | `certlm.msc` → Intermédiaires       | WSFR-SUB-CA visible             |
| **Cert Machine**     | `certlm.msc` → Personnel            | Certificat émis par WSFR-SUB-CA |
| **Edge Homepage**    | Ouvrir Edge                         | Page = www.wsl2025.org          |
| **Control Panel**    | Win+I (utilisateur non-IT)          | Accès bloqué                    |
| **Lecteurs**         | Explorateur → Ce PC                 | U:, S:, P: visibles             |

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
- [ ] IP statique configurée (10.4.10.1/24, Gateway 10.4.10.254)
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
- [ ] CRL du Root CA (WSFR-ROOT-CA.crl) copiée dans C:\inetpub\PKI
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

---

## 🔍 Script de Vérification Complète

> Copier-coller ce script dans PowerShell pour générer un rapport complet de vérification.

```powershell
# ============================================
# SCRIPT DE VERIFICATION HQDCSRV - COMPLET
# Copier-coller tout ce bloc dans PowerShell
# ============================================

$outputFile = "C:\HQDCSRV_Verification.txt"

# Fonction pour écrire dans le fichier
function Write-Check {
    param([string]$Section, [string]$Content)
    $header = "`n" + "="*60 + "`n$Section`n" + "="*60
    Add-Content -Path $outputFile -Value $header
    Add-Content -Path $outputFile -Value $Content
}

# Initialiser le fichier
"VERIFICATION HQDCSRV - $(Get-Date)" | Out-File -FilePath $outputFile -Force
Add-Content -Path $outputFile -Value "Serveur: $env:COMPUTERNAME"

# 1. ROLES ET FONCTIONNALITES
Write-Check "1. ROLES INSTALLES" (Get-WindowsFeature | Where-Object Installed | Select-Object Name, InstallState | Format-Table -AutoSize | Out-String)

# 2. ADCS - Autorité de Certification
Write-Check "2. ADCS - CA Info" (certutil -ca | Out-String)
Write-Check "2. ADCS - Templates publiés" (certutil -CATemplates | Out-String)

# 3. DNS
Write-Check "3. DNS - Zones" (Get-DnsServerZone | Format-Table -AutoSize | Out-String)
Write-Check "3. DNS - Forwarders" (Get-DnsServerForwarder | Out-String)

# 4. IIS - Site PKI
Write-Check "4. IIS - Sites" (Get-Website | Format-Table Name, State, PhysicalPath | Out-String)
Write-Check "4. IIS - PKI Bindings" (Get-WebBinding -Name "PKI" -ErrorAction SilentlyContinue | Out-String)
Write-Check "4. IIS - Contenu PKI" (Get-ChildItem "C:\inetpub\PKI" -ErrorAction SilentlyContinue | Format-Table Name, Length, LastWriteTime | Out-String)

# 5. STOCKAGE - RAID et Volumes
Write-Check "5. DISQUES" (Get-Disk | Format-Table Number, FriendlyName, OperationalStatus, Size, PartitionStyle | Out-String)
Write-Check "5. VOLUMES" (Get-Volume | Format-Table DriveLetter, FileSystemLabel, FileSystem, Size, SizeRemaining | Out-String)

# 6. FSRM - Quotas et Filtres
Write-Check "6. FSRM - Quota Templates" (Get-FsrmQuotaTemplate | Format-Table Name, Size | Out-String)
Write-Check "6. FSRM - Quotas" (Get-FsrmQuota | Format-Table Path, Size | Out-String)
Write-Check "6. FSRM - Auto Quotas" (Get-FsrmAutoQuota | Format-Table Path, Template | Out-String)
Write-Check "6. FSRM - File Screen Templates" (Get-FsrmFileScreenTemplate | Format-Table Name | Out-String)
Write-Check "6. FSRM - File Screens" (Get-FsrmFileScreen | Format-Table Path, Template | Out-String)

# 7. PARTAGES SMB
Write-Check "7. PARTAGES SMB" (Get-SmbShare | Where-Object { $_.Name -notlike "*$" -or $_.Name -in @("users$","Department$","Public$") } | Format-Table Name, Path, Description | Out-String)
Write-Check "7. PARTAGES - Permissions SMB" (
    @("users$", "Department$", "Public$") | ForEach-Object {
        "`n--- $_ ---"
        Get-SmbShareAccess -Name $_ -ErrorAction SilentlyContinue | Format-Table AccountName, AccessControlType, AccessRight | Out-String
    } | Out-String
)

# 8. STRUCTURE DOSSIERS
Write-Check "8. STRUCTURE D:\shares" (Get-ChildItem "D:\shares" -Recurse -Depth 2 -Directory -ErrorAction SilentlyContinue | Select-Object FullName | Out-String)

# 9. GPO
Write-Check "9. GPO - Liste" (Get-GPO -All | Format-Table DisplayName, GpoStatus, CreationTime | Out-String)
Write-Check "9. GPO - Links" (
    Get-GPO -All | ForEach-Object {
        $gpo = $_
        $links = (Get-GPOReport -Guid $gpo.Id -ReportType Xml | Select-Xml -XPath "//gp:LinksTo/gp:SOMPath" -Namespace @{gp="http://www.microsoft.com/GroupPolicy/Settings"}).Node.'#text'
        if ($links) { "$($gpo.DisplayName) -> $($links -join ', ')" }
    } | Out-String
)

# 10. HOME FOLDERS - Echantillon
Write-Check "10. HOME FOLDERS - Echantillon (5 premiers)" (
    Get-ADUser -Filter * -SearchBase "OU=HQ,DC=hq,DC=wsl2025,DC=org" -Properties HomeDirectory, HomeDrive -ResultSetSize 5 |
    Format-Table SamAccountName, HomeDirectory, HomeDrive | Out-String
)
Write-Check "10. DOSSIERS UTILISATEURS - Count" ("Nombre de dossiers dans D:\shares\datausers: " + (Get-ChildItem "D:\shares\datausers" -Directory -ErrorAction SilentlyContinue).Count)

# 11. CERTIFICATS
Write-Check "11. CERTIFICATS - Demandes en attente" (certutil -view -out "RequestID,CommonName,Disposition" | Select-Object -First 20 | Out-String)

# 12. NTP
Write-Check "12. NTP - Config" (w32tm /query /configuration | Out-String)
Write-Check "12. NTP - Status" (w32tm /query /status | Out-String)

# 13. SERVICES
Write-Check "13. SERVICES CRITIQUES" (
    Get-Service -Name CertSvc, W3SVC, DNS, SrmSvc, LanmanServer -ErrorAction SilentlyContinue |
    Format-Table Name, DisplayName, Status | Out-String
)

# Fin
Add-Content -Path $outputFile -Value "`n`n========== FIN DE LA VERIFICATION =========="
Write-Host "`n`nVérification terminée !" -ForegroundColor Green
Write-Host "Fichier créé : $outputFile" -ForegroundColor Cyan
Write-Host "Taille : $((Get-Item $outputFile).Length / 1KB) KB" -ForegroundColor Cyan
Get-Item $outputFile
```

Le fichier de sortie sera créé à : `C:\HQDCSRV_Verification.txt`
