# HQFWSRV - Firewall HQ

> **OS** : Debian 13 CLI (ou Stormshield hardware)  
> **IP DMZ** : 217.4.160.1 (VLAN 30 - eth0)  
> **IP Interne** : 10.4.10.5 (VLAN 10 - eth1)  
> **Rôle** : Firewall nftables, NAT/Redirection

---

## 🎯 Contexte (Sujet)

Ce serveur sécurise les communications entre Internet (DMZ) et le réseau interne :

| Service               | Description                                               |
| --------------------- | --------------------------------------------------------- |
| **Firewall nftables** | Règles de filtrage pour protéger les ressources internes. |
| **NAT/DNAT**          | Redirection HTTP/HTTPS vers HQWEBSRV (217.4.160.2).       |
| **RDS Forward**       | Redirection MS RDS (3389) vers HQWEBSRV.                  |
| **Ports fermés**      | Tous les ports non utilisés sont bloqués.                 |

> ⚠️ Le VLAN 10 est utilisé uniquement pour l'authentification AD.

---

## 📋 Prérequis

- [ ] Debian 13 installé
- [ ] 2 interfaces réseau (DMZ + Interne)
- [ ] HQWEBSRV prêt (217.4.160.2)

---

## 1️⃣ Configuration de base

### Hostname

```bash
hostnamectl set-hostname hqfwsrv
```

### Interfaces réseau

```bash
cat > /etc/network/interfaces << 'EOF'
# Interface DMZ (VLAN 30) - vers Internet/EDGE routers
auto eth0
iface eth0 inet static
    address 217.4.160.1
    netmask 255.255.255.0
    gateway 217.4.160.254

# Interface Interne (VLAN 10) - vers Servers
auto eth1
iface eth1 inet static
    address 10.4.10.5
    netmask 255.255.255.0
EOF
```

### Activer le forwarding

```bash
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p
```

---

## 2️⃣ Installation nftables

```bash
apt update && apt install -y nftables
systemctl enable nftables
```

---

## 3️⃣ Configuration nftables

```bash
cat > /etc/nftables.conf << 'EOF'
#!/usr/sbin/nft -f

flush ruleset

# Définition des variables
define DMZ_IF = "eth0"
define INT_IF = "eth1"
define WEBSERVER = 217.4.160.2
define DMZ_IP = 217.4.160.1

table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;
        
        # Connexions établies
        ct state established,related accept
        
        # Loopback
        iif "lo" accept
        
        # ICMP (ping)
        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept
        
        # SSH depuis le réseau interne uniquement
        iif $INT_IF tcp dport 22 accept
        
        # Drop tout le reste
        log prefix "NFT-INPUT-DROP: " drop
    }
    
    chain forward {
        type filter hook forward priority 0; policy drop;
        
        # Connexions établies
        ct state established,related accept
        
        # ===== DMZ vers HQWEBSRV =====
        # Web (HTTP/HTTPS)
        iif $DMZ_IF ip daddr $WEBSERVER tcp dport {80, 443} accept
        
        # RDP vers HQWEBSRV
        iif $DMZ_IF ip daddr $WEBSERVER tcp dport 3389 accept
        
        # ===== HQWEBSRV vers Interne (pour AD) =====
        iif $DMZ_IF oif $INT_IF tcp dport {88, 135, 389, 445, 464, 636, 3268, 3269} accept
        iif $DMZ_IF oif $INT_IF udp dport {88, 123, 135, 389, 445, 464} accept
        
        # ===== Interne vers DMZ =====
        iif $INT_IF oif $DMZ_IF accept
        
        # Log et drop
        log prefix "NFT-FORWARD-DROP: " drop
    }
    
    chain output {
        type filter hook output priority 0; policy accept;
    }
}
EOF
```

### Appliquer la configuration

```bash
nft -f /etc/nftables.conf
systemctl restart nftables
```

---

## 4️⃣ Règles détaillées par service

### Ports ouverts (Internet → DMZ → HQWEBSRV)

| Service | Port | Protocole | Destination            |
| ------- | ---- | --------- | ---------------------- |
| HTTP    | 80   | TCP       | 217.4.160.2 (HQWEBSRV) |
| HTTPS   | 443  | TCP       | 217.4.160.2 (HQWEBSRV) |
| RDP     | 3389 | TCP       | 217.4.160.2 (HQWEBSRV) |

### Ports ouverts (HQWEBSRV → Interne pour AD)

| Service        | Port       | Protocole | Destination         |
| -------------- | ---------- | --------- | ------------------- |
| Kerberos       | 88         | TCP/UDP   | 10.4.10.1 (HQDCSRV) |
| LDAP           | 389        | TCP/UDP   | 10.4.10.1           |
| LDAPS          | 636        | TCP       | 10.4.10.1           |
| SMB            | 445        | TCP       | 10.4.10.1           |
| DNS            | 53         | TCP/UDP   | 10.4.10.1           |
| Global Catalog | 3268, 3269 | TCP       | 10.4.10.1           |

---

## 5️⃣ Logging et monitoring

### Voir les logs

```bash
# Les logs sont envoyés à syslog
tail -f /var/log/syslog | grep NFT
journalctl -f | grep nft
```

### Voir les règles actives

```bash
nft list ruleset
```

---

## 6️⃣ Commandes utiles

```bash
# Ajouter une règle temporaire
nft add rule inet filter forward iif eth0 tcp dport 8080 accept

# Lister avec handles
nft -a list ruleset

# Supprimer par handle
nft delete rule inet filter forward handle X

# Sauvegarder
nft list ruleset > /etc/nftables.conf.backup
```

---

## ✅ Vérification Finale

### 🔌 Comment se connecter à HQFWSRV

1. Ouvrir un terminal SSH ou utiliser la console VMware
2. Se connecter : `ssh root@217.4.160.1` (depuis DMZ) ou `ssh root@10.4.10.5` (depuis LAN)
3. Tu dois voir le prompt : `root@hqfwsrv:~#`

---

### Test 1 : Vérifier le forwarding IP

**Étape 1** : Tape cette commande :
```bash
sysctl net.ipv4.ip_forward
```

**Étape 2** : Regarde le résultat :
```
net.ipv4.ip_forward = 1
```

✅ **C'est bon si** : La valeur est `= 1`
❌ **Problème si** : La valeur est `= 0` → Le routage ne fonctionne pas

---

### Test 2 : Vérifier que nftables est actif

**Étape 1** : Tape cette commande :
```bash
systemctl is-active nftables
```

**Étape 2** : Regarde le résultat :
```
active
```

✅ **C'est bon si** : Tu vois `active`
❌ **Problème si** : `inactive` → Les règles firewall ne sont pas chargées

---

### Test 3 : Vérifier les règles nftables

**Étape 1** : Tape cette commande :
```bash
nft list tables
```

**Étape 2** : Regarde le résultat :
```
table inet filter
```

✅ **C'est bon si** : Tu vois au moins une table listée
❌ **Problème si** : Rien ne s'affiche → Pas de règles configurées

---

### Test 4 : Ping vers HQWEBSRV (DMZ)

**Étape 1** : Tape cette commande :
```bash
ping -c 2 217.4.160.2
```

**Étape 2** : Regarde le résultat :
```
64 bytes from 217.4.160.2: icmp_seq=1 ttl=128 time=0.5 ms
64 bytes from 217.4.160.2: icmp_seq=2 ttl=128 time=0.4 ms
```

✅ **C'est bon si** : Tu vois des réponses avec des temps
❌ **Problème si** : "Destination Host Unreachable" → Problème réseau DMZ

---

### Test 5 : Ping vers réseau interne (HQDCSRV)

**Étape 1** : Tape cette commande :
```bash
ping -c 2 10.4.10.1
```

**Étape 2** : Regarde le résultat :
```
64 bytes from 10.4.10.1: icmp_seq=1 ttl=128 time=0.3 ms
```

✅ **C'est bon si** : Tu vois des réponses
❌ **Problème si** : Pas de réponse → Problème interface eth1 ou routage

---

### 📋 Résumé rapide (copie-colle tout d'un coup)

```bash
echo "=== IP FORWARD ===" && sysctl net.ipv4.ip_forward
echo "=== NFTABLES ===" && systemctl is-active nftables
echo "=== TABLES ===" && nft list tables
echo "=== PING HQWEBSRV ===" && ping -c 1 217.4.160.2 | grep "bytes from" || echo "ECHEC"
echo "=== PING INTERNE ===" && ping -c 1 10.4.10.1 | grep "bytes from" || echo "ECHEC"
```

---

## 📝 Architecture

```
Internet
    │
    ▼
┌─────────────────┐
│  EDGE1/EDGE2    │  217.4.160.253/252 (HSRP VIP: 217.4.160.254)
└────────┬────────┘
         │ VLAN 30
         ▼
┌─────────────────┐
│    HQFWSRV      │  217.4.160.1 (eth0)
│   (Firewall)    │  10.4.10.5 (eth1)
└────────┬────────┘
         │
    ┌────┴────┐
    │         │
    ▼         ▼
HQWEBSRV   Servers VLAN 10
217.4.160.2  10.4.10.0/24
```

---

## 📝 Notes

- **IP DMZ** : 217.4.160.1
- **IP Interne** : 10.4.10.5
- HQWEBSRV est sur 217.4.160.2 dans le VLAN 30
- Le trafic web arrive directement sur HQWEBSRV via le VLAN 30
- HQFWSRV filtre le trafic entre DMZ et réseau interne (VLAN 10)
