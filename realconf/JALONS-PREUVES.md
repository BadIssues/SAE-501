# 📋 Preuves Jalons Cœur de Réseau - SAE501 (N=4)

> **WorldSkills Lyon 2025** - wsl2025.org

---

## 📑 Table des Matières

- [Jalons Concernés](#jalons-concernés)
- [Jalon 5 - Plan d'Adressage IP + DNS](#jalon-5--plan-dadressage-ip--dns)
- [Jalon 10 - Déploiement VLAN Switches](#jalon-10--déploiement-vlan-switches)
- [Jalon 12 - Déploiement OSPF/BGP Routeurs](#jalon-12--déploiement-ospfbgp-routeurs)
- [Jalon 13 - HSRP Configuration Switches](#jalon-13--hsrp-configuration-switches)
- [Jalon 14 - HSRP EDGE Routeurs](#jalon-14--hsrp-edge-routeurs)
- [Jalon 15 - NAT EDGE WANRTR](#jalon-15--nat-edge-wanrtr)
- [Jalon 16 - Accès DMZ](#jalon-16--accès-dmz)
- [Jalon 17 - EDGEX NAT/PAT VPN](#jalon-17--edgex-natpat-vpn)
- [Checklist Finale](#checklist-finale)
- [Commandes Copier-Coller](#commandes-copier-coller-par-équipement)

---

## Jalons Concernés

### ✅ Traités dans ce document (Cœur de réseau)

| Jalon | Description                   |
| :---: | ----------------------------- |
|   5   | Plan d'adressage IP + DNS     |
|  10   | Déploiement VLAN switches     |
|  12   | Déploiement OSPF/BGP routeurs |
|  13   | HSRP configuration switches   |
|  14   | HSRP EDGE routeurs            |
|  15   | NAT EDGE WANRTR               |
|  16   | Accès DMZ                     |
|  17   | EDGEX NAT/PAT VPN             |

### ❌ Non traités ici

|  Jalons  | Description                        |
| :------: | ---------------------------------- |
|   1-4    | Gestion projet (PilPro)            |
|   7-8    | Simulation EVE-NG (vérifié sur PC) |
| 6, 9, 11 | ESXi                               |
|  18-19   | DNS/CA (Cyber)                     |

---

## Jalon 5 – Plan d'Adressage IP + DNS

### 📁 Ce qu'il faut rendre

- [ ] Fichier `PLAN-ADRESSAGE-IP.pdf` (ou .txt)
- [ ] Schéma DNS avec les zones et serveurs

### 📋 Contenu attendu

1. Tableau des VLANs (10, 20, 30, 99, 100, 200, 300, 666)
2. Adresses IP de tous les équipements
3. Plages DHCP
4. Configuration HSRP (VIP, priorités)
5. Schéma DNS (DNSSRV → DCWSL → HQDCSRV/REMDCSRV)

> ✅ **Fichier déjà prêt** : `realconf/PLAN-ADRESSAGE-IP.txt`

---

## Jalon 10 – Déploiement VLAN Switches

**Ordre** : CORESW1 → CORESW2 → ACCSW1 → ACCSW2

### Étape 1 : CORESW1

**Connexion** : SSH vers `10.4.99.253` • Login: `admin` / `P@ssw0rd`

```cisco
show vlan brief
show vtp status
show interfaces trunk
show etherchannel summary
show spanning-tree root
show ip interface brief
```

**Captures à faire :**

| Fichier                 | Commande                    | Vérification   |
| ----------------------- | --------------------------- | -------------- |
| `J10-CORESW1-vlans.png` | `show vlan brief`           | VLANs présents |
| `J10-CORESW1-vtp.png`   | `show vtp status`           | VTP Server     |
| `J10-CORESW1-trunk.png` | `show interfaces trunk`     | Trunks actifs  |
| `J10-CORESW1-lacp.png`  | `show etherchannel summary` | Po1 actif      |
| `J10-CORESW1-stp.png`   | `show spanning-tree root`   | Root Bridge    |

### Étape 2 : CORESW2

**Connexion** : SSH vers `10.4.99.252`

```cisco
show vlan brief
show vtp status
show interfaces trunk
show etherchannel summary
show spanning-tree root
show ip interface brief
```

**Captures à faire :**

| Fichier                 | Commande                    | Vérification      |
| ----------------------- | --------------------------- | ----------------- |
| `J10-CORESW2-vlans.png` | `show vlan brief`           | VLANs présents    |
| `J10-CORESW2-vtp.png`   | `show vtp status`           | VTP Server backup |
| `J10-CORESW2-lacp.png`  | `show etherchannel summary` | Po1 actif         |
| `J10-CORESW2-stp.png`   | `show spanning-tree root`   | Secondary Root    |

### Étape 3 : ACCSW1

**Connexion** : SSH vers `10.4.99.11`

```cisco
show vlan brief
show vtp status
show interfaces trunk
show port-security
show errdisable recovery
ping 10.4.99.253
ping 10.4.99.252
```

**Captures à faire :**

| Fichier                  | Commande                       |
| ------------------------ | ------------------------------ |
| `J10-ACCSW1-vlans.png`   | `show vlan brief`              |
| `J10-ACCSW1-vtp.png`     | `show vtp status` (VTP Client) |
| `J10-ACCSW1-trunk.png`   | `show interfaces trunk`        |
| `J10-ACCSW1-portsec.png` | `show port-security`           |
| `J10-ACCSW1-ping.png`    | Ping CORESW1 et CORESW2        |

### Étape 4 : ACCSW2

**Connexion** : SSH vers `10.4.99.12`

```cisco
show vlan brief
show vtp status
show interfaces trunk
show port-security
show errdisable recovery
ping 10.4.99.253
ping 10.4.99.252
```

**Captures à faire :**

| Fichier                | Commande                       |
| ---------------------- | ------------------------------ |
| `J10-ACCSW2-vlans.png` | `show vlan brief`              |
| `J10-ACCSW2-vtp.png`   | `show vtp status` (VTP Client) |
| `J10-ACCSW2-trunk.png` | `show interfaces trunk`        |

### Étape 5 : Test depuis un PC Client

Sur un PC dans VLAN 20 (DHCP ou IP manuelle `10.4.20.x`) :

```cmd
ipconfig
ping 10.4.20.254
ping 10.4.10.254
ping 10.4.99.254
```

**Capture** : `J10-PC-ping-vip.png` → Ping vers les VIP HSRP

### 📁 Résumé Jalon 10 – 17 fichiers

| #   | Fichier                  |
| --- | ------------------------ |
| 1   | `J10-CORESW1-vlans.png`  |
| 2   | `J10-CORESW1-vtp.png`    |
| 3   | `J10-CORESW1-trunk.png`  |
| 4   | `J10-CORESW1-lacp.png`   |
| 5   | `J10-CORESW1-stp.png`    |
| 6   | `J10-CORESW2-vlans.png`  |
| 7   | `J10-CORESW2-vtp.png`    |
| 8   | `J10-CORESW2-lacp.png`   |
| 9   | `J10-CORESW2-stp.png`    |
| 10  | `J10-ACCSW1-vlans.png`   |
| 11  | `J10-ACCSW1-vtp.png`     |
| 12  | `J10-ACCSW1-trunk.png`   |
| 13  | `J10-ACCSW1-portsec.png` |
| 14  | `J10-ACCSW1-ping.png`    |
| 15  | `J10-ACCSW2-vlans.png`   |
| 16  | `J10-ACCSW2-vtp.png`     |
| 17  | `J10-ACCSW2-trunk.png`   |
| 18  | `J10-PC-ping-vip.png`    |

---

## Jalon 12 – Déploiement OSPF/BGP Routeurs

**Ordre** : EDGE1 → EDGE2 → WANRTR

### Étape 1 : EDGE1

**Connexion** : Console ou SSH • Login: `admin` / `P@ssw0rd`

```cisco
show ip interface brief
show ip ospf neighbor
show ip ospf database
show ip bgp summary
show ip bgp
show ip route
ping 91.4.222.98
ping 10.4.254.14
ping 10.4.254.10
```

**Captures à faire :**

| Fichier                    | Commande                  | Vérification    |
| -------------------------- | ------------------------- | --------------- |
| `J12-EDGE1-interfaces.png` | `show ip interface brief` | Interfaces UP   |
| `J12-EDGE1-ospf.png`       | `show ip ospf neighbor`   | Voisin WANRTR   |
| `J12-EDGE1-bgp.png`        | `show ip bgp summary`     | 2 peers         |
| `J12-EDGE1-routes.png`     | `show ip route`           | Routes OSPF/BGP |
| `J12-EDGE1-ping.png`       | Ping WANRTR et EDGE2      | Connectivité    |

### Étape 2 : EDGE2

```cisco
show ip interface brief
show ip ospf neighbor
show ip bgp summary
show ip bgp
show ip route
ping 31.4.126.14
ping 10.4.254.17
ping 10.4.254.9
```

**Captures à faire :**

| Fichier                    | Commande                  |
| -------------------------- | ------------------------- |
| `J12-EDGE2-interfaces.png` | `show ip interface brief` |
| `J12-EDGE2-ospf.png`       | `show ip ospf neighbor`   |
| `J12-EDGE2-bgp.png`        | `show ip bgp summary`     |
| `J12-EDGE2-routes.png`     | `show ip route`           |
| `J12-EDGE2-ping.png`       | Ping WANRTR et EDGE1      |

### Étape 3 : WANRTR

```cisco
show ip interface brief
show vrf
show ip vrf interfaces
show ip ospf vrf MAN neighbor
show bgp vrf INET summary
show bgp vrf INET
ping vrf INET 91.4.222.97
ping vrf INET 31.4.126.13
ping vrf MAN 10.4.254.13
ping vrf MAN 10.4.254.18
```

**Captures à faire :**

| Fichier               | Commande                              | Vérification |
| --------------------- | ------------------------------------- | ------------ |
| `J12-WANRTR-vrf.png`  | `show vrf` + `show ip vrf interfaces` | VRF INET/MAN |
| `J12-WANRTR-ospf.png` | `show ip ospf vrf MAN neighbor`       | 2 voisins    |
| `J12-WANRTR-bgp.png`  | `show bgp vrf INET summary`           | 2 peers      |
| `J12-WANRTR-ping.png` | Ping avec VRF                         | Connectivité |

### 📁 Résumé Jalon 12 – 14 fichiers

| Équipement | Fichiers                            |
| ---------- | ----------------------------------- |
| EDGE1      | interfaces, ospf, bgp, routes, ping |
| EDGE2      | interfaces, ospf, bgp, routes, ping |
| WANRTR     | vrf, ospf, bgp, ping                |

---

## Jalon 13 – HSRP Configuration Switches

**Ordre** : CORESW1 → CORESW2 → Test failover

### Étape 1 : CORESW1 (Active)

**Connexion** : SSH vers `10.4.99.253`

```cisco
show standby brief
show track 10
```

**Vérifier :**

- État "Active" pour les groupes 10, 20, 99
- Priority = 110
- Track 10 = UP

**Captures :**

- `J13-CORESW1-hsrp.png` → show standby brief (Active)
- `J13-CORESW1-track.png` → show track 10 (UP)

### Étape 2 : CORESW2 (Standby)

**Connexion** : SSH vers `10.4.99.252`

```cisco
show standby brief
show track 20
```

**Vérifier :**

- État "Standby" pour les groupes 10, 20, 99
- Priority = 100

**Captures :**

- `J13-CORESW2-hsrp.png` → show standby brief (Standby)
- `J13-CORESW2-track.png` → show track 20

### Étape 3 : Test de Failover 🎬

> 💡 **Vidéo recommandée** pour cette étape

**1. Lancer un ping continu depuis ACCSW1 :**

```cmd
ping 10.4.99.254 -t
```

**2. Sur CORESW1, couper l'interface :**

```cisco
conf t
interface Vlan100
shutdown
end
```

**3. Observer :**

- Le ping continue après quelques secondes
- CORESW2 devient Active

**4. Vérifier sur CORESW2 :**

```cisco
show standby brief
```

→ Maintenant Active

**5. Réactiver sur CORESW1 :**

```cisco
conf t
interface Vlan100
no shutdown
end
```

**6. Vérifier que CORESW1 redevient Active (preempt)**

**Captures :**

- `J13-failover-avant.png` → show standby brief avant shutdown
- `J13-failover-apres.png` → show standby brief après shutdown
- `J13-failover-ping.png` → Ping continu qui ne s'arrête pas

> 🎬 **Vidéo optionnelle** : `J13-VIDEO-HSRP-Failover.mp4`

### ⚠️ Remise en état après test

```cisco
! Sur CORESW1
conf t
interface Vlan100
no shutdown
end

! Vérification finale
show standby brief
```

→ CORESW1 = Active, CORESW2 = Standby

### 📁 Résumé Jalon 13 – 7 fichiers + vidéo

| Fichier                                     |
| ------------------------------------------- |
| `J13-CORESW1-hsrp.png`                      |
| `J13-CORESW1-track.png`                     |
| `J13-CORESW2-hsrp.png`                      |
| `J13-CORESW2-track.png`                     |
| `J13-failover-avant.png`                    |
| `J13-failover-apres.png`                    |
| `J13-failover-ping.png`                     |
| _(Optionnel)_ `J13-VIDEO-HSRP-Failover.mp4` |

---

## Jalon 14 – HSRP EDGE Routeurs

**Ordre** : EDGE1 → EDGE2

### Étape 1 : EDGE1 (Active)

```cisco
show standby brief
show track 10
```

**Vérifier :**

- Groupe 30 (VLAN DMZ) = Active
- Priority = 110
- VIP = 217.4.160.254

**Captures :**

- `J14-EDGE1-hsrp.png` → show standby brief (Active)
- `J14-EDGE1-track.png` → show track 10

### Étape 2 : EDGE2 (Standby)

```cisco
show standby brief
show track 20
```

**Vérifier :**

- Groupe 30 = Standby
- Priority = 100

**Captures :**

- `J14-EDGE2-hsrp.png` → show standby brief (Standby)
- `J14-EDGE2-track.png` → show track 20

### 📁 Résumé Jalon 14 – 4 fichiers

| Fichier               |
| --------------------- |
| `J14-EDGE1-hsrp.png`  |
| `J14-EDGE1-track.png` |
| `J14-EDGE2-hsrp.png`  |
| `J14-EDGE2-track.png` |

---

## Jalon 15 – NAT EDGE WANRTR

**Ordre** : EDGE1 → EDGE2 → Test depuis PC

### Étape 1 : EDGE1

```cisco
show ip nat translations
show ip nat statistics
show access-lists NAT-ACL
```

**Vérifier :**

- NAT-ACL autorise `10.4.0.0/16`
- Translations présentes (si trafic actif)

**Captures :**

- `J15-EDGE1-nat-translations.png`
- `J15-EDGE1-nat-stats.png`
- `J15-EDGE1-nat-acl.png`

### Étape 2 : EDGE2

```cisco
show ip nat translations
show ip nat statistics
show access-lists NAT-ACL
```

**Captures :**

- `J15-EDGE2-nat-translations.png`
- `J15-EDGE2-nat-stats.png`

### Étape 3 : Test NAT depuis un PC interne

**1. Sur un PC dans VLAN 10 ou 20 :**

```cmd
ping 8.8.4.1
```

**2. Retourner sur EDGE1 :**

```cisco
show ip nat translations
```

**3. Vérifier que la translation apparaît**

**Captures :**

- `J15-PC-ping-internet.png` → Ping depuis PC vers 8.8.4.1
- `J15-EDGE1-nat-after-ping.png` → show ip nat translations avec entrée

### 📁 Résumé Jalon 15 – 7 fichiers

| Fichier                          |
| -------------------------------- |
| `J15-EDGE1-nat-translations.png` |
| `J15-EDGE1-nat-stats.png`        |
| `J15-EDGE1-nat-acl.png`          |
| `J15-EDGE2-nat-translations.png` |
| `J15-EDGE2-nat-stats.png`        |
| `J15-PC-ping-internet.png`       |
| `J15-EDGE1-nat-after-ping.png`   |

---

## Jalon 16 – Accès DMZ

**Ordre** : EDGE1 → EDGE2 → Test connectivité

### Étape 1 : EDGE1

```cisco
show ip interface brief | include .30
show ip interface GigabitEthernet0/1.30
show standby brief
```

**Vérifier :**

- Interface Gi0/1.30 UP
- IP = 217.4.160.253/24
- HSRP VIP = 217.4.160.254

**Captures :**

- `J16-EDGE1-dmz-interface.png`
- `J16-EDGE1-dmz-hsrp.png`

### Étape 2 : EDGE2

```cisco
show ip interface brief | include .30
show standby brief
```

**Vérifier :**

- Interface Gi0/1.30 UP
- IP = 217.4.160.252/24

**Capture :**

- `J16-EDGE2-dmz-interface.png`

### Étape 3 : Test Ping entre EDGE1 et EDGE2 via DMZ

```cisco
! Sur EDGE1
ping 217.4.160.252

! Sur EDGE2
ping 217.4.160.253
```

**Capture :** `J16-ping-dmz.png`

### Étape 4 : Test depuis le serveur DMZ (si disponible)

Sur HQWEBSRV (217.4.160.2) ou HQFWSRV (217.4.160.1) :

```cmd
ping 217.4.160.254
```

**Capture :** `J16-dmz-server-ping.png`

### 📁 Résumé Jalon 16 – 5 fichiers

| Fichier                                             |
| --------------------------------------------------- |
| `J16-EDGE1-dmz-interface.png`                       |
| `J16-EDGE1-dmz-hsrp.png`                            |
| `J16-EDGE2-dmz-interface.png`                       |
| `J16-ping-dmz.png`                                  |
| `J16-dmz-server-ping.png` _(si serveur disponible)_ |

---

## Jalon 17 – EDGEX NAT/PAT VPN

**Ordre** : EDGE1 → EDGE2 → Test depuis Internet

### Étape 1 : EDGE1

```cisco
show running-config | include nat
show ip interface Loopback0
show ip route static
```

**Vérifier les règles NAT statiques :**

| IP Publique         | IP Privée       | Service       |
| ------------------- | --------------- | ------------- |
| `191.4.157.33:4443` | `10.4.10.2:443` | VPN OpenVPN   |
| `191.4.157.33:80`   | `10.4.10.3:80`  | Webmail HTTP  |
| `191.4.157.33:443`  | `10.4.10.3:443` | Webmail HTTPS |

**Captures :**

- `J17-EDGE1-nat-config.png` → show run | include nat
- `J17-EDGE1-loopback.png` → show ip interface Loopback0
- `J17-EDGE1-routes-null0.png` → show ip route static

### Étape 2 : EDGE2

```cisco
show running-config | include nat
show ip interface Loopback0
```

**Vérifier les règles NAT statiques (backup) :**

| IP Publique         | IP Privée       | Service       |
| ------------------- | --------------- | ------------- |
| `191.4.157.34:4443` | `10.4.10.2:443` | VPN OpenVPN   |
| `191.4.157.34:80`   | `10.4.10.3:80`  | Webmail HTTP  |
| `191.4.157.34:443`  | `10.4.10.3:443` | Webmail HTTPS |

**Captures :**

- `J17-EDGE2-nat-config.png`
- `J17-EDGE2-loopback.png`

### Étape 3 : Test depuis Internet (si disponible)

Depuis un PC côté Internet (8.8.4.x) ou INETCLT :

```cmd
ping 191.4.157.33
ping 191.4.157.34
```

Si serveur VPN/Webmail configuré :

- Connexion HTTPS vers `https://webmail.wsl2025.org`
- Connexion VPN vers `vpn.wsl2025.org:4443`

**Capture :** `J17-internet-ping-loopback.png`

### 📁 Résumé Jalon 17 – 5-6 fichiers

| Fichier                                          |
| ------------------------------------------------ |
| `J17-EDGE1-nat-config.png`                       |
| `J17-EDGE1-loopback.png`                         |
| `J17-EDGE1-routes-null0.png`                     |
| `J17-EDGE2-nat-config.png`                       |
| `J17-EDGE2-loopback.png`                         |
| `J17-internet-ping-loopback.png` _(si possible)_ |

---

## Checklist Finale

### Jalon 5 (1 fichier)

- [ ] `PLAN-ADRESSAGE-IP.pdf`

### Jalon 10 (17 captures)

| Équipement | Captures                         |
| ---------- | -------------------------------- |
| CORESW1    | vlans, vtp, trunk, lacp, stp     |
| CORESW2    | vlans, vtp, lacp, stp            |
| ACCSW1     | vlans, vtp, trunk, portsec, ping |
| ACCSW2     | vlans, vtp, trunk                |
| PC         | ping VIP                         |

### Jalon 12 (14 captures)

| Équipement | Captures                            |
| ---------- | ----------------------------------- |
| EDGE1      | interfaces, ospf, bgp, routes, ping |
| EDGE2      | interfaces, ospf, bgp, routes, ping |
| WANRTR     | vrf, ospf, bgp, ping                |

### Jalon 13 (7 captures + vidéo)

| Équipement | Captures              |
| ---------- | --------------------- |
| CORESW1    | hsrp (Active), track  |
| CORESW2    | hsrp (Standby), track |
| Failover   | avant, après, ping    |

### Jalon 14 (4 captures)

| Équipement | Captures    |
| ---------- | ----------- |
| EDGE1      | hsrp, track |
| EDGE2      | hsrp, track |

### Jalon 15 (7 captures)

| Équipement | Captures                     |
| ---------- | ---------------------------- |
| EDGE1      | translations, stats, acl     |
| EDGE2      | translations, stats          |
| PC         | ping internet + translations |

### Jalon 16 (5 captures)

| Équipement | Captures                    |
| ---------- | --------------------------- |
| EDGE1      | interface, hsrp             |
| EDGE2      | interface                   |
| Ping       | entre EDGE + depuis serveur |

### Jalon 17 (5-6 captures)

| Équipement | Captures                           |
| ---------- | ---------------------------------- |
| EDGE1      | nat config, loopback, routes null0 |
| EDGE2      | nat config, loopback               |
| Internet   | ping loopback                      |

---

## Commandes Copier-Coller par Équipement

### CORESW1 (Jalons 10, 13)

```cisco
show vlan brief
show vtp status
show interfaces trunk
show etherchannel summary
show spanning-tree root
show standby brief
show track 10
show ip interface brief
```

### CORESW2 (Jalons 10, 13)

```cisco
show vlan brief
show vtp status
show interfaces trunk
show etherchannel summary
show spanning-tree root
show standby brief
show track 20
show ip interface brief
```

### ACCSW1 (Jalon 10)

```cisco
show vlan brief
show vtp status
show interfaces trunk
show port-security
show errdisable recovery
ping 10.4.99.253
ping 10.4.99.252
```

### ACCSW2 (Jalon 10)

```cisco
show vlan brief
show vtp status
show interfaces trunk
show port-security
show errdisable recovery
ping 10.4.99.253
ping 10.4.99.252
```

### EDGE1 (Jalons 12, 14, 15, 16, 17)

```cisco
show ip interface brief
show ip ospf neighbor
show ip ospf database
show ip bgp summary
show ip bgp
show ip route
show standby brief
show track 10
show ip nat translations
show ip nat statistics
show access-lists NAT-ACL
show ip interface Loopback0
show ip route static
show running-config | include nat
ping 91.4.222.98
ping 10.4.254.14
ping 10.4.254.10
ping 217.4.160.252
```

### EDGE2 (Jalons 12, 14, 15, 16, 17)

```cisco
show ip interface brief
show ip ospf neighbor
show ip bgp summary
show ip bgp
show ip route
show standby brief
show track 20
show ip nat translations
show ip nat statistics
show access-lists NAT-ACL
show ip interface Loopback0
show ip route static
show running-config | include nat
ping 31.4.126.14
ping 10.4.254.17
ping 10.4.254.9
ping 217.4.160.253
```

### WANRTR (Jalon 12)

```cisco
show ip interface brief
show vrf
show ip vrf interfaces
show ip ospf neighbor
show ip bgp summary
show ip bgp
ping 91.4.222.97
ping 31.4.126.13
ping 10.4.254.13
ping 10.4.254.18
```

---

<p align="center">
  <sub>SAE 501 - WorldSkills Lyon 2025 - Groupe 4</sub>
</p>
