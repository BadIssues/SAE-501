================================================================================
                    CONFIGURATIONS VIRTUELLES EVE-NG
                      WorldSkills Lyon 2025 (N=4)
================================================================================

Ce dossier contient les configurations pour la simulation EVE-NG.

================================================================================
                         STRUCTURE DES DOSSIERS
================================================================================

virtconf/
├── jalon7-switches/        <- LAB 1 : Switches VLAN uniquement
│   ├── README.txt          <- Instructions pour le lab
│   ├── cmd-coresw1.txt     <- Config CORESW1
│   ├── cmd-coresw2.txt     <- Config CORESW2
│   ├── cmd-accsw1.txt      <- Config ACCSW1
│   ├── cmd-accsw2.txt      <- Config ACCSW2
│   ├── cmd-switchbaie.txt  <- Config SWITCHBAIE
│   └── vpcs.txt            <- IPs des VPCs pour tests
│
├── jalon8-routeurs/        <- LAB 2 : Routeurs OSPF/BGP uniquement
│   ├── README.txt          <- Instructions pour le lab
│   ├── cmd-wanrtr.txt      <- Config WANRTR (VRF)
│   ├── cmd-edge1.txt       <- Config EDGE1 (avec lien direct vers EDGE2)
│   ├── cmd-edge2.txt       <- Config EDGE2 (avec lien direct vers EDGE1)
│   ├── cmd-internet.txt    <- Simulateur Internet
│   ├── cmd-man.txt         <- Simulateur Site Remote (MAN/REMFW)
│   └── vpcs.txt            <- IPs des VPCs pour tests
│
└── (fichiers racine)       <- Configs complètes (all-in-one si besoin)

================================================================================
                    JALON 7 - SIMULATION SWITCHES VLAN
================================================================================

Objectif : Démontrer VLANs, VTP, Trunks, LACP, STP, HSRP

Équipements :
  - CORESW1 (IOL L2 - 8 interfaces)
  - CORESW2 (IOL L2 - 8 interfaces)
  - ACCSW1 (IOL L2 - 8 interfaces)
  - ACCSW2 (IOL L2 - 8 interfaces)
  - SWITCHBAIE (IOL L2 - 8 interfaces)
  - VPCs pour tests

Tests à montrer :
  1. show vlan brief (VLANs créés)
  2. show vtp status (VTP Server/Client synchronisé)
  3. show interfaces trunk (802.1Q trunks)
  4. show etherchannel summary (LACP Po1)
  5. show spanning-tree root (CORESW1 est Root)
  6. show standby brief (HSRP Active/Standby)
  7. Ping entre VPCs du même VLAN
  8. Ping vers VIP HSRP

================================================================================
                    JALON 8 - SIMULATION ROUTEURS OSPF/BGP
================================================================================

Objectif : Démontrer OSPF, BGP (eBGP/iBGP), VRF, NAT, Route-maps

Équipements :
  - WANRTR (IOL L3 ou CSR1000V)
  - EDGE1 (IOL L3)
  - EDGE2 (IOL L3)
  - INTERNET (IOL L3 - simule Internet)
  - MAN (IOL L3 - simule site Remote)
  - VPCs pour tests

Différence avec le réseau réel :
  - EDGE1 et EDGE2 sont connectés DIRECTEMENT via e0/2
  - Le peering iBGP utilise ce lien direct (pas via switches)

Tests à montrer :
  1. show ip ospf neighbor (tous en FULL)
  2. show ip bgp summary (eBGP + iBGP établis)
  3. show ip bgp (routes reçues)
  4. show ip route bgp (préférence via EDGE1)
  5. ping vrf INET/MAN depuis WANRTR
  6. Traceroute pour montrer le chemin préféré

================================================================================
                    IMAGES EVE-NG RECOMMANDÉES
================================================================================

Switches (IOL L2) :
  - i86bi-linux-l2-adventerprisek9-15.2d.bin
  - Ou vios_l2-adventerprisek9-m.vmdk

Routeurs (IOL L3) :
  - i86bi-linux-l3-adventerprisek9-15.4.2T4.bin
  - Ou CSR1000V pour WANRTR (supporte VRF)

VPCs :
  - VPCS intégré à EVE-NG

================================================================================
                    ORDRE DE DÉPLOIEMENT
================================================================================

Jalon 7 (Switches) :
  1. CORESW1 (crée les VLANs)
  2. CORESW2
  3. Attendre sync VTP (~30s)
  4. ACCSW1, ACCSW2
  5. SWITCHBAIE
  6. VPCs

Jalon 8 (Routeurs) :
  1. WANRTR
  2. EDGE1
  3. EDGE2
  4. INTERNET
  5. MAN
  6. VPCs

================================================================================



