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

## 7️⃣ Serveur VPN OpenVPN (Mode TAP Bridge)

> ⚠️ **Exigences du sujet** :
>
> - Protocole : OpenVPN
> - Port : **4443**
> - Adresse publique NAT : **191.4.157.33:4443**
> - Authentification : **Certificat + user/password Active Directory**
> - Certificat : **Émis par HQDCSRV** (Sub CA WSFR-SUB-CA)
> - **Clients obtiennent une IP du DHCP du réseau Clients** (pas un pool VPN séparé)
> - Accès : Ressources HQ **ET** Remote site

### Installation

```bash
apt install -y openvpn openvpn-auth-ldap bridge-utils
```

### Prérequis : Utiliser le certificat Wildcard existant

> ✅ **INFO** : On utilise le certificat wildcard `*.wsl2025.org` déjà émis par HQDCSRV (Sub CA).
> Ce certificat couvre `vpn.wsl2025.org` et tous les sous-domaines.

#### Fichiers disponibles sur HQINFRASRV (dans `~` ou `/root`)

| Fichier                | Description                                          |
| ---------------------- | ---------------------------------------------------- |
| `wildcard-wsl2025.pfx` | Certificat wildcard avec clé privée (format PKCS#12) |
| `WSFR-ROOT-CA.cer`     | Certificat Root CA                                   |
| `SubCA.cer`            | Certificat Sub CA (HQDCSRV)                          |

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

### Configuration du Bridge réseau

> ⚠️ **IMPORTANT** : Le mode TAP Bridge permet aux clients VPN d'obtenir une IP du DHCP du réseau Clients (VLAN 20).

#### Identifier l'interface du VLAN 20 (Clients)

```bash
# Lister les interfaces
ip addr show

# L'interface du VLAN 20 est généralement ens224 ou ens192.20
# Adapter selon votre configuration
```

#### Configurer le bridge dans /etc/network/interfaces

```bash
cat >> /etc/network/interfaces << 'EOF'

# Bridge pour OpenVPN TAP
auto br0
iface br0 inet manual
    bridge_ports ens224
    bridge_stp off
    bridge_fd 0
EOF
```

#### Scripts de bridge pour OpenVPN

```bash
# Script de démarrage du bridge
cat > /etc/openvpn/bridge-start.sh << 'EOF'
#!/bin/bash
BR="br0"
TAP="tap0"
ETH="ens224"

# Créer l'interface TAP
openvpn --mktun --dev $TAP

# Créer le bridge si nécessaire
if ! brctl show $BR 2>/dev/null | grep -q $BR; then
    brctl addbr $BR
fi

# Ajouter les interfaces au bridge
brctl addif $BR $ETH 2>/dev/null
brctl addif $BR $TAP 2>/dev/null

# IMPORTANT : Activer le mode promiscuous sur TOUTES les interfaces du bridge
ip link set $ETH up promisc on
ip link set $TAP up promisc on
ip link set $BR up promisc on

echo "Bridge $BR configuré avec $ETH et $TAP (promiscuous mode activé)"
EOF
chmod +x /etc/openvpn/bridge-start.sh

# Script d'arrêt du bridge
cat > /etc/openvpn/bridge-stop.sh << 'EOF'
#!/bin/bash
BR="br0"
TAP="tap0"

# Retirer l'interface TAP du bridge
brctl delif $BR $TAP 2>/dev/null

# Supprimer l'interface TAP
openvpn --rmtun --dev $TAP

echo "Interface $TAP supprimée du bridge $BR"
EOF
chmod +x /etc/openvpn/bridge-stop.sh
```

### Configuration de l'authentification LDAP (Active Directory)

> ⚠️ **IMPORTANT** : Créer un compte de service `service vpn` dans AD pour l'authentification LDAP.

```bash
cat > /etc/openvpn/auth-ldap.conf << 'EOF'
<LDAP>
    URL             ldap://10.4.10.1:389
    BindDN          "CN=service vpn,CN=Users,DC=hq,DC=wsl2025,DC=org"
    Password        P@ssw0rd
    Timeout         15
    TLSEnable       no
    FollowReferrals no
</LDAP>

<Authorization>
    BaseDN          "DC=hq,DC=wsl2025,DC=org"
    SearchFilter    "(sAMAccountName=%u)"
    RequireGroup    false
</Authorization>
EOF

chmod 600 /etc/openvpn/auth-ldap.conf
```

### Configuration serveur OpenVPN (Mode TAP Bridge)

```bash
cat > /etc/openvpn/server.conf << 'EOF'
# === Interface TAP + Bridge ===
port 4443
proto udp
dev tap0
dev-type tap

# === Certificats (wildcard *.wsl2025.org émis par HQDCSRV Sub CA) ===
ca /etc/openvpn/certs/ca-chain.crt
cert /etc/openvpn/certs/vpn-server.crt
key /etc/openvpn/certs/vpn-server.key
dh /etc/openvpn/certs/dh2048.pem
tls-auth /etc/openvpn/ta.key 0

# === Mode Bridge ===
# Pas de directive "server" - Les clients obtiennent leur IP via DHCP du réseau

# === Authentification LDAP (Active Directory) ===
plugin /usr/lib/openvpn/openvpn-auth-ldap.so /etc/openvpn/auth-ldap.conf
verify-client-cert none

# === Sécurité ===
cipher AES-256-GCM
auth SHA256
tls-version-min 1.2

# === Performance ===
keepalive 10 120
persist-key
persist-tun

# === Routes poussées aux clients ===
push "route 10.4.10.0 255.255.255.0"
push "route 10.4.0.0 255.255.0.0"
push "route 10.4.100.0 255.255.255.128"

# === Scripts Bridge ===
up /etc/openvpn/bridge-start.sh
down /etc/openvpn/bridge-stop.sh
script-security 2

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
```

### Démarrer le service

```bash
# Démarrer le bridge d'abord
/etc/openvpn/bridge-start.sh

# Démarrer OpenVPN
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

# Vérifier l'interface TAP
ip addr show tap0

# Vérifier le bridge
brctl show br0
```

### Créer le fichier client .ovpn

> Ce fichier sera utilisé par les clients VPN (VPNCLT) pour se connecter.
> Le client utilisera le mode TAP et obtiendra une IP via DHCP.

```bash
# Créer le fichier .ovpn avec les certificats embarqués
cat > /root/wsl2025-client.ovpn << 'OVPNEOF'
client
dev tap
proto udp
remote vpn.wsl2025.org 4443
remote 191.4.157.33 4443

resolv-retry infinite
nobind
persist-key
persist-tun

# Sécurité
cipher AES-256-GCM
auth SHA256
remote-cert-tls server

# Authentification utilisateur AD
auth-user-pass

# Logs
verb 3

OVPNEOF

# Ajouter le certificat CA (chaîne complète)
echo "<ca>" >> /root/wsl2025-client.ovpn
cat /etc/openvpn/certs/ca-chain.crt >> /root/wsl2025-client.ovpn
echo "</ca>" >> /root/wsl2025-client.ovpn

# Ajouter la clé TLS-Auth
echo "" >> /root/wsl2025-client.ovpn
echo "<tls-auth>" >> /root/wsl2025-client.ovpn
cat /etc/openvpn/ta.key >> /root/wsl2025-client.ovpn
echo "</tls-auth>" >> /root/wsl2025-client.ovpn
echo "key-direction 1" >> /root/wsl2025-client.ovpn

echo "✅ Fichier créé : /root/wsl2025-client.ovpn"
```

### Transférer le fichier .ovpn vers DNSSRV

> On transfère le fichier vers DNSSRV (8.8.4.1) pour que les clients Internet puissent le télécharger.

```bash
# Copier le fichier vers DNSSRV via SCP
scp /root/wsl2025-client.ovpn root@8.8.4.1:/var/www/html/wsl2025.ovpn

# Vérifier que le transfert a fonctionné
ssh root@8.8.4.1 "ls -la /var/www/html/wsl2025.ovpn"
```

> 📥 **Téléchargement depuis le client** : `http://8.8.4.1/wsl2025.ovpn`

---

## 8️⃣ BONUS : Authentification Samba avec Active Directory

> 🎯 **Objectif** : Au lieu d'utiliser des utilisateurs locaux (jean, tom, emma), Samba va authentifier les utilisateurs directement via Active Directory (hq.wsl2025.org).

### Prérequis

- [ ] HQDCSRV opérationnel (contrôleur de domaine hq.wsl2025.org)
- [ ] DNS configuré pour résoudre `hq.wsl2025.org` et `hqdcsrv.hq.wsl2025.org`
- [ ] Synchronisation NTP fonctionnelle (Kerberos est sensible au décalage horaire)

### Étape 1 : Installer les paquets nécessaires

```bash
apt update
# On installe UNIQUEMENT winbind (pas sssd) pour éviter les conflits
apt install -y realmd adcli samba-common-bin krb5-user packagekit winbind libpam-winbind libnss-winbind
```

> ⚠️ Lors de l'installation de `krb5-user`, on te demandera :
>
> - **Default Kerberos realm** : `HQ.WSL2025.ORG` (en MAJUSCULES !)
> - **Kerberos servers** : `hqdcsrv.hq.wsl2025.org`
> - **Administrative server** : `hqdcsrv.hq.wsl2025.org`

### Étape 2 : Configurer Kerberos

```bash
cat > /etc/krb5.conf << 'EOF'
[libdefaults]
    default_realm = HQ.WSL2025.ORG
    dns_lookup_realm = false
    dns_lookup_kdc = true
    rdns = false
    ticket_lifetime = 24h
    forwardable = true

[realms]
    HQ.WSL2025.ORG = {
        kdc = hqdcsrv.hq.wsl2025.org
        admin_server = hqdcsrv.hq.wsl2025.org
        default_domain = hq.wsl2025.org
    }
    WSL2025.ORG = {
        kdc = dcwsl.wsl2025.org
        admin_server = dcwsl.wsl2025.org
        default_domain = wsl2025.org
    }

[domain_realm]
    .hq.wsl2025.org = HQ.WSL2025.ORG
    hq.wsl2025.org = HQ.WSL2025.ORG
    .wsl2025.org = WSL2025.ORG
    wsl2025.org = WSL2025.ORG
EOF
```

### Étape 3 : Vérifier la résolution DNS

```bash
# Tester la résolution du contrôleur de domaine
nslookup hqdcsrv.hq.wsl2025.org
ping -c 2 hqdcsrv.hq.wsl2025.org

# Vérifier les enregistrements SRV
host -t SRV _ldap._tcp.hq.wsl2025.org
host -t SRV _kerberos._tcp.hq.wsl2025.org
```

### Étape 4 : Joindre le domaine Active Directory

```bash
# Découvrir le domaine
realm discover hq.wsl2025.org

# Joindre le domaine avec WINBIND uniquement (important : évite les conflits avec sssd)
# Tu peux utiliser "Administrator" ou "vtim" (du groupe IT)
realm join --user=Administrator --client-software=winbind hq.wsl2025.org

# Vérifier que la machine est dans le domaine (doit afficher UNE SEULE entrée avec winbind)
realm list
```

> 📝 **Mot de passe** : Utilise le mot de passe de l'administrateur AD (P@ssw0rd ou celui configuré)

> ⚠️ **Si tu vois DEUX entrées dans `realm list`** (une winbind, une sssd), fais :
>
> ```bash
> realm leave hq.wsl2025.org
> systemctl stop sssd && systemctl disable sssd
> realm join --user=Administrator --client-software=winbind hq.wsl2025.org
> ```

### Étape 5 : Configurer Samba pour Active Directory

```bash
# Sauvegarder l'ancienne configuration
cp /etc/samba/smb.conf /etc/samba/smb.conf.backup-local

# Créer la nouvelle configuration AD
cat > /etc/samba/smb.conf << 'EOF'
[global]
    workgroup = HQ
    realm = HQ.WSL2025.ORG
    server string = HQINFRASRV File Server (AD Auth)

    # Sécurité Active Directory
    security = ads
    encrypt passwords = yes

    # Backend Winbind pour l'authentification
    idmap config * : backend = tdb
    idmap config * : range = 3000-7999
    idmap config HQ : backend = rid
    idmap config HQ : range = 10000-999999

    # Options Winbind
    winbind use default domain = yes
    winbind enum users = yes
    winbind enum groups = yes
    winbind refresh tickets = yes

    # Mapping des utilisateurs
    template shell = /bin/bash
    template homedir = /home/%U

    # Logs
    log file = /var/log/samba/log.%m
    max log size = 1000
    log level = 1

[Public]
    path = /srv/datastorage/shares/public
    comment = Partage public lecture seule
    browseable = yes
    read only = yes
    guest ok = yes

[Private]
    path = /srv/datastorage/shares/private
    comment = Partage privé (AD Users)
    browseable = no
    read only = no

    # Utilisateurs AD autorisés (remplacer par les vrais noms AD)
    # Tom = vtim, Emma = estique, Jean = jticipe (selon l'annexe du sujet)
    valid users = @"Domain Users"
    write list = vtim estique
    read list = jticipe

    # Sécurité
    hide dot files = yes
    veto files = /*.exe/*.zip/
    hosts allow = 10.4.0.0/16
EOF
```

### Étape 6 : Configurer NSS et PAM pour Winbind

```bash
# Ajouter winbind à NSS
cat > /etc/nsswitch.conf << 'EOF'
passwd:         files systemd winbind
group:          files systemd winbind
shadow:         files winbind
gshadow:        files

hosts:          files dns
networks:       files

protocols:      db files
services:       db files
ethers:         db files
rpc:            db files

netgroup:       nis
EOF
```

### Étape 7 : Redémarrer les services

```bash
# Redémarrer les services dans le bon ordre
systemctl restart winbind
systemctl restart smbd nmbd

# Activer au démarrage
systemctl enable winbind smbd nmbd
```

### Étape 8 : Vérifier l'intégration AD

```bash
# Tester l'authentification Kerberos
kinit Administrator@HQ.WSL2025.ORG
klist

# Vérifier que Winbind voit les utilisateurs AD
wbinfo -u    # Liste des utilisateurs
wbinfo -g    # Liste des groupes

# Vérifier un utilisateur spécifique
wbinfo -i vtim
getent passwd vtim

# Tester la connexion Samba avec un utilisateur AD
smbclient -L localhost -U vtim
```

### Étape 9 : Créer les répertoires home pour les utilisateurs AD

```bash
# Créer le répertoire home de base
mkdir -p /home

# Option : Créer automatiquement les homes à la première connexion
# Ajouter dans /etc/pam.d/common-session :
echo "session required pam_mkhomedir.so skel=/etc/skel umask=0077" >> /etc/pam.d/common-session
```

### Étape 10 : Ajuster les permissions des partages

```bash
# Définir les permissions pour que les utilisateurs AD puissent écrire
# On utilise les GID de Winbind

# Public : lecture pour tous
chmod 755 /srv/datastorage/shares/public

# Private : accès pour les utilisateurs du domaine
chmod 770 /srv/datastorage/shares/private
chown root:"domain users" /srv/datastorage/shares/private
```

---

### ✅ Tests de vérification du bonus

| Test      | Commande                                | Résultat attendu                                  |
| --------- | --------------------------------------- | ------------------------------------------------- |
| Domaine   | `realm list`                            | Affiche `hq.wsl2025.org` avec status "configured" |
| Kerberos  | `klist`                                 | Affiche un ticket valide                          |
| Users AD  | `wbinfo -u`                             | Liste les utilisateurs AD (vtim, npresso, etc.)   |
| Groups AD | `wbinfo -g`                             | Liste les groupes AD (Domain Users, IT, etc.)     |
| Getent    | `getent passwd vtim`                    | Affiche les infos de l'utilisateur vtim           |
| Samba     | `smbclient //localhost/Private -U vtim` | Connexion réussie avec credentials AD             |

### Test complet Samba AD

```bash
# Test de connexion au partage Private avec un utilisateur AD
smbclient //localhost/Private -U vtim%P@ssw0rd -c "ls"

# Créer un fichier test
smbclient //localhost/Private -U vtim%P@ssw0rd -c "put /etc/hostname testfile.txt"

# Vérifier que le fichier a été créé avec le bon propriétaire
ls -la /srv/datastorage/shares/private/
```

---

### 🔧 Dépannage

#### Erreur "NT_STATUS_LOGON_FAILURE"

```bash
# Vérifier que le compte existe dans AD
wbinfo -i vtim

# Vérifier Kerberos
kinit vtim@HQ.WSL2025.ORG
```

#### Erreur "Could not get domain info"

```bash
# Rejoindre le domaine
net ads join -U Administrator

# Vérifier la connexion AD
net ads testjoin
```

#### Les utilisateurs AD ne sont pas visibles

```bash
# Redémarrer winbind
systemctl restart winbind

# Vider le cache
net cache flush

# Vérifier les logs
tail -f /var/log/samba/log.winbindd
```

#### Erreur de synchronisation horaire

```bash
# Kerberos est très sensible au décalage horaire (max 5 min)
ntpq -p
# Si décalage, forcer la synchro :
systemctl stop ntpsec
ntpdate hqdcsrv.hq.wsl2025.org
systemctl start ntpsec
```

---

## ✅ Vérifications

| Test       | Commande                          | Résultat attendu                                   |
| ---------- | --------------------------------- | -------------------------------------------------- |
| DHCP       | `journalctl -u isc-dhcp-server`   | Service actif, failover OK                         |
| Samba      | `smbclient -L localhost -U vtim`  | Partages Public et Private visibles (avec user AD) |
| iSCSI      | `tgtadm --mode target --op show`  | Target LUN1 visible                                |
| VPN        | `systemctl status openvpn@server` | Active (running)                                   |
| VPN Port   | `ss -ulnp \| grep 4443`           | Port 4443/udp en écoute                            |
| VPN Tunnel | `ip addr show tun0`               | Interface tun0 avec IP 10.4.22.1                   |
| VPN Logs   | `tail /var/log/openvpn.log`       | Pas d'erreurs                                      |
| NTP        | `ntpq -p`                         | Synchronisé (stratum 10)                           |
| Forwarding | `sysctl net.ipv4.ip_forward`      | = 1                                                |

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
