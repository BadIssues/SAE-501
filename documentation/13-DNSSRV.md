# DNSSRV - Serveur DNS Public et Root CA

> **OS** : Debian 13 CLI  
> **IP** : 8.8.4.1 (Internet)  
> **Rôles** : DNS Public, Root CA, DNSSEC

---

## 🎯 Contexte (Sujet)

Ce serveur fournit les services DNS publics et PKI pour l'infrastructure :

| Service     | Description                                                                                           |
| ----------- | ----------------------------------------------------------------------------------------------------- |
| **DNS**     | Zones `worldskills.org` et `wsl2025.org` (vue publique). Enregistrements pour www, ftp, vpn, webmail. |
| **DNSSEC**  | Zones signées pour la sécurité.                                                                       |
| **Root CA** | Autorité de certification racine `WSFR-ROOT-CA`. Signe le Sub CA de HQDCSRV.                          |
| **CRL**     | Publie les listes de révocation de certificats.                                                       |

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

### Configuration finale (Utilisateur Admin, Bannière SSH, NTP)

```bash
# 1. Créer l'utilisateur admin avec le mot de passe P@ssw0rd
useradd -m -s /bin/bash admin
echo "admin:P@ssw0rd" | chpasswd
usermod -aG sudo admin

# 2. Configurer la bannière SSH
echo "/!\ Restricted access. Only for authorized people /!\" > /etc/ssh/banner
echo "Banner /etc/ssh/banner" >> /etc/ssh/sshd_config
# Session closed after 5 minutes (300s) of inactivity and 20 minutes (1200s) absolute
echo "ClientAliveInterval 300" >> /etc/ssh/sshd_config
echo "ClientAliveCountMax 0" >> /etc/ssh/sshd_config

systemctl restart ssh

# 3. Configuration NTP (avec authentification si nécessaire, ici simple synchro)
apt install -y ntpsec
# Pointer vers HQINFRASRV (si joignable) ou un serveur public pour le WAN
echo "server 0.debian.pool.ntp.org iburst" >> /etc/ntpsec/ntp.conf
systemctl restart ntpsec
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
# Extensions CDP/AIA pour que les clients puissent vérifier la révocation
crlDistributionPoints = URI:http://pki.hq.wsl2025.org/WSFR-ROOT-CA.crl
authorityInfoAccess = caIssuers;URI:http://pki.hq.wsl2025.org/WSFR-ROOT-CA.crt

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

> **IMPORTANT** :
>
> 1. Vous devez d'abord **créer la Root CA** (étapes ci-dessus) avant de pouvoir signer quoi que ce soit !
> 2. Sur HQDCSRV, exécuter `Install-AdcsCertificationAuthority` qui génère automatiquement un fichier `.req`
> 3. Récupérer ce fichier `.req` et le copier sur DNSSRV pour le signer.

#### Étape 1 : Récupérer le fichier depuis HQDCSRV

```bash
# Depuis DNSSRV, récupérer le fichier via SCP
# Le nom du fichier peut varier (ex: HQDCSRV.hq.wsl2025.org_WSFR-SUB-CA.req)
scp administrateur@10.4.10.1:/C:/*.req /etc/ssl/CA/requests/SubCA.req

# OU depuis HQDCSRV (PowerShell)
# scp C:\*.req root@8.8.4.1:/etc/ssl/CA/requests/SubCA.req
```

#### Étape 2 : Signer le certificat SubCA

```bash
cd /etc/ssl/CA

# Signer la demande (il demandera le mot de passe de la clé Root CA)
openssl ca -config openssl.cnf \
    -extensions v3_intermediate_ca \
    -days 3650 -notext -md sha256 \
    -in requests/SubCA.req \
    -out certs/SubCA.crt

# Confirmer avec 'y' deux fois
```

#### Étape 3 : Renvoyer les certificats vers HQDCSRV

```bash
# Copier les 2 fichiers vers HQDCSRV
scp /etc/ssl/CA/certs/SubCA.crt administrateur@10.4.10.1:/
scp /etc/ssl/CA/certs/ca.crt administrateur@10.4.10.1:/WSFR-ROOT-CA.cer
```

#### ✅ Vérification

```bash
# Vérifier le certificat SubCA généré
openssl x509 -in certs/SubCA.crt -text -noout | head -30

# Vérifier que les fichiers sont dans requests et certs
ls -la requests/
ls -la certs/
```

---

## 6️⃣ Publication de la CRL du Root CA

> **IMPORTANT** : La CRL du Root CA doit être accessible depuis les clients pour que la vérification de révocation fonctionne !

### Option A : Copier la CRL vers HQDCSRV (recommandé)

La CRL du Root CA doit être publiée sur `http://pki.hq.wsl2025.org/WSFR-ROOT-CA.crl` car c'est l'URL dans le certificat Sub CA.

```bash
# 1. Générer la CRL du Root CA
cd /etc/ssl/CA
openssl ca -config openssl.cnf -gencrl -out crl/ca.crl

# 2. Copier la CRL et le certificat vers HQDCSRV
scp crl/ca.crl administrateur@10.4.10.1:/c$/inetpub/PKI/WSFR-ROOT-CA.crl
scp certs/ca.crt administrateur@10.4.10.1:/c$/inetpub/PKI/WSFR-ROOT-CA.crt
```

### Script d'automatisation (sur DNSSRV)

```bash
# Créer un script de mise à jour de la CRL
cat > /etc/ssl/CA/update-crl.sh << 'EOF'
#!/bin/bash
cd /etc/ssl/CA
openssl ca -config openssl.cnf -gencrl -out crl/ca.crl
scp crl/ca.crl administrateur@10.4.10.1:/c$/inetpub/PKI/WSFR-ROOT-CA.crl
EOF

chmod +x /etc/ssl/CA/update-crl.sh

# Automatisation (toutes les heures)
(crontab -l 2>/dev/null; echo "0 * * * * /etc/ssl/CA/update-crl.sh") | crontab -
```

### Option B : Serveur Web local sur DNSSRV

Si DNSSRV doit aussi servir les CRL localement :

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

## ✅ Vérifications complètes (Checklist SAE 501)

### 1. Configuration Système (Sujet 3.1)

| Test        | Commande attendue             | Résultat attendu                                                |
| ----------- | ----------------------------- | --------------------------------------------------------------- |
| Hostname    | `hostname`                    | `dnssrv`                                                        |
| Domaine DNS | `cat /etc/resolv.conf`        | `wsl2025.org` (ou configuré via DHCP/Interface)                 |
| Timezone    | `timedatectl`                 | Time zone correcte (Paris)                                      |
| NTP         | `ntpq -p`                     | Synchronisé avec `hqinfrasrv` (si accessible) ou source externe |
| Fail2Ban    | `fail2ban-client status sshd` | Status `active`                                                 |

### 2. Service DNS (Sujet 3.4 - DNSSRV)

| Test                     | Commande attendue                            | Résultat attendu                     |
| ------------------------ | -------------------------------------------- | ------------------------------------ |
| **Zone worldskills.org** |                                              |                                      |
| Site Web                 | `dig @localhost www.worldskills.org`         | `8.8.4.2` (inetsrv)                  |
| FTP                      | `dig @localhost ftp.worldskills.org`         | `8.8.4.2` (inetsrv)                  |
| WAN Router               | `dig @localhost wanrtr.worldskills.org`      | `8.8.4.6`                            |
| **Zone wsl2025.org**     |                                              |                                      |
| Webmail                  | `dig @localhost webmail.wsl2025.org`         | `191.4.157.33`                       |
| VPN                      | `dig @localhost vpn.wsl2025.org`             | `191.4.157.33`                       |
| Firewall HQ              | `dig @localhost hqfwsrv.wsl2025.org`         | `217.4.160.1`                        |
| Alias WWW                | `dig @localhost www.wsl2025.org`             | CNAME -> `hqfwsrv`                   |
| Alias Auth               | `dig @localhost authentication.wsl2025.org`  | CNAME -> `hqfwsrv`                   |
| **Sécurité**             |                                              |                                      |
| DNSSEC                   | `dig @localhost +dnssec www.worldskills.org` | Présence de l'enregistrement `RRSIG` |

### 3. Service PKI / Root CA (Sujet 3.4)

| Test            | Commande attendue                                                   | Résultat attendu                                                                              |
| --------------- | ------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| Certificat Root | `openssl x509 -in /etc/ssl/CA/certs/ca.crt -text -noout`            | Issuer=Subject=`CN=WSFR-ROOT-CA`, Org=`Worldskills France`, OU=`Worldskills France Lyon 2025` |
| CRL (HTTP)      | `curl -I http://8.8.4.1/pki/ca.crl`                                 | `HTTP/1.1 200 OK`                                                                             |
| Contenu CRL     | `openssl crl -inform DER -in /var/www/html/pki/ca.crl -text -noout` | Affiche la liste (vide ou avec révocations)                                                   |
| Automatisation  | `crontab -l`                                                        | Ligne présente pour `openssl ca -gencrl`                                                      |

### 5. Configuration Finale (Sujet 2.1)

| Test              | Commande attendue                       | Résultat attendu                   |
| ----------------- | --------------------------------------- | ---------------------------------- |
| Utilisateur Admin | `id admin`                              | Existe, groupe sudo/wheel          |
| Bannière SSH      | `ssh admin@localhost`                   | Affiche "/!\ Restricted access..." |
| Timeout SSH       | `grep ClientAlive /etc/ssh/sshd_config` | Interval 300 (5min)                |
| NTP               | `ntpq -p`                               | Synchronisé                        |

---

---

## ✅ Vérification Finale

### 🔌 Comment se connecter à DNSSRV

1. Ouvrir un terminal SSH ou utiliser la console VMware
2. Se connecter : `ssh root@8.8.4.1` (mot de passe : celui configuré)
3. Tu dois voir le prompt : `root@dnssrv:~#`

---

### Test 1 : Vérifier que BIND9 est actif

**Étape 1** : Tape cette commande :
```bash
systemctl is-active bind9
```

**Étape 2** : Regarde le résultat :
```
active
```

✅ **C'est bon si** : `active`
❌ **Problème si** : `inactive` ou `failed` → DNS pas démarré

---

### Test 2 : Tester la résolution DNS - worldskills.org

**Étape 1** : Tape cette commande :
```bash
dig @localhost www.worldskills.org +short
```

**Étape 2** : Regarde le résultat :
```
8.8.4.2
```

✅ **C'est bon si** : Tu vois l'IP `8.8.4.2` (INETSRV)
❌ **Problème si** : Rien ou erreur → Enregistrement DNS manquant

---

### Test 3 : Tester la résolution DNS - wsl2025.org

**Étape 1** : Tape cette commande :
```bash
dig @localhost vpn.wsl2025.org +short
```

**Étape 2** : Regarde le résultat :
```
191.4.157.33
```

✅ **C'est bon si** : Tu vois l'IP `191.4.157.33`
❌ **Problème si** : Autre IP ou rien

---

### Test 4 : Vérifier DNSSEC

**Étape 1** : Tape cette commande :
```bash
dig @localhost www.worldskills.org +dnssec | grep -c RRSIG
```

**Étape 2** : Regarde le résultat :
```
1
```
(ou un nombre > 0)

✅ **C'est bon si** : Le nombre est supérieur à 0 (il y a des signatures)
❌ **Problème si** : `0` → DNSSEC pas activé

---

### Test 5 : Vérifier le Root CA

**Étape 1** : Tape cette commande :
```bash
openssl x509 -in /etc/ssl/CA/certs/ca.crt -noout -subject
```

**Étape 2** : Regarde le résultat :
```
subject=C = FR, O = Worldskills France, OU = Worldskills France Lyon 2025, CN = WSFR-ROOT-CA
```

✅ **C'est bon si** : Tu vois `CN = WSFR-ROOT-CA`
❌ **Problème si** : Fichier non trouvé → Root CA pas générée

---

### Test 6 : Vérifier la CRL via Apache

**Étape 1** : Tape cette commande :
```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost/pki/ca.crl
```

**Étape 2** : Regarde le résultat :
```
200
```

✅ **C'est bon si** : Code `200`
❌ **Problème si** : `404` → Fichier CRL manquant ou Apache pas configuré

---

### 📋 Résumé rapide (copie-colle tout d'un coup)

```bash
echo "=== BIND9 ===" && systemctl is-active bind9
echo "=== DNS worldskills ===" && dig @localhost www.worldskills.org +short
echo "=== DNS vpn ===" && dig @localhost vpn.wsl2025.org +short
echo "=== DNSSEC ===" && dig @localhost www.worldskills.org +dnssec 2>/dev/null | grep -c RRSIG
echo "=== ROOT CA ===" && openssl x509 -in /etc/ssl/CA/certs/ca.crt -noout -subject 2>/dev/null | grep -o "CN = .*"
echo "=== CRL ===" && curl -s -o /dev/null -w "HTTP %{http_code}\n" http://localhost/pki/ca.crl
echo "=== APACHE ===" && systemctl is-active apache2
```
