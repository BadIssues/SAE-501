# HQMAILSRV - Serveur Mail HQ

> **OS** : Debian 13 CLI  
> **IP ens192** : 10.4.10.3/24 (VLAN 10 - Servers)  
> **IP ens224** : 10.4.20.2/24 (VLAN 20 - Clients) - Interface DHCP Failover  
> **Rôles** : Mail SMTP/IMAP, Webmail, ZFS, DHCP Failover (Secondary), DNS Secondary

---

## 📋 Prérequis

- [ ] Debian 13 installé
- [ ] **2 cartes réseau** : ens192 (VLAN 10) + ens224 (VLAN 20 pour DHCP)
- [ ] 3 disques supplémentaires de 1 Go chacun (pour ZFS)
- [ ] HQDCSRV opérationnel (certificats)
- [ ] HQINFRASRV opérationnel (iSCSI pour backup et DHCP failover)

---

## 1️⃣ Configuration de base

### Hostname et réseau

```bash
hostnamectl set-hostname hqmailsrv

cat > /etc/network/interfaces << 'EOF'
# Interface VLAN 10 - Servers
auto ens192
iface ens192 inet static
    address 10.4.10.3
    netmask 255.255.255.0
    gateway 10.4.10.254
    dns-nameservers 10.4.10.1
    dns-search wsl2025.org hq.wsl2025.org

# Interface VLAN 20 - Clients (pour DHCP Failover)
auto ens224
iface ens224 inet static
    address 10.4.20.2
    netmask 255.255.255.0
EOF
```

### SSH et Fail2Ban

```bash
apt update && apt install -y openssh-server fail2ban

cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true

[postfix]
enabled = true

[dovecot]
enabled = true
EOF

systemctl enable --now fail2ban
```

---

## 2️⃣ Stockage ZFS

### Installation ZFS

```bash
apt install -y zfsutils-linux
```

### Création du pool RAID-Z (RAID 5)

```bash
# Identifier les 3 disques
lsblk

# Créer le pool avec RAID-Z et chiffrement
zpool create -o ashift=12 \
    -O encryption=aes-256-gcm \
    -O keyformat=passphrase \
    -O keylocation=prompt \
    zfspool raidz /dev/sdb /dev/sdc /dev/sdd

# Créer le dataset data
zfs create zfspool/data

# Monter sur /data
zfs set mountpoint=/data zfspool/data

# Déplacer /home vers /data/home
zfs create zfspool/data/home
rsync -av /home/ /data/home/
rm -rf /home/*
ln -s /data/home /home
```

### Vérification

```bash
zpool status
zfs list
```

---

## 3️⃣ Client iSCSI (pour backup)

```bash
apt install -y open-iscsi

# Découverte de la cible
iscsiadm -m discovery -t sendtargets -p 10.4.10.2

# Configuration des credentials
cat >> /etc/iscsi/iscsid.conf << 'EOF'
node.session.auth.authmethod = CHAP
node.session.auth.username = iscsiuser
node.session.auth.password = P@ssw0rd
EOF

# Connexion
iscsiadm -m node --targetname iqn.2025-01.org.wsl2025:storage.lun1 --portal 10.4.10.2 --login

# Formater et monter le LUN iSCSI
mkfs.ext4 /dev/sde  # Adapter selon le device détecté
mkdir -p /mnt/backup
echo "/dev/sde /mnt/backup ext4 _netdev 0 0" >> /etc/fstab
mount -a
```

---

## 4️⃣ Backup automatisé avec rsync

```bash
# Script de backup
cat > /usr/local/bin/backup-home.sh << 'EOF'
#!/bin/bash
rsync -avz --delete /data/home/ /mnt/backup/home-backup/
EOF

chmod +x /usr/local/bin/backup-home.sh

# Cron pour 22h chaque jour
echo "0 22 * * * root /usr/local/bin/backup-home.sh" >> /etc/crontab
```

---

## 5️⃣ Serveur Mail Postfix (SMTP)

### Installation

```bash
apt install -y postfix postfix-ldap libsasl2-modules
```

### Configuration Postfix

```bash
cat > /etc/postfix/main.cf << 'EOF'
# Paramètres de base
myhostname = hqmailsrv.wsl2025.org
mydomain = wsl2025.org
myorigin = $mydomain
mydestination = $myhostname, localhost.$mydomain, localhost, $mydomain

# Réseau
inet_interfaces = all
inet_protocols = ipv4
mynetworks = 127.0.0.0/8, 10.4.0.0/16

# Mailbox
home_mailbox = Maildir/

# TLS/SSL (SMTPS)
smtpd_tls_cert_file = /etc/ssl/certs/mail.crt
smtpd_tls_key_file = /etc/ssl/private/mail.key
smtpd_tls_security_level = encrypt
smtpd_tls_auth_only = yes
smtp_tls_security_level = may

# SASL Authentication
smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth
smtpd_sasl_auth_enable = yes
smtpd_recipient_restrictions = permit_sasl_authenticated, permit_mynetworks, reject_unauth_destination

# Bloquer les .zip en pièce jointe
mime_header_checks = regexp:/etc/postfix/mime_header_checks
EOF

# Règle pour bloquer .zip
echo '/name=[^>]*\.zip/ REJECT Les fichiers .zip ne sont pas autorisés' > /etc/postfix/mime_header_checks
postmap /etc/postfix/mime_header_checks
```

### Activer SMTPS (port 465)

```bash
cat >> /etc/postfix/master.cf << 'EOF'
smtps     inet  n       -       y       -       -       smtpd
  -o syslog_name=postfix/smtps
  -o smtpd_tls_wrappermode=yes
  -o smtpd_sasl_auth_enable=yes
EOF
```

---

## 6️⃣ Serveur IMAP Dovecot

### Installation

```bash
apt install -y dovecot-imapd dovecot-lmtpd
```

### Configuration Dovecot

```bash
cat > /etc/dovecot/conf.d/10-mail.conf << 'EOF'
mail_location = maildir:~/Maildir
EOF

cat > /etc/dovecot/conf.d/10-ssl.conf << 'EOF'
ssl = required
ssl_cert = </etc/ssl/certs/mail.crt
ssl_key = </etc/ssl/private/mail.key
ssl_min_protocol = TLSv1.2
EOF

cat > /etc/dovecot/conf.d/10-auth.conf << 'EOF'
disable_plaintext_auth = yes
auth_mechanisms = plain login
EOF

cat > /etc/dovecot/conf.d/10-master.conf << 'EOF'
service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0660
    user = postfix
    group = postfix
  }
}
EOF
```

---

## 7️⃣ Création des utilisateurs mail

```bash
# Créer les utilisateurs du sujet
for user in vtim npresso jticipe rola estique rtaha dpeltier; do
    useradd -m -s /bin/bash $user
    echo "$user:P@ssw0rd" | chpasswd
    mkdir -p /data/home/$user/Maildir
    chown -R $user:$user /data/home/$user
done
```

### Aliases pour les groupes de distribution

```bash
cat >> /etc/aliases << 'EOF'
all: vtim, npresso, jticipe, rola, estique, rtaha, dpeltier
admin: vtim, dpeltier
EOF

newaliases
```

---

## 8️⃣ Webmail (Roundcube)

### Installation

```bash
apt install -y apache2 php php-mysql php-intl php-xml php-mbstring php-zip mariadb-server roundcube roundcube-mysql
```

### Configuration Apache

```bash
cat > /etc/apache2/sites-available/webmail.conf << 'EOF'
<VirtualHost *:80>
    ServerName webmail.wsl2025.org
    Redirect permanent / https://webmail.wsl2025.org/
</VirtualHost>

<VirtualHost *:443>
    ServerName webmail.wsl2025.org
    DocumentRoot /var/lib/roundcube/public_html

    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/webmail.crt
    SSLCertificateKeyFile /etc/ssl/private/webmail.key

    <Directory /var/lib/roundcube/public_html>
        Options -Indexes
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF

a2enmod ssl rewrite
a2ensite webmail
systemctl restart apache2
```

### Configuration Roundcube

```bash
# Éditer /etc/roundcube/config.inc.php
nano /etc/roundcube/config.inc.php
```

```php
$config['default_host'] = 'ssl://localhost';
$config['default_port'] = 993;
$config['smtp_server'] = 'ssl://localhost';
$config['smtp_port'] = 465;
$config['smtp_user'] = '%u';
$config['smtp_pass'] = '%p';
```

---

## 9️⃣ DHCP Failover (Secondary/Fille)

> ⚠️ **IMPORTANT** : HQMAILSRV est le serveur DHCP **secondaire (fille)** pour le VLAN 20 (Clients).
> Le failover est assuré avec HQINFRASRV qui est le serveur **primaire (mère)**.
> Les deux serveurs communiquent via leurs interfaces dans le VLAN 20 :
>
> - HQINFRASRV : 10.4.20.1 (ens224) - Primary
> - HQMAILSRV : 10.4.20.2 (ens224) - Secondary

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

# Failover configuration (Secondary - Fille)
failover peer "dhcp-failover" {
    secondary;
    address 10.4.20.2;           # IP de HQMAILSRV dans le VLAN 20
    port 647;
    peer address 10.4.20.1;      # IP de HQINFRASRV dans le VLAN 20
    peer port 647;
    max-response-delay 30;
    max-unacked-updates 10;
    load balance max seconds 3;
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

# Subnet Servers (déclaration requise car l'interface ens192 est dans ce subnet)
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
# Vérifier la syntaxe de la configuration
dhcpd -t -cf /etc/dhcp/dhcpd.conf

# Voir les logs de communication failover
journalctl -u isc-dhcp-server | grep -i failover

# Vérifier l'état du service
systemctl status isc-dhcp-server
```

> ✅ Le failover est configuré avec HQINFRASRV (primary). Les deux serveurs se partagent 50% des adresses IP.

---

## 🔟 DNS Secondary

```bash
apt install -y bind9

cat > /etc/bind/named.conf.local << 'EOF'
zone "wsl2025.org" {
    type slave;
    file "/var/cache/bind/wsl2025.org.zone";
    masters { 10.4.10.4; };
};
EOF

systemctl restart bind9
```

---

## ✅ Vérifications

| Test      | Commande                                  |
| --------- | ----------------------------------------- |
| ZFS       | `zpool status && zfs list`                |
| iSCSI     | `iscsiadm -m session`                     |
| Postfix   | `systemctl status postfix`                |
| Dovecot   | `systemctl status dovecot`                |
| Webmail   | `curl -k https://localhost`               |
| SMTP Test | `openssl s_client -connect localhost:465` |
| IMAP Test | `openssl s_client -connect localhost:993` |

---

## 📝 Notes

- **IP ens192 (VLAN 10 Servers)** : 10.4.10.3/24
- **IP ens224 (VLAN 20 Clients)** : 10.4.20.2/24 - Interface DHCP Secondary (Fille)
- Les certificats SSL doivent être demandés à HQDCSRV (Sub CA)
- Le webmail est accessible depuis l'externe via NAT sur **191.4.157.33** ports 80/443
- Configurer DNSSEC avec le certificat de HQDCSRV
- Le DHCP failover fonctionne avec HQINFRASRV (10.4.20.1) dans le VLAN 20
