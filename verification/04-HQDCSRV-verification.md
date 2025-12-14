# Vérification HQDCSRV - Contrôleur de Domaine Enfant + ADCS

> **Serveur** : HQDCSRV  
> **IP** : 10.4.10.1  
> **Rôles** : AD DS (Child Domain), DNS, ADCS (Sub CA), File Server, GPO

---

## ✅ 1. Configuration de base

### Hostname

```powershell
hostname
```

**Attendu** : `HQDCSRV`

### IP

```powershell
Get-NetIPAddress -InterfaceAlias "Ethernet*" | Where-Object { $_.AddressFamily -eq "IPv4" }
```

**Attendu** : `10.4.10.1/24`

---

## ✅ 2. Active Directory

### Domaine enfant

```powershell
Get-ADDomain | Select-Object Name, DNSRoot, ParentDomain
```

**Attendu** :

- Name : `hq`
- DNSRoot : `hq.wsl2025.org`
- ParentDomain : `wsl2025.org`

### Trust avec le parent

```powershell
Get-ADTrust -Filter * | Select-Object Name, Direction, TrustType
```

**Attendu** : Trust bidirectionnel avec `wsl2025.org`

### OUs créées

```powershell
Get-ADOrganizationalUnit -Filter * | Select-Object Name
```

**Attendu** : HQ, Users, Computers, Groups, Shadow groups, IT, Direction, Factory, Sales, AUTO

### Utilisateurs

```powershell
# Utilisateurs HQ (hors wslusr)
Get-ADUser -Filter * -SearchBase "OU=Users,OU=HQ,DC=hq,DC=wsl2025,DC=org" |
    Where-Object { $_.SamAccountName -notlike "wslusr*" } |
    Select-Object SamAccountName, Name
```

**Attendu** :

- Ness PRESSO (Direction)
- Jean TICIPE (Factory)
- Vincent TIM (IT)
- Rick OLA (Sales)

### Utilisateurs provisionnés

```powershell
(Get-ADUser -Filter "SamAccountName -like 'wslusr*'" -SearchBase "DC=hq,DC=wsl2025,DC=org").Count
```

**Attendu** : `1000` (ou le nombre créé)

---

## ✅ 3. DNS

### Zone hq.wsl2025.org

```powershell
Get-DnsServerZone -Name "hq.wsl2025.org"
```

**Attendu** : Zone existe

### Enregistrements

```powershell
Resolve-DnsName hqdcsrv.hq.wsl2025.org
Resolve-DnsName pki.hq.wsl2025.org
```

**Attendu** :
| Nom | IP |
|-----|-----|
| hqdcsrv.hq.wsl2025.org | 10.4.10.1 |
| pki.hq.wsl2025.org | 10.4.10.1 |

### Forwarder

```powershell
Get-DnsServerForwarder
```

**Attendu** : `10.4.10.4` (DCWSL)

---

## ✅ 4. ADCS (Autorité de Certification)

### Service CA

```powershell
Get-Service certsvc
certutil -ping
```

**Attendu** : Service `Running`, ping OK

### Certificat Sub CA avec extensions CDP/AIA

```powershell
certutil -ca.cert | Select-String "pki.hq.wsl2025.org"
```

**Attendu** : URLs visibles :

- `http://pki.hq.wsl2025.org/WSFR-ROOT-CA.crl`
- `http://pki.hq.wsl2025.org/WSFR-ROOT-CA.crt`

### Templates publiés

```powershell
Get-CATemplate | Select-Object Name
```

**Attendu** : `WSFR_Services`, `WSFR_Machines`, `WSFR_Users`

### CRL Flags (vérification activée)

```powershell
certutil -getreg ca\CRLFlags
```

**Attendu** : `CRLFlags = 2` (CRLF_DELETE_EXPIRED_CRLS) - PAS de IGNORE_OFFLINE

---

## ✅ 5. Site IIS PKI

### Fichiers présents

```powershell
Get-ChildItem C:\inetpub\PKI
```

**Attendu** :

- `WSFR-SUB-CA.crl`
- `WSFR-ROOT-CA.crl`

### Accès HTTP

```powershell
Invoke-WebRequest -Uri "http://pki.hq.wsl2025.org/WSFR-SUB-CA.crl" -UseBasicParsing | Select-Object StatusCode
Invoke-WebRequest -Uri "http://pki.hq.wsl2025.org/WSFR-ROOT-CA.crl" -UseBasicParsing | Select-Object StatusCode
```

**Attendu** : `StatusCode = 200` pour les deux

---

## ✅ 6. Stockage RAID-5

### Volume D:

```powershell
Get-Volume -DriveLetter D
```

**Attendu** : Volume existe, taille ~57 Go (3x20 Go en RAID-5)

### Déduplication

```powershell
Get-DedupStatus -Volume D:
```

**Attendu** : Déduplication active

---

## ✅ 7. Partages SMB

### Partages créés

```powershell
Get-SmbShare | Where-Object { $_.Name -like "*$" -and $_.Name -notlike "ADMIN*" -and $_.Name -notlike "IPC*" -and $_.Name -notlike "C*" }
```

**Attendu** : `users$`, `Department$`, `Public$`

### Permissions SMB (IMPORTANT)

```powershell
Get-SmbShareAccess -Name "users$"
Get-SmbShareAccess -Name "Department$"
Get-SmbShareAccess -Name "Public$"
```

**Attendu** :

| Partage     | Compte                      | Droit      |
| ----------- | --------------------------- | ---------- |
| users$      | Admins du domaine           | Full       |
| users$      | Utilisateurs authentifiés   | Change     |
| Department$ | Admins du domaine           | Full       |
| Department$ | **Utilisateurs du domaine** | **Change** |
| Public$     | Admins du domaine           | Full       |
| Public$     | **Utilisateurs du domaine** | **Change** |

> ⚠️ Si `Utilisateurs du domaine` n'a pas `Change` sur Department$ et Public$, les lecteurs S: et P: ne se monteront pas !

### Correction si nécessaire

```powershell
# 1. Permissions SMB
Grant-SmbShareAccess -Name "Department$" -AccountName "HQ\Utilisateurs du domaine" -AccessRight Change -Force
Grant-SmbShareAccess -Name "Public$" -AccountName "HQ\Utilisateurs du domaine" -AccessRight Change -Force

# 2. Permissions NTFS sur dossiers racines (OBLIGATOIRE)
$domainUsers = New-Object System.Security.Principal.NTAccount("HQ", "Utilisateurs du domaine")

$acl = Get-Acl "D:\shares\Department"
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule($domainUsers, "ReadAndExecute,ListDirectory", "ContainerInherit,ObjectInherit", "None", "Allow")
$acl.AddAccessRule($rule)
Set-Acl "D:\shares\Department" $acl

$acl = Get-Acl "D:\shares\Public"
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule($domainUsers, "ReadAndExecute,ListDirectory", "ContainerInherit,ObjectInherit", "None", "Allow")
$acl.AddAccessRule($rule)
Set-Acl "D:\shares\Public" $acl
```

### Accès

```powershell
Test-Path "\\hq.wsl2025.org\users$"
Test-Path "\\HQDCSRV\Department$"
Test-Path "\\HQDCSRV\Public$"
```

**Attendu** : `True` pour les trois

---

## ✅ 8. GPO (Vérification GUI)

### 8.1 Ouvrir gpmc.msc

1. **Win+R** → `gpmc.msc` → Entrée
2. **Forêt: wsl2025.org** → **Domaines** → **hq.wsl2025.org** → **Objets de stratégie de groupe**

### 8.2 Vérifier chaque GPO

| GPO                            | Vérification GUI                                                                                                                                                                                                    |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Deploy-Certificates**        | Clic droit → Modifier → `Config ordinateur > Stratégies > Paramètres Windows > Paramètres de sécurité > Stratégies de clé publique` → ✅ WSFR-ROOT-CA dans Racines de confiance, ✅ WSFR-SUB-CA dans Intermédiaires |
| **Certificate-Autoenrollment** | Même chemin → ✅ "Inscription automatique" = Activé (Ordinateur ET Utilisateur)                                                                                                                                     |
| **Edge-Homepage-Intranet**     | `Config ordinateur > Stratégies > Modèles d'administration > Microsoft Edge > Démarrage...` → ✅ URL configurée                                                                                                     |
| **Block-ControlPanel**         | `Config utilisateur > Stratégies > Modèles d'administration > Panneau de configuration` → ✅ "Interdire l'accès" = Activé                                                                                           |
| **Enterprise-Logo**            | `Config ordinateur > Stratégies > Modèles d'administration > Panneau de configuration > Personnalisation` → ✅ "Forcer image écran verrouillage" = Activé avec chemin                                               |
| **Drive-Mappings**             | `Config utilisateur > Stratégies > Paramètres Windows > Scripts > Ouverture de session` → ✅ MapDrives.bat présent                                                                                                  |

### 8.3 Vérifier l'exclusion IT sur Block-ControlPanel

1. Clic sur **Block-ControlPanel**
2. Onglet **Délégation** → **Avancé...**
3. ✅ Groupe **IT** avec **Refuser** sur "Appliquer la stratégie de groupe"

### 8.4 Vérifier les fichiers NETLOGON

```powershell
# Vérifier le script de mappage
Test-Path "\\hq.wsl2025.org\NETLOGON\MapDrives.bat"

# Vérifier le logo
Test-Path "\\hq.wsl2025.org\NETLOGON\Logo\logo.jpg"
```

**Attendu** : `True` pour les deux

---

## ✅ 9. NTP (Synchronisation avec HQINFRASRV)

### Vérifier la source NTP

```powershell
# Source actuelle
w32tm /query /source
```

**Attendu** : `hqinfrasrv.wsl2025.org`

### Vérifier le statut

```powershell
# Statut de synchronisation
w32tm /query /status
```

**Attendu** :
- Leap Indicator: 0 (pas d'avertissement)
- Stratum: 2 ou 3
- Source: hqinfrasrv.wsl2025.org

### Tester la connexion

```powershell
# Test de connexion au serveur NTP
w32tm /stripchart /computer:hqinfrasrv.wsl2025.org /samples:3
```

**Attendu** : Réponses avec offset en millisecondes (pas d'erreur)

### Configuration si nécessaire

```powershell
# Configurer HQINFRASRV comme source NTP
w32tm /config /manualpeerlist:"hqinfrasrv.wsl2025.org" /syncfromflags:manual /reliable:yes /update
Restart-Service w32time
w32tm /resync
```

---

## 📋 Checklist finale HQDCSRV

| #   | Test                          | Résultat |
| --- | ----------------------------- | -------- |
| 1   | Hostname = HQDCSRV            | ⬜       |
| 2   | Domaine hq.wsl2025.org        | ⬜       |
| 3   | Trust avec wsl2025.org        | ⬜       |
| 4   | OUs créées                    | ⬜       |
| 5   | 4 utilisateurs HQ             | ⬜       |
| 6   | 1000 wslusr provisionnés      | ⬜       |
| 7   | Zone DNS hq.wsl2025.org       | ⬜       |
| 8   | Service ADCS running          | ⬜       |
| 9   | Extensions CDP/AIA dans SubCA | ⬜       |
| 10  | Templates publiés             | ⬜       |
| 11  | CRL accessible HTTP           | ⬜       |
| 12  | Volume D: RAID-5              | ⬜       |
| 13  | Partages SMB                  | ⬜       |
| 14  | 6 GPO créées                  | ⬜       |
| 15  | NTP synchro HQINFRASRV        | ⬜       |

---

# 🖥️ Tests sur HQCLT (Client)

## Utilisateurs disponibles

| Utilisateur    | Département | Type         | Mot de passe |
| -------------- | ----------- | ------------ | ------------ |
| `hq\npresso`   | Direction   | Normal       | `P@ssw0rd`   |
| `hq\jticipe`   | Factory     | Normal       | `P@ssw0rd`   |
| `hq\vtim`      | **IT**      | **IT/Admin** | `P@ssw0rd`   |
| `hq\rola`      | Sales       | Normal       | `P@ssw0rd`   |
| `hq\wslusr001` | AUTO        | Normal       | `P@ssw0rd`   |

> ⚠️ Adapter les noms selon tes utilisateurs réels :
>
> ```powershell
> Get-ADUser -Filter * -SearchBase "OU=Users,OU=HQ,DC=hq,DC=wsl2025,DC=org" | Select SamAccountName, Name
> ```

---

## 🔧 Préparation HQCLT

```powershell
gpupdate /force
Restart-Computer
```

---

## ✅ Test 1 : Certificats Root et Sub CA

### Utilisateur : `hq\administrateur`

1. Ouvrir **`certlm.msc`** (Win+R → certlm.msc)
2. **Autorités de certification racines de confiance** → Certificats
3. ✅ **WSFR-ROOT-CA** visible
4. **Autorités de certification intermédiaires** → Certificats
5. ✅ **WSFR-SUB-CA** visible

### PowerShell :

```powershell
Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.Subject -like "*WSFR*" }
Get-ChildItem Cert:\LocalMachine\CA | Where-Object { $_.Subject -like "*WSFR*" }
```

---

## ✅ Test 2 : Certificat Machine Auto-enrollé

### Utilisateur : `hq\administrateur`

1. Ouvrir **`certlm.msc`**
2. **Personnel** → Certificats
3. ✅ Certificat `HQCLT.hq.wsl2025.org` émis par **WSFR-SUB-CA**

### PowerShell :

```powershell
Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Issuer -like "*WSFR-SUB-CA*" }
```

---

## ✅ Test 3 : Page d'accueil Edge

### Utilisateur : `hq\wslusr001` (P@ssw0rd)

1. Se connecter
2. Ouvrir **Microsoft Edge**
3. ✅ Page d'accueil = `http://hqmailsrv.wsl2025.org` (ou URL configurée)

---

## ✅ Test 4a : Panneau de configuration BLOQUÉ

### Utilisateur : `hq\wslusr001` ou `hq\npresso` ou `hq\jticipe` ou `hq\rola`

> ⚠️ N'importe qui **SAUF IT**

1. Se connecter
2. Appuyer **Win + I**
3. ✅ Message : **"Cette opération a été annulée en raison de restrictions..."**

---

## ✅ Test 4b : Panneau de configuration OK (IT)

### Utilisateur : `hq\vtim` (Vincent TIM - département IT)

> ⚠️ **Prérequis** : Le groupe IT doit avoir "Deny Apply Group Policy" sur la GPO Block-ControlPanel (voir doc section 8.4)

1. Se déconnecter
2. Se connecter avec `hq\vtim` / `P@ssw0rd`
3. Appuyer **Win + I**
4. ✅ Paramètres **S'OUVRE normalement**

### Si ça ne fonctionne pas :

Vérifier sur HQDCSRV :

```powershell
Get-GPPermission -Name "Block-ControlPanel" -All | Format-Table Trustee, Permission, Denied
```

Le groupe `IT` doit avoir `Denied = True` pour `GpoApply`.

---

## ✅ Test 5 : Lecteurs Réseau

### Utilisateur : `hq\wslusr001`

1. Se connecter
2. Ouvrir **Explorateur** → **Ce PC**
3. ✅ Vérifier :

| Lecteur | Pointe vers       | Chemin UNC                          |
| ------- | ----------------- | ----------------------------------- |
| **U:**  | Dossier personnel | `\\hq.wsl2025.org\users$\wslusr001` |
| **S:**  | Département       | `\\HQDCSRV\Department$`             |
| **P:**  | Public            | `\\HQDCSRV\Public$`                 |

### PowerShell :

```powershell
Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Name -in @("U", "S", "P") }
```

### Si S: et P: ne se montent pas :

1. Vérifier les permissions SMB sur HQDCSRV (voir section 7)
2. Forcer le mappage manuel :

```cmd
net use S: \\HQDCSRV\Department$ /persistent:yes
net use P: \\HQDCSRV\Public$ /persistent:yes
```

Si "Accès refusé" → Les permissions SMB sont incorrectes sur le serveur.

---

## ✅ Test 6 : Home Folder

### Utilisateur : `hq\wslusr001`

1. Double-clic sur **U:**
2. Créer un fichier test (clic droit → Nouveau → Document texte)
3. ✅ Fichier créé avec succès

---

## ✅ Test 6b : Quota 20 Mo sur Home Drive

### Utilisateur : `hq\wslusr001`

> ✅ Le quota est configuré en **HardLimit** (blocage strict) - conforme au sujet

#### Test depuis le client (PowerShell Admin) :

```powershell
# Créer un fichier de 15 Mo (doit fonctionner)
fsutil file createnew U:\test15mo.bin 15728640

# Créer un fichier de 25 Mo (doit ÉCHOUER - quota dépassé)
fsutil file createnew U:\test25mo.bin 26214400
# Attendu : Erreur "Espace disque insuffisant" ou "Quota dépassé"

# Vérifier l'espace total utilisé
Get-ChildItem U:\ -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum |
    Select-Object @{N='TotalMo';E={[math]::Round($_.Sum/1MB,2)}}

# Nettoyer les fichiers de test
Remove-Item U:\test*.bin -Force
```

#### Vérification GUI sur HQDCSRV :

1. **Win+R** → `fsrm.msc` → Entrée
2. **Gestion de quota** → **Modèles de quotas**
3. ✅ Vérifier que **UserQuota20MB** existe avec :
   - Limite : 20 Mo
   - Type : **Limite inconditionnelle** (HardLimit)
4. **Gestion de quota** → **Quotas automatiques**
5. ✅ Vérifier que `D:\shares\datausers` a un quota automatique avec le modèle **UserQuota20MB**
6. **Gestion de quota** → **Quotas**
7. ✅ Vérifier que chaque dossier utilisateur a un quota de 20 Mo appliqué

#### Vérification PowerShell sur HQDCSRV :

```powershell
# Vérifier le template (SoftLimit = False = HardLimit)
Get-FsrmQuotaTemplate -Name "UserQuota20MB" | Select-Object Name, Size, SoftLimit

# Vérifier l'auto-quota
Get-FsrmAutoQuota -Path "D:\shares\datausers"

# Vérifier les quotas appliqués aux utilisateurs
Get-FsrmQuota -Path "D:\shares\datausers\*" | Format-Table Path, @{N='SizeMB';E={$_.Size/1MB}}, @{N='UsedMB';E={$_.Usage/1MB}}
```

**Attendu** :

- Template `UserQuota20MB` avec **SoftLimit = False** (HardLimit)
- Auto-quota sur `D:\shares\datausers`
- Chaque sous-dossier utilisateur a un quota de 20 Mo

> ⚠️ **Si les quotas ne sont pas appliqués aux dossiers existants** :
> L'auto-quota ne s'applique qu'aux NOUVEAUX sous-dossiers. Pour les dossiers existants :
>
> ```powershell
> Get-ChildItem "D:\shares\datausers" -Directory | ForEach-Object {
>     New-FsrmQuota -Path $_.FullName -Template "UserQuota20MB" -ErrorAction SilentlyContinue
> }
> ```

---

## ✅ Test 6c : Blocage des exécutables sur Home Drive

### Utilisateur : `hq\wslusr001`

```powershell
# Essayer de copier un .exe sur U: (doit échouer)
Copy-Item "C:\Windows\System32\calc.exe" "U:\calc.exe"
```

**Attendu** : ❌ Accès refusé / Opération bloquée

#### Vérification GUI sur HQDCSRV :

1. **Win+R** → `fsrm.msc` → Entrée
2. **Gestion du filtrage de fichiers** → **Filtres de fichiers**
3. ✅ Vérifier qu'un filtre existe sur `D:\shares\datausers` avec :
   - Type : **Filtrage actif**
   - Groupe de fichiers : **Fichiers exécutables** (ou Executables)

#### Vérification PowerShell sur HQDCSRV :

```powershell
Get-FsrmFileScreen -Path "D:\shares\datausers"
Get-FsrmFileGroup -Name "Fichiers exécutables"
```

---

## ✅ Test 7 : Logo Entreprise

### Utilisateur : N'importe lequel

1. Appuyer **Win + L** (verrouiller)
2. ✅ Logo visible sur l'écran de verrouillage

---

## 📊 Tableau récapitulatif HQCLT

| #   | Test                     | Utilisateur         | Résultat |
| --- | ------------------------ | ------------------- | -------- |
| 1   | Cert Root/Sub            | `hq\administrateur` | ✅       |
| 2   | Cert Machine             | `hq\administrateur` | ✅       |
| 3   | Edge Homepage            | `hq\wslusr001`      | ✅       |
| 4a  | Control Panel **BLOQUÉ** | `hq\wslusr001`      | ✅       |
| 4b  | Control Panel **OK**     | `hq\vtim` (IT)      | ✅       |
| 5   | Lecteurs U:, S:, P:      | `hq\wslusr001`      | ✅       |
| 6   | Home Folder écriture     | `hq\wslusr001`      | ✅       |
| 6b  | Quota 20 Mo              | `hq\wslusr001`      | ✅       |
| 6c  | Blocage .exe             | `hq\wslusr001`      | ✅       |
| 7   | Logo                     | N'importe           | ✅       |

> ✅ **Tous les tests HQCLT validés !** (14 décembre 2025)

---

## 🔄 Ordre des tests recommandé

1. **Redémarrer HQCLT** après `gpupdate /force`
2. Connexion **`hq\administrateur`** → Tests 1, 2
3. Déconnexion → Connexion **`hq\wslusr001`** → Tests 3, 4a, 5, 6, 6b, 6c
4. Déconnexion → Connexion **`hq\vtim`** → Test 4b
5. **Win+L** → Test 7
