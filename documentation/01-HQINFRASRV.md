# HQINFRASRV - Serveur Infrastructure HQ

> **OS** : Debian 13 CLI  
> **IP** : 10.4.10.2 (VLAN 10 - Servers)  
> **Rôles** : DHCP, VPN OpenVPN, Stockage LVM/iSCSI, Samba, NTP

---

## 📋 Prérequis

- [ ] Debian 13 installé
- [ ] Accès réseau fonctionnel (VLAN 10 - Servers)
- [ ] 2 disques supplémentaires de 5 Go chacun
- [ ] HQDCSRV opérationnel (pour les certificats)

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
auto eth0
iface eth0 inet static
    address 10.4.10.2
    netmask 255.255.255.0
    gateway 10.4.10.254
    dns-nameservers 10.4.10.1
    dns-search wsl2025.org hq.wsl2025.org
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
apt install -y chrony

cat > /etc/chrony/chrony.conf << 'EOF'
# Serveur NTP pour l'infrastructure
server 0.fr.pool.ntp.org iburst
server 1.fr.pool.ntp.org iburst

# Autoriser les clients du réseau local
allow 10.4.0.0/16

# Clé d'authentification NTP
keyfile /etc/chrony/chrony.keys
EOF

# Créer la clé d'authentification
echo "1 SHA1 HEX:$(openssl rand -hex 20)" > /etc/chrony/chrony.keys
chmod 600 /etc/chrony/chrony.keys

systemctl restart chrony
```

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

## 5️⃣ Serveur DHCP

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

# Failover configuration (Primary)
failover peer "dhcp-failover" {
    primary;
    address 10.4.10.2;
    port 647;
    peer address 10.4.10.3;
    peer port 647;
    max-response-delay 30;
    max-unacked-updates 10;
    load balance max seconds 3;
    mclt 1800;
    split 128;
}

# Subnet Clients (VLAN 20) - 10.4.20.0/23
subnet 10.4.20.0 netmask 255.255.254.0 {
    option routers 10.4.20.254;
    option broadcast-address 10.4.21.255;
    pool {
        failover peer "dhcp-failover";
        range 10.4.20.1 10.4.21.200;
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

# Interface d'écoute
echo 'INTERFACESv4="eth0"' > /etc/default/isc-dhcp-server

systemctl restart isc-dhcp-server
systemctl enable isc-dhcp-server
```

### Configuration DHCP Relay sur les switches
> Déjà fait dans le cœur de réseau (`ip helper-address 10.4.10.2`)

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

### Installation
```bash
apt install -y openvpn easy-rsa
```

### Génération des certificats
```bash
make-cadir /etc/openvpn/easy-rsa
cd /etc/openvpn/easy-rsa

# Initialiser la PKI
./easyrsa init-pki
./easyrsa build-ca nopass  # Ou utiliser le certificat de HQDCSRV

# Générer le certificat serveur
./easyrsa gen-req server nopass
./easyrsa sign-req server server

# Générer les paramètres DH
./easyrsa gen-dh

# Générer la clé TLS
openvpn --genkey secret /etc/openvpn/ta.key
```

### Configuration serveur OpenVPN
```bash
cat > /etc/openvpn/server.conf << 'EOF'
port 4443
proto udp
dev tun

ca /etc/openvpn/easy-rsa/pki/ca.crt
cert /etc/openvpn/easy-rsa/pki/issued/server.crt
key /etc/openvpn/easy-rsa/pki/private/server.key
dh /etc/openvpn/easy-rsa/pki/dh.pem
tls-auth /etc/openvpn/ta.key 0

server 10.4.22.0 255.255.255.0
push "route 10.4.0.0 255.255.0.0"
push "dhcp-option DNS 10.4.10.1"
push "dhcp-option DOMAIN hq.wsl2025.org"

keepalive 10 120
cipher AES-256-GCM
user nobody
group nogroup
persist-key
persist-tun
verb 3
EOF

systemctl enable --now openvpn@server
```

### Activer le forwarding IP
```bash
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p
```

---

## ✅ Vérifications

| Test | Commande |
|------|----------|
| DHCP | `journalctl -u isc-dhcp-server` |
| Samba | `smbclient -L localhost -U jean` |
| iSCSI | `tgtadm --mode target --op show` |
| VPN | `systemctl status openvpn@server` |
| NTP | `chronyc sources` |

---

## 📝 Notes

- Le port VPN 4443 est NATé depuis 191.4.157.33 sur les routeurs EDGE
- Les certificats VPN peuvent être signés par HQDCSRV (Sub CA)
- Pour l'authentification AD du VPN, installer `openvpn-auth-ldap`
- IP du serveur : **10.4.10.2**
