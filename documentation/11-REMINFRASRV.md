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
> ```
> REMINFRASRV is a Active Directory Domain Member
> This server provide fault tolerance in the Remote Site for different services: DNS, DHCP, DFS
> Create a DFS Domain root with REMINFRASRV
> ```

---

## 1️⃣ Configuration de base

### Hostname et IP
```powershell
Rename-Computer -NewName "REMINFRASRV" -Restart

# Configuration IP
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 10.4.100.2 -PrefixLength 25 -DefaultGateway 10.4.100.126
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 10.4.100.1, 10.4.10.1
```

---

## 2️⃣ Joindre le domaine

```powershell
Add-Computer -DomainName "rem.wsl2025.org" -Credential (Get-Credential) -Restart
```

---

## 3️⃣ Installation des rôles

```powershell
Install-WindowsFeature -Name DNS, DHCP, FS-DFS-Namespace, FS-DFS-Replication -IncludeManagementTools
```

---

## 4️⃣ DNS Secondary

### Configurer comme serveur DNS secondaire
```powershell
# Ajouter les zones secondaires
Add-DnsServerSecondaryZone -Name "rem.wsl2025.org" -ZoneFile "rem.wsl2025.org.dns" -MasterServers 10.4.100.1
Add-DnsServerSecondaryZone -Name "hq.wsl2025.org" -ZoneFile "hq.wsl2025.org.dns" -MasterServers 10.4.10.1

# Forwarder
Add-DnsServerForwarder -IPAddress 10.4.100.1
```

---

## 5️⃣ DHCP Failover

### Autoriser le serveur DHCP
```powershell
Add-DhcpServerInDC -DnsName "reminfrasrv.rem.wsl2025.org" -IPAddress 10.4.100.2
```

### Configurer le failover avec REMDCSRV
```powershell
# Sur REMDCSRV, configurer le failover
Add-DhcpServerv4Failover -Name "REM-Failover" `
    -PartnerServer "reminfrasrv.rem.wsl2025.org" `
    -ScopeId 10.4.100.0 `
    -LoadBalancePercent 50 `
    -SharedSecret "P@ssw0rd" `
    -Force
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

| Élément | Attendu | Commande |
|---------|---------|----------|
| Domaine | rem.wsl2025.org | `(Get-WmiObject Win32_ComputerSystem).Domain` |
| DNS Zones | Secondaires | `Get-DnsServerZone` |
| DHCP Failover | Actif | `Get-DhcpServerv4Failover` |
| DFS Namespace | \\rem.wsl2025.org\files | `Get-DfsnRoot` |
| DFS Folders | users, Department | `Get-DfsnFolder -Path "\\rem.wsl2025.org\*"` |

---

## 📝 Notes

- **IP** : 10.4.100.2/25
- Ce serveur assure la **tolérance de panne** pour DNS, DHCP et DFS
- Le **namespace DFS** (`\\rem.wsl2025.org\...`) est hébergé sur ce serveur
- Les **données** restent sur REMDCSRV (ou répliquées si DFS-R configuré)
- En cas de panne de REMDCSRV, ce serveur peut prendre le relais

---

## 🔗 Dépendances

| Machine | Requis pour |
|---------|-------------|
| REMDCSRV | Partages users et Department |
| REMFW | Connectivité réseau |

---

## 🎯 Résumé des chemins DFS

| Chemin DFS (namespace) | Cible réelle |
|------------------------|--------------|
| `\\rem.wsl2025.org\users` | `\\remdcsrv.rem.wsl2025.org\users` |
| `\\rem.wsl2025.org\Department` | `\\remdcsrv.rem.wsl2025.org\Department` |

