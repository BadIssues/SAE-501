# SAE 501 - Infrastructure Réseau WSL2025

[![WorldSkills](https://img.shields.io/badge/WorldSkills-Lyon%202025-blue)](https://worldskills.org)
[![Status](https://img.shields.io/badge/Status-En%20cours-yellow)](/)

## 📋 Description

Projet SAE501 - Configuration d'une infrastructure réseau complète pour WorldSkills Lyon 2025 (WSL2025).

Ce dépôt contient :
- 🌐 **Configurations réseau** : Switches, routeurs (Cisco IOS)
- 📄 **Documentation** : Guides de déploiement pour chaque serveur
- 📊 **Plans** : Adressage IP, VLANs, jalons

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         INTERNET                            │
│         DNSSRV (8.8.4.1) │ INETSRV (8.8.4.2)               │
└─────────────────────┬───────────────────────────────────────┘
                      │
              ┌───────┴───────┐
              │    WANRTR     │
              └───────┬───────┘
         ┌────────────┴────────────┐
         │                         │
    ┌────┴────┐               ┌────┴────┐
    │  EDGE1  │───iBGP────────│  EDGE2  │
    └────┬────┘               └────┬────┘
         │                         │
    ┌────┴────┐               ┌────┴────┐
    │ CORESW1 │───Po1─────────│ CORESW2 │
    └────┬────┘               └────┬────┘
         │                         │
    ┌────┴────┐               ┌────┴────┐
    │ ACCSW1  │               │ ACCSW2  │
    └─────────┘               └─────────┘
         │                         │
      Serveurs                  Clients
```

## 📁 Structure du projet

```
configreseau/
├── documentation/          # Guides de déploiement (17 fichiers)
│   ├── 00-INDEX.md         # Index et ordre de déploiement
│   ├── 01-HQINFRASRV.md    # DHCP, VPN, Samba
│   ├── 02-HQMAILSRV.md     # Mail, Webmail
│   ├── 03-DCWSL.md         # Forest Root AD
│   ├── 04-HQDCSRV.md       # Child AD, PKI
│   └── ...
├── realconf/               # Configurations réseau réelles
│   ├── PLAN-ADRESSAGE-IP.txt
│   ├── edge1.txt, edge2.txt
│   ├── coresw1.txt, coresw2.txt
│   └── ...
├── virtconf/               # Configurations virtuelles (GNS3)
└── sujet1.md, sujet2.md    # Sujets de référence
```

## 🌐 Plan d'adressage (N=4)

| VLAN | Nom | Réseau | Passerelle |
|------|-----|--------|------------|
| 10 | Servers | 10.4.10.0/24 | 10.4.10.254 |
| 20 | Clients | 10.4.20.0/23 | 10.4.20.254 |
| 30 | DMZ | 217.4.160.0/24 | 217.4.160.254 |
| 99 | Management | 10.4.99.0/24 | 10.4.99.254 |

## 🖥️ Serveurs

| Machine | IP | OS | Rôle |
|---------|-----|-----|------|
| HQDCSRV | 10.4.10.1 | Win Server 2022 | AD, DNS, PKI |
| HQINFRASRV | 10.4.10.2 | Debian 13 | DHCP, VPN, NTP |
| HQMAILSRV | 10.4.10.3 | Debian 13 | Mail, Webmail |
| DCWSL | 10.4.10.4 | Debian 13 | Forest Root AD |
| DNSSRV | 8.8.4.1 | Debian 13 | DNS Public, Root CA |

## 🔐 Informations

- **Domaine** : wsl2025.org
- **Mot de passe par défaut** : `P@ssw0rd`

## 📚 Documentation

Voir le dossier [`documentation/`](documentation/) pour les guides complets de déploiement.

## 👥 Équipe

Projet réalisé dans le cadre du BUT3 Réseaux & Télécommunications - Université de Franche-Comté.

---

*WorldSkills Lyon 2025 - IT Network Systems Administration*

