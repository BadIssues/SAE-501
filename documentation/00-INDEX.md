# 📘 Documentation Technique SAE 501

> **Contexte** : Infrastructure réseau WorldSkills Lyon 2025 (Adaptation SAE 501 BUT R&T)

## 🏗️ Architecture Globale

```mermaid
graph TD
    %% --- Zone REMOTE (Gauche) ---
    subgraph REMOTE [Site Distant - MAN]
        direction TB
        REMFW[REMFW<br>Firewall Remote]
        REMDCSRV[REMDCSRV<br>AD Remote]
        REMINFRASRV[REMINFRASRV]
        REMCLT[REMCLT]
        
        REMFW --- REMDCSRV & REMINFRASRV & REMCLT
    end

    %% --- Zone WAN/Central (Milieu) ---
    subgraph WAN [Cœur WAN]
        WANRTR[WANRTR<br>Routeur FAI<br>VRF INET / VRF MAN]
    end

    %% --- Zone INTERNET (Droite) ---
    subgraph INTERNET [Zone Internet]
        direction TB
        INETSW[Switch Internet]
        DNSSRV[DNSSRV<br>DNS Public]
        INETSRV[INETSRV<br>Web + FTP]
        VPNCLT[VPNCLT]
        INETCLT[INETCLT]
        
        INETSW --- DNSSRV & INETSRV & VPNCLT & INETCLT
    end

    %% --- Zone HQ (Bas) ---
    subgraph HQ [Siège Social HQ]
        direction TB
        
        %% Routeurs de Bordure
        EDGE1[EDGE1<br>Routeur Bordure 1]
        EDGE2[EDGE2<br>Routeur Bordure 2]
        
        %% Cœur de Réseau
        CORESW1[CORESW1<br>Cœur 1<br>HSRP Active]
        CORESW2[CORESW2<br>Cœur 2<br>HSRP Standby]
        
        %% Accès
        ACCSW1[ACCSW1<br>Switch Accès 1]
        ACCSW2[ACCSW2<br>Switch Accès 2]
        
        %% Services & Clients
        subgraph SERVERS [VLAN 10 - Serveurs]
            HQDCSRV
            HQINFRASRV
            HQMAILSRV
        end
        
        subgraph CLIENTS [VLAN 20 - Clients]
            HQCLT
        end
        
        subgraph MANAGEMENT [VLAN 99]
            MGMTCLT
        end
        
        subgraph DMZ [VLAN 30 - DMZ Publique]
            HQFWSRV[HQFWSRV<br>Firewall]
            HQWEBSRV[HQWEBSRV<br>Web/RDS]
        end
    end

    %% --- Connexions ---
    
    %% REMOTE vers WANRTR (VRF MAN)
    REMFW <-->|OSPF Area 4| WANRTR

    %% INTERNET vers WANRTR (VRF INET)
    WANRTR --- INETSW

    %% WANRTR vers HQ (Double lien par VRF)
    WANRTR <-->|BGP AS 65430<br>VRF INET| EDGE1
    WANRTR <-->|BGP AS 65430<br>VRF INET| EDGE2
    
    WANRTR <-->|OSPF Area 4<br>VRF MAN| EDGE1
    WANRTR <-->|OSPF Area 4<br>VRF MAN| EDGE2

    %% Interconnexions HQ - Layer 3
    EDGE1 <-->|iBGP - VLAN 300| EDGE2
    EDGE1 <-->|VLAN 100| CORESW1
    EDGE2 <-->|VLAN 200| CORESW2
    
    %% Interconnexions HQ - Layer 2
    CORESW1 <==>|LACP Po1<br>Trunk 10,20,30,99| CORESW2
    
    %% Trunks Access - Config exacte
    CORESW1 ===|Trunk 10,20,30,99| ACCSW1
    CORESW1 ===|Trunk 10,20,30,99| ACCSW2
    CORESW2 ===|Trunk 10,20,30,99| ACCSW1
    CORESW2 ===|Trunk 10,20,30,99| ACCSW2
    
    %% Connexions Access vers End Devices (VLANs spécifiques)
    ACCSW1 ---|VLAN 10| HQDCSRV
    ACCSW1 ---|VLAN 10| HQINFRASRV
    ACCSW1 ---|VLAN 10| HQMAILSRV
    ACCSW1 ---|VLAN 20| HQCLT
    
    ACCSW2 ---|VLAN 99| MGMTCLT
    ACCSW2 ---|VLAN 30| HQFWSRV
    HQFWSRV ---|VLAN 30| HQWEBSRV
```

---

## 📁 Index des Procédures

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

---

## 📊 Ordre de déploiement recommandé

1. **Infrastructure de base** (Cœur de réseau + DNSSRV + DCWSL)
2. **Services HQ** (HQDCSRV, HQINFRASRV, HQMAILSRV)
3. **Sécurité et DMZ** (HQFWSRV, HQWEBSRV)
4. **Site Remote** (REMFW, REMDCSRV)
5. **Clients et Tests**
