# REMINFRASRV - Serveur Infrastructure Remote

> **OS** : Windows Server 2022  
> **IP** : 10.4.100.2 (VLAN Remote)  
> **Rôles** : AD Member, DNS Secondary, DHCP Failover, DFS

---

## 📋 Prérequis

- [ ] Windows Server 2022 installé
- [ ] REMDCSRV opérationnel (10.4.100.1)
- [ ] Connectivité avec le site HQ

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

## 6️⃣ DFS Namespace et Réplication

### Ajouter au namespace DFS existant
```powershell
# Créer les dossiers locaux
New-Item -Path "C:\shares\datausers" -ItemType Directory
New-Item -Path "C:\shares\Department" -ItemType Directory

# Partages
New-SmbShare -Name "users$" -Path "C:\shares\datausers" -FullAccess "Administrators" -ChangeAccess "Authenticated Users"
New-SmbShare -Name "Department$" -Path "C:\shares\Department" -FullAccess "Administrators"

# Ajouter comme cible DFS (failover)
New-DfsnFolderTarget -Path "\\rem.wsl2025.org\files\users" -TargetPath "\\reminfrasrv.rem.wsl2025.org\users$"
New-DfsnFolderTarget -Path "\\rem.wsl2025.org\files\Department" -TargetPath "\\reminfrasrv.rem.wsl2025.org\Department$"
```

### Configurer la réplication DFS
```powershell
# Créer le groupe de réplication
New-DfsReplicationGroup -GroupName "REM-Replication" | 
    New-DfsReplicatedFolder -FolderName "users" |
    Add-DfsrMember -ComputerName "remdcsrv.rem.wsl2025.org", "reminfrasrv.rem.wsl2025.org"

# Configurer la connexion
Add-DfsrConnection -GroupName "REM-Replication" -SourceComputerName "remdcsrv.rem.wsl2025.org" -DestinationComputerName "reminfrasrv.rem.wsl2025.org"

# Définir le dossier primaire
Set-DfsrMembership -GroupName "REM-Replication" -FolderName "users" -ComputerName "remdcsrv.rem.wsl2025.org" -ContentPath "C:\shares\datausers" -PrimaryMember $true
Set-DfsrMembership -GroupName "REM-Replication" -FolderName "users" -ComputerName "reminfrasrv.rem.wsl2025.org" -ContentPath "C:\shares\datausers"
```

---

## ✅ Vérifications

| Test | Commande |
|------|----------|
| DNS | `Resolve-DnsName reminfrasrv.rem.wsl2025.org` |
| DHCP | `Get-DhcpServerv4Failover` |
| DFS | `Get-DfsnFolder -Path "\\rem.wsl2025.org\files\*"` |
| Réplication | `Get-DfsrState` |

---

## 📝 Notes

- **IP** : 10.4.100.2
- Ce serveur assure la tolérance de panne pour DNS, DHCP et DFS
- En cas de panne de REMDCSRV, ce serveur prend le relais
- La réplication DFS synchronise les données entre les deux serveurs

