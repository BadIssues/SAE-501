# SAE 501 - Guide de Déploiement Infrastructure WSL2025

## 📋 Vue d'ensemble

Ce guide détaille les étapes de configuration pour l'infrastructure IT de WorldSkills Lyon 2025.

> ⚠️ **Note** : Le cœur de réseau (switches et routeurs) est déjà configuré et fonctionnel dans le dossier `realconf/`.

---

## 📁 Structure de la documentation

### 🌐 Site HQ (Siège)

| Fichier | Machine | Description |
|---------|---------|-------------|
| [01-HQINFRASRV.md](01-HQINFRASRV.md) | HQINFRASRV | DHCP, VPN OpenVPN, Stockage LVM, iSCSI, Samba |
| [02-HQMAILSRV.md](02-HQMAILSRV.md) | HQMAILSRV | ZFS, Mail SMTP/IMAP, Webmail, DHCP Failover |
| [03-DCWSL.md](03-DCWSL.md) | DCWSL | DNS racine, Active Directory Forest Root |
| [04-HQDCSRV.md](04-HQDCSRV.md) | HQDCSRV | AD Child Domain, PKI/ADCS, DNS, Stockage, GPO |
| [05-HQFWSRV.md](05-HQFWSRV.md) | HQFWSRV | Firewall nftables, NAT/PAT |
| [06-HQWEBSRV.md](06-HQWEBSRV.md) | HQWEBSRV | Serveur Web IIS, RDS |
| [07-HQCLT.md](07-HQCLT.md) | HQCLT | Client Windows 11 |
| [08-MGMTCLT.md](08-MGMTCLT.md) | MGMTCLT | Client Management, Ansible |

### 🏢 Site Remote (WSFR)

| Fichier | Machine | Description |
|---------|---------|-------------|
| [09-REMFW.md](09-REMFW.md) | REMFW | Firewall/Routeur ACL |
| [10-REMDCSRV.md](10-REMDCSRV.md) | REMDCSRV | AD Child Domain, DHCP, DNS, DFS |
| [11-REMINFRASRV.md](11-REMINFRASRV.md) | REMINFRASRV | AD Member, Failover services |
| [12-REMCLT.md](12-REMCLT.md) | REMCLT | Client Windows 11 |

### 🌍 Site Internet

| Fichier | Machine | Description |
|---------|---------|-------------|
| [13-DNSSRV.md](13-DNSSRV.md) | DNSSRV | DNS Public, Root CA |
| [14-INETSRV.md](14-INETSRV.md) | INETSRV | Web Docker HA, FTP |
| [15-VPNCLT.md](15-VPNCLT.md) | VPNCLT | Client VPN |
| [16-INETCLT.md](16-INETCLT.md) | INETCLT | Client Internet |

---

## 🔐 Informations communes

### Mot de passe par défaut
```
P@ssw0rd
```
> Note : Le zéro est entre le "w" et le "r"

### Domaines
- **Domaine racine** : `wsl2025.org`
- **Domaine HQ** : `hq.wsl2025.org`
- **Domaine Remote** : `rem.wsl2025.org`

### Systèmes d'exploitation
| Type | OS |
|------|-----|
| HQINFRASRV, HQMAILSRV, DNSSRV, INETSRV | Debian 13 CLI |
| MGMTCLT, INETCLT | Debian 13 GUI |
| HQDCSRV, HQWEBSRV, REMDCSRV, REMINFRASRV | Windows Server 2022 |
| HQCLT, REMCLT, VPNCLT | Windows 11 |

---

## 📊 Ordre de déploiement recommandé

### Phase 1 : Infrastructure de base
1. ✅ Cœur de réseau (DÉJÀ FAIT)
2. DNSSRV (Root CA + DNS public)
3. DCWSL (Forest Root AD)
4. HQDCSRV (Child Domain + Sub CA)

### Phase 2 : Services HQ
5. HQINFRASRV (DHCP, VPN, Stockage)
6. HQMAILSRV (Mail, Webmail)
7. HQFWSRV (Firewall)
8. HQWEBSRV (Web, RDS)

### Phase 3 : Site Remote
9. REMDCSRV (AD Remote)
10. REMINFRASRV (Failover)
11. REMFW (Firewall Remote)

### Phase 4 : Clients
12. HQCLT, REMCLT, MGMTCLT
13. VPNCLT, INETCLT
14. INETSRV (Web HA, FTP)

---

## 📝 Légende des statuts

- ⬜ À faire
- 🔄 En cours
- ✅ Terminé
- ❌ Problème

