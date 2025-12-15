# Corrections à apporter aux configurations CONFPE

## Comparaison avec REALCONF - Configurations de référence

Ce document liste toutes les corrections nécessaires pour aligner les configurations de `confpe/` sur les bonnes pratiques définies dans `realconf/`.

> **Note:** Les adresses IP utilisent le numéro de groupe 6 (confpe) vs 4 (realconf). Les différences d'adressage liées au numéro de groupe sont normales. Ce document se concentre sur les **différences structurelles et fonctionnelles**.

---

## 🔴 EDGE1 - Corrections requises

### 1. Sécurité - MANQUANT

#### 1.1 Encryption des mots de passe
```diff
- no service password-encryption
+ service password-encryption
```

#### 1.2 Enable secret - MANQUANT
```cisco
enable secret 5 $1$mERr$hx5rVt7rPNoS4wqbXKX7m0
```

#### 1.3 Configuration SSH renforcée - MANQUANT
```cisco
ip ssh time-out 120
ip ssh authentication-retries 3
```

#### 1.4 ACL de sécurité SSH - MANQUANT
```cisco
ip access-list extended SSH-ACCESS
 permit tcp 10.6.99.0 0.0.0.255 any eq 22
 deny   tcp any any eq 22 log
 permit ip any any
```

#### 1.5 Banner de connexion - MANQUANT
```cisco
banner login ^C
/!\ Restricted access. Only for authorized people /!\
^C
```

#### 1.6 Configuration VTY sécurisée - À CORRIGER
```diff
  line vty 0 4
+  access-class SSH-ACCESS in
+  exec-timeout 5 0
+  absolute-timeout 20
   login local
-  transport input telnet ssh
+  transport input ssh
```

---

### 2. Interfaces - ERREURS DE PLACEMENT

#### 2.1 Structure actuelle (INCORRECTE)
Les interfaces sont mal positionnées sur les ports physiques :

| Interface actuelle (confpe) | Devrait être (realconf) |
|----------------------------|-------------------------|
| Gi0/0.30 (DMZ) | Gi0/1.30 |
| Gi0/0.100 (vers CORESW1) | Gi0/1.100 |
| Gi0/0.300 (iBGP EDGE2) | Gi0/1.300 |
| Gi0/1.13 (vers WANRTR MAN) | Gi0/0.13 |
| Gi0/1.14 (vers WANRTR INET) | Gi0/0.14 |

#### 2.2 Interface Gi0/0.13 - Configuration correcte
```cisco
interface GigabitEthernet0/0.13
 description LINK-TO-WANRTR (VRF MAN)
 encapsulation dot1Q 13
 ip address 10.6.254.5 255.255.255.252
 ip nat inside
 ip ospf authentication message-digest
 ip ospf message-digest-key 1 md5 P@ssw0rd
 ip ospf network point-to-point
```

#### 2.3 Interface Gi0/0.14 - Masque incorrect
```diff
  interface GigabitEthernet0/0.14
   encapsulation dot1Q 14
-  ip address 91.6.222.97 255.255.255.252
+  ip address 91.6.222.97 255.255.255.248
   ip nat outside
```

#### 2.4 Interface DMZ (VLAN 30) - Masque et Track HSRP manquants
```diff
  interface GigabitEthernet0/1.30
   encapsulation dot1Q 30
-  ip address 217.6.160.12 255.255.255.240
+  ip address 217.6.160.253 255.255.255.0
   standby 30 ip 217.6.160.14
   standby 30 priority 110
   standby 30 preempt
+  standby 30 track 10 decrement 20
   ip nat inside
```

---

### 3. Track Object - MANQUANT
```cisco
track 10 interface GigabitEthernet0/1.100 line-protocol
```

---

### 4. OSPF - Corrections majeures

#### 4.1 Configuration OSPF actuelle vs correcte
```diff
- router ospf 6
-  router-id 1.1.1.1
+ router ospf 1
+  router-id 10.6.254.13
+  area 6 nssa no-summary
+  passive-interface default
+  no passive-interface GigabitEthernet0/0.13
+  no passive-interface GigabitEthernet0/1.300
   redistribute static subnets
+  redistribute bgp 6060 subnets route-map BGP-TO-OSPF
   network 10.6.254.0 0.0.0.3 area 6
   network 10.6.254.4 0.0.0.3 area 6
   network 10.6.254.12 0.0.0.3 area 6
+  network 91.6.222.96 0.0.0.7 area 6
```

#### 4.2 Point-to-point sur interfaces OSPF - MANQUANT
Ajouter sur les interfaces OSPF :
```cisco
 ip ospf network point-to-point
```

---

### 5. BGP - Route-map manquante

#### 5.1 Route-map BGP-TO-OSPF - MANQUANT
```cisco
ip prefix-list INTERNET-PREFIX seq 10 permit 8.8.6.0/29

route-map BGP-TO-OSPF permit 10
 match ip address prefix-list INTERNET-PREFIX
```

---

### 6. Routes statiques - Corrections

#### 6.1 Routes Null0 pour agrégation BGP - MANQUANT
```cisco
ip route 191.6.157.32 255.255.255.240 Null0
ip route 217.6.160.0 255.255.255.0 Null0
```

---

### 7. NAT - Corrections mineures

#### 7.1 Règle NAT statique VPN port 4443 - MANQUANT/DIFFÉRENT
```diff
- ip nat inside source static tcp 10.6.10.2 80 191.6.157.33 80 extendable
- ip nat inside source static tcp 10.6.10.2 443 191.6.157.33 443 extendable
+ ip nat inside source static tcp 10.6.10.2 443 191.6.157.33 4443 extendable
+ ip nat inside source static tcp 10.6.10.3 80 191.6.157.33 80 extendable
+ ip nat inside source static tcp 10.6.10.3 443 191.6.157.33 443 extendable
```

#### 7.2 ACL NAT - Règle manquante pour réseau Remote
```diff
  ip access-list extended NAT-ACL
   permit ip 10.6.0.0 0.0.255.255 any
+  permit ip 10.116.6.0 0.0.0.3 any
```

---

## 🔴 EDGE2 - Corrections requises

### 1. Sécurité - MÊMES PROBLÈMES QUE EDGE1

- ❌ `service password-encryption` manquant
- ❌ `enable secret` manquant
- ❌ Configuration SSH renforcée manquante
- ❌ ACL SSH-ACCESS manquante
- ❌ Banner login manquant
- ❌ Configuration VTY non sécurisée

---

### 2. Interfaces - MÊMES ERREURS DE PLACEMENT QUE EDGE1

| Interface actuelle (confpe) | Devrait être (realconf) |
|----------------------------|-------------------------|
| Gi0/0.30 (DMZ) | Gi0/1.30 |
| Gi0/0.200 (vers CORESW2) | Gi0/1.200 |
| Gi0/0.300 (iBGP EDGE1) | Gi0/1.300 |
| Gi0/1.15 (vers WANRTR MAN) | Gi0/0.15 |
| Gi0/1.16 (vers WANRTR INET) | Gi0/0.16 |

---

### 3. HSRP - Track manquant
```diff
+ track 20 interface GigabitEthernet0/1.200 line-protocol

  interface GigabitEthernet0/1.30
   standby 30 ip 217.6.160.14
+  standby 30 priority 100
   standby 30 preempt
+  standby 30 track 20 decrement 20
```

---

### 4. NAT - COMPLÈTEMENT MANQUANT !

**CRITIQUE:** EDGE2 n'a AUCUNE configuration NAT dans confpe !

```cisco
! Ajouter sur les interfaces appropriées:
! - ip nat inside sur les interfaces internes
! - ip nat outside sur Gi0/0.16

ip nat inside source list NAT-ACL interface GigabitEthernet0/0.16 overload
ip nat inside source static tcp 10.6.10.2 443 191.6.157.34 4443 extendable
ip nat inside source static tcp 10.6.10.3 80 191.6.157.34 80 extendable
ip nat inside source static tcp 10.6.10.3 443 191.6.157.34 443 extendable

ip access-list extended NAT-ACL
 permit ip 10.6.0.0 0.0.255.255 any
 permit ip 10.116.6.0 0.0.0.3 any
```

---

### 5. OSPF - Mêmes corrections que EDGE1

```diff
- router ospf 6
-  router-id 2.2.2.2
+ router ospf 1
+  router-id 10.6.254.18
+  area 6 nssa no-summary
+  passive-interface default
+  no passive-interface GigabitEthernet0/0.15
+  no passive-interface GigabitEthernet0/1.300
   redistribute static subnets
+  redistribute bgp 6060 subnets route-map BGP-TO-OSPF
```

---

### 6. BGP - Route-map PREPEND-OUT manquante

```diff
  neighbor 31.6.126.14 activate
- neighbor 31.6.126.14 route-map SET-LOCAL-PREF in
+ neighbor 31.6.126.14 route-map PREPEND-OUT out

+ route-map PREPEND-OUT permit 10
+  set as-path prepend 6060 6060
```

**Note:** EDGE2 doit utiliser AS-PATH prepend pour être le routeur de backup, pas SET-LOCAL-PREF.

---

### 7. Routes statiques Null0 - MANQUANT
```cisco
ip route 191.6.157.32 255.255.255.240 Null0
ip route 217.6.160.0 255.255.255.0 Null0
```

---

## 🔴 WANRTR - Corrections requises

### 1. Sécurité - MÊMES PROBLÈMES

- ❌ `service password-encryption` manquant
- ❌ `enable secret` manquant
- ❌ Configuration SSH renforcée manquante
- ❌ ACL SSH-ACCESS manquante
- ❌ Banner login manquant
- ❌ Configuration VTY non sécurisée

---

### 2. VRF - Syntaxe obsolète

#### 2.1 Utiliser la nouvelle syntaxe VRF
```diff
- ip vrf INET
-  rd 6560:20
- ip vrf MAN
-  rd 6060:10

+ vrf definition INET
+  rd 1:1
+  address-family ipv4
+  exit-address-family
+ 
+ vrf definition MAN
+  rd 2:2
+  address-family ipv4
+  exit-address-family
```

#### 2.2 Syntaxe interface VRF
```diff
- ip vrf forwarding MAN
+ vrf forwarding MAN
```

---

### 3. Interface Gi0/0.13 - Configuration incomplète
```diff
  interface GigabitEthernet0/0.13
-  ip ospf cost 10
+  description LINK-TO-EDGE1 (VRF MAN)
+  encapsulation dot1Q 13
+  vrf forwarding MAN
+  ip address 10.6.254.6 255.255.255.252
+  ip ospf authentication message-digest
+  ip ospf message-digest-key 1 md5 P@ssw0rd
+  ip ospf network point-to-point
+  ip ospf cost 10
```

**Note:** L'interface Gi0/0.13 dans confpe n'a que `ip ospf cost 10`, toute la configuration est manquante !

---

### 4. OSPF - Corrections

```diff
- router ospf 6 vrf MAN
-  router-id 3.3.3.3
+ router ospf 1 vrf MAN
+  router-id 10.6.254.14
+  area 6 nssa
+  passive-interface default
+  no passive-interface GigabitEthernet0/0.13
+  no passive-interface GigabitEthernet0/1.15
+  no passive-interface FastEthernet0/0/0
```

---

### 5. BGP - Corrections AS Number

```diff
- router bgp 6560
-  bgp router-id 3.3.3.3
+ router bgp 65430
+  bgp router-id 91.6.222.98
```

---

### 6. Track et EEM - MANQUANT

Pour la haute disponibilité du lien vers REMFW :
```cisco
track 1 interface FastEthernet0/0/0 line-protocol

event manager applet INTERFACE-RECOVERY
 event track 1 state down
 action 1.0 cli command "enable"
 action 2.0 cli command "configure terminal"
 action 3.0 cli command "interface FastEthernet0/0/0"
 action 4.0 cli command "no shutdown"
 action 5.0 cli command "end"
 action 6.0 syslog msg "Interface have been re-enabled automatically due to down status"
```

---

### 7. Interface Internet - Masque incorrect

```diff
  interface FastEthernet0/1/0
   description WAN_INTERNET
   ip vrf forwarding INET
-  ip address 8.8.6.254 255.255.255.0
+  ip address 8.8.6.6 255.255.255.248
```

---

### 8. Route statique - Masque incorrect

```diff
- ip route vrf INET 8.8.6.0 255.255.255.0 Null0
+ ip route vrf INET 8.8.6.0 255.255.255.248 Null0
```

---

### 9. BGP Network - Masque incorrect

```diff
  address-family ipv4 vrf INET
-  network 8.8.6.0 mask 255.255.255.0
+  network 8.8.6.0 mask 255.255.255.248
```

---

## 📋 Résumé des corrections prioritaires

### CRITIQUE (bloquant)
1. **EDGE2** : NAT complètement absent
2. **WANRTR** : Interface Gi0/0.13 quasi-vide
3. **Tous** : Mauvais placement des interfaces (Gi0/0 ↔ Gi0/1)

### HAUTE PRIORITÉ
4. **Tous** : OSPF - Area NSSA, passive-interface, point-to-point
5. **Tous** : HSRP tracking manquant
6. **EDGE2** : Route-map PREPEND-OUT au lieu de SET-LOCAL-PREF
7. **WANRTR** : Syntaxe VRF obsolète

### SÉCURITÉ
8. **Tous** : service password-encryption
9. **Tous** : enable secret
10. **Tous** : ACL SSH-ACCESS
11. **Tous** : Banner login
12. **Tous** : VTY timeout et transport SSH only

---

## ✅ Commandes de vérification après corrections

```cisco
! Vérifier OSPF
show ip ospf neighbor
show ip ospf interface brief
show ip route ospf

! Vérifier BGP
show ip bgp summary
show ip bgp neighbors
show ip bgp

! Vérifier HSRP
show standby brief
show track

! Vérifier NAT
show ip nat translations
show ip nat statistics

! Vérifier VRF (WANRTR)
show vrf
show ip route vrf MAN
show ip route vrf INET
```

