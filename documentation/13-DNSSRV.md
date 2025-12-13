# DNSSRV - Serveur DNS Public et Root CA

> **OS** : Debian 13 CLI  
> **IP** : 8.8.4.1 (Internet)  
> **Rôles** : DNS Public, Root CA, DNSSEC

---

## 📋 Prérequis

- [ ] Debian 13 installé
- [ ] IP statique configurée
- [ ] Accès Internet

---

## 1️⃣ Configuration de base

### Hostname et réseau

```bash
hostnamectl set-hostname dnssrv

cat > /etc/network/interfaces << 'EOF'
auto eth0
iface eth0 inet static
    address 8.8.4.1
    netmask 255.255.255.248
    gateway 8.8.4.6
    dns-nameservers 127.0.0.1
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
EOF

systemctl enable --now fail2ban
```

---

## 2️⃣ Installation BIND9

```bash
apt install -y bind9 bind9utils bind9-doc dnsutils
```

---

## 3️⃣ Configuration DNS

### Configuration principale

```bash
cat > /etc/bind/named.conf.options << 'EOF'
options {
    directory "/var/cache/bind";

    recursion yes;
    allow-recursion { any; };

    forwarders {
        8.8.8.8;
        1.1.1.1;
    };

    dnssec-validation auto;

    listen-on { any; };
    listen-on-v6 { none; };
};
EOF
```

### Zones locales

```bash
cat > /etc/bind/named.conf.local << 'EOF'
// Zone worldskills.org
zone "worldskills.org" {
    type master;
    file "/etc/bind/zones/db.worldskills.org";
    allow-transfer { none; };
};

// Zone wsl2025.org (vue publique)
zone "wsl2025.org" {
    type master;
    file "/etc/bind/zones/db.wsl2025.org";
    allow-transfer { none; };
};
EOF
```

### Zone worldskills.org

```bash
mkdir -p /etc/bind/zones

cat > /etc/bind/zones/db.worldskills.org << 'EOF'
$TTL    604800
@       IN      SOA     dnssrv.worldskills.org. admin.worldskills.org. (
                              2025011201         ; Serial
                              604800             ; Refresh
                              86400              ; Retry
                              2419200            ; Expire
                              604800 )           ; Negative Cache TTL
;
@       IN      NS      dnssrv.worldskills.org.

; Serveurs
dnssrv          IN      A       8.8.4.1
inetsrv         IN      A       8.8.4.2
wanrtr          IN      A       8.8.4.6

; Alias
www             IN      CNAME   inetsrv.worldskills.org.
ftp             IN      CNAME   inetsrv.worldskills.org.
EOF
```

### Zone wsl2025.org (vue publique)

```bash
cat > /etc/bind/zones/db.wsl2025.org << 'EOF'
$TTL    604800
@       IN      SOA     dnssrv.worldskills.org. admin.wsl2025.org. (
                              2025011201         ; Serial
                              604800             ; Refresh
                              86400              ; Retry
                              2419200            ; Expire
                              604800 )           ; Negative Cache TTL
;
@       IN      NS      dnssrv.worldskills.org.

; Serveurs publics
hqfwsrv         IN      A       217.4.160.1
vpn             IN      A       191.4.157.33
webmail         IN      A       191.4.157.33

; Alias
www             IN      CNAME   hqfwsrv.wsl2025.org.
authentication  IN      CNAME   hqfwsrv.wsl2025.org.
EOF
```

### Vérifier et recharger

```bash
named-checkconf
named-checkzone worldskills.org /etc/bind/zones/db.worldskills.org
named-checkzone wsl2025.org /etc/bind/zones/db.wsl2025.org

systemctl restart bind9
systemctl enable bind9
```

---

## 4️⃣ DNSSEC

### Générer les clés

```bash
cd /etc/bind/zones

# Clé de signature de zone (ZSK)
dnssec-keygen -a RSASHA256 -b 2048 -n ZONE worldskills.org
dnssec-keygen -a RSASHA256 -b 2048 -n ZONE wsl2025.org

# Clé de signature de clé (KSK)
dnssec-keygen -a RSASHA256 -b 4096 -n ZONE -f KSK worldskills.org
dnssec-keygen -a RSASHA256 -b 4096 -n ZONE -f KSK wsl2025.org
```

### Signer les zones

```bash
# Ajouter les clés aux zones
cat Kworldskills.org.*.key >> /etc/bind/zones/db.worldskills.org
cat Kwsl2025.org.*.key >> /etc/bind/zones/db.wsl2025.org

# Signer
dnssec-signzone -A -3 $(head -c 1000 /dev/random | sha1sum | cut -b 1-16) -N INCREMENT -o worldskills.org -t db.worldskills.org
dnssec-signzone -A -3 $(head -c 1000 /dev/random | sha1sum | cut -b 1-16) -N INCREMENT -o wsl2025.org -t db.wsl2025.org
```

### Mettre à jour la configuration

```bash
# Modifier named.conf.local pour utiliser les zones signées
sed -i 's/db.worldskills.org/db.worldskills.org.signed/' /etc/bind/named.conf.local
sed -i 's/db.wsl2025.org/db.wsl2025.org.signed/' /etc/bind/named.conf.local

systemctl restart bind9
```

---

## 5️⃣ Root CA (Autorité de Certification Racine)

### Installation OpenSSL

```bash
apt install -y openssl
```

### Créer la structure PKI

```bash
mkdir -p /etc/ssl/CA/{certs,crl,newcerts,private,requests}
chmod 700 /etc/ssl/CA/private
touch /etc/ssl/CA/index.txt
echo 1000 > /etc/ssl/CA/serial
echo 1000 > /etc/ssl/CA/crlnumber
```

### Configuration OpenSSL

```bash
cat > /etc/ssl/CA/openssl.cnf << 'EOF'
[ ca ]
default_ca = CA_default

[ CA_default ]
dir               = /etc/ssl/CA
certs             = $dir/certs
crl_dir           = $dir/crl
new_certs_dir     = $dir/newcerts
database          = $dir/index.txt
serial            = $dir/serial
RANDFILE          = $dir/private/.rand
private_key       = $dir/private/ca.key
certificate       = $dir/certs/ca.crt
crlnumber         = $dir/crlnumber
crl               = $dir/crl/ca.crl
crl_extensions    = crl_ext
default_crl_days  = 30
default_md        = sha256
name_opt          = ca_default
cert_opt          = ca_default
default_days      = 375
preserve          = no
policy            = policy_strict

[ policy_strict ]
countryName             = match
stateOrProvinceName     = match
organizationName        = match
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ req ]
default_bits        = 4096
distinguished_name  = req_distinguished_name
string_mask         = utf8only
default_md          = sha256
x509_extensions     = v3_ca

[ req_distinguished_name ]
countryName                     = Country Name (2 letter code)
stateOrProvinceName             = State or Province Name
localityName                    = Locality Name
0.organizationName              = Organization Name
organizationalUnitName          = Organizational Unit Name
commonName                      = Common Name
emailAddress                    = Email Address

countryName_default             = FR
stateOrProvinceName_default     = Auvergne Rhone-Alpes
localityName_default            = Lyon
0.organizationName_default      = Worldskills France
organizationalUnitName_default  = Worldskills France Lyon 2025
emailAddress_default            = npresso@wsl2025.org

[ v3_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign

[ v3_intermediate_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true, pathlen:0
keyUsage = critical, digitalSignature, cRLSign, keyCertSign

[ server_cert ]
basicConstraints = CA:FALSE
nsCertType = server
nsComment = "OpenSSL Generated Server Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer:always
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth

[ crl_ext ]
authorityKeyIdentifier=keyid:always
EOF
```

### Générer le certificat Root CA

```bash
cd /etc/ssl/CA

# Générer la clé privée
openssl genrsa -aes256 -out private/ca.key 4096
chmod 400 private/ca.key

# Générer le certificat Root CA (WSFR-ROOT-CA)
openssl req -config openssl.cnf \
    -key private/ca.key \
    -new -x509 -days 7300 -sha256 -extensions v3_ca \
    -out certs/ca.crt \
    -subj "/C=FR/ST=Auvergne Rhone-Alpes/L=Lyon/O=Worldskills France/OU=Worldskills France Lyon 2025/CN=WSFR-ROOT-CA/emailAddress=npresso@wsl2025.org"

# Vérifier
openssl x509 -noout -text -in certs/ca.crt
```

### Signer un certificat SubCA (pour HQDCSRV)

> **IMPORTANT** : Vous devez d'abord récupérer le fichier `C:\SubCA.req` généré sur le serveur **HQDCSRV** et le copier dans `/etc/ssl/CA/requests/SubCA.req` sur ce serveur (DNSSRV).

```bash
# Une fois le fichier SubCA.req copié dans requests/
openssl ca -config openssl.cnf \
    -extensions v3_intermediate_ca \
    -days 3650 -notext -md sha256 \
    -in requests/SubCA.req \
    -out certs/SubCA.crt
```

---

## 6️⃣ Serveur Web pour CRL/AIA (optionnel)

> **Note** : Cette étape est nécessaire pour publier la liste de révocation (CRL) accessible via HTTP.

```bash
apt update && apt install -y apache2

mkdir -p /var/www/html/pki
cp /etc/ssl/CA/certs/ca.crt /var/www/html/pki/WSFR-ROOT-CA.crt

# Générer CRL
openssl ca -config /etc/ssl/CA/openssl.cnf -gencrl -out /var/www/html/pki/ca.crl

systemctl enable apache2

# Automatisation de la CRL (toutes les 5 min pour le lab)
(crontab -l 2>/dev/null; echo "*/5 * * * * openssl ca -config /etc/ssl/CA/openssl.cnf -gencrl -out /var/www/html/pki/ca.crl") | crontab -
```

---

## ✅ Vérifications

| Test        | Commande                                          |
| ----------- | ------------------------------------------------- |
| DNS         | `dig @localhost www.worldskills.org`              |
| DNS wsl2025 | `dig @localhost www.wsl2025.org`                  |
| DNSSEC      | `dig @localhost +dnssec www.worldskills.org`      |
| Root CA     | `openssl x509 -in /etc/ssl/CA/certs/ca.crt -text` |
| CRL         | `curl http://8.8.4.1/pki/ca.crl`                  |

---

## 📝 Notes

- **IP** : 8.8.4.1
- Ce serveur est le DNS public pour worldskills.org et wsl2025.org (vue externe)
- Le certificat Root CA (WSFR-ROOT-CA) signe le SubCA de HQDCSRV
- Le mot de passe de la clé Root CA doit être gardé en sécurité
- DNSSEC est activé sur les deux zones
