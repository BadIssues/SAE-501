#!/bin/bash

# Script d'installation automatique des paquets pour le projet SAE501
# Usage: ./install_packages.sh <nom_machine>

if [ -z "$1" ]; then
    echo "Usage: $0 <nom_machine>"
    echo "Machines disponibles : hqinfrasrv, hqmailsrv, hqfwsrv, mgmtclt, dnssrv, inetsrv, inetclt, remfw"
    exit 1
fi

MACHINE=$1

echo ">>> Mise à jour des dépôts..."
apt update

echo ">>> Installation pour : $MACHINE"

case $MACHINE in
    "hqinfrasrv")
        echo "Installation des paquets Infrastructure HQ (DHCP, VPN, iSCSI, Samba)..."
        apt install -y openssh-server fail2ban chrony lvm2 tgt isc-dhcp-server samba openvpn easy-rsa
        ;;
        
    "hqmailsrv")
        echo "Installation des paquets Mail HQ (Postfix, Dovecot, AMP, ZFS)..."
        # Note: L'installation de Roundcube peut demander des interactions (dbconfig-common).
        # On peut pré-configurer ou installer de manière non-interactive si nécessaire, 
        # mais ici on laisse l'intéractivité pour la config DB.
        DEBIAN_FRONTEND=noninteractive apt install -y openssh-server fail2ban zfsutils-linux open-iscsi \
            postfix postfix-ldap libsasl2-modules \
            dovecot-imapd dovecot-lmtpd \
            apache2 php php-mysql php-intl php-xml php-mbstring php-zip mariadb-server \
            isc-dhcp-server bind9
            
        echo "Installation de Roundcube (peut demander une config manuelle)..."
        apt install -y roundcube roundcube-mysql
        ;;
        
    "hqfwsrv"|"remfw")
        echo "Installation des outils Firewall (nftables)..."
        apt install -y nftables
        ;;
        
    "mgmtclt")
        echo "Installation du poste d'administration (Ansible, Git, TFTP)..."
        apt install -y ansible python3-pip git curl wget openssh-client tftp-hpa tftpd-hpa lftp
        ;;
        
    "dnssrv")
        echo "Installation DNS Server (Bind9, NTPsec)..."
        apt install -y openssh-server fail2ban ntpsec \
            bind9 bind9utils bind9-doc dnsutils \
            openssl apache2
        ;;
        
    "inetsrv")
        echo "Installation Services Internet (Docker, FTP)..."
        apt install -y openssh-server fail2ban docker.io docker-compose vsftpd
        ;;
        
    "inetclt")
        echo "Installation Client Internet (Firefox, Curl, Outils réseau)..."
        apt install -y firefox-esr curl wget dnsutils netcat-openbsd lftp
        ;;
        
    *)
        echo "Erreur : Machine '$MACHINE' inconnue."
        echo "Choix possibles : hqinfrasrv, hqmailsrv, hqfwsrv, mgmtclt, dnssrv, inetsrv, inetclt, remfw"
        exit 1
        ;;
esac

echo ">>> Installation terminée pour $MACHINE !"



