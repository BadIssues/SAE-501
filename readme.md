<p align="center">
  <img src="https://img.shields.io/badge/🏆_WorldSkills-Lyon_2025-FFD700?style=for-the-badge&labelColor=0055A4" alt="WorldSkills Lyon 2025"/>
</p>

<h1 align="center">
  🌐 Infrastructure Réseau WSL2025
  <br/>
  <sub>SAE 501 - Concevoir, Réaliser et Présenter une Solution Technologique</sub>
</h1>

<p align="center">
  <img src="https://img.shields.io/badge/Groupe-4-FF6B6B?style=for-the-badge&logo=users&logoColor=white" alt="Groupe 4"/>
  <img src="https://img.shields.io/badge/BUT_R%26T-3ème_Année-4ECDC4?style=for-the-badge&logo=graduation-cap&logoColor=white" alt="BUT R&T 3"/>
  <img src="https://img.shields.io/badge/IUT_Belfort--Montbéliard-Université_de_Franche--Comté-1E3A8A?style=for-the-badge" alt="IUT BM"/>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Status-✅_Opérationnel-success?style=flat-square" alt="Status"/>
  <img src="https://img.shields.io/badge/Version-1.3-blue?style=flat-square" alt="Version"/>
  <img src="https://img.shields.io/badge/Date-Décembre_2025-purple?style=flat-square" alt="Date"/>
</p>

<p align="center">
  <a href="#presentation">📌 Présentation</a> •
  <a href="#architecture">🏗️ Architecture</a> •
  <a href="#technologies">🛠️ Technologies</a> •
  <a href="#equipe">👥 Équipe</a> •
  <a href="#documentation">📂 Documentation</a>
</p>

---

<a id="presentation"></a>

## 🎯 Présentation

> _« Le professionnel R&T, en charge d'un projet technique, doit assurer l'ensemble des étapes du projet en concevant, réalisant et en présentant une solution technique mariant les différentes technologies réseaux, télécommunications et informatiques. »_
> — Programme National BUT R&T

Ce projet est réalisé dans le cadre de la **SAE 501** en 3ème année de **BUT Réseaux & Télécommunications** à l'IUT de Belfort-Montbéliard. Il s'appuie sur le sujet officiel de la compétition **WorldSkills Lyon 2025 - Skill 39 (IT Network Systems Administration)**.

### 📋 Contexte WorldSkills

|                        |                                                                 |
| ---------------------- | --------------------------------------------------------------- |
| 🏢 **Client fictif**   | WorldSkills Lyon 2025 (WSL2025) - Organisation des compétitions |
| 🤝 **Partenaire**      | WorldSkills France (WSFR) - Site distant connecté via MAN       |
| 👥 **Effectif simulé** | ~120 employés répartis sur 2 sites                              |
| 🎯 **Objectif**        | Infrastructure réseau complète, sécurisée et redondante         |

### 🏆 Compétences Développées

<table>
<tr>
<td align="center" width="25%">

**🔧 Infrastructure**
<br/>
<sub>Architecture multi-sites<br/>Redondance HSRP/LACP<br/>VRF & Segmentation</sub>

</td>
<td align="center" width="25%">

**🌐 Routage**
<br/>
<sub>OSPF Multi-Area<br/>BGP eBGP/iBGP<br/>NAT/PAT</sub>

</td>
<td align="center" width="25%">

**🖥️ Services**
<br/>
<sub>Active Directory<br/>DNS/DHCP/PKI<br/>Mail/Web/VPN</sub>

</td>
<td align="center" width="25%">

**🔐 Sécurité**
<br/>
<sub>Firewall nftables<br/>Certificats X.509<br/>VPN OpenVPN</sub>

</td>
</tr>
</table>

---

<a id="architecture"></a>

## 🏗️ Architecture

### Vue d'ensemble

```
                        ┌─────────────────────────────────────────┐
                        │         🌐 ZONE INTERNET (8.8.4.0/29)   │
                        │  DNSSRV   INETSRV   VPNCLT    INETCLT   │
                        │  8.8.4.1  8.8.4.2   8.8.4.3   8.8.4.4   │
                        │  Root CA  Web+FTP   VPN Test  Test CLT  │
                        └────────────────┬────────────────────────┘
                                         │
┌────────────────────┐      ┌────────────┴────────────┐      ┌────────────────────┐
│  🏭 SITE REMOTE    │      │        WANRTR           │      │   🏢 SITE HQ       │
│     (WSFR)         │      │   ┌───────────────┐     │      │    (WSL2025)       │
│                    │      │   │ VRF INET      │     │      │                    │
│  ┌──────────┐      │      │   │ VRF MAN       │     │      │ ┌────────────────┐ │
│  │  REMFW   │◄─────┼──────┼───│ AS 65430      │─────┼──────┼►│ EDGE1 + EDGE2  │ │
│  │ 10.116.4.1      │ OSPF │   └───────────────┘     │ BGP+ │ │ (iBGP + HSRP)  │ │
│  └────┬─────┘      │Area 4│                         │ OSPF │ └───────┬────────┘ │
│       │            │      └─────────────────────────┘      │  VLAN   │ VLAN     │
│  ┌────┴────┐       │                                       │  100    │ 200      │
│  │REMDCSRV │       │                                       │ ┌───────┴───────┐  │
│  │REMINFRA │       │                                       │ │CORESW1─CORESW2│  │
│  │ REMCLT  │       │                                       │ │(HSRP + LACP)  │  │
│  └─────────┘       │                                       │ └───────┬───────┘  │
│ 10.4.100.0/25      │                                       │         │Trunks    │
└────────────────────┘                                       │ ┌───────┴───────┐  │
                                                             │ │ACCSW1 + ACCSW2│  │
                                                             │ └───────┬───────┘  │
                                                             │         │          │
  ┌──────────────────────────────────────────────────────────┼─────────┴─────┐    │
  │                         VLANS HQ                         │               │    │
  │  ┌─────────────────┐ ┌──────────────┐ ┌───────────────┐ │┌────────────┐ │    │
  │  │ VLAN 10 Servers │ │VLAN 20 Client│ │VLAN 99 Mgmt   │ ││VLAN 30 DMZ │ │    │
  │  │ HQDCSRV  .1     │ │ HQCLT (DHCP) │ │ MGMTCLT .1    │ ││HQFWSRV .1  │ │    │
  │  │ HQINFRASRV .2   │ │              │ │ (Ansible)     │ ││HQWEBSRV .2 │ │    │
  │  │ HQMAILSRV .3    │ │              │ │               │ ││(IIS + RDS) │ │    │
  │  │ DCWSL .4        │ │              │ │               │ │└────────────┘ │    │
  │  │ (Forest Root)   │ │              │ │               │ │ 217.4.160.0/24│    │
  │  └─────────────────┘ └──────────────┘ └───────────────┘ └──────────────┘│    │
  │   10.4.10.0/24        10.4.20.0/23     10.4.99.0/24                     │    │
  └─────────────────────────────────────────────────────────────────────────┘    │
└────────────────────────────────────────────────────────────────────────────────┘
```

### Schéma Mermaid Interactif

```mermaid
graph TD
    %% === ZONE REMOTE (Site Distant WSFR) ===
    subgraph REMOTE ["🏭 Site Distant - WSFR (MAN)"]
        direction TB
        REMFW["🔥 REMFW<br/>Cisco CSR1000v<br/>10.116.4.1"]
        REMDCSRV["🖥️ REMDCSRV<br/>AD + DHCP + DNS"]
        REMINFRASRV["🖥️ REMINFRASRV<br/>DFS Failover"]
        REMCLT["💻 REMCLT<br/>Windows 11"]

        REMFW --- REMDCSRV
        REMFW --- REMINFRASRV
        REMFW --- REMCLT
    end

    %% === ZONE WAN CENTRAL ===
    subgraph WAN ["☁️ Cœur WAN - FAI (AS 65430)"]
        WANRTR["🌐 WANRTR<br/>BGP AS 65430<br/>VRF INET / VRF MAN"]
    end

    %% === ZONE INTERNET ===
    subgraph INTERNET ["🌍 Zone Internet (8.8.4.0/29)"]
        direction TB
        DNSSRV["🔐 DNSSRV<br/>DNS Public<br/>Root CA"]
        INETSRV["🌐 INETSRV<br/>Web HA + FTPS"]
        VPNCLT["💻 VPNCLT<br/>Client VPN"]
        INETCLT["💻 INETCLT<br/>Client Test"]
    end

    %% === ZONE HQ (Siège Social) ===
    subgraph HQ ["🏢 Siège Social HQ - WSL2025 (AS 65416)"]
        direction TB

        %% Routeurs Edge
        EDGE1["⚡ EDGE1<br/>BGP AS 65416<br/>HSRP Active"]
        EDGE2["⚡ EDGE2<br/>BGP AS 65416<br/>HSRP Standby"]

        %% Core Switches
        CORESW1["🔷 CORESW1<br/>L3 Switch<br/>HSRP Active"]
        CORESW2["🔷 CORESW2<br/>L3 Switch<br/>HSRP Standby"]

        %% Access Switches
        ACCSW1["🔹 ACCSW1"]
        ACCSW2["🔹 ACCSW2"]

        %% VLAN 10 - Serveurs
        subgraph SERVERS ["📦 VLAN 10 - Serveurs (10.4.10.0/24)"]
            HQDCSRV["🖥️ HQDCSRV<br/>AD + PKI + DNS"]
            HQINFRASRV["🖥️ HQINFRASRV<br/>DHCP + VPN + NTP"]
            HQMAILSRV["📧 HQMAILSRV<br/>Mail + Webmail"]
            DCWSL["🏛️ DCWSL<br/>Forest Root DC"]
        end

        %% VLAN 20 - Clients
        subgraph CLIENTS ["👥 VLAN 20 - Clients (10.4.20.0/23)"]
            HQCLT["💻 HQCLT<br/>Windows 11"]
        end

        %% VLAN 99 - Management
        subgraph MGMT ["🔧 VLAN 99 - Management"]
            MGMTCLT["🛠️ MGMTCLT<br/>Ansible"]
        end

        %% VLAN 30 - DMZ
        subgraph DMZ ["🛡️ VLAN 30 - DMZ (217.4.160.0/24)"]
            HQFWSRV["🔥 HQFWSRV<br/>pfSense"]
            HQWEBSRV["🌐 HQWEBSRV<br/>IIS + RDS"]
        end
    end

    %% === CONNEXIONS PRINCIPALES ===

    %% Remote vers WAN
    REMFW <-->|"OSPF Area 4<br/>10.116.4.0/30"| WANRTR

    %% Internet vers WAN
    WANRTR ---|"8.8.4.0/29"| DNSSRV
    WANRTR --- INETSRV
    WANRTR --- VPNCLT
    WANRTR --- INETCLT

    %% WAN vers HQ (Double liaison BGP)
    WANRTR <-->|"eBGP 65430↔65416<br/>+ OSPF Area 4"| EDGE1
    WANRTR <-->|"eBGP 65430↔65416<br/>+ OSPF Area 4"| EDGE2

    %% Interconnexions HQ Layer 3 (iBGP)
    EDGE1 <-->|"iBGP AS 65416<br/>VLAN 300"| EDGE2
    EDGE1 <-->|"VLAN 100"| CORESW1
    EDGE2 <-->|"VLAN 200"| CORESW2

    %% Core Switch interconnexion
    CORESW1 <==>|"LACP Po1<br/>Trunk VLANs"| CORESW2

    %% Trunks vers Access
    CORESW1 ---|"Trunk"| ACCSW1
    CORESW1 ---|"Trunk"| ACCSW2
    CORESW2 ---|"Trunk"| ACCSW1
    CORESW2 ---|"Trunk"| ACCSW2

    %% Access vers End Devices
    ACCSW1 ---|"VLAN 10"| HQDCSRV
    ACCSW1 ---|"VLAN 10"| HQINFRASRV
    ACCSW1 ---|"VLAN 10"| HQMAILSRV
    ACCSW1 ---|"VLAN 10"| DCWSL
    ACCSW1 ---|"VLAN 20"| HQCLT
    ACCSW2 ---|"VLAN 99"| MGMTCLT
    ACCSW2 ---|"VLAN 30"| HQFWSRV

    %% DMZ interne
    HQFWSRV ---|"DMZ Interne"| HQWEBSRV
```

---

<a id="technologies"></a>

## 🛠️ Technologies

### Stack Réseau

<p align="center">
  <img src="https://img.shields.io/badge/Cisco_IOS-1BA0D7?style=for-the-badge&logo=cisco&logoColor=white" alt="Cisco"/>
  <img src="https://img.shields.io/badge/OSPF-Area_4_NSSA-orange?style=for-the-badge" alt="OSPF"/>
  <img src="https://img.shields.io/badge/BGP-AS_65416_/_65430-green?style=for-the-badge" alt="BGP"/>
  <img src="https://img.shields.io/badge/HSRP-Active_/_Standby-red?style=for-the-badge" alt="HSRP"/>
  <img src="https://img.shields.io/badge/VRF-INET_/_MAN-purple?style=for-the-badge" alt="VRF"/>
</p>
<p align="center">
  <img src="https://img.shields.io/badge/LACP-Etherchannel-1BA0D7?style=flat-square" alt="LACP"/>
  <img src="https://img.shields.io/badge/VTP-v2-1BA0D7?style=flat-square" alt="VTP"/>
  <img src="https://img.shields.io/badge/STP-Rapid--PVST+-1BA0D7?style=flat-square" alt="STP"/>
  <img src="https://img.shields.io/badge/NAT-PAT_/_Static-1BA0D7?style=flat-square" alt="NAT"/>
  <img src="https://img.shields.io/badge/ACL-Security-1BA0D7?style=flat-square" alt="ACL"/>
</p>

### Stack Systèmes

<p align="center">
  <img src="https://img.shields.io/badge/Windows_Server-2022-0078D6?style=for-the-badge&logo=windows&logoColor=white" alt="Windows Server"/>
  <img src="https://img.shields.io/badge/Debian-13_Trixie-A81D33?style=for-the-badge&logo=debian&logoColor=white" alt="Debian"/>
  <img src="https://img.shields.io/badge/Windows-11-0078D6?style=for-the-badge&logo=windows11&logoColor=white" alt="Windows 11"/>
</p>
<p align="center">
  <img src="https://img.shields.io/badge/Active_Directory-Forest_+_Child-0078D4?style=flat-square&logo=microsoft" alt="AD DS"/>
  <img src="https://img.shields.io/badge/Samba_AD-DC-006600?style=flat-square" alt="Samba"/>
  <img src="https://img.shields.io/badge/ADCS-PKI_SubCA-0078D4?style=flat-square" alt="ADCS"/>
  <img src="https://img.shields.io/badge/GPO-Policies-0078D4?style=flat-square" alt="GPO"/>
  <img src="https://img.shields.io/badge/DFS-Replication-0078D4?style=flat-square" alt="DFS"/>
</p>

### Stack Services

<p align="center">
  <img src="https://img.shields.io/badge/OpenVPN-VPN-EA7E20?style=for-the-badge&logo=openvpn&logoColor=white" alt="OpenVPN"/>
  <img src="https://img.shields.io/badge/IIS-Web_Server-5E5E5E?style=for-the-badge&logo=microsoft&logoColor=white" alt="IIS"/>
  <img src="https://img.shields.io/badge/Docker-HA_Web-2496ED?style=for-the-badge&logo=docker&logoColor=white" alt="Docker"/>
  <img src="https://img.shields.io/badge/Ansible-Automation-EE0000?style=for-the-badge&logo=ansible&logoColor=white" alt="Ansible"/>
  <img src="https://img.shields.io/badge/pfSense-Firewall-212121?style=for-the-badge&logo=pfsense&logoColor=white" alt="pfSense"/>
</p>
<p align="center">
  <img src="https://img.shields.io/badge/Postfix-SMTP-blue?style=flat-square" alt="Postfix"/>
  <img src="https://img.shields.io/badge/Dovecot-IMAP-blue?style=flat-square" alt="Dovecot"/>
  <img src="https://img.shields.io/badge/Roundcube-Webmail-blue?style=flat-square" alt="Roundcube"/>
  <img src="https://img.shields.io/badge/BIND9-DNS-green?style=flat-square" alt="BIND"/>
  <img src="https://img.shields.io/badge/ISC_DHCP-DHCP-green?style=flat-square" alt="DHCP"/>
  <img src="https://img.shields.io/badge/DNSSEC-Security-green?style=flat-square" alt="DNSSEC"/>
</p>

### Stack Stockage

<p align="center">
  <img src="https://img.shields.io/badge/ZFS-RAID--Z1-FF6600?style=flat-square" alt="ZFS"/>
  <img src="https://img.shields.io/badge/LVM-Logical_Volumes-FF6600?style=flat-square" alt="LVM"/>
  <img src="https://img.shields.io/badge/iSCSI-SAN-FF6600?style=flat-square" alt="iSCSI"/>
  <img src="https://img.shields.io/badge/RAID--5-Windows-FF6600?style=flat-square" alt="RAID-5"/>
  <img src="https://img.shields.io/badge/Samba-SMB_Shares-006600?style=flat-square" alt="Samba"/>
  <img src="https://img.shields.io/badge/FTPS-Secure_FTP-006600?style=flat-square" alt="FTPS"/>
</p>

### Stack Sécurité

<p align="center">
  <img src="https://img.shields.io/badge/Root_CA-OpenSSL-DC143C?style=flat-square" alt="Root CA"/>
  <img src="https://img.shields.io/badge/Sub_CA-ADCS-DC143C?style=flat-square" alt="Sub CA"/>
  <img src="https://img.shields.io/badge/X.509-Certificates-DC143C?style=flat-square" alt="X.509"/>
  <img src="https://img.shields.io/badge/Fail2Ban-IDS-DC143C?style=flat-square" alt="Fail2Ban"/>
  <img src="https://img.shields.io/badge/SSHv2-RSA_2048-DC143C?style=flat-square" alt="SSH"/>
  <img src="https://img.shields.io/badge/MD5-OSPF_Auth-DC143C?style=flat-square" alt="MD5"/>
</p>

---

## 📊 Plan d'Adressage IP Complet (N=4)

### 🏷️ VLANs

| VLAN | Nom | Description | Réseau |
|:---:|---|---|---|
| 10 | Servers | Serveurs HQ | `10.4.10.0/24` |
| 20 | Clients | Clients HQ (DHCP) | `10.4.20.0/23` |
| 30 | DMZ | Zone DMZ publique | `217.4.160.0/24` |
| 99 | Management | Gestion équipements | `10.4.99.0/24` |
| 100 | CORESW1-EDGE1 | Lien CORESW1 ↔ EDGE1 | `10.4.254.0/30` |
| 200 | CORESW2-EDGE2 | Lien CORESW2 ↔ EDGE2 | `10.4.254.4/30` |
| 300 | IBGP_peering | iBGP EDGE1 ↔ EDGE2 | `10.4.254.8/30` |
| 666 | Blackhole | Native VLAN (sécurité) | N/A |

### 🏢 Site HQ - VLAN 10 (Servers) - `10.4.10.0/24`

| Équipement | IP | Rôle |
|---|---|---|
| HQDCSRV | `10.4.10.1` | Child DC, DNS, ADCS SubCA, GPO |
| HQINFRASRV | `10.4.10.2` | DHCP, VPN, NTP, Samba, iSCSI |
| HQMAILSRV | `10.4.10.3` | SMTP, IMAP, Webmail, DHCP Failover |
| DCWSL | `10.4.10.4` | Forest Root DC, DNS wsl2025.org |
| HQFWSRV (LAN) | `10.4.10.5` | pfSense - interface Servers |
| CORESW1 | `10.4.10.253` | HSRP Active |
| CORESW2 | `10.4.10.252` | HSRP Standby |
| **VIP HSRP** | `10.4.10.254` | **Gateway virtuelle** |

### 🏢 Site HQ - VLAN 20 (Clients) - `10.4.20.0/23`

| Équipement | IP | Rôle |
|---|---|---|
| HQCLT | DHCP | Client Windows 11 |
| CORESW1 | `10.4.20.253` | HSRP Active |
| CORESW2 | `10.4.20.252` | HSRP Standby |
| **VIP HSRP** | `10.4.20.254` | **Gateway virtuelle** |

> **DHCP** : Plage `10.4.20.1 - 10.4.21.200` • Lease 2h • DNS: `hqdcsrv.hq.wsl2025.org`

### 🏢 Site HQ - VLAN 30 (DMZ) - `217.4.160.0/24`

| Équipement | IP | Rôle |
|---|---|---|
| HQFWSRV (WAN) | `217.4.160.1` | pfSense - interface DMZ |
| HQWEBSRV | `217.4.160.2` | IIS, RDS (Word/Excel) |
| EDGE1 | `217.4.160.253` | HSRP Active |
| EDGE2 | `217.4.160.252` | HSRP Standby |
| **VIP HSRP** | `217.4.160.254` | **Gateway virtuelle publique** |

### 🏢 Site HQ - VLAN 99 (Management) - `10.4.99.0/24`

| Équipement | IP | Rôle |
|---|---|---|
| MGMTCLT | `10.4.99.1` | Ansible (Debian GUI) |
| ACCSW1 | `10.4.99.11` | Access Switch 1 |
| ACCSW2 | `10.4.99.12` | Access Switch 2 |
| CORESW1 | `10.4.99.253` | HSRP Active |
| CORESW2 | `10.4.99.252` | HSRP Standby |
| **VIP HSRP** | `10.4.99.254` | **Gateway virtuelle** |

### 🔗 Liens Internes (Core Network)

| Liaison | VLAN | Réseau | IP Équipement 1 | IP Équipement 2 |
|---|:---:|---|---|---|
| CORESW1 ↔ EDGE1 | 100 | `10.4.254.0/30` | CORESW1: `.2` | EDGE1: `.1` |
| CORESW2 ↔ EDGE2 | 200 | `10.4.254.4/30` | CORESW2: `.6` | EDGE2: `.5` |
| EDGE1 ↔ EDGE2 (iBGP) | 300 | `10.4.254.8/30` | EDGE1: `.9` | EDGE2: `.10` |
| EDGE1 ↔ WANRTR (MAN) | 13 | `10.4.254.12/30` | EDGE1: `.13` | WANRTR: `.14` |
| EDGE2 ↔ WANRTR (MAN) | 15 | `10.4.254.16/30` | EDGE2: `.18` | WANRTR: `.17` |

### 🌐 Liens Internet (VRF INET)

| Liaison | VLAN | Réseau | IP Équipement 1 | IP Équipement 2 |
|---|:---:|---|---|---|
| EDGE1 ↔ WANRTR | 14 | `91.4.222.96/29` | EDGE1: `.97` | WANRTR: `.98` |
| EDGE2 ↔ WANRTR | 16 | `31.4.126.12/30` | EDGE2: `.13` | WANRTR: `.14` |

**Provider Independent IPs (Loopback0)** : `191.4.157.32/28`
- EDGE1: `191.4.157.33` • EDGE2: `191.4.157.34`

### 🌍 Zone Internet - `8.8.4.0/29`

| Équipement | IP | Rôle |
|---|---|---|
| DNSSRV | `8.8.4.1` | DNS Public, Root CA |
| INETSRV | `8.8.4.2` | Web HA (Docker), FTPS |
| VPNCLT | `8.8.4.3` | Client VPN (test) |
| INETCLT | `8.8.4.4` | Client Internet (test) |
| WANRTR | `8.8.4.6` | Gateway Internet |

### 🏭 Site Remote - `10.4.100.0/25`

| Équipement | IP | Rôle |
|---|---|---|
| REMDCSRV | `10.4.100.1` | AD Child, DNS, DHCP |
| REMINFRASRV | `10.4.100.2` | DFS, Failover |
| REMCLT | DHCP | Client Windows 11 |
| REMFW | `10.4.100.126` | Gateway / Firewall |

> **Lien WAN** : REMFW (`10.116.4.1`) ↔ WANRTR (`10.116.4.2`) via `10.116.4.0/30`
> **DHCP** : Plage `10.4.100.10 - 10.4.100.120` • DNS: `remdcsrv.rem.wsl2025.org`

### ⚙️ Configuration HSRP

| Groupe | VLAN | VIP | Active | Standby | Priority |
|:---:|:---:|---|---|---|---|
| 10 | 10 | `10.4.10.254` | CORESW1 | CORESW2 | 110/100 |
| 20 | 20 | `10.4.20.254` | CORESW1 | CORESW2 | 110/100 |
| 99 | 99 | `10.4.99.254` | CORESW1 | CORESW2 | 110/100 |
| 30 | 30 | `217.4.160.254` | EDGE1 | EDGE2 | 110/100 |

### 🔀 Protocoles de Routage

**OSPF Area 4 (NSSA) - VRF MAN**
- Participants : EDGE1, EDGE2, WANRTR, REMFW
- Auth : MD5 (`P@ssw0rd`)
- Network Type : Point-to-Point

**BGP**
| AS | Équipements | Type |
|---|---|---|
| 65416 | EDGE1, EDGE2 | iBGP entre eux |
| 65430 | WANRTR | eBGP avec EDGE1/EDGE2 |

**Réseaux annoncés :**
- AS 65416 : `191.4.157.32/28`, `217.4.160.0/24`
- AS 65430 : `8.8.4.0/29`

### 🔄 Configuration NAT

**PAT (Overload)** : `10.4.0.0/16` → Interface WAN

**Static NAT :**
| Service | IP Publique | IP Privée | Port |
|---|---|---|---|
| VPN OpenVPN | `191.4.157.33:4443` | `10.4.10.2:443` | TCP |
| Webmail HTTP | `191.4.157.33:80` | `10.4.10.3:80` | TCP |
| Webmail HTTPS | `191.4.157.33:443` | `10.4.10.3:443` | TCP |

---

## 🖥️ Inventaire des Machines

### 🏢 Site HQ (Siège - 6 serveurs)

| Serveur        | OS                   | IP            | Rôles                                |                 Doc                  |
| -------------- | -------------------- | ------------- | ------------------------------------ | :----------------------------------: |
| **HQDCSRV**    | Windows Server 2022  | `10.4.10.1`   | AD DS, DNS, ADCS (SubCA), GPO        |  [📘](documentation/04-HQDCSRV.md)   |
| **HQINFRASRV** | Debian 13            | `10.4.10.2`   | DHCP, VPN OpenVPN, NTP, Samba, iSCSI | [📘](documentation/01-HQINFRASRV.md) |
| **HQMAILSRV**  | Debian 13            | `10.4.10.3`   | Postfix, Dovecot, Roundcube, ZFS     | [📘](documentation/02-HQMAILSRV.md)  |
| **DCWSL**      | Debian 13 (Samba AD) | `10.4.10.4`   | Forest Root DC, DNS wsl2025.org      |   [📘](documentation/03-DCWSL.md)    |
| **HQFWSRV**    | pfSense              | `217.4.160.1` | Firewall, NAT/PAT, Routing           |  [📘](documentation/05-HQFWSRV.md)   |
| **HQWEBSRV**   | Windows Server 2022  | `217.4.160.2` | IIS, RDS (RemoteApp)                 |  [📘](documentation/06-HQWEBSRV.md)  |

### 🏭 Site Remote (3 équipements)

| Équipement      | OS                   | IP             | Rôles                      |                  Doc                  |
| --------------- | -------------------- | -------------- | -------------------------- | :-----------------------------------: |
| **REMFW**       | Cisco IOS (CSR1000v) | `10.4.100.126` | Routeur/Firewall ACL, OSPF |    [📘](documentation/09-REMFW.md)    |
| **REMDCSRV**    | Windows Server 2022  | `10.4.100.1`   | AD Child, DHCP, DNS, DFS   |  [📘](documentation/10-REMDCSRV.md)   |
| **REMINFRASRV** | Windows Server 2022  | `10.4.100.2`   | Failover DHCP/DNS, DFS     | [📘](documentation/11-REMINFRASRV.md) |

### 🌐 Zone Internet (4 machines)

| Machine     | OS            | IP        | Rôles                       |                Doc                |
| ----------- | ------------- | --------- | --------------------------- | :-------------------------------: |
| **DNSSRV**  | Debian 13     | `8.8.4.1` | DNS Public, Root CA, DNSSEC | [📘](documentation/13-DNSSRV.md)  |
| **INETSRV** | Debian 13     | `8.8.4.2` | Web HA (Docker), FTPS       | [📘](documentation/14-INETSRV.md) |
| **VPNCLT**  | Windows 11    | `8.8.4.3` | Client VPN (test)           | [📘](documentation/15-VPNCLT.md)  |
| **INETCLT** | Debian 13 GUI | `8.8.4.4` | Client Internet (test)      | [📘](documentation/16-INETCLT.md) |

---

## 🚀 Guide de Déploiement

### Ordre recommandé

```
Phase 1 - Fondations          Phase 2 - Services HQ        Phase 3 - Expansion
━━━━━━━━━━━━━━━━━━━           ━━━━━━━━━━━━━━━━━━━          ━━━━━━━━━━━━━━━━━━
   ┌─────────────┐               ┌─────────────┐              ┌─────────────┐
   │ 1. Switches │               │ 4. HQINFRASRV│              │ 7. REMFW    │
   │   & VLANs   │               │   DHCP/VPN  │              │   Routing   │
   └──────┬──────┘               └──────┬──────┘              └──────┬──────┘
          ▼                             ▼                            ▼
   ┌─────────────┐               ┌─────────────┐              ┌─────────────┐
   │ 2. Routeurs │               │ 5. HQFWSRV  │              │ 8. REMDCSRV │
   │ OSPF & BGP  │               │   Firewall  │              │   AD Child  │
   └──────┬──────┘               └──────┬──────┘              └──────┬──────┘
          ▼                             ▼                            ▼
   ┌─────────────┐               ┌─────────────┐              ┌─────────────┐
   │ 3. DNSSRV   │               │ 6. HQWEBSRV │              │ 9. Clients  │
   │  + DCWSL    │               │  + MAILSRV  │              │   & Tests   │
   └─────────────┘               └─────────────┘              └─────────────┘
```

### Commandes rapides

```bash
# Vérifier les adjacences OSPF
show ip ospf neighbor

# Vérifier les sessions BGP
show ip bgp summary

# Tester la connectivité inter-sites
ping 10.4.100.1 source 10.4.10.1
```

---

<a id="documentation"></a>

## 📂 Structure du Projet

```
📁 configreseau/
├── 📄 readme.md                 # Ce fichier
├── 📄 sujet1.md                 # Sujet technique complet (EN)
├── 📄 sujet2.md                 # Présentation SAE 501 (FR)
├── 🖼️ SAE501-2025-*.jpg         # Schémas d'architecture (4 fichiers)
│
├── 📁 documentation/            # 📘 Guides d'installation détaillés
│   ├── 00-INDEX.md              # Table des matières
│   └── [01-16]-*.md             # Procédures par machine
│
├── 📁 realconf/                 # ⚙️ Configurations réelles (Cisco IOS)
│   ├── PLAN-ADRESSAGE-IP.txt    # Plan d'adressage complet
│   ├── JALONS-PREUVES.txt       # Preuves de validation
│   ├── edge1.txt / edge2.txt    # Configs routeurs bordure
│   ├── coresw1.txt / coresw2.txt # Configs switches cœur
│   ├── accsw1.txt / accsw2.txt  # Configs switches accès
│   ├── wanrtr.txt               # Config routeur WAN (VRF)
│   └── remfw.txt                # Config firewall remote
│
└── 📁 virtconf/                 # 🧪 Configurations virtuelles (GNS3/EVE-NG)
    ├── jalon7-switches/         # Configs switches (jalon 7)
    └── jalon8-routeurs/         # Configs routeurs (jalon 8)
```

---

<a id="equipe"></a>

## 👥 Équipe - Groupe 4

<table>
<tr>
<td align="center" width="25%">
<img src="https://img.shields.io/badge/🔐-Antonin_MICHON-DC143C?style=for-the-badge" alt="Antonin MICHON"/><br/>
<sub><b>Parcours Cyber</b></sub><br/>
<sub>PKI • Firewall • VPN</sub>
</td>
<td align="center" width="25%">
<img src="https://img.shields.io/badge/🔐-Curtis_LEMIEUX-DC143C?style=for-the-badge" alt="Curtis LEMIEUX"/><br/>
<sub><b>Parcours Cyber</b></sub><br/>
<sub>AD • DNS • Sécurité</sub>
</td>
<td align="center" width="25%">
<img src="https://img.shields.io/badge/📊-Damien_LETALLEUR-FF8C00?style=for-the-badge" alt="Damien LETALLEUR"/><br/>
<sub><b>Parcours PilPro</b></sub><br/>
<sub>Gestion de projet</sub>
</td>
<td align="center" width="25%">
<img src="https://img.shields.io/badge/📊-Lucien_DELAGRANGE-FF8C00?style=for-the-badge" alt="Lucien DELAGRANGE"/><br/>
<sub><b>Parcours PilPro</b></sub><br/>
<sub>Gestion de projet</sub>
</td>
</tr>
</table>

> 📍 **Salle de réunion** : 005 | **Infra réseau** : Salle 203

---

## 🔐 Credentials par défaut

| Service            | Utilisateur     | Mot de passe |
| ------------------ | --------------- | ------------ |
| Équipements réseau | `admin`         | `P@ssw0rd`   |
| Domaine AD         | `Administrator` | `P@ssw0rd`   |
| Linux (root)       | `root`          | `P@ssw0rd`   |

> ⚠️ **Note** : Le zéro (0) est entre le "w" et le "r"

### Domaines Active Directory

```
wsl2025.org          (Forest Root - DCWSL)
├── hq.wsl2025.org   (Child Domain - HQDCSRV)
└── rem.wsl2025.org  (Child Domain - REMDCSRV)
```

---

## 📈 Progression

```
Cœur Réseau      [██████████████████████████████] 100% ✅
Services HQ      [██████████████████████████████] 100% ✅
Site Remote      [██████████████████████████████] 100% ✅
Documentation    [██████████████████████████████] 100% ✅
Tests & Valid.   [██████████████████████████████] 100% ✅
```

---

## 📚 Ressources

- 🔗 [WorldSkills France](https://www.worldskills-france.org)
- 🔗 [Moodle SAE 501](https://moodle.univ-fcomte.fr)
- 🔗 [IUT Belfort-Montbéliard](https://www.iut-bm.univ-fcomte.fr/)

---

<p align="center">
  <img src="https://img.shields.io/badge/Made_with-❤️-red?style=for-the-badge" alt="Made with love"/>
  <img src="https://img.shields.io/badge/IUT_Belfort--Montbéliard-2025-1E3A8A?style=for-the-badge" alt="IUT BM"/>
</p>

<p align="center">
  <sub>
    <b>SAE 501</b> • BUT Réseaux & Télécommunications • 3ème année<br/>
    Université de Franche-Comté • Décembre 2025<br/><br/>
    <i>Basé sur le sujet WorldSkills Lyon 2025 - Skill 39 (IT Network Systems Administration)</i>
  </sub>
</p>

<p align="center">
  <sub>
    © WorldSkills France - Reproduction autorisée à des fins pédagogiques non commerciales
  </sub>
</p>
