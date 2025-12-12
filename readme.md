# 🌐 Infrastructure Réseau WSL2025 (SAE 501)

[![WorldSkills](https://img.shields.io/badge/Based%20on-WorldSkills%202025-blue?style=for-the-badge)](https://worldskills.org)
[![Academic Project](https://img.shields.io/badge/Context-BUT3%20R%26T-green?style=for-the-badge)](https://www.iut-bm.univ-fcomte.fr/)
[![Status](https://img.shields.io/badge/Status-Opérationnel-success?style=for-the-badge)](/)

## 📋 Présentation du Projet

Ce projet est réalisé dans le cadre de la **SAE 501 (Situation d'Apprentissage et d'Évaluation)** en 3ème année de **BUT Réseaux & Télécommunications**.

Il s'appuie sur le sujet officiel de la compétition **WorldSkills Lyon 2025 - Skill 39 (IT Network Systems Administration)**, adapté pour les besoins pédagogiques de la formation. L'objectif est de concevoir et déployer une infrastructure réseau complète, sécurisée et redondante, simulant un environnement d'entreprise réel.

### 🎯 Objectifs Pédagogiques
- **Architecture Réseau** : Conception d'une topologie complexe multi-sites (HQ, Remote, Internet).
- **Protocoles Avancés** : Mise en œuvre de OSPF, BGP, VRF, HSRP, Etherchannel.
- **Services Systèmes** : Déploiement de services critiques (AD, DNS, PKI, Web, Mail).
- **Sécurité** : Segmentation, Firewalling, VPN, Sécurisation des accès.
- **Automatisation** : Utilisation d'Ansible pour la configuration des équipements.

---

## 🏗️ Architecture Réseau

Le routeur **WANRTR** est le point central de l'architecture, séparant les flux via des VRF (INET et MAN).

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

## 🌍 Plan d'Adressage IP (N=4)

| Zone | VLAN | Nom | Réseau | Passerelle (VIP) |
|---|---|---|---|---|
| **HQ** | 10 | Servers | `10.4.10.0/24` | `10.4.10.254` |
| **HQ** | 20 | Clients | `10.4.20.0/23` | `10.4.20.254` |
| **HQ** | 30 | DMZ | `217.4.160.0/24` | `217.4.160.254` |
| **HQ** | 99 | Management | `10.4.99.0/24` | `10.4.99.254` |
| **Remote** | 100 | Remote LAN | `10.4.100.0/25` | `10.4.100.126` |
| **Internet** | - | Public | `8.8.4.0/29` | `8.8.4.6` |

### Liaisons d'Interconnexion (N=4)

| Liaison | VLAN | Réseau | IPs | VRF | Protocole |
|---|---|---|---|---|---|
| EDGE1-WANRTR | 13 | `10.4.254.12/30` | .13 / .14 | MAN | OSPF |
| EDGE1-WANRTR | 14 | `91.4.222.96/29` | .97 / .98 | INET | eBGP |
| EDGE2-WANRTR | 15 | `10.4.254.16/30` | .18 / .17 | MAN | OSPF |
| EDGE2-WANRTR | 16 | `31.4.126.12/30` | .13 / .14 | INET | eBGP |
| WANRTR-REMFW | - | `10.116.4.0/30` | .2 / .1 | MAN | OSPF |

---

## 🖥️ Inventaire des Serveurs

### 🏢 Site HQ (Siège)
| Serveur | OS | IP | Rôles Principaux | Documentation |
|---|---|---|---|---|
| **HQDCSRV** | Win 2022 | `10.4.10.1` | AD DS, DNS, ADCS (SubCA), GPO | [Voir le guide](documentation/04-HQDCSRV.md) |
| **HQINFRASRV** | Debian 13 | `10.4.10.2` | DHCP, VPN OpenVPN, NTP, Samba | [Voir le guide](documentation/01-HQINFRASRV.md) |
| **HQMAILSRV** | Debian 13 | `10.4.10.3` | Postfix, Dovecot, Roundcube, ZFS | [Voir le guide](documentation/02-HQMAILSRV.md) |
| **DCWSL** | Debian 13 | `10.4.10.4` | Samba AD (Forest Root), DNS | [Voir le guide](documentation/03-DCWSL.md) |
| **HQFWSRV** | Debian 13 | `217.4.160.1` | Firewall (nftables), Routing | [Voir le guide](documentation/05-HQFWSRV.md) |
| **HQWEBSRV** | Win 2022 | `217.4.160.2` | IIS, RDS (RemoteApp) | [Voir le guide](documentation/06-HQWEBSRV.md) |

### 🏭 Site Remote
| Serveur | OS | IP | Rôles Principaux | Documentation |
|---|---|---|---|---|
| **REMFW** | Cisco IOS | `10.4.100.126` | Routeur/Firewall (ACL), OSPF | [Voir le guide](documentation/09-REMFW.md) |
| **REMDCSRV** | Win 2022 | `10.4.100.1` | AD (Child), DHCP, DNS | [Voir le guide](documentation/10-REMDCSRV.md) |
| **REMINFRASRV**| Win 2022 | `10.4.100.2` | Failover DHCP, DFS | [Voir le guide](documentation/11-REMINFRASRV.md) |

### 🌐 Zone Internet
| Serveur | OS | IP | Rôles Principaux | Documentation |
|---|---|---|---|---|
| **DNSSRV** | Debian 13 | `8.8.4.1` | DNS Public, Root CA, DNSSEC | [Voir le guide](documentation/13-DNSSRV.md) |
| **INETSRV** | Debian 13 | `8.8.4.2` | Web HA (Docker), FTP (FTPS) | [Voir le guide](documentation/14-INETSRV.md) |

---

## 🚀 Guide de Déploiement Rapide

1. **Cœur de Réseau** : Déployez les configurations Cisco présentes dans le dossier [`realconf/`](realconf/).
   - Veillez à bien configurer les VRF `INET` et `MAN` sur WANRTR.
   - Vérifiez les adjacences OSPF (Area 4) et BGP (AS 65430).

2. **Infrastructure de Confiance (PKI/DNS)** :
   - Installez **DNSSRV** (Root CA).
   - Installez **DCWSL** (Forest Root).
   - Installez **HQDCSRV** et signez son certificat SubCA via DNSSRV.

3. **Services HQ** :
   - Déployez **HQINFRASRV** (DHCP, VPN).
   - Configurez **HQFWSRV** et **HQWEBSRV** (DMZ).
   - Mettez en place la messagerie sur **HQMAILSRV**.

4. **Site Remote** :
   - Configurez **REMFW** et connectez-le au WAN.
   - Installez **REMDCSRV** et joignez-le à la forêt.

---

## 📂 Structure du Dépôt

```bash
configreseau/
├── documentation/          # 📘 Guides d'installation pas-à-pas (Markdown)
│   ├── 00-INDEX.md         # Table des matières détaillée
│   └── [01-16]-*.md        # Procédures pour chaque machine
├── realconf/               # ⚙️ Configurations Cisco IOS réelles (Running-config)
│   ├── JALONS-PREUVES.txt  # Preuves de validation des jalons
│   ├── PLAN-ADRESSAGE.txt  # Plan IP complet
│   └── *.txt               # Configs routeurs/switches
├── virtconf/               # 🧪 Configurations pour environnement virtuel (GNS3/EVE-NG)
└── sujet*.md               # 📄 Sujets originaux de la compétition
```

## 🔐 Accès et Credentials

- **Domaine AD** : `wsl2025.org`
- **Utilisateur Admin** : `Administrator` / `admin`
- **Mot de passe par défaut** : `P@ssw0rd` *(Zéro entre w et r)*

## 👥 Auteurs

Projet réalisé dans le cadre du **BUT3 Réseaux & Télécommunications** - *Université de Franche-Comté*.

> *WorldSkills Lyon 2025 - IT Network Systems Administration*
