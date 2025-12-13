# DCWSL - Contrôleur de Domaine Racine (Forest Root)

> **OS** : Windows Server 2022  
> **IP** : 10.4.10.4 (VLAN 10 - Servers)  
> **Rôles** : AD DS (Forest Root), DNS (Zone wsl2025.org), Global Catalog

---

## 📋 Prérequis

- [ ] Windows Server 2022 installé
- [ ] IP statique configurée
- [ ] Accès réseau vers DNSSRV (8.8.4.1) et le LAN

---

## 1️⃣ Configuration de base

### Hostname et IP

```powershell
# Renommer le serveur
Rename-Computer -NewName "DCWSL" -Restart

# Configuration IP statique (VLAN 10)
# Gateway = VIP HSRP des Core Switches
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 10.4.10.4 -PrefixLength 24 -DefaultGateway 10.4.10.254

# DNS temporaire (localhost + DNSSRV pour l'installation)
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 127.0.0.1, 8.8.4.1
```

---

## 2️⃣ Installation Active Directory

### Installer les rôles

```powershell
Install-WindowsFeature -Name AD-Domain-Services, DNS, RSAT-AD-Tools, RSAT-DNS-Server -IncludeManagementTools
```

### Promouvoir en Contrôleur de Domaine (Nouvelle Forêt)

```powershell
# Création de la forêt wsl2025.org
Install-ADDSForest `
    -DomainName "wsl2025.org" `
    -DomainNetbiosName "WSL2025" `
    -ForestMode WinThreshold `
    -DomainMode WinThreshold `
    -InstallDns:$true `
    -SafeModeAdministratorPassword (ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force) `
    -Force
```

---

## 3️⃣ Configuration DNS

### Forwarder (Redirection)

Les requêtes inconnues (Internet) doivent être envoyées à **DNSSRV**.

```powershell
# Supprimer les Root Hints par défaut si nécessaire
# Ajouter le Forwarder vers DNSSRV
Add-DnsServerForwarder -IPAddress 8.8.4.1 -PassThru
```

### Création des Enregistrements (Sujet 3.2 - DCWSL)

Conformément au sujet, nous devons créer les enregistrements pour l'infrastructure.

```powershell
$Zone = "wsl2025.org"

# --- Serveurs HQ ---
Add-DnsServerResourceRecordA -ZoneName $Zone -Name "hqinfrasrv" -IPv4Address "10.4.10.2"
Add-DnsServerResourceRecordA -ZoneName $Zone -Name "dcwsl" -IPv4Address "10.4.10.4"
Add-DnsServerResourceRecordA -ZoneName $Zone -Name "hqmailsrv" -IPv4Address "10.4.10.3"

# --- Firewall & Services Publics (DMZ / NAT) ---
# HQFWSRV : IP DMZ (217.4.160.1 selon plan)
Add-DnsServerResourceRecordA -ZoneName $Zone -Name "hqfwsrv" -IPv4Address "217.4.160.1"

# Alias Web
Add-DnsServerResourceRecordCName -ZoneName $Zone -Name "www" -HostNameAlias "hqfwsrv.wsl2025.org"
Add-DnsServerResourceRecordCName -ZoneName $Zone -Name "webmail" -HostNameAlias "hqmailsrv.wsl2025.org"

# VPN (IP Publique NAT)
Add-DnsServerResourceRecordA -ZoneName $Zone -Name "vpn" -IPv4Address "191.4.157.33"

# --- Infrastructure Réseau ---
# Switches (VLAN 99 - Mgmt)
Add-DnsServerResourceRecordA -ZoneName $Zone -Name "accsw1" -IPv4Address "10.4.99.11"
Add-DnsServerResourceRecordA -ZoneName $Zone -Name "accsw2" -IPv4Address "10.4.99.12"
Add-DnsServerResourceRecordA -ZoneName $Zone -Name "coresw1" -IPv4Address "10.4.99.253"
Add-DnsServerResourceRecordA -ZoneName $Zone -Name "coresw2" -IPv4Address "10.4.99.252"

# Routeurs (IPs d'interconnexion ou Loopback selon topologie)
# Edge1/2 (VLAN 100/200 côté LAN ou IP d'interco)
Add-DnsServerResourceRecordA -ZoneName $Zone -Name "edge1" -IPv4Address "10.4.254.1"
Add-DnsServerResourceRecordA -ZoneName $Zone -Name "edge2" -IPv4Address "10.4.254.5"

# WAN Router (Lien MAN)
Add-DnsServerResourceRecordA -ZoneName $Zone -Name "wanrtr" -IPv4Address "10.116.4.2"

# Remote Firewall (Lien MAN)
Add-DnsServerResourceRecordA -ZoneName $Zone -Name "remfw" -IPv4Address "10.4.100.126"
```

### DNSSEC

Signer la zone wsl2025.org avec DNSSEC :

```powershell
# Vérifier si la zone est déjà signée
Get-DnsServerZone -Name "wsl2025.org" | Select-Object ZoneName, IsSigned, KeyMasterServer

# Si pas encore signée, signer avec les paramètres par défaut
Invoke-DnsServerZoneSign -ZoneName "wsl2025.org" -SignWithDefault -Force
```

#### ✅ Vérification DNSSEC

```powershell
# Vérifier que la zone est signée
Get-DnsServerZone -Name "wsl2025.org" | Select-Object ZoneName, IsSigned
# Résultat attendu : IsSigned = True

# Vérifier les clés de signature
Get-DnsServerSigningKey -ZoneName "wsl2025.org"
```

> ⚠️ **Note** : Si la zone est déjà signée, la commande retournera une erreur indiquant que la zone est déjà signée. C'est normal.

---

## 4️⃣ Vérifications

### ✅ Vérification Active Directory

```powershell
# Vérifier le domaine
Get-ADDomain
# Résultat attendu : Name = wsl2025, DNSRoot = wsl2025.org

# Vérifier la forêt
Get-ADForest
# Résultat attendu : RootDomain = wsl2025.org

# Vérifier le Global Catalog
Get-ADDomainController | Select-Object Name, IsGlobalCatalog
```

### ✅ Vérification DNS

```powershell
# Vérifier la zone
Get-DnsServerZone -Name "wsl2025.org"

# Vérifier tous les enregistrements
Get-DnsServerResourceRecord -ZoneName "wsl2025.org" | Format-Table RecordType, HostName -AutoSize

# Test de résolution
Resolve-DnsName hqinfrasrv.wsl2025.org
Resolve-DnsName www.wsl2025.org
Resolve-DnsName vpn.wsl2025.org
```

### Tableau récapitulatif

| Test            | Commande PowerShell                 | Résultat Attendu    |
| --------------- | ----------------------------------- | ------------------- |
| Domaine         | `Get-ADDomain`                      | `wsl2025.org`       |
| DNS Local       | `Resolve-DnsName dcwsl.wsl2025.org` | `10.4.10.4`         |
| DNS Forward     | `Resolve-DnsName google.com`        | Réponse via 8.8.4.1 |
| Enregistrements | `Resolve-DnsName vpn.wsl2025.org`   | `191.4.157.33`      |

---

## 📋 Checklist finale

- [ ] Serveur renommé DCWSL
- [ ] IP statique configurée (10.4.10.4/24, Gateway 10.4.10.254)
- [ ] Forêt wsl2025.org créée
- [ ] DNS zone wsl2025.org configurée
- [ ] 15 enregistrements DNS créés
- [ ] Forwarder vers DNSSRV (8.8.4.1)
- [ ] DNSSEC activé (zone signée)

---

## 📝 Notes

- **IP** : 10.4.10.4
- C'est le serveur DNS faisant autorité pour tout le domaine racine.
- Les sous-domaines `hq.wsl2025.org` (HQDCSRV) et `rem.wsl2025.org` (REMDCSRV) seront délégués ou gérés directement par leurs contrôleurs respectifs qui forwarderont vers DCWSL.
