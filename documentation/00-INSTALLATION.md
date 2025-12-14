# 📥 Guide d'Installation Global (Préparation)

Ce document recense l'ensemble des paquets nécessaires pour chaque machine Linux de l'infrastructure.
L'objectif est d'effectuer ces installations en une seule fois, tant que les machines ont accès à Internet (avant la configuration du réseau final qui peut couper l'accès).

> **Note :** Vous pouvez utiliser le script `install_packages.sh` situé à la racine du projet pour automatiser cette étape.

---

## 🚀 Méthode Rapide (Script)

1. Transférez le script `install_packages.sh` sur la machine concernée (ou copiez-collez son contenu).
2. Rendez le script exécutable :
   ```bash
   chmod +x install_packages.sh
   ```
3. Lancez le script avec le nom de la machine en argument :
   ```bash
   ./install_packages.sh hqinfrasrv
   ```
   _(Remplacez `hqinfrasrv` par le nom de la machine actuelle)_

---

## 📦 Détail des paquets par machine

Si vous préférez l'installation manuelle, voici les commandes pour chaque serveur.

### 🏢 Site HQ (Siège)

#### HQINFRASRV (Infrastructure : DHCP, VPN, iSCSI, Samba)

```bash
apt update
apt install -y openssh-server fail2ban chrony lvm2 tgt isc-dhcp-server samba openvpn easy-rsa
```

#### HQMAILSRV (Messagerie & Stockage ZFS)

```bash
apt update
apt install -y openssh-server fail2ban zfsutils-linux open-iscsi \
    postfix postfix-ldap libsasl2-modules \
    dovecot-imapd dovecot-lmtpd \
    apache2 php php-mysql php-intl php-xml php-mbstring php-zip mariadb-server \
    roundcube roundcube-mysql \
    isc-dhcp-server bind9
```

#### HQFWSRV (Firewall de Bordure)

```bash
apt update
apt install -y nftables
```

#### MGMTCLT (Poste d'Administration)

```bash
apt update
apt install -y ansible python3-pip git curl wget openssh-client tftp-hpa tftpd-hpa lftp
```

---

### 🌍 Site Internet & DNS

#### DNSSRV (DNS Public & Autorité racine)

```bash
apt update
apt install -y openssh-server fail2ban ntpsec \
    bind9 bind9utils bind9-doc dnsutils \
    openssl apache2
```

#### INETSRV (Serveur Web Docker & FTP)

```bash
apt update
apt install -y openssh-server fail2ban docker.io docker-compose vsftpd
```

#### INETCLT (Client Internet de test)

```bash
apt update
apt install -y firefox-esr curl wget dnsutils netcat-openbsd lftp
```

---

### 🏭 Site Remote

#### REMFW (Firewall Remote)

```bash
apt update
apt install -y nftables
```

_(Les autres serveurs Remote comme REMDCSRV/REMINFRASRV sont sous Windows Server ou utilisent des rôles similaires à HQ)_

---

## 📝 Après l'installation

Une fois les paquets installés :

1. Vous pouvez couper l'accès internet (NAT) si nécessaire pour passer à la configuration réseau finale.
2. Procédez à la configuration IP statique de chaque machine selon les fiches respectives.

