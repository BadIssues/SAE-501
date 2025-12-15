# HQINFRASRV - Serveur Infrastructure HQ

> **OS** : Debian 13 CLI  
> **IP ens192** : 10.4.10.2/24 (VLAN 10 - Servers)  
> **IP ens224** : 10.4.20.1/23 (VLAN 20 - Clients) - Interface DHCP  
> **Rôles** : DHCP Primary, VPN OpenVPN, Stockage LVM/iSCSI, Samba, NTP

---

## 🎯 Contexte (Sujet)

Ce serveur fournit plusieurs services d'infrastructure pour le site HQ :

| Service      | Description                                                                                                       |
| ------------ | ----------------------------------------------------------------------------------------------------------------- |
| **DHCP**     | Serveur primaire pour les réseaux Clients (VLAN 20) et Management (VLAN 99). Failover avec HQMAILSRV. Bail de 2h. |
| **VPN**      | Serveur OpenVPN sur port 4443, accessible via 191.4.157.33 (NAT). Auth par certificat HQDCSRV + user/password AD. |
| **Stockage** | LVM avec 2 disques de 5Go. LV `lvdatastorage` (2Go, ext4) + LV `lviscsi` (2Go) pour target iSCSI.                 |
| **Samba**    | Partage `Public` (lecture seule) + `Private` (caché, RW Tom/Emma, RO Jean, blocage .exe/.zip).                    |
| **NTP**      | Serveur de temps pour toute l'infrastructure. Authentification par restriction réseau.                            |

---

## 📋 Prérequis

- [ ] Debian 13 installé
- [ ] **2 cartes réseau** : ens192 (VLAN 10) + ens224 (VLAN 20 pour DHCP)
- [ ] 2 disques supplémentaires de 5 Go chacun
- [ ] HQDCSRV opérationnel (pour les certificats)
- [ ] HQMAILSRV configuré pour le DHCP failover (Secondary)

---

## 1️⃣ Configuration de base

### Hostname et domaine

```bash
hostnamectl set-hostname hqinfrasrv
echo "hqinfrasrv.wsl2025.org" > /etc/hostname
```

### Configuration réseau

```bash
nano /etc/network/interfaces
```

```
# Interface VLAN 10 - Servers
auto ens192
iface ens192 inet static
    address 10.4.10.2
    netmask 255.255.255.0
    gateway 10.4.10.254
    dns-nameservers 10.4.10.1
    dns-search wsl2025.org hq.wsl2025.org

# Interface VLAN 20 - Clients (pour DHCP)
auto ens224
iface ens224 inet static
    address 10.4.20.1
    netmask 255.255.254.0
```

### SSH et Fail2Ban

```bash
apt update && apt install -y openssh-server fail2ban

# Configuration Fail2Ban
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
EOF

systemctl enable --now fail2ban
```

---

## 2️⃣ Configuration NTP (Serveur de temps)

```bash
apt install -y ntpsec

cat > /etc/ntpsec/ntp.conf << 'EOF'
# Fichier de drift
driftfile /var/lib/ntpsec/ntp.drift

# === Horloge locale ===
server 127.127.1.0
fudge 127.127.1.0 stratum 10

# === Authentification NTP ===
keys /etc/ntpsec/ntp.keys
trustedkey 1
requestkey 1
controlkey 1

# === Restrictions ===
restrict default ignore
restrict 127.0.0.1
restrict ::1

# Autoriser le LAN AUTHENTIFIÉ
restrict 10.4.0.0 mask 255.255.0.0 nomodify notrap
EOF

# Créer la clé d'authentification
echo "1 MD5 SAE501NTPKey2025" > /etc/ntpsec/ntp.keys
chmod 600 /etc/ntpsec/ntp.keys

systemctl enable --now ntpsec
systemctl restart ntpsec
```

### Vérification NTP

```bash
# Vérifier le statut
systemctl status ntpsec

# Vérifier les sources
ntpq -p
# Doit afficher *LOCAL(0) avec stratum 10

# Vérifier que le service écoute
ss -ulnp | grep 123
```

> 💡 **Note** : L'authentification NTP est sécurisée par :
>
> - Restriction réseau (`restrict 10.4.0.0 mask 255.255.0.0`) : seuls les clients du LAN peuvent se synchroniser
> - Clés d'authentification dans `/etc/ntpsec/ntp.keys`

---

## 3️⃣ Stockage LVM

### Création des volumes physiques

```bash
apt install -y lvm2

# Identifier les disques (remplacer sdX par les vrais noms)
lsblk

# Créer les PV
pvcreate /dev/sdb /dev/sdc

# Créer le VG
vgcreate vgstorage /dev/sdb /dev/sdc

# Créer les LV
lvcreate -L 2G -n lvdatastorage vgstorage
lvcreate -L 2G -n lviscsi vgstorage

# Formater et monter lvdatastorage
mkfs.ext4 /dev/vgstorage/lvdatastorage
mkdir -p /srv/datastorage
echo "/dev/vgstorage/lvdatastorage /srv/datastorage ext4 defaults 0 2" >> /etc/fstab
mount -a
```

---

## 4️⃣ iSCSI Target

```bash
apt install -y tgt

cat > /etc/tgt/conf.d/iscsi.conf << 'EOF'
<target iqn.2025-01.org.wsl2025:storage.lun1>
    backing-store /dev/vgstorage/lviscsi
    initiator-address 10.4.10.3
    incominguser iscsiuser P@ssw0rd
</target>
EOF

systemctl restart tgt
systemctl enable tgt
```

---

## 5️⃣ Serveur DHCP (Primary/Mère)

> ⚠️ **IMPORTANT** : HQINFRASRV est le serveur DHCP **primaire (mère)** pour le VLAN 20 (Clients).
> Le failover est assuré avec HQMAILSRV qui est le serveur **secondaire (fille)**.
> Les deux serveurs communiquent via leurs interfaces dans le VLAN 20 :
>
> - HQINFRASRV : 10.4.20.1 (ens224)
> - HQMAILSRV : 10.4.20.2 (ens224)

```bash
apt install -y isc-dhcp-server

cat > /etc/dhcp/dhcpd.conf << 'EOF'
# Configuration globale
authoritative;
default-lease-time 7200;  # 2 heures
max-lease-time 7200;

# Options communes
option domain-name "hq.wsl2025.org";
option domain-name-servers 10.4.10.1;
option ntp-servers 10.4.10.2;

# Failover configuration (Primary - Mère)
failover peer "dhcp-failover" {
    primary;
    address 10.4.20.1;           # IP de HQINFRASRV dans le VLAN 20
    port 647;
    peer address 10.4.20.2;      # IP de HQMAILSRV dans le VLAN 20
    peer port 647;
    max-response-delay 30;
    max-unacked-updates 10;
    load balance max seconds 3;
    mclt 1800;
    split 128;                   # 50/50 load balancing
}

# Subnet Clients (VLAN 20) - 10.4.20.0/23
subnet 10.4.20.0 netmask 255.255.254.0 {
    option routers 10.4.20.254;
    option broadcast-address 10.4.21.255;
    pool {
        failover peer "dhcp-failover";
        range 10.4.20.10 10.4.21.200;   # Plage DHCP (évite les IPs des serveurs DHCP)
    }
}

# Subnet Management (VLAN 99)
subnet 10.4.99.0 netmask 255.255.255.0 {
    range 10.4.99.2 10.4.99.100;
    option routers 10.4.99.254;
}

# Subnet Servers (pour le relais DHCP)
subnet 10.4.10.0 netmask 255.255.255.0 {
}
EOF

# Interface d'écoute - VLAN 20 (ens224)
echo 'INTERFACESv4="ens224"' > /etc/default/isc-dhcp-server

systemctl restart isc-dhcp-server
systemctl enable isc-dhcp-server
```

### Vérification du failover

```bash
# Vérifier l'état du failover
dhcpd -t -cf /etc/dhcp/dhcpd.conf

# Voir les logs de communication failover
journalctl -u isc-dhcp-server | grep -i failover
```

### Configuration DHCP Relay sur les switches

> Déjà fait dans le cœur de réseau (`ip helper-address 10.4.20.1` et `ip helper-address 10.4.20.2`)

---

## 6️⃣ Serveur Samba

### Création des utilisateurs locaux

```bash
useradd -m jean
useradd -m tom
useradd -m emma

echo "jean:P@ssw0rd" | chpasswd
echo "tom:P@ssw0rd" | chpasswd
echo "emma:P@ssw0rd" | chpasswd
```

### Installation et configuration Samba

```bash
apt install -y samba

# Créer les répertoires
mkdir -p /srv/datastorage/shares/public
mkdir -p /srv/datastorage/shares/private
chmod 755 /srv/datastorage/shares/public
chmod 770 /srv/datastorage/shares/private

# Ajouter les utilisateurs Samba
smbpasswd -a jean
smbpasswd -a tom
smbpasswd -a emma

cat > /etc/samba/smb.conf << 'EOF'
[global]
    workgroup = WSL2025
    server string = HQINFRASRV File Server
    security = user
    map to guest = never

[Public]
    path = /srv/datastorage/shares/public
    browseable = yes
    read only = yes
    guest ok = yes

[Private]
    path = /srv/datastorage/shares/private
    browseable = no
    read only = no
    valid users = jean tom emma
    write list = tom emma
    read list = jean
    hide dot files = yes
    veto files = /*.exe/*.zip/
    hosts allow = 10.4.0.0/16
EOF

systemctl restart smbd nmbd
systemctl enable smbd nmbd
```

---

## 7️⃣ Serveur VPN OpenVPN

> ⚠️ **Exigences du sujet** :
>
> - Protocole : OpenVPN
> - Port : **4443**
> - Adresse publique NAT : **191.4.157.33:4443**
> - Authentification : **Certificat + user/password Active Directory**
> - Certificat : **Émis par HQDCSRV** (Sub CA WSFR-SUB-CA)
> - Accès : Ressources HQ **ET** Remote site

### Installation

```bash
apt install -y openvpn openvpn-auth-ldap
```

### Prérequis : Utiliser le certificat Wildcard existant

> ✅ **INFO** : On utilise le certificat wildcard `*.wsl2025.org` déjà émis par HQDCSRV (Sub CA).
> Ce certificat couvre `vpn.wsl2025.org` et tous les sous-domaines.

#### Fichiers disponibles sur HQINFRASRV (dans `~` ou `/root`)

| Fichier | Description |
|---------|-------------|
| `wildcard-wsl2025.pfx` | Certificat wildcard avec clé privée (format PKCS#12) |
| `WSFR-ROOT-CA.cer` | Certificat Root CA |
| `SubCA.cer` | Certificat Sub CA (HQDCSRV) |

#### Étape 1 : Créer le dossier et convertir le certificat wildcard

```bash
mkdir -p /etc/openvpn/certs
cd /etc/openvpn/certs

# Copier les certificats CA depuis le home
cp ~/WSFR-ROOT-CA.cer /etc/openvpn/certs/ca-root.crt
cp ~/SubCA.cer /etc/openvpn/certs/ca-sub.crt

# Convertir le PFX en certificat (.crt) et clé privée (.key)
# Mot de passe du PFX : P@ssw0rd (ou celui utilisé lors de l'export)

# Extraire le certificat
openssl pkcs12 -in ~/wildcard-wsl2025.pfx -clcerts -nokeys -out /etc/openvpn/certs/vpn-server.crt

# Extraire la clé privée (sans mot de passe)
openssl pkcs12 -in ~/wildcard-wsl2025.pfx -nocerts -nodes -out /etc/openvpn/certs/vpn-server.key

# Sécuriser la clé privée
chmod 600 /etc/openvpn/certs/vpn-server.key
```

#### Étape 2 : Créer la chaîne de certificats CA

```bash
# Créer la chaîne de certificats complète (Sub CA + Root CA)
cat /etc/openvpn/certs/ca-sub.crt /etc/openvpn/certs/ca-root.crt > /etc/openvpn/certs/ca-chain.crt
```

### Générer les paramètres DH et clé TLS

```bash
cd /etc/openvpn/certs

# Générer les paramètres Diffie-Hellman
openssl dhparam -out dh2048.pem 2048

# Générer la clé TLS-Auth
openvpn --genkey secret /etc/openvpn/ta.key
```

### Configuration de l'authentification LDAP (Active Directory)

```bash
cat > /etc/openvpn/auth-ldap.conf << 'EOF'
<LDAP>
    URL             ldap://hqdcsrv.hq.wsl2025.org:389
    BindDN          "CN=Administrateur,CN=Users,DC=hq,DC=wsl2025,DC=org"
    Password        P@ssw0rd
    Timeout         15
    TLSEnable       no
    FollowReferrals yes
</LDAP>

<Authorization>
    BaseDN          "DC=hq,DC=wsl2025,DC=org"
    SearchFilter    "(sAMAccountName=%u)"
    RequireGroup    false
</Authorization>
EOF

chmod 600 /etc/openvpn/auth-ldap.conf
```

### Configuration serveur OpenVPN

```bash
cat > /etc/openvpn/server.conf << 'EOF'
# === Interface et Port ===
port 4443
proto udp
dev tun

# === Certificats (wildcard *.wsl2025.org émis par HQDCSRV Sub CA) ===
ca /etc/openvpn/certs/ca-chain.crt
cert /etc/openvpn/certs/vpn-server.crt
key /etc/openvpn/certs/vpn-server.key
dh /etc/openvpn/certs/dh2048.pem
tls-auth /etc/openvpn/ta.key 0

# === Réseau VPN ===
server 10.4.22.0 255.255.255.0

# === Routes poussées aux clients ===
# Accès au site HQ (10.4.x.x)
push "route 10.4.0.0 255.255.0.0"
# Accès au site Remote (10.4.100.x via MAN)
push "route 10.4.100.0 255.255.255.0"
# Lien MAN (10.116.4.x)
push "route 10.116.4.0 255.255.255.0"

# === Options DNS ===
push "dhcp-option DNS 10.4.10.1"
push "dhcp-option DOMAIN hq.wsl2025.org"
push "dhcp-option DOMAIN wsl2025.org"

# === Authentification LDAP (Active Directory) ===
plugin /usr/lib/openvpn/openvpn-auth-ldap.so /etc/openvpn/auth-ldap.conf
verify-client-cert require

# === Sécurité ===
cipher AES-256-GCM
auth SHA256
tls-version-min 1.2

# === Performance ===
keepalive 10 120
persist-key
persist-tun

# === Permissions ===
user nobody
group nogroup

# === Logs ===
verb 3
log-append /var/log/openvpn.log
status /var/log/openvpn-status.log
EOF

chmod 600 /etc/openvpn/server.conf
```

### Activer le forwarding IP

```bash
# Activer le forwarding IPv4
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# Ajouter une règle iptables pour le NAT (si nécessaire)
iptables -t nat -A POSTROUTING -s 10.4.22.0/24 -o ens192 -j MASQUERADE

# Persister les règles iptables
apt install -y iptables-persistent
netfilter-persistent save
```

### Démarrer le service

```bash
systemctl enable --now openvpn@server
systemctl status openvpn@server
```

### Vérification VPN

```bash
# Vérifier le service
systemctl status openvpn@server

# Vérifier les logs
tail -f /var/log/openvpn.log

# Vérifier que le port 4443 écoute
ss -ulnp | grep 4443

# Vérifier l'interface TUN
ip addr show tun0
```

---

## ✅ Vérifications

| Test       | Commande                          | Résultat attendu                    |
| ---------- | --------------------------------- | ----------------------------------- |
| DHCP       | `journalctl -u isc-dhcp-server`   | Service actif, failover OK          |
| Samba      | `smbclient -L localhost -U jean`  | Partages Public et Private visibles |
| iSCSI      | `tgtadm --mode target --op show`  | Target LUN1 visible                 |
| VPN        | `systemctl status openvpn@server` | Active (running)                    |
| VPN Port   | `ss -ulnp \| grep 4443`           | Port 4443/udp en écoute             |
| VPN Tunnel | `ip addr show tun0`               | Interface tun0 avec IP 10.4.22.1    |
| VPN Logs   | `tail /var/log/openvpn.log`       | Pas d'erreurs                       |
| NTP        | `ntpq -p`                         | Synchronisé (stratum 10)            |
| Forwarding | `sysctl net.ipv4.ip_forward`      | = 1                                 |

---

## 📝 Notes

### Configuration Réseau

- **IP ens192 (VLAN 10 Servers)** : 10.4.10.2/24
- **IP ens224 (VLAN 20 Clients)** : 10.4.20.1/23 - Interface DHCP Primary
- Le DHCP failover fonctionne avec HQMAILSRV (10.4.20.2) dans le VLAN 20

### Configuration VPN (selon le sujet)

| Paramètre        | Valeur                                      |
| ---------------- | ------------------------------------------- |
| Protocole        | OpenVPN                                     |
| Port             | **4443/UDP**                                |
| Adresse publique | **191.4.157.33** (NAT sur EDGE1/EDGE2)      |
| Réseau tunnel    | 10.4.22.0/24                                |
| Authentification | **Certificat (HQDCSRV) + user/password AD** |
| Accès            | Ressources HQ + Remote site                 |

### NAT VPN sur les routeurs EDGE

Les routeurs EDGE1/EDGE2 doivent avoir cette règle NAT :

```
ip nat inside source static udp 10.4.10.2 4443 191.4.157.33 4443 extendable
```

### Certificat VPN

- On utilise le **certificat wildcard `*.wsl2025.org`** déjà émis par HQDCSRV (Sub CA)
- Le fichier source `wildcard-wsl2025.pfx` est converti en `.crt` et `.key` pour OpenVPN
- La chaîne de certificats inclut : Root CA (WSFR-ROOT-CA) + Sub CA (WSFR-SUB-CA)
- Fichiers utilisés :
  - `/etc/openvpn/certs/vpn-server.crt` (extrait du PFX)
  - `/etc/openvpn/certs/vpn-server.key` (clé privée extraite du PFX)
  - `/etc/openvpn/certs/ca-chain.crt` (chaîne CA)

### Authentification Active Directory

- Le plugin `openvpn-auth-ldap` vérifie les credentials contre AD (hq.wsl2025.org)
- Les utilisateurs du domaine peuvent se connecter avec leur login/mot de passe AD
- L'authentification combine : certificat client valide + credentials AD

---

## ✅ Vérification Finale

### 🔌 Comment se connecter à HQINFRASRV

1. Ouvrir un terminal SSH depuis ton PC ou utiliser la console VMware
2. Se connecter : `ssh root@10.4.10.2` (mot de passe : celui configuré)
3. Tu dois voir le prompt : `root@hqinfrasrv:~#`

---

### Test 1 : Vérifier les services

**Étape 1** : Tape cette commande et appuie sur Entrée :
```bash
systemctl is-active isc-dhcp-server smbd tgt openvpn@server ntpsec
```

**Étape 2** : Regarde le résultat. Tu dois voir :
```
active
active
active
active
active
```

✅ **C'est bon si** : Tu vois 5 fois "active" (un par ligne)
❌ **Problème si** : Tu vois "inactive" ou "failed" → Le service n'est pas démarré

---

### Test 2 : Vérifier le DHCP

**Étape 1** : Tape cette commande :
```bash
dhcpd -t -cf /etc/dhcp/dhcpd.conf
```

**Étape 2** : Regarde le résultat :

✅ **C'est bon si** : Aucun message d'erreur, juste des infos sur le fichier
❌ **Problème si** : Tu vois "error" ou "warning" → Problème de configuration

---

### Test 3 : Vérifier le stockage LVM

**Étape 1** : Tape cette commande :
```bash
lvs
```

**Étape 2** : Regarde le résultat. Tu dois voir quelque chose comme :
```
  LV             VG         Attr       LSize
  lvdatastorage  vgstorage  -wi-ao---- 2.00g
  lviscsi        vgstorage  -wi-ao---- 2.00g
```

✅ **C'est bon si** : Tu vois les 2 lignes avec `lvdatastorage` et `lviscsi`, chacun avec environ 2Go
❌ **Problème si** : Les lignes n'apparaissent pas ou taille différente

---

### Test 4 : Vérifier iSCSI

**Étape 1** : Tape cette commande :
```bash
tgtadm --mode target --op show | head -5
```

**Étape 2** : Regarde le résultat. Tu dois voir :
```
Target 1: iqn.2025-01.org.wsl2025:storage.lun1
    System information:
        Driver: iscsi
        State: ready
```

✅ **C'est bon si** : Tu vois "Target 1:" avec le nom `iqn.2025-01.org.wsl2025:storage.lun1` et "State: ready"
❌ **Problème si** : Rien ne s'affiche ou "State: offline"

---

### Test 5 : Vérifier Samba

**Étape 1** : Tape cette commande (avec le mot de passe dans la commande) :
```bash
smbclient -L localhost -U jean%P@ssw0rd 2>/dev/null | grep -E "Public|Private"
```

**Étape 2** : Regarde le résultat :
```
        Public
```

✅ **C'est bon si** : Tu vois "Public" (mais PAS "Private" car il est caché)
❌ **Problème si** : Tu ne vois rien ou une erreur d'authentification

---

### Test 6 : Vérifier le VPN OpenVPN

**Étape 1** : Vérifie que le port 4443 est en écoute :
```bash
ss -ulnp | grep 4443
```

**Étape 2** : Regarde le résultat. Tu dois voir :
```
UNCONN 0  0  0.0.0.0:4443  0.0.0.0:*  users:(("openvpn",pid=XXXX,fd=X))
```

✅ **C'est bon si** : Tu vois une ligne avec `:4443` et `openvpn`
❌ **Problème si** : Rien ne s'affiche → OpenVPN n'écoute pas

**Étape 3** : Vérifie l'interface tunnel :
```bash
ip addr show tun0 2>/dev/null | grep "inet "
```

**Étape 2** : Tu dois voir :
```
    inet 10.4.22.1/24 ...
```

✅ **C'est bon si** : Tu vois l'IP `10.4.22.1`
❌ **Problème si** : Erreur "Device not found" → Le tunnel n'est pas créé (pas de client connecté, c'est normal si aucun client)

---

### Test 7 : Vérifier NTP

**Étape 1** : Tape cette commande :
```bash
ntpq -p
```

**Étape 2** : Regarde le résultat. Tu dois voir :
```
     remote           refid      st t when poll reach   delay   offset  jitter
==============================================================================
*LOCAL(0)        .LOCL.          10 l   ...
```

✅ **C'est bon si** : Tu vois une ligne avec `*LOCAL(0)` et le stratum (st) = 10
❌ **Problème si** : Pas de ligne avec `*` devant

---

### 📋 Résumé rapide (copie-colle tout d'un coup)

```bash
echo "=== SERVICES ===" && systemctl is-active isc-dhcp-server smbd tgt openvpn@server ntpsec
echo "=== LVM ===" && lvs 2>/dev/null | grep -E "lvdatastorage|lviscsi"
echo "=== ISCSI ===" && tgtadm --mode target --op show 2>/dev/null | grep -E "Target|State"
echo "=== SAMBA ===" && smbclient -L localhost -U jean%P@ssw0rd 2>/dev/null | grep Public
echo "=== VPN PORT ===" && ss -ulnp | grep 4443
echo "=== NTP ===" && ntpq -p 2>/dev/null | grep -E "^\*|remote"
```

Tu peux copier-coller ce bloc entier. Chaque section doit afficher quelque chose de correct.
