# DCWSL - Contrôleur de Domaine Forest Root

> **OS** : Debian 13 CLI (Samba AD DC)  
> **IP** : 10.4.10.4 (VLAN 10 - Servers)  
> **Rôles** : DNS racine wsl2025.org, Active Directory Forest Root

---

## 📋 Prérequis

- [ ] Debian 13 installé
- [ ] IP statique configurée
- [ ] Accès réseau fonctionnel

---

## 1️⃣ Configuration de base

### Hostname
```bash
hostnamectl set-hostname dcwsl
```

### Configuration réseau
```bash
cat > /etc/network/interfaces << 'EOF'
auto eth0
iface eth0 inet static
    address 10.4.10.4
    netmask 255.255.255.0
    gateway 10.4.10.254
    dns-nameservers 127.0.0.1
EOF
```

---

## 2️⃣ Installation Samba AD DC

```bash
apt update
apt install -y samba krb5-user krb5-config winbind libpam-winbind libnss-winbind

# Arrêter les services
systemctl stop smbd nmbd winbind
systemctl disable smbd nmbd winbind

# Sauvegarder l'ancienne config
mv /etc/samba/smb.conf /etc/samba/smb.conf.bak
```

### Provision du domaine
```bash
samba-tool domain provision \
    --use-rfc2307 \
    --realm=WSL2025.ORG \
    --domain=WSL2025 \
    --server-role=dc \
    --dns-backend=SAMBA_INTERNAL \
    --adminpass='P@ssw0rd'
```

### Configuration Kerberos
```bash
cp /var/lib/samba/private/krb5.conf /etc/krb5.conf
```

### Démarrer Samba AD
```bash
systemctl unmask samba-ad-dc
systemctl enable samba-ad-dc
systemctl start samba-ad-dc
```

---

## 3️⃣ Configuration DNS

### Zone wsl2025.org - Enregistrements selon le plan d'adressage
```bash
# Connexion en tant qu'administrator
samba-tool dns zonecreate localhost wsl2025.org -U administrator

# Serveurs HQ
samba-tool dns add localhost wsl2025.org hqinfrasrv A 10.4.10.2 -U administrator
samba-tool dns add localhost wsl2025.org dcwsl A 10.4.10.4 -U administrator
samba-tool dns add localhost wsl2025.org hqmailsrv A 10.4.10.3 -U administrator
samba-tool dns add localhost wsl2025.org hqfwsrv A 217.4.160.1 -U administrator

# CNAME
samba-tool dns add localhost wsl2025.org www CNAME hqfwsrv.wsl2025.org -U administrator
samba-tool dns add localhost wsl2025.org webmail CNAME hqmailsrv.wsl2025.org -U administrator

# VPN
samba-tool dns add localhost wsl2025.org vpn A 191.4.157.33 -U administrator

# Switches
samba-tool dns add localhost wsl2025.org accsw1 A 10.4.99.11 -U administrator
samba-tool dns add localhost wsl2025.org accsw2 A 10.4.99.12 -U administrator
samba-tool dns add localhost wsl2025.org coresw1 A 10.4.99.253 -U administrator
samba-tool dns add localhost wsl2025.org coresw2 A 10.4.99.252 -U administrator

# Routeurs
samba-tool dns add localhost wsl2025.org edge1 A 10.4.254.1 -U administrator
samba-tool dns add localhost wsl2025.org edge2 A 10.4.254.5 -U administrator
samba-tool dns add localhost wsl2025.org wanrtr A 10.116.4.2 -U administrator
samba-tool dns add localhost wsl2025.org remfw A 10.4.100.126 -U administrator
```

### Forwarder vers DNSSRV
```bash
# Configurer le forwarder vers DNSSRV (8.8.4.1) pour les résolutions externes
cat >> /etc/samba/smb.conf << 'EOF'
[global]
    dns forwarder = 8.8.4.1
EOF

samba-tool dns update localhost wsl2025.org @ A 10.4.10.4 -U administrator
```

---

## 4️⃣ Vérification du domaine

```bash
# Tester le domaine
samba-tool domain level show

# Tester Kerberos
kinit administrator@WSL2025.ORG

# Tester DNS
host -t A dcwsl.wsl2025.org localhost
host -t A hqinfrasrv.wsl2025.org localhost

# Tester LDAP
ldapsearch -x -H ldap://localhost -b "DC=wsl2025,DC=org"
```

---

## 5️⃣ Créer les sites AD

```bash
# Créer le site HQ
samba-tool sites create HQ

# Créer le site Remote
samba-tool sites create Remote
```

---

## ✅ Vérifications

| Test | Commande |
|------|----------|
| Samba AD | `samba-tool domain level show` |
| DNS | `host -t A dcwsl.wsl2025.org localhost` |
| Kerberos | `kinit administrator@WSL2025.ORG` |
| LDAP | `ldapsearch -x -H ldap://localhost -b "DC=wsl2025,DC=org"` |

---

## 📝 Notes

- **IP** : 10.4.10.4
- Ce serveur est le **Global Catalog** et la racine de la forêt `wsl2025.org`
- HQDCSRV sera ajouté comme domaine enfant `hq.wsl2025.org`
- REMDCSRV sera ajouté comme domaine enfant `rem.wsl2025.org`
- Toutes les requêtes DNS inconnues sont forwardées vers DNSSRV (8.8.4.1)
