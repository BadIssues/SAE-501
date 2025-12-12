================================================================
JALON 8 - SIMULATION ROUTEURS OSPF/BGP (EVE-NG)
================================================================

TOPOLOGIE:
----------
         PC1 (8.8.4.1)
           |
      WANRTR (AS65430)
      /           \
   EDGE1 ------- EDGE2   (AS65416)
     |             |
   PC2           PC3
(10.4.10.1)   (10.4.20.1)

MAPPING INTERFACES EVE-NG:
--------------------------
WANRTR: e0/0->EDGE2, e0/1->EDGE1, e0/2->PC1
EDGE1:  e0/0->WANRTR, e0/1->EDGE2, e0/2->PC2
EDGE2:  e0/0->WANRTR, e0/1->EDGE1, e0/2->PC3

ORDRE DE CONFIGURATION:
-----------------------
1. WANRTR
2. EDGE1
3. EDGE2
4. PC1: ip 8.8.4.1 255.255.255.248 8.8.4.6
5. PC2: ip 10.4.10.1 255.255.255.0 10.4.10.254
6. PC3: ip 10.4.20.1 255.255.255.0 10.4.20.254

PROTOCOLES:
-----------
- OSPF Area 4 NSSA + MD5 auth
- BGP: AS65430 (WANRTR) <-> AS65416 (EDGE1/2)
- iBGP entre EDGE1-EDGE2
- NAT/PAT sur EDGE1 et EDGE2

VERIFICATIONS:
--------------
show ip ospf neighbor
show ip bgp summary
show ip bgp
show ip route
show ip nat translations
================================================================
