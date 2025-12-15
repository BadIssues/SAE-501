# DCWSL - Contrôleur de Domaine Racine (Forest Root)

> **OS** : Windows Server 2022  
> **IP** : 10.4.10.4 (VLAN 10 - Servers)  
> **Rôles** : AD DS (Forest Root), DNS (Zone wsl2025.org), Global Catalog

---

## 🎯 Contexte (Sujet)

Ce serveur est la **racine de la forêt Active Directory** `wsl2025.org` :

| Service              | Description                                                                                               |
| -------------------- | --------------------------------------------------------------------------------------------------------- |
| **Active Directory** | Forest root, Global Catalog. Domaine parent de `hq.wsl2025.org` et `rem.wsl2025.org`.                     |
| **DNS**              | Zone `wsl2025.org` avec tous les enregistrements de l'infrastructure (serveurs, switches, routeurs, VPN). |
| **DNSSEC**           | Zone signée avec certificat.                                                                              |
| **Forwarder**        | Requêtes externes redirigées vers DNSSRV (8.8.4.1).                                                       |

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

---

## ✅ Vérification Finale

### 🔌 Comment se connecter à DCWSL

1. Ouvrir la console VMware ou Bureau à distance (RDP) vers `10.4.10.4`
2. Se connecter avec `Administrateur` / `P@ssw0rd`
3. Clic droit sur le bouton Windows → **Windows PowerShell (Admin)**
4. Tu dois voir le prompt : `PS C:\Users\Administrateur>`

---

### Test 1 : Vérifier Active Directory

**Étape 1** : Tape cette commande et appuie sur Entrée :
```powershell
Get-ADDomain | Format-List Name, DNSRoot, Forest
```

**Étape 2** : Regarde le résultat. Tu dois voir :
```
Name    : wsl2025
DNSRoot : wsl2025.org
Forest  : wsl2025.org
```

✅ **C'est bon si** : Tu vois exactement ces 3 valeurs
❌ **Problème si** : Erreur ou valeurs différentes

---

### Test 2 : Vérifier que c'est un Global Catalog

**Étape 1** : Tape cette commande :
```powershell
Get-ADDomainController | Format-List Name, IsGlobalCatalog
```

**Étape 2** : Regarde le résultat :
```
Name             : DCWSL
IsGlobalCatalog  : True
```

✅ **C'est bon si** : `IsGlobalCatalog` est `True`
❌ **Problème si** : `IsGlobalCatalog` est `False`

---

### Test 3 : Vérifier la zone DNS

**Étape 1** : Tape cette commande :
```powershell
Get-DnsServerZone -Name "wsl2025.org" | Format-List ZoneName, ZoneType, IsSigned
```

**Étape 2** : Regarde le résultat :
```
ZoneName : wsl2025.org
ZoneType : Primary
IsSigned : True
```

✅ **C'est bon si** : `ZoneType` = `Primary` ET `IsSigned` = `True`
❌ **Problème si** : `IsSigned` = `False` → DNSSEC pas activé

---

### Test 4 : Vérifier les enregistrements DNS

**Étape 1** : Tape cette commande :
```powershell
Resolve-DnsName vpn.wsl2025.org
```

**Étape 2** : Regarde le résultat. Tu dois voir :
```
Name                     Type   TTL   Section    IPAddress
----                     ----   ---   -------    ---------
vpn.wsl2025.org          A      3600  Answer     191.4.157.33
```

✅ **C'est bon si** : L'IP est `191.4.157.33`
❌ **Problème si** : Erreur "DNS name does not exist" → Enregistrement manquant

**Étape 3** : Teste aussi les autres enregistrements :
```powershell
Resolve-DnsName www.wsl2025.org
Resolve-DnsName webmail.wsl2025.org
```

---

### Test 5 : Vérifier le forwarder DNS

**Étape 1** : Tape cette commande :
```powershell
Get-DnsServerForwarder | Format-List IPAddress
```

**Étape 2** : Regarde le résultat :
```
IPAddress : {8.8.4.1}
```

✅ **C'est bon si** : Tu vois `8.8.4.1` dans la liste
❌ **Problème si** : Liste vide ou autre IP

**Étape 3** : Teste la résolution externe :
```powershell
Resolve-DnsName google.com
```

✅ **C'est bon si** : Tu obtiens des IPs Google
❌ **Problème si** : Timeout → Forwarder ne fonctionne pas

---

### 📋 Résumé rapide (copie-colle tout d'un coup)

```powershell
Write-Host "=== DOMAINE ===" -ForegroundColor Cyan
(Get-ADDomain).DNSRoot

Write-Host "=== GLOBAL CATALOG ===" -ForegroundColor Cyan
(Get-ADDomainController).IsGlobalCatalog

Write-Host "=== ZONE DNS ===" -ForegroundColor Cyan
Get-DnsServerZone -Name "wsl2025.org" | Select-Object ZoneName, ZoneType, IsSigned

Write-Host "=== TEST DNS VPN ===" -ForegroundColor Cyan
(Resolve-DnsName vpn.wsl2025.org -ErrorAction SilentlyContinue).IPAddress

Write-Host "=== FORWARDER ===" -ForegroundColor Cyan
(Get-DnsServerForwarder).IPAddress.IPAddressToString
```

Tu peux copier-coller ce bloc entier. Chaque section doit afficher la bonne valeur.
