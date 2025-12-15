# INETSRV - Serveur Web et FTP Internet

> **OS** : Debian 13 CLI  
> **IP** : 8.8.4.2/29 (Internet - réseau 8.8.4.0/29)  
> **Gateway** : 8.8.4.6 (WANRTR)  
> **DNS** : 8.8.4.1 (DNSSRV)  
> **Rôles** : Web Server (Docker HA), FTP Server (FTPS)

---

> **Sujet** :
>
> ```
> INETSRV hosts web services such as websites HTTPS, HTTPS (HTTP is automatically
> redirected to HTTPS) and FTP Services are respectively accessible by using
> www.worldskills.org and ftp.worldskills.org.
> All certificates are provided by DNSSRV
>
> Web server: Configure a redundant Web server with High Availability and load
> balancing running in two docker containers. PHP support is enabled.
> Configure a start page which displays the IP address of the client and the type
> and version of web browser used by the client and the actual date and time.
> Configure a page named bad.html with a dangerous content.
> As a basic security measure, make sure that no sensitive information is displayed
> in the HTTP headers and the footer.
>
> FTP: This server is used for scripts and Ansible Playbooks Storage
> Configure a secured FTPS server. Create user named devops.
> Allow uploading / downloading file from FTP.
> ```

---

## 📋 Prérequis

- [ ] Debian 13 CLI installé
- [ ] DNSSRV opérationnel (8.8.4.1) avec Root CA configuré
- [ ] Enregistrements DNS sur DNSSRV :
  - `A inetsrv.worldskills.org` → 8.8.4.2
  - `CNAME www.worldskills.org` → inetsrv.worldskills.org
  - `CNAME ftp.worldskills.org` → inetsrv.worldskills.org
- [ ] Connectivité réseau vers DNSSRV

---

## 1️⃣ Configuration de base

### 🔴 IMPORTANT : Installation de TOUS les paquets (faire en premier !)

> ⚠️ **Installer tous les paquets MAINTENANT pendant que tu as Internet !**

```bash
apt update && apt install -y \
    openssh-server \
    fail2ban \
    docker.io \
    docker-compose \
    vsftpd \
    curl \
    openssl \
    ca-certificates
```

### Télécharger les images Docker (pendant que tu as Internet)

```bash
# Télécharger les images Docker maintenant
docker pull nginx:alpine
docker pull php:8-fpm-alpine
docker pull haproxy:alpine

# Vérifier
docker images
```

---

### Hostname et réseau

```bash
hostnamectl set-hostname inetsrv

cat > /etc/network/interfaces << 'EOF'
auto eth0
iface eth0 inet static
    address 8.8.4.2
    netmask 255.255.255.248
    gateway 8.8.4.6
    dns-nameservers 8.8.4.1
EOF
```

### SSH et Fail2Ban

```bash
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true

[vsftpd]
enabled = true
EOF

systemctl enable --now fail2ban
```

---

## 2️⃣ Docker (déjà installé)

> ✅ Docker a été installé à l'étape 1. Activer le service :

```bash
systemctl enable --now docker
```

---

## 3️⃣ Serveur Web HA avec HAProxy + Nginx

### Structure des fichiers

```bash
mkdir -p /opt/webserver/{nginx1,nginx2,haproxy,html}
```

### Page d'accueil PHP

```bash
cat > /opt/webserver/html/index.php << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>WorldSkills - Web Server</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 50px; }
        .info { background: #f0f0f0; padding: 20px; border-radius: 10px; }
    </style>
</head>
<body>
    <h1>WorldSkills Web Server</h1>
    <div class="info">
        <h2>Informations Client</h2>
        <p><strong>Adresse IP:</strong> <?php echo $_SERVER['REMOTE_ADDR']; ?></p>
        <p><strong>Navigateur:</strong> <?php echo $_SERVER['HTTP_USER_AGENT']; ?></p>
        <p><strong>Date et heure:</strong> <?php echo date('d/m/Y H:i:s'); ?></p>
        <p><strong>Serveur:</strong> <?php echo gethostname(); ?></p>
    </div>
</body>
</html>
EOF
```

### Page bad.html (contenu dangereux simulé)

```bash
cat > /opt/webserver/html/bad.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Dangerous Content</title>
</head>
<body>
    <h1>⚠️ Warning: Dangerous Content</h1>
    <p>This page contains simulated malicious content for testing purposes.</p>
    <script>
        // Simulated malicious script (harmless)
        console.log("This is a test of dangerous content detection");
    </script>
</body>
</html>
EOF
```

### Configuration Nginx (sans info sensible)

```bash
cat > /opt/webserver/nginx1/nginx.conf << 'EOF'
server {
    listen 80;
    server_name www.worldskills.org;
    root /var/www/html;
    index index.php index.html;

    # Masquer les informations serveur
    server_tokens off;

    location / {
        try_files $uri $uri/ =404;
    }

    location ~ \.php$ {
        fastcgi_pass php:9000;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }

    # Masquer les headers sensibles
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options DENY;
    add_header X-XSS-Protection "1; mode=block";
}
EOF

cp /opt/webserver/nginx1/nginx.conf /opt/webserver/nginx2/nginx.conf
```

### Configuration HAProxy

```bash
cat > /opt/webserver/haproxy/haproxy.cfg << 'EOF'
global
    daemon
    maxconn 256

defaults
    mode http
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms

frontend http_front
    bind *:80
    bind *:443 ssl crt /etc/ssl/certs/worldskills.pem
    redirect scheme https code 301 if !{ ssl_fc }
    default_backend http_back

backend http_back
    balance roundrobin
    option httpchk GET /
    server web1 nginx1:80 check
    server web2 nginx2:80 check

listen stats
    bind *:8080
    stats enable
    stats uri /stats
    stats auth admin:P@ssw0rd
EOF
```

### Docker Compose

```bash
cat > /opt/webserver/docker-compose.yml << 'EOF'
version: '3.8'

services:
  nginx1:
    image: nginx:alpine
    container_name: nginx1
    volumes:
      - ./nginx1/nginx.conf:/etc/nginx/conf.d/default.conf:ro
      - ./html:/var/www/html:ro
    networks:
      - webnet

  nginx2:
    image: nginx:alpine
    container_name: nginx2
    volumes:
      - ./nginx2/nginx.conf:/etc/nginx/conf.d/default.conf:ro
      - ./html:/var/www/html:ro
    networks:
      - webnet

  php:
    image: php:8-fpm-alpine
    container_name: php
    volumes:
      - ./html:/var/www/html:ro
    networks:
      - webnet

  haproxy:
    image: haproxy:alpine
    container_name: haproxy
    ports:
      - "80:80"
      - "443:443"
      - "8080:8080"
    volumes:
      - ./haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro
      - /etc/ssl/certs/worldskills.pem:/etc/ssl/certs/worldskills.pem:ro
    depends_on:
      - nginx1
      - nginx2
    networks:
      - webnet

networks:
  webnet:
    driver: bridge
EOF
```

### Démarrer les conteneurs

```bash
cd /opt/webserver
docker-compose up -d
```

---

## 4️⃣ Certificat SSL Wildcard (signé par DNSSRV)

> **Sujet** : "All certificates are provided by DNSSRV"
>
> 💡 On utilise un **certificat wildcard `*.worldskills.org`** pour couvrir tous les sous-domaines :
>
> - www.worldskills.org
> - ftp.worldskills.org
> - Tout autre sous-domaine futur

### Étape 1 : Générer la clé et la demande de certificat wildcard

```bash
# Créer le dossier si nécessaire
mkdir -p /etc/ssl/private

# Générer la clé privée et la demande CSR wildcard
openssl req -new -nodes \
    -keyout /etc/ssl/private/worldskills.key \
    -out /tmp/worldskills.csr \
    -subj "/C=FR/ST=Auvergne Rhone-Alpes/L=Lyon/O=Worldskills France/CN=*.worldskills.org"
```

### Étape 2 : Envoyer la demande à DNSSRV

```bash
# Copier le CSR vers DNSSRV
scp /tmp/worldskills.csr root@8.8.4.1:/tmp/
```

### Étape 3 : Sur DNSSRV - Signer le certificat wildcard

```bash
# À exécuter sur DNSSRV
openssl x509 -req -in /tmp/worldskills.csr \
    -CA /etc/ssl/CA/certs/ca.crt \
    -CAkey /etc/ssl/CA/private/ca.key \
    -CAcreateserial \
    -out /tmp/worldskills.crt \
    -days 365 \
    -extfile <(printf "subjectAltName=DNS:*.worldskills.org,DNS:worldskills.org")
```

> ⚠️ **Notes** :
>
> - Le SAN inclut `*.worldskills.org` ET `worldskills.org` car le wildcard ne couvre pas le domaine racine.
> - La clé `ca.key` est protégée par mot de passe (celui défini lors de la création du Root CA).

### Étape 4 : Récupérer le certificat signé

```bash
# Sur INETSRV - Récupérer le certificat
scp root@8.8.4.1:/tmp/worldskills.crt /etc/ssl/certs/

# Récupérer aussi le Root CA pour la chaîne
scp root@8.8.4.1:/etc/ssl/CA/certs/ca.crt /etc/ssl/certs/WSFR-ROOT-CA.crt
```

### Étape 5 : Créer le bundle pour HAProxy

```bash
# HAProxy nécessite un fichier PEM avec : clé + certificat + CA
cat /etc/ssl/private/worldskills.key \
    /etc/ssl/certs/worldskills.crt \
    /etc/ssl/certs/WSFR-ROOT-CA.crt > /etc/ssl/certs/worldskills.pem

chmod 644 /etc/ssl/certs/worldskills.pem
```

> ✅ **Ce certificat wildcard sera utilisé pour le Web ET le FTP !**

---

## 5️⃣ Serveur FTP (FTPS)

> ✅ vsftpd a été installé à l'étape 1.

### Configuration FTPS

```bash
cat > /etc/vsftpd.conf << 'EOF'
listen=YES
listen_ipv6=NO
anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=022
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES
chroot_local_user=YES
allow_writeable_chroot=YES
secure_chroot_dir=/var/run/vsftpd/empty
pam_service_name=vsftpd

# FTPS Configuration
ssl_enable=YES
ssl_tlsv1_2=YES
ssl_sslv2=NO
ssl_sslv3=NO
rsa_cert_file=/etc/ssl/certs/ftp.crt
rsa_private_key_file=/etc/ssl/private/ftp.key
force_local_data_ssl=YES
force_local_logins_ssl=YES
require_ssl_reuse=NO

# Passive mode
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40100
pasv_address=8.8.4.2
pasv_addr_resolve=NO
EOF
```

### Créer l'utilisateur devops

```bash
useradd -m -s /bin/bash devops
echo "devops:P@ssw0rd" | chpasswd

# Créer le répertoire pour les playbooks
mkdir -p /home/devops/playbooks
chown devops:devops /home/devops/playbooks
```

### Certificat FTP (utilise le wildcard)

> 💡 **On réutilise le certificat wildcard `*.worldskills.org`** créé à l'étape 4 !
> Pas besoin de créer un certificat séparé pour FTP.

```bash
# Créer des liens symboliques pour vsftpd (qui attend ftp.crt et ftp.key)
ln -sf /etc/ssl/certs/worldskills.crt /etc/ssl/certs/ftp.crt
ln -sf /etc/ssl/private/worldskills.key /etc/ssl/private/ftp.key
```

> ✅ Le certificat wildcard `*.worldskills.org` couvre automatiquement `ftp.worldskills.org`

### Démarrer vsftpd

```bash
systemctl restart vsftpd
systemctl enable vsftpd
```

---

## ✅ Vérifications complètes

### 1. Vérifications sur INETSRV (serveur)

```bash
# Services actifs
systemctl status docker
systemctl status vsftpd
systemctl status fail2ban

# Conteneurs Docker
docker ps
# Attendu : 4 conteneurs UP (nginx1, nginx2, php, haproxy)

# Ports ouverts
ss -tlnp | grep -E ':(21|80|443|8080)'
# Attendu : 21 (vsftpd), 80/443/8080 (docker-proxy)

# Certificat SSL valide
openssl s_client -connect 127.0.0.1:443 -servername www.worldskills.org < /dev/null 2>/dev/null | openssl x509 -noout -subject -issuer
# Attendu : subject=CN=*.worldskills.org, issuer=CN=WSFR-ROOT-CA

# Test FTPS avec openssl
openssl s_client -connect 127.0.0.1:21 -starttls ftp < /dev/null 2>/dev/null | head -20
# Attendu : Affiche le certificat *.worldskills.org
```

### 2. Vérifications Web (depuis un client)

| Test | URL / Commande | Résultat attendu |
|------|----------------|------------------|
| Page d'accueil | `https://www.worldskills.org/` | Affiche IP client, navigateur, date/heure |
| Page dangereuse | `https://www.worldskills.org/bad.html` | Page avec contenu "dangereux" simulé |
| Redirection HTTP→HTTPS | `http://www.worldskills.org/` | Redirige automatiquement vers HTTPS |
| HAProxy Stats | `http://8.8.4.2:8080/stats` | Page de statistiques (login: admin/P@ssw0rd) |
| Load Balancing | Rafraîchir plusieurs fois | Le "Serveur" change entre les conteneurs |

### 3. Vérifications FTPS avec FileZilla (depuis un client Windows)

#### Configuration FileZilla :

| Paramètre | Valeur |
|-----------|--------|
| **Hôte** | `ftp.worldskills.org` ou `8.8.4.2` |
| **Port** | `21` |
| **Protocole** | FTP - File Transfer Protocol |
| **Chiffrement** | `Require explicit FTP over TLS` |
| **Type d'authentification** | Normale |
| **Utilisateur** | `devops` |
| **Mot de passe** | `P@ssw0rd` |

#### Tests à effectuer :

| Test | Action | Résultat attendu |
|------|--------|------------------|
| Connexion FTPS | Se connecter avec FileZilla | ✅ Connexion établie (avertissement certificat si Root CA non installé) |
| Certificat TLS | Vérifier le certificat affiché | ✅ Délivré à `*.worldskills.org` par `WSFR-ROOT-CA` |
| Lister fichiers | Afficher le contenu | ✅ Dossier `playbooks` visible |
| Upload | Glisser un fichier vers le serveur | ✅ Fichier uploadé dans `/home/devops/` |
| Download | Télécharger un fichier | ✅ Fichier récupéré |

> ⚠️ **Note** : Si un avertissement de certificat s'affiche, c'est normal ! Cela signifie que FTPS fonctionne. Accepter le certificat ou installer le Root CA sur le client.

### 4. Checklist finale

- [ ] **Docker** : 4 conteneurs UP (nginx1, nginx2, php, haproxy)
- [ ] **Web HTTPS** : Page d'accueil affiche IP, navigateur, date/heure
- [ ] **Web bad.html** : Page dangereuse accessible
- [ ] **Redirection HTTP→HTTPS** : Fonctionne
- [ ] **HAProxy Stats** : Accessible sur :8080/stats, web1 et web2 en vert
- [ ] **FTPS** : Connexion avec FileZilla, certificat TLS affiché
- [ ] **FTP Upload/Download** : Fonctionne avec l'utilisateur devops
- [ ] **Fail2Ban** : Service actif

---

## 📝 Notes

- **IP** : 8.8.4.2
- Le load balancer HAProxy distribue le trafic entre nginx1 et nginx2
- HTTP est automatiquement redirigé vers HTTPS
- Les headers sensibles (Server, X-Powered-By) sont masqués
- Le FTP utilise FTPS (FTP over TLS) sur les ports 21 et 40000-40100
- Les playbooks Ansible de MGMTCLT sont stockés dans `/home/devops/playbooks`
- **Certificat wildcard** `*.worldskills.org` utilisé pour Web ET FTP

---

## 🔧 Dépannage

### Erreur "Connexion refusée" en FTPS local

Le mode passif est configuré pour les connexions externes (pasv_address=8.8.4.2). Pour tester localement :

```bash
lftp -u devops,P@ssw0rd -e "set ssl:verify-certificate no; set ftp:passive-mode off; ls; quit" ftp://127.0.0.1
```

### HAProxy ne démarre pas (certificat introuvable)

```bash
# Vérifier que le fichier PEM existe et a les bonnes permissions
ls -la /etc/ssl/certs/worldskills.pem
chmod 644 /etc/ssl/certs/worldskills.pem

# Relancer
cd /opt/webserver && docker-compose down && docker-compose up -d
```

### Avertissement certificat sur les clients

Installer le Root CA (`WSFR-ROOT-CA`) sur le client :

- **Windows** : Importer dans le magasin "Autorités de certification racines de confiance"
- **Linux** : `cp WSFR-ROOT-CA.crt /usr/local/share/ca-certificates/ && update-ca-certificates`
- **FileZilla** : Accepter le certificat et cocher "Toujours faire confiance"

---

## ✅ Vérification Finale

> **Instructions** : Exécuter ces commandes sur INETSRV pour valider le bon fonctionnement.

### 1. Docker - Conteneurs actifs
```bash
docker ps --format "table {{.Names}}\t{{.Status}}"
```
✅ 4 conteneurs : nginx1, nginx2, php, haproxy - tous "Up"

### 2. Web HTTPS
```bash
curl -k https://localhost | head -5
```
✅ Doit afficher la page avec IP client, navigateur, date

### 3. Redirection HTTP → HTTPS
```bash
curl -I http://localhost 2>/dev/null | head -1
```
✅ Doit retourner `HTTP/1.1 301` ou `302` (redirection)

### 4. Page bad.html
```bash
curl -k https://localhost/bad.html | head -3
```
✅ Doit afficher le contenu "dangereux"

### 5. HAProxy Stats
```bash
curl -s http://localhost:8080/stats | grep -c "UP"
```
✅ Doit retourner 2 ou plus (web1 et web2 UP)

### 6. FTP Service
```bash
systemctl is-active vsftpd
ss -tlnp | grep 21
```
✅ Service actif, port 21 en écoute

### 7. Test connexion FTPS (depuis un autre poste)
```bash
# Sur INETCLT ou autre :
lftp -u devops,P@ssw0rd -e "set ssl:verify-certificate no; ls; quit" ftp://ftp.worldskills.org
```
✅ Doit lister les fichiers

### Tableau récapitulatif

| Test | Commande | Résultat attendu |
|------|----------|------------------|
| Docker | `docker ps` | 4 conteneurs UP |
| Web HTTPS | `curl -k https://localhost` | Page HTML |
| HTTP→HTTPS | `curl -I http://localhost` | 301/302 |
| HAProxy | `curl http://localhost:8080/stats` | Interface stats |
| vsftpd | `systemctl is-active vsftpd` | `active` |
| Port 21 | `ss -tlnp \| grep 21` | En écoute |
