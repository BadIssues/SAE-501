================================================================================
              JALON 7 - SIMULATION SWITCHES VLAN (EVE-NG)
================================================================================

Ce lab contient uniquement les SWITCHES pour démontrer :
- Configuration des VLANs
- VTP (Server/Client)
- Trunks 802.1Q
- Spanning-Tree (Rapid-PVST)
- HSRP sur les Core Switches
- Routage inter-VLAN

================================================================================
                         TOPOLOGIE EVE-NG
================================================================================

                    +-------+
                    |  VPC  | 10.4.10.1 (VLAN 10)
                    +---+---+
                        |eth0
                        |
                   e0/3 |
              +---------+---------+         +-----------------+
              |      CORESW1      |---e0/0--|     CORESW2     |
              +---------+---------+         +-----------------+
                   e0/1 |  e0/2                e0/1 |  e0/2
                        |     \                    |     /
                        |      \                   |    /
                   e0/0 |       \e0/2         e0/1 |   /e0/2
              +---------+--------+\          +-----+--/-------+
              |      ACCSW1       |  \      /|     ACCSW2     |
              +---------+---------+   \    / +---------+------+
                        |e0/1          \  /            |
                        +---------------\/-------------+
                                   e0/0  /\  e0/0
                                        /  \
                   e0/3 +--------------+    +--------------+ e0/3
                        |                                   |
                   e0/0 |                                   | e0/1
              +---------+-----------------------------------+------+
              |                    SWITCHESXI                      |
              +------------------------+---------------------------+
                                       |e0/2
                                       |
                                   +---+---+
                                   | Node7 | 10.4.20.1 (VLAN 20)
                                   +-------+

================================================================================
                    MAPPING INTERFACES
================================================================================

CORESW1 :
  e0/0 -> CORESW2 e0/0      (LACP Po1 - lien 1)
  e1/0 -> CORESW2 e0/3      (LACP Po1 - lien 2)
  e0/1 -> ACCSW1 e0/0       (trunk)
  e0/2 -> ACCSW2 e0/2       (trunk croisé)
  e0/3 -> VPC               (access VLAN 10)

CORESW2 :
  e0/0 -> CORESW1 e0/0      (LACP Po1 - lien 1)
  e0/3 -> CORESW1 e1/0      (LACP Po1 - lien 2)
  e0/1 -> ACCSW2 e0/1       (trunk)
  e0/2 -> ACCSW1 e0/2       (trunk croisé)

ACCSW1 :
  e0/0 -> CORESW1 e0/1      (trunk)
  e0/1 -> ACCSW2 e0/0       (trunk inter-access)
  e0/2 -> CORESW2 e0/2      (trunk croisé)
  e0/3 -> SWITCHESXI e0/0   (trunk)

ACCSW2 :
  e0/0 -> ACCSW1 e0/1       (trunk inter-access)
  e0/1 -> CORESW2 e0/1      (trunk)
  e0/2 -> CORESW1 e0/2      (trunk croisé)
  e0/3 -> SWITCHESXI e0/1   (trunk)

SWITCHESXI :
  e0/0 -> ACCSW1 e0/3       (trunk)
  e0/1 -> ACCSW2 e0/3       (trunk)
  e0/2 -> Node7             (access VLAN 20)

================================================================================
                    VLANs CONFIGURÉS
================================================================================

VLAN 10  - Servers      - 10.4.10.0/24  - VIP: 10.4.10.254
VLAN 20  - Clients      - 10.4.20.0/24  - VIP: 10.4.20.254
VLAN 30  - DMZ          - 217.4.160.0/24 - VIP: 217.4.160.254
VLAN 99  - Management   - 10.4.99.0/24  - VIP: 10.4.99.254
VLAN 666 - Blackhole    - Native VLAN (sécurité)

================================================================================
                    ORDRE DE CONFIGURATION
================================================================================

1. CORESW1 (VTP Server, crée les VLANs, STP Root priority 4096)
2. CORESW2 (VTP Server, STP Secondary priority 8192)
3. Attendre la synchronisation VTP (~10-30s)
4. ACCSW1 (VTP Client)
5. ACCSW2 (VTP Client)
6. SWITCHESXI (VTP Client)
7. Configurer les VPCs

================================================================================
                    CONFIGURATION DES VPCs
================================================================================

VPC (sur CORESW1 e0/3 - VLAN 10) :
  ip 10.4.10.1 255.255.255.0 10.4.10.254
  save

Node7 (sur SWITCHESXI e0/2 - VLAN 20) :
  ip 10.4.20.1 255.255.255.0 10.4.20.254
  save

================================================================================
                    COMMANDES DE VÉRIFICATION PAR ÉQUIPEMENT
================================================================================

--- CORESW1 ---
show vlan brief
show vtp status
show interfaces trunk
show etherchannel summary
show spanning-tree root
show standby brief
show port-security

--- CORESW2 ---
show vlan brief
show vtp status
show interfaces trunk
show etherchannel summary
show spanning-tree root
show standby brief

--- ACCSW1 ---
show vlan brief
show vtp status
show interfaces trunk
show errdisable recovery

--- ACCSW2 ---
show vlan brief
show vtp status
show interfaces trunk
show errdisable recovery

--- SWITCHESXI ---
show vlan brief
show vtp status
show interfaces trunk
show port-security
show errdisable recovery

--- VPC (VLAN 10) ---
ip 10.4.10.1 255.255.255.0 10.4.10.254
save
ping 10.4.10.254
ping 10.4.10.253
ping 10.4.10.252
ping 10.4.20.254
ping 10.4.20.1

--- Node7 (VLAN 20) ---
ip 10.4.20.1 255.255.255.0 10.4.20.254
save
ping 10.4.20.254
ping 10.4.20.253
ping 10.4.20.252
ping 10.4.10.254
ping 10.4.10.1

================================================================================
                    RÉSULTATS ATTENDUS
================================================================================

CORESW1 :
  - VLANs 10, 20, 30, 99, 666 présents
  - VTP Server, revision synchronisée
  - Po1(SU) avec Et0/0(P) et Et1/0(P)
  - Root pour tous les VLANs (priority 4096)
  - HSRP Active (priority 110)

CORESW2 :
  - VLANs synchronisés par VTP
  - VTP Server, même revision que CORESW1
  - Po1(SU) avec Et0/0(P) et Et0/3(P)
  - Root via Et0/0 (cost 100)
  - HSRP Standby (priority 100)

ACCSW1/ACCSW2/SWITCHESXI :
  - VLANs reçus par VTP (Client)
  - Trunks actifs avec VLANs 10,20,30,99
  - errdisable recovery 30 secondes

VPCs :
  - Ping VIP HSRP : 100% success
  - Ping CORESW1/2 : 100% success
  - Ping inter-VLAN : 100% success

================================================================================
