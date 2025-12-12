# SAE 501 - Guide de Déploiement Infrastructure WSL2025

## 📋 Vue d'ensemble

Ce guide détaille les étapes de configuration pour l'infrastructure IT de WorldSkills Lyon 2025.

> ⚠️ **Note** : Le cœur de réseau (switches et routeurs) est déjà configuré et fonctionnel dans le dossier `realconf/`.

> 📍 **Plan d'adressage** : N=4 (voir `realconf/PLAN-ADRESSAGE-IP.txt`)

---

## 📁 Structure de la documentation

### 🌐 Site HQ (Siège)

| Fichier | Machine | IP | Description |
|---------|---------|-----|-------------|
| [01-HQINFRASRV.md](01-HQINFRASRV.md) | HQINFRASRV | 10.4.10.2 | DHCP, VPN OpenVPN, Stockage LVM, iSCSI, Samba |
| [02-HQMAILSRV.md](02-HQMAILSRV.md) | HQMAILSRV | 10.4.10.3 | ZFS, Mail SMTP/IMAP, Webmail, DHCP Failover |
| [03-DCWSL.md](03-DCWSL.md) | DCWSL | 10.4.10.4 | DNS racine, Active Directory Forest Root |
| [04-HQDCSRV.md](04-HQDCSRV.md) | HQDCSRV | 10.4.10.1 | AD Child Domain, PKI/ADCS, DNS, Stockage, GPO |
| [05-HQFWSRV.md](05-HQFWSRV.md) | HQFWSRV | 217.4.160.1 / 10.4.10.5 | Firewall nftables, NAT/PAT |
| [06-HQWEBSRV.md](06-HQWEBSRV.md) | HQWEBSRV | 217.4.160.2 | Serveur Web IIS, RDS |
| [07-HQCLT.md](07-HQCLT.md) | HQCLT | DHCP | Client Windows 11 |
| [08-MGMTCLT.md](08-MGMTCLT.md) | MGMTCLT | 10.4.99.1 | Client Management, Ansible |

### 🏢 Site Remote (WSFR)

| Fichier | Machine | IP | Description |
|---------|---------|-----|-------------|
| [09-REMFW.md](09-REMFW.md) | REMFW | 10.116.4.1 / 10.4.100.126 | Firewall/Routeur ACL |
| [10-REMDCSRV.md](10-REMDCSRV.md) | REMDCSRV | 10.4.100.1 | AD Child Domain, DHCP, DNS, DFS |
| [11-REMINFRASRV.md](11-REMINFRASRV.md) | REMINFRASRV | 10.4.100.2 | AD Member, Failover services |
| [12-REMCLT.md](12-REMCLT.md) | REMCLT | DHCP | Client Windows 11 |

### 🌍 Site Internet

| Fichier | Machine | IP | Description |
|---------|---------|-----|-------------|
| [13-DNSSRV.md](13-DNSSRV.md) | DNSSRV | 8.8.4.1 | DNS Public, Root CA |
| [14-INETSRV.md](14-INETSRV.md) | INETSRV | 8.8.4.2 | Web Docker HA, FTP |
| [15-VPNCLT.md](15-VPNCLT.md) | VPNCLT | 8.8.4.3 | Client VPN |
| [16-INETCLT.md](16-INETCLT.md) | INETCLT | 8.8.4.4 | Client Internet |

---

## 🔐 Informations communes

### Mot de passe par défaut
```
P@ssw0rd
```
> Note : Le zéro est entre le "w" et le "r"

### Domaines
- **Domaine racine** : `wsl2025.org` (DCWSL)
- **Domaine HQ** : `hq.wsl2025.org` (HQDCSRV)
- **Domaine Remote** : `rem.wsl2025.org` (REMDCSRV)

### Systèmes d'exploitation
| Type | OS |
|------|-----|
| HQINFRASRV, HQMAILSRV, DNSSRV, INETSRV | Debian 13 CLI |
| MGMTCLT, INETCLT | Debian 13 GUI |
| HQDCSRV, HQWEBSRV, REMDCSRV, REMINFRASRV | Windows Server 2022 |
| HQCLT, REMCLT, VPNCLT | Windows 11 |

---

## 🌐 Plan d'adressage résumé

### VLANs HQ
| VLAN | Nom | Réseau | Gateway |
|------|-----|--------|---------|
| 10 | Servers | 10.4.10.0/24 | 10.4.10.254 |
| 20 | Clients | 10.4.20.0/23 | 10.4.20.254 |
| 30 | DMZ | 217.4.160.0/24 | 217.4.160.254 |
| 99 | Management | 10.4.99.0/24 | 10.4.99.254 |

### Site Remote
| Réseau | Description |
|--------|-------------|
| 10.4.100.0/25 | Clients Remote |
| 10.116.4.0/30 | Lien MAN WANRTR-REMFW |

### Internet
| Réseau | Description |
|--------|-------------|
| 8.8.4.0/29 | Serveurs Internet |
| 191.4.157.32/28 | Provider Independent (VPN, Webmail) |

---

## 📊 Ordre de déploiement recommandé

### Phase 1 : Infrastructure de base
1. ✅ Cœur de réseau (DÉJÀ FAIT)
2. ⬜ DNSSRV (Root CA + DNS public)
3. ⬜ DCWSL (Forest Root AD)
4. ⬜ HQDCSRV (Child Domain + Sub CA)

### Phase 2 : Services HQ
5. ⬜ HQINFRASRV (DHCP, VPN, Stockage)
6. ⬜ HQMAILSRV (Mail, Webmail)
7. ⬜ HQFWSRV (Firewall)
8. ⬜ HQWEBSRV (Web, RDS)

### Phase 3 : Site Remote
9. ⬜ REMDCSRV (AD Remote)
10. ⬜ REMINFRASRV (Failover)
11. ⬜ REMFW (ACL Firewall)

### Phase 4 : Clients et Tests
12. ⬜ HQCLT, REMCLT, MGMTCLT
13. ⬜ INETSRV (Web HA, FTP)
14. ⬜ VPNCLT, INETCLT (Tests)

---

## 📝 Légende des statuts

- ⬜ À faire
- 🔄 En cours
- ✅ Terminé
- ❌ Problème

---

## 📚 Ressources

- Plan d'adressage complet : `realconf/PLAN-ADRESSAGE-IP.txt`
- Configuration réseau : `realconf/`
- Sujets : `sujet1.md`, `sujet2.md`
