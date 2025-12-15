# REMFW - Firewall/Routeur Site Remote

> **OS** : Cisco CSR1000V (VM)  
> **IP MAN** : 10.116.4.1 (Gi1)  
> **IP LAN** : 10.4.100.126 (Gi2)  
> **Rôle** : Routeur, Firewall ACL, OSPF

---

## 🎯 Contexte (Sujet)

Ce routeur/firewall connecte le site Remote au réseau MAN (vers HQ) :

| Fonction             | Description                                                                                              |
| -------------------- | -------------------------------------------------------------------------------------------------------- |
| **OSPF**             | Adjacence avec WANRTR (VRF MAN), authentification MD5.                                                   |
| **ACL Firewall**     | Filtrage du trafic entrant depuis HQ. Seuls les services autorisés passent (SSH, DNS, HTTPS, Microsoft). |
| **Gateway**          | Passerelle par défaut (10.4.100.126) pour le réseau Remote (10.4.100.0/25).                              |
| **Route par défaut** | Trafic inconnu routé vers WANRTR.                                                                        |

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

### 🔌 Comment se connecter à REMFW

1. Ouvrir la console VMware du routeur REMFW
2. Appuie sur Entrée pour voir le prompt
3. Tu dois voir : `REMFW>` ou `REMFW#`
4. Si tu es en mode `>`, tape `enable` puis le mot de passe pour passer en mode `#`

---

### Test 1 : Vérifier les interfaces

**Étape 1** : Tape cette commande :
```
show ip interface brief
```

**Étape 2** : Regarde le résultat :
```
Interface              IP-Address      OK? Method Status    Protocol
GigabitEthernet1       10.116.4.1      YES manual up        up
GigabitEthernet2       10.4.100.126    YES manual up        up
```

✅ **C'est bon si** : Gi1 et Gi2 sont tous les deux `up` / `up`
❌ **Problème si** : `administratively down` ou `down` → Interface désactivée

---

### Test 2 : Vérifier OSPF

**Étape 1** : Tape cette commande :
```
show ip ospf neighbor
```

**Étape 2** : Regarde le résultat :
```
Neighbor ID     Pri   State           Dead Time   Address         Interface
10.116.4.2        1   FULL/  -        00:00:35    10.116.4.2      Gi1
```

✅ **C'est bon si** : Tu vois un voisin (WANRTR) en état `FULL`
❌ **Problème si** : Tableau vide → OSPF n'a pas établi de voisinage

---

### Test 3 : Vérifier les routes OSPF

**Étape 1** : Tape cette commande :
```
show ip route ospf
```

**Étape 2** : Regarde le résultat (tu dois voir des routes vers HQ) :
```
O IA  10.4.10.0/24 [110/XX] via 10.116.4.2, ...
O IA  10.4.20.0/23 [110/XX] via 10.116.4.2, ...
```

✅ **C'est bon si** : Tu vois des routes commençant par `O` vers `10.4.x.x`
❌ **Problème si** : Aucune route → OSPF ne reçoit pas les routes de WANRTR

---

### Test 4 : Vérifier l'ACL

**Étape 1** : Tape cette commande :
```
show ip access-lists FIREWALL-INBOUND
```

**Étape 2** : Regarde le résultat :
```
Extended IP access list FIREWALL-INBOUND
    10 permit tcp any any established (XXX matches)
    20 permit tcp 10.4.0.0 0.0.255.255 any eq 22 (XXX matches)
    ...
```

✅ **C'est bon si** : Tu vois l'ACL avec des règles et des compteurs (matches)
❌ **Problème si** : "not found" → ACL pas configurée

---

### Test 5 : Ping vers HQ

**Étape 1** : Tape cette commande :
```
ping 10.4.10.1
```

**Étape 2** : Regarde le résultat :
```
Type escape sequence to abort.
Sending 5, 100-byte ICMP Echos to 10.4.10.1, timeout is 2 seconds:
!!!!!
Success rate is 100 percent (5/5)
```

✅ **C'est bon si** : Tu vois `!!!!!` et "Success rate is 100 percent"
❌ **Problème si** : `.....` et "0 percent" → Pas de route ou ACL bloque

---

### 📋 Résumé rapide (tape ces commandes une par une)

```
show ip interface brief | include Gig
show ip ospf neighbor
show ip route ospf | include 10.4
show ip access-lists FIREWALL-INBOUND | include matches
ping 10.4.10.1
```

### Tableau récapitulatif

| Test          | Commande                      | Résultat attendu |
| ------------- | ----------------------------- | ---------------- |
| Gi1 UP        | `show ip int brief \| i Gi1`  | `up/up`          |
| Gi2 UP        | `show ip int brief \| i Gi2`  | `up/up`          |
| OSPF neighbor | `show ip ospf neighbor`       | 1 voisin `FULL`  |
| Route HQ      | `show ip route \| i 10.4.0.0` | Présente         |
| ACL           | `show ip access-lists`        | FIREWALL-INBOUND |
| Ping HQDCSRV  | `ping 10.4.10.1`              | Réponse          |

---

## 📝 Notes

- La configuration complète est disponible dans `realconf/remfw.txt`.
- L'ACL `FIREWALL-INBOUND` est appliquée en **entrée** sur l'interface WAN (Gi1).
- Pas d'ACL en sortie sur le LAN (Gi2) dans la configuration actuelle.
