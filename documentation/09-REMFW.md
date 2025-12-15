# REMFW - Firewall/Routeur Site Remote

> **OS** : Cisco CSR1000V (VM)  
> **IP MAN** : 10.116.4.1 (Gi1)  
> **IP LAN** : 10.4.100.126 (Gi2)  
> **Rôle** : Routeur, Firewall ACL, OSPF

---

## 🎯 Contexte (Sujet)

Ce routeur/firewall connecte le site Remote au réseau MAN (vers HQ) :

| Fonction | Description |
|----------|-------------|
| **OSPF** | Adjacence avec WANRTR (VRF MAN), authentification MD5. |
| **ACL Firewall** | Filtrage du trafic entrant depuis HQ. Seuls les services autorisés passent (SSH, DNS, HTTPS, Microsoft). |
| **Gateway** | Passerelle par défaut (10.4.100.126) pour le réseau Remote (10.4.100.0/25). |
| **Route par défaut** | Trafic inconnu routé vers WANRTR. |

---

## 📋 Prérequis

- [ ] VM Cisco CSR1000V déployée
- [ ] Connectivité WAN avec WANRTR établie
- [ ] Configuration appliquée via `realconf/remfw.txt`

---

## 1️⃣ Configuration des interfaces

Conformément à la configuration réelle :

```bash
interface GigabitEthernet1
 description TO-WANRTR-Fe0/0/0 (VRF MAN)
 ip address 10.116.4.1 255.255.255.252
 ip ospf authentication message-digest
 ip ospf message-digest-key 1 md5 P@ssw0rd
 ip ospf network point-to-point
 ip access-group FIREWALL-INBOUND in
 negotiation auto
!
interface GigabitEthernet2
 description TO-REMOTE-LAN
 ip address 10.4.100.126 255.255.255.128
 negotiation auto
```

---

## 2️⃣ ACL de Sécurité (FIREWALL-INBOUND)

Cette ACL filtre le trafic entrant depuis le WAN (HQ) vers le LAN Remote.

```bash
ip access-list extended FIREWALL-INBOUND
 remark === Allow established connections ===
 permit tcp any any established
 
 remark === Allow SSH from HQ ===
 permit tcp 10.4.0.0 0.0.255.255 any eq 22
 
 remark === Allow DNS ===
 permit udp any any eq domain
 permit tcp any any eq domain
 
 remark === Allow HTTPS ===
 permit tcp any any eq 443
 
 remark === Allow HTTP ===
 permit tcp any any eq 80
 
 remark === Allow ICMP ===
 permit icmp any any
 
 remark === Allow Microsoft Services ===
 permit tcp any any eq 445
 permit udp any any eq 445
 permit tcp any any range 135 139
 permit udp any any range 135 139
 
 remark === Allow Kerberos ===
 permit tcp any any eq 88
 permit udp any any eq 88
 
 remark === Allow LDAP ===
 permit tcp any any eq 389
 permit udp any any eq 389
 permit tcp any any eq 636
 
 remark === Allow NTP ===
 permit udp any any eq ntp
 
 remark === Deny all other ===
 deny   ip any any log
```

---

## 3️⃣ Sécurisation SSH (Management)

L'accès SSH est restreint aux réseaux d'administration et au LAN local.

```bash
ip access-list extended SSH-ACCESS
 permit tcp 10.4.99.0 0.0.0.255 any eq 22
 permit tcp 10.4.100.0 0.0.0.127 any eq 22
 deny   tcp any any eq 22 log
 permit ip any any

line vty 0 4
 access-class SSH-ACCESS in
 transport input ssh
```

---

## 4️⃣ Routage OSPF

Configuration OSPF pour l'interconnexion avec le WAN (Area 4 NSSA).

```bash
router ospf 1
 router-id 10.116.4.1
 area 4 nssa no-summary
 passive-interface default
 no passive-interface GigabitEthernet1
 network 10.116.4.0 0.0.0.3 area 4
 network 10.4.100.0 0.0.0.127 area 4
 default-information originate
```

---

## ✅ Vérification Finale

> **Instructions** : Exécuter ces commandes sur REMFW (console ou SSH) pour valider le bon fonctionnement.

### 1. Interfaces UP
```
show ip interface brief
```
✅ Gi1 (10.116.4.1) et Gi2 (10.4.100.126) doivent être `up/up`

### 2. OSPF - Voisinage avec WANRTR
```
show ip ospf neighbor
```
✅ Doit montrer un voisin (WANRTR) en état `FULL`

### 3. Routes OSPF reçues
```
show ip route ospf
```
✅ Doit afficher les routes vers HQ (10.4.0.0/16) et autres réseaux

### 4. ACL Firewall active
```
show ip access-lists FIREWALL-INBOUND
```
✅ L'ACL doit être présente avec des compteurs (hits)

### 5. Ping vers HQ (via OSPF)
```
ping 10.4.10.1
```
✅ HQDCSRV doit répondre

### 6. Ping vers Internet (via route par défaut)
```
ping 8.8.4.1
```
✅ DNSSRV doit répondre (si route par défaut configurée)

### Tableau récapitulatif

| Test | Commande | Résultat attendu |
|------|----------|------------------|
| Gi1 UP | `show ip int brief \| i Gi1` | `up/up` |
| Gi2 UP | `show ip int brief \| i Gi2` | `up/up` |
| OSPF neighbor | `show ip ospf neighbor` | 1 voisin `FULL` |
| Route HQ | `show ip route \| i 10.4.0.0` | Présente |
| ACL | `show ip access-lists` | FIREWALL-INBOUND |
| Ping HQDCSRV | `ping 10.4.10.1` | Réponse |

---

## 📝 Notes

- La configuration complète est disponible dans `realconf/remfw.txt`.
- L'ACL `FIREWALL-INBOUND` est appliquée en **entrée** sur l'interface WAN (Gi1).
- Pas d'ACL en sortie sur le LAN (Gi2) dans la configuration actuelle.
