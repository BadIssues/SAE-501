# REMFW - Firewall/Routeur Site Remote

> **OS** : Cisco CSR1000V (VM)  
> **IP MAN** : 10.116.N.X  
> **IP LAN** : 10.N.100.X  
> **Rôle** : Routeur, Firewall ACL, OSPF

---

## 📋 Prérequis

- [ ] VM Cisco CSR1000V déployée
- [ ] Interfaces configurées (MAN et LAN)
- [ ] Adjacence OSPF avec WANRTR fonctionnelle

---

## ⚠️ Note

La configuration de base du routage OSPF est déjà faite dans le cœur de réseau (`realconf/`). Ce document se concentre sur les **ACLs de sécurité**.

---

## 1️⃣ Configuration de base

### Vérifier la configuration existante
```
show running-config
show ip interface brief
show ip ospf neighbor
```

---

## 2️⃣ ACLs de sécurité

### ACL pour le trafic entrant depuis HQ

```
! ACL pour autoriser les services depuis HQ vers Remote
ip access-list extended FROM_HQ
 ! DNS
 permit udp 10.0.0.0 0.255.255.255 any eq 53
 permit tcp 10.0.0.0 0.255.255.255 any eq 53
 
 ! HTTPS
 permit tcp 10.0.0.0 0.255.255.255 any eq 443
 
 ! SSH
 permit tcp 10.0.0.0 0.255.255.255 any eq 22
 
 ! Active Directory / Kerberos
 permit tcp 10.0.0.0 0.255.255.255 any eq 88
 permit udp 10.0.0.0 0.255.255.255 any eq 88
 permit tcp 10.0.0.0 0.255.255.255 any eq 464
 permit udp 10.0.0.0 0.255.255.255 any eq 464
 
 ! LDAP / LDAPS
 permit tcp 10.0.0.0 0.255.255.255 any eq 389
 permit udp 10.0.0.0 0.255.255.255 any eq 389
 permit tcp 10.0.0.0 0.255.255.255 any eq 636
 
 ! SMB / CIFS
 permit tcp 10.0.0.0 0.255.255.255 any eq 445
 permit tcp 10.0.0.0 0.255.255.255 any eq 139
 permit udp 10.0.0.0 0.255.255.255 any eq 137
 permit udp 10.0.0.0 0.255.255.255 any eq 138
 
 ! RPC / DCE
 permit tcp 10.0.0.0 0.255.255.255 any eq 135
 permit tcp 10.0.0.0 0.255.255.255 any range 49152 65535
 
 ! Global Catalog
 permit tcp 10.0.0.0 0.255.255.255 any eq 3268
 permit tcp 10.0.0.0 0.255.255.255 any eq 3269
 
 ! NTP
 permit udp 10.0.0.0 0.255.255.255 any eq 123
 
 ! ICMP
 permit icmp 10.0.0.0 0.255.255.255 any
 
 ! Connexions établies
 permit tcp any any established
 
 ! Deny all other
 deny ip any any log
```

### ACL pour le trafic sortant vers Internet

```
! ACL pour autoriser Remote vers Internet
ip access-list extended TO_INTERNET
 ! HTTP/HTTPS
 permit tcp 10.N.100.0 0.0.0.255 any eq 80
 permit tcp 10.N.100.0 0.0.0.255 any eq 443
 
 ! DNS
 permit udp 10.N.100.0 0.0.0.255 any eq 53
 permit tcp 10.N.100.0 0.0.0.255 any eq 53
 
 ! ICMP
 permit icmp 10.N.100.0 0.0.0.255 any
 
 ! Deny all other
 deny ip any any log
```

---

## 3️⃣ Application des ACLs

```
! Appliquer sur l'interface MAN (vers WANRTR)
interface GigabitEthernet2
 description Connexion MAN vers WANRTR
 ip access-group FROM_HQ in

! Appliquer sur l'interface LAN (vers clients Remote)
interface GigabitEthernet3
 description LAN Remote Site
 ip access-group TO_INTERNET out
```

---

## 4️⃣ Route par défaut

```
! Route par défaut vers WANRTR
ip route 0.0.0.0 0.0.0.0 10.116.N.X
```

---

## 5️⃣ Sécurisation SSH

```
! Configuration SSH (déjà faite normalement)
ip access-list standard SSH_ACCESS
 permit 10.N.99.0 0.0.0.255
 deny any log

line vty 0 4
 access-class SSH_ACCESS in
 transport input ssh
```

---

## 6️⃣ Logging

```
! Activer le logging
logging buffered 16384 informational
logging trap informational

! Log les ACL deny
ip access-list extended FROM_HQ
 deny ip any any log
```

---

## 7️⃣ Vérification des ACLs

### Commandes de vérification
```
! Voir les ACLs
show access-lists

! Voir les hits sur les ACLs
show ip access-lists FROM_HQ
show ip access-lists TO_INTERNET

! Voir les interfaces
show ip interface GigabitEthernet2
show ip interface GigabitEthernet3

! Logs
show logging
```

---

## 8️⃣ Tableau récapitulatif des ports

| Service | Port | Protocole | Direction |
|---------|------|-----------|-----------|
| DNS | 53 | TCP/UDP | Bidirectionnel |
| HTTP | 80 | TCP | Sortant |
| HTTPS | 443 | TCP | Bidirectionnel |
| SSH | 22 | TCP | Entrant |
| Kerberos | 88, 464 | TCP/UDP | Entrant |
| LDAP | 389 | TCP/UDP | Entrant |
| LDAPS | 636 | TCP | Entrant |
| SMB | 445, 139 | TCP | Entrant |
| NetBIOS | 137, 138 | UDP | Entrant |
| RPC | 135 | TCP | Entrant |
| RPC Dynamic | 49152-65535 | TCP | Entrant |
| Global Catalog | 3268, 3269 | TCP | Entrant |
| NTP | 123 | UDP | Entrant |

---

## ✅ Vérifications

| Test | Commande |
|------|----------|
| OSPF | `show ip ospf neighbor` |
| Routes | `show ip route` |
| ACLs | `show access-lists` |
| Connectivity | Ping depuis REMCLT vers HQ |

---

## 📝 Notes

- Les ports RPC dynamiques (49152-65535) sont nécessaires pour AD
- L'ACL `established` permet le retour des connexions initiées
- Tous les paquets refusés sont loggés pour le debugging
- Ajuster les adresses `10.N.X.X` selon votre plan d'adressage

