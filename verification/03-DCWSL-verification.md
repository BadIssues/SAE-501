# Vérification DCWSL - Contrôleur de Domaine Racine

> **Serveur** : DCWSL  
> **IP** : 10.4.10.4  
> **Rôles** : AD DS (Forest Root), DNS, Global Catalog

---

## ✅ 1. Configuration de base

### Hostname

```powershell
hostname
```

**Attendu** : `DCWSL`

### IP

```powershell
Get-NetIPAddress -InterfaceAlias "Ethernet*" | Where-Object { $_.AddressFamily -eq "IPv4" }
```

**Attendu** : `10.4.10.4/24`

### Gateway

```powershell
Get-NetRoute -DestinationPrefix "0.0.0.0/0"
```

**Attendu** : `10.4.10.254`

---

## ✅ 2. Active Directory

### Domaine

```powershell
Get-ADDomain | Select-Object Name, DNSRoot, NetBIOSName
```

**Attendu** :
- Name : `wsl2025`
- DNSRoot : `wsl2025.org`
- NetBIOSName : `WSL2025`

### Forêt

```powershell
Get-ADForest | Select-Object Name, RootDomain, ForestMode
```

**Attendu** :
- RootDomain : `wsl2025.org`
- ForestMode : `Windows2016Forest` ou supérieur

### Global Catalog

```powershell
Get-ADDomainController | Select-Object Name, IsGlobalCatalog
```

**Attendu** : `IsGlobalCatalog = True`

---

## ✅ 3. DNS

### Zone wsl2025.org

```powershell
Get-DnsServerZone -Name "wsl2025.org"
```

**Attendu** : Zone existe et est `Primary`

### Forwarder

```powershell
Get-DnsServerForwarder
```

**Attendu** : `8.8.4.1` (DNSSRV)

### Enregistrements DNS

```powershell
# Tester les résolutions
Resolve-DnsName dcwsl.wsl2025.org
Resolve-DnsName hqinfrasrv.wsl2025.org
Resolve-DnsName vpn.wsl2025.org
Resolve-DnsName www.wsl2025.org
```

**Attendu** :
| Nom | IP |
|-----|-----|
| dcwsl.wsl2025.org | 10.4.10.4 |
| hqinfrasrv.wsl2025.org | 10.4.10.2 |
| vpn.wsl2025.org | 191.4.157.33 |
| www.wsl2025.org | CNAME → hqfwsrv |

### DNSSEC

```powershell
Get-DnsServerZone -Name "wsl2025.org" | Select-Object ZoneName, IsSigned
```

**Attendu** : `IsSigned = True`

---

## ✅ 4. Résolution externe

```powershell
Resolve-DnsName google.com
```

**Attendu** : Résolution réussie (via forwarder 8.8.4.1)

---

## 📋 Checklist finale

| Test | Commande | Résultat |
|------|----------|----------|
| Hostname | `hostname` | ⬜ DCWSL |
| IP | `Get-NetIPAddress` | ⬜ 10.4.10.4 |
| Domaine | `Get-ADDomain` | ⬜ wsl2025.org |
| Global Catalog | `Get-ADDomainController` | ⬜ True |
| Zone DNS | `Get-DnsServerZone` | ⬜ wsl2025.org |
| Forwarder | `Get-DnsServerForwarder` | ⬜ 8.8.4.1 |
| DNSSEC | Zone signée | ⬜ True |
| Résolution externe | `Resolve-DnsName google.com` | ⬜ OK |
