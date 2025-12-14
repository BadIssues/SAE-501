# REMINFRASRV - Serveur Infrastructure Remote

> **OS** : Windows Server 2022  
> **IP** : 10.4.100.2/25  
> **Gateway** : 10.4.100.126 (REMFW)  
> **Rôles** : AD Member, DNS Secondary, DHCP Failover, DFS Namespace

---

## 📋 Prérequis

- [ ] Windows Server 2022 installé
- [ ] REMDCSRV opérationnel (10.4.100.1) avec domaine `rem.wsl2025.org`
- [ ] Partages `users` et `Department` créés sur REMDCSRV
- [ ] Connectivité avec le site HQ
- [ ] **Carte réseau "Portail Captif" désactivée** (si présente)

> ⚠️ **IMPORTANT - Carte Portail Captif** : Si une carte réseau "Portail Captif" est activée sur le serveur, **la désactiver** avant de commencer la configuration.

> **Sujet** :
>
> ```
> REMINFRASRV is a Active Directory Domain Member
> This server provide fault tolerance in the Remote Site for different services: DNS, DHCP, DFS
> Create a DFS Domain root with REMINFRASRV
> ```

---

## 1️⃣ Configuration de base

### 1.1 Renommer le serveur

#### PowerShell

```powershell
Rename-Computer -NewName "REMINFRASRV" -Restart
```

#### GUI

1. **Win+R** → `sysdm.cpl` → Entrée
2. Onglet **Nom de l'ordinateur** → **Modifier...**
3. **Nom de l'ordinateur** : `REMINFRASRV`
4. **OK** → Redémarrer

---

### 1.2 Configuration IP

#### PowerShell

```powershell
New-NetIPAddress -InterfaceAlias "Ethernet0" -IPAddress 10.4.100.2 -PrefixLength 25 -DefaultGateway 10.4.100.126
Set-DnsClientServerAddress -InterfaceAlias "Ethernet0" -ServerAddresses 10.4.100.1
```

#### GUI

1. **Panneau de configuration** → **Centre Réseau et partage** → **Modifier les paramètres de la carte**
2. Clic droit sur **Ethernet0** → **Propriétés**
3. Double-clic sur **Protocole Internet version 4 (TCP/IPv4)**
4. Configurer :
   - ✅ **Utiliser l'adresse IP suivante**
   - **Adresse IP** : `10.4.100.2`
   - **Masque** : `255.255.255.128`
   - **Passerelle** : `10.4.100.126`
   - ✅ **Utiliser l'adresse de serveur DNS suivante**
   - **DNS préféré** : `10.4.100.1`
5. **OK** → **Fermer**

---

## 2️⃣ Joindre le domaine

#### PowerShell

```powershell
Add-Computer -DomainName "rem.wsl2025.org" -Credential (Get-Credential) -Restart
```

#### GUI

1. **Win+R** → `sysdm.cpl` → Entrée
2. Onglet **Nom de l'ordinateur** → **Modifier...**
3. ✅ **Membre d'un : Domaine** → `rem.wsl2025.org`
4. **OK** → Entrer les credentials `REM\Administrateur` ou `WSL2025\Administrateur`
5. **OK** → Redémarrer

---

## 3️⃣ Installation des rôles

#### PowerShell

```powershell
Install-WindowsFeature -Name DNS, DHCP, FS-DFS-Namespace, FS-DFS-Replication -IncludeManagementTools
```

#### GUI (Server Manager)

1. Ouvrir **Server Manager**
2. **Gérer** → **Ajouter des rôles et fonctionnalités**
3. **Suivant** jusqu'à **Rôles de serveurs**
4. Cocher :
   - ✅ **Serveur DHCP**
   - ✅ **Serveur DNS**
5. **Suivant** jusqu'à **Fonctionnalités**
6. Développer **Services de fichiers et de stockage** → **Services de fichiers et iSCSI** :
   - ✅ **Espaces de noms DFS**
   - ✅ **Réplication DFS**
7. **Suivant** → **Installer**
8. Redémarrer si demandé

---

## 4️⃣ DNS Secondary

> **Sujet** : "Fault tolerance for DNS" - REMINFRASRV héberge des zones secondaires.

### 4.1 Autoriser les transferts sur REMDCSRV (Prérequis)

> ⚠️ **Sur REMDCSRV**, autoriser les transferts de zone vers REMINFRASRV :

```powershell
# Sur REMDCSRV
Set-DnsServerPrimaryZone -Name "rem.wsl2025.org" -SecureSecondaries TransferToSecureServers -SecondaryServers 10.4.100.2
```

**Ou en GUI sur REMDCSRV** :
1. Ouvrir **DNS Manager** (`dnsmgmt.msc`)
2. Clic droit sur la zone `rem.wsl2025.org` → **Propriétés**
3. Onglet **Transferts de zone** → ✅ Cocher **Autoriser les transferts de zone**
4. Sélectionner **Uniquement vers les serveurs suivants** → Ajouter `10.4.100.2`
5. **OK**

---

### 4.2 Créer les zones secondaires sur REMINFRASRV

#### PowerShell

```powershell
# Ajouter la zone secondaire rem.wsl2025.org
Add-DnsServerSecondaryZone -Name "rem.wsl2025.org" -ZoneFile "rem.wsl2025.org.dns" -MasterServers 10.4.100.1

# Forwarder vers REMDCSRV
Add-DnsServerForwarder -IPAddress 10.4.100.1
```

#### GUI (DNS Manager)

1. Ouvrir **DNS Manager** (`dnsmgmt.msc`)
2. Clic droit sur **Zones de recherche directe** → **Nouvelle zone...**
3. **Type de zone** : ✅ **Zone secondaire** → **Suivant**
4. **Nom de la zone** : `rem.wsl2025.org` → **Suivant**
5. **Serveurs maîtres** : Ajouter `10.4.100.1` → **Suivant**
6. **Terminer**

**Configurer le redirecteur** :
1. Clic droit sur **REMINFRASRV** (racine) → **Propriétés**
2. Onglet **Redirecteurs** → **Modifier...**
3. Ajouter : `10.4.100.1`
4. **OK**

---

## 5️⃣ DHCP Failover

> **Sujet** : "Fault tolerance for DHCP" - Failover avec REMDCSRV.

### 5.1 Autoriser le serveur DHCP dans AD

#### PowerShell

```powershell
Add-DhcpServerInDC -DnsName "reminfrasrv.rem.wsl2025.org" -IPAddress 10.4.100.2
```

#### GUI

1. Ouvrir **DHCP** (`dhcpmgmt.msc`)
2. Clic droit sur **DHCP** → **Gérer les serveurs autorisés...**
3. Cliquer **Autoriser**
4. Entrer : `reminfrasrv.rem.wsl2025.org`
5. **OK**

---

### 5.2 Configurer le Failover (Sur REMDCSRV !)

> ⚠️ **Exécuter cette commande sur REMDCSRV**, pas sur REMINFRASRV !

#### PowerShell (sur REMDCSRV)

```powershell
Add-DhcpServerv4Failover -Name "REM-Failover" `
    -PartnerServer "reminfrasrv.rem.wsl2025.org" `
    -ScopeId 10.4.100.0 `
    -LoadBalancePercent 50 `
    -SharedSecret "P@ssw0rd" `
    -Force
```

#### GUI (sur REMDCSRV)

1. Ouvrir **DHCP** (`dhcpmgmt.msc`) sur **REMDCSRV**
2. Développer **IPv4** → Clic droit sur le scope **Remote-Clients** → **Configurer le basculement...**
3. **Suivant**
4. **Ajouter un serveur** → Entrer `reminfrasrv.rem.wsl2025.org` → **OK**
5. **Mode** : ✅ **Équilibrage de charge** (50%)
6. **Secret partagé** : `P@ssw0rd`
7. **Suivant** → **Terminer**

### 5.3 Vérification DHCP Failover

```powershell
# Sur REMDCSRV ou REMINFRASRV
Get-DhcpServerv4Failover
Get-DhcpServerv4Scope
```

---

## 6️⃣ DFS Namespace (Création du Domain Root)

> **Sujet** : "Create a DFS Domain root with REMINFRASRV"
>
> C'est REMINFRASRV qui héberge le namespace DFS. Les partages réels sont sur REMDCSRV.

### 6.1 Créer le dossier racine DFS

```powershell
# Créer le dossier pour la racine DFS
New-Item -Path "C:\DFSRoots\files" -ItemType Directory -Force

# Partager le dossier racine
New-SmbShare -Name "files" -Path "C:\DFSRoots\files" -FullAccess "Tout le monde"
```

### 6.2 Créer le Namespace DFS Domain-based

```powershell
# Créer le namespace DFS (Domain-based V2)
New-DfsnRoot -TargetPath "\\reminfrasrv.rem.wsl2025.org\files" `
    -Type DomainV2 `
    -Path "\\rem.wsl2025.org\files"

# Vérifier
Get-DfsnRoot -Path "\\rem.wsl2025.org\files"
```

### 6.3 Ajouter les liens vers les partages REMDCSRV

```powershell
# Lien vers Home Drives (users)
New-DfsnFolder -Path "\\rem.wsl2025.org\users" `
    -TargetPath "\\remdcsrv.rem.wsl2025.org\users"

# Lien vers Department
New-DfsnFolder -Path "\\rem.wsl2025.org\Department" `
    -TargetPath "\\remdcsrv.rem.wsl2025.org\Department"

# Vérifier
Get-DfsnFolder -Path "\\rem.wsl2025.org\*"
```

### 6.4 Vérification DFS

```powershell
# Lister le namespace
Get-DfsnRoot -Path "\\rem.wsl2025.org\files"

# Lister les dossiers
Get-DfsnFolder -Path "\\rem.wsl2025.org\*"

# Tester l'accès
Test-Path "\\rem.wsl2025.org\users"
Test-Path "\\rem.wsl2025.org\Department"
```

### 6.5 GUI - Créer le Namespace DFS (Alternative)

1. Ouvrir **Server Manager** → **Outils** → **Gestion du système de fichiers distribués DFS**
2. Clic droit sur **Espaces de noms** → **Nouvel espace de noms...**
3. **Serveur** : `REMINFRASRV` → **Suivant**
4. **Nom** : `files` → **Suivant**
5. **Type** : ✅ **Espace de noms de domaine** → **Suivant**
6. **Créer**

Ensuite, ajouter les dossiers :

1. Clic droit sur `\\rem.wsl2025.org\files` → **Nouveau dossier...**
2. **Nom** : `users`
3. **Cibles** : Cliquer **Ajouter** → `\\remdcsrv.rem.wsl2025.org\users`
4. Répéter pour `Department`

---

## 7️⃣ DFS Replication (Optionnel - Tolérance de panne)

> ⚠️ **Note** : La réplication DFS synchronise les données entre REMDCSRV et REMINFRASRV pour la haute disponibilité. C'est optionnel selon le niveau de détail du sujet.

### 7.1 Créer les dossiers locaux sur REMINFRASRV

```powershell
New-Item -Path "C:\shares\datausers" -ItemType Directory -Force
New-Item -Path "C:\shares\Department" -ItemType Directory -Force
```

### 7.2 Créer les partages locaux (pour réplication)

```powershell
New-SmbShare -Name "users-local" -Path "C:\shares\datausers" -FullAccess "Tout le monde"
New-SmbShare -Name "Department-local" -Path "C:\shares\Department" -FullAccess "Tout le monde"
```

### 7.3 Configurer la réplication DFS

```powershell
# Créer le groupe de réplication pour users
New-DfsReplicationGroup -GroupName "REM-Users-Replication"
Add-DfsrMember -GroupName "REM-Users-Replication" -ComputerName "remdcsrv.rem.wsl2025.org", "reminfrasrv.rem.wsl2025.org"
New-DfsReplicatedFolder -GroupName "REM-Users-Replication" -FolderName "users"

# Configurer la connexion bidirectionnelle
Add-DfsrConnection -GroupName "REM-Users-Replication" `
    -SourceComputerName "remdcsrv.rem.wsl2025.org" `
    -DestinationComputerName "reminfrasrv.rem.wsl2025.org"

# Définir les chemins et le membre primaire
Set-DfsrMembership -GroupName "REM-Users-Replication" -FolderName "users" `
    -ComputerName "remdcsrv.rem.wsl2025.org" `
    -ContentPath "C:\shares\datausers" `
    -PrimaryMember $true

Set-DfsrMembership -GroupName "REM-Users-Replication" -FolderName "users" `
    -ComputerName "reminfrasrv.rem.wsl2025.org" `
    -ContentPath "C:\shares\datausers"
```

### 7.4 Ajouter REMINFRASRV comme cible failover

```powershell
# Ajouter une deuxième cible au namespace (failover)
New-DfsnFolderTarget -Path "\\rem.wsl2025.org\users" `
    -TargetPath "\\reminfrasrv.rem.wsl2025.org\users-local"

New-DfsnFolderTarget -Path "\\rem.wsl2025.org\Department" `
    -TargetPath "\\reminfrasrv.rem.wsl2025.org\Department-local"
```

---

## ✅ Vérifications

```powershell
# === DOMAINE ===
(Get-WmiObject Win32_ComputerSystem).Domain
# Attendu : rem.wsl2025.org

# === DNS ===
Resolve-DnsName reminfrasrv.rem.wsl2025.org
Get-DnsServerZone
# Attendu : Zones secondaires rem.wsl2025.org

# === DHCP ===
Get-DhcpServerInDC
Get-DhcpServerv4Failover
# Attendu : Failover avec REMDCSRV

# === DFS NAMESPACE ===
Get-DfsnRoot -Path "\\rem.wsl2025.org\files"
Get-DfsnFolder -Path "\\rem.wsl2025.org\*"
# Attendu : Namespace avec users et Department

# === ACCÈS ===
Test-Path "\\rem.wsl2025.org\users"
Test-Path "\\rem.wsl2025.org\Department"
# Attendu : True
```

| Élément       | Attendu                 | Commande                                      |
| ------------- | ----------------------- | --------------------------------------------- |
| Domaine       | rem.wsl2025.org         | `(Get-WmiObject Win32_ComputerSystem).Domain` |
| DNS Zones     | Secondaires             | `Get-DnsServerZone`                           |
| DHCP Failover | Actif                   | `Get-DhcpServerv4Failover`                    |
| DFS Namespace | \\rem.wsl2025.org\files | `Get-DfsnRoot`                                |
| DFS Folders   | users, Department       | `Get-DfsnFolder -Path "\\rem.wsl2025.org\*"`  |

---

## 📝 Notes

- **IP** : 10.4.100.2/25
- Ce serveur assure la **tolérance de panne** pour DNS, DHCP et DFS
- Le **namespace DFS** (`\\rem.wsl2025.org\...`) est hébergé sur ce serveur
- Les **données** restent sur REMDCSRV (ou répliquées si DFS-R configuré)
- En cas de panne de REMDCSRV, ce serveur peut prendre le relais

---

## 🔗 Dépendances

| Machine  | Requis pour                  |
| -------- | ---------------------------- |
| REMDCSRV | Partages users et Department |
| REMFW    | Connectivité réseau          |

---

## 🎯 Résumé des chemins DFS

| Chemin DFS (namespace)         | Cible réelle                            |
| ------------------------------ | --------------------------------------- |
| `\\rem.wsl2025.org\users`      | `\\remdcsrv.rem.wsl2025.org\users`      |
| `\\rem.wsl2025.org\Department` | `\\remdcsrv.rem.wsl2025.org\Department` |
