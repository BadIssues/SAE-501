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
    -CA /etc/ssl/certs/WSFR-ROOT-CA.crt \
    -CAkey /etc/ssl/private/WSFR-ROOT-CA.key \
    -CAcreateserial \
    -out /tmp/worldskills.crt \
    -days 365 \
    -extfile <(printf "subjectAltName=DNS:*.worldskills.org,DNS:worldskills.org")
```

> ⚠️ **Note** : Le SAN inclut `*.worldskills.org` ET `worldskills.org` car le wildcard ne couvre pas le domaine racine.

### Étape 4 : Récupérer le certificat signé

```bash
# Sur INETSRV - Récupérer le certificat
scp root@8.8.4.1:/tmp/worldskills.crt /etc/ssl/certs/

# Récupérer aussi le Root CA pour la chaîne
scp root@8.8.4.1:/etc/ssl/certs/WSFR-ROOT-CA.crt /etc/ssl/certs/
```

### Étape 5 : Créer le bundle pour HAProxy

```bash
# HAProxy nécessite un fichier PEM avec : clé + certificat + CA
cat /etc/ssl/private/worldskills.key \
    /etc/ssl/certs/worldskills.crt \
    /etc/ssl/certs/WSFR-ROOT-CA.crt > /etc/ssl/certs/worldskills.pem

chmod 600 /etc/ssl/certs/worldskills.pem
```

> ✅ **Ce certificat wildcard sera utilisé pour le Web ET le FTP !**

---

## 5️⃣ Serveur FTP (FTPS)

> ✅ vsftpd a été installé à l'étape 1.

### Configuration FTPS

```bash
cat > /etc/vsftpd.conf << 'EOF'
listen=YES
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
ssl_tlsv1=YES
ssl_sslv2=NO
ssl_sslv3=NO
rsa_cert_file=/etc/ssl/certs/ftp.crt
rsa_private_key_file=/etc/ssl/private/ftp.key
force_local_data_ssl=YES
force_local_logins_ssl=YES

# Passive mode
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40100
pasv_address=8.8.4.2
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

## ✅ Vérifications

| Test          | Commande                                 |
| ------------- | ---------------------------------------- |
| Web HTTP      | `curl -I http://8.8.4.2`                 |
| Web HTTPS     | `curl -Ik https://www.worldskills.org`   |
| HAProxy Stats | `curl http://8.8.4.2:8080/stats`         |
| Docker        | `docker ps`                              |
| FTP           | `lftp -u devops,P@ssw0rd ftps://8.8.4.2` |

---

## 📝 Notes

- **IP** : 8.8.4.2
- Le load balancer HAProxy distribue le trafic entre nginx1 et nginx2
- HTTP est automatiquement redirigé vers HTTPS
- Les headers sensibles (Server, X-Powered-By) sont masqués
- Le FTP utilise FTPS (FTP over TLS) sur les ports 21 et 40000-40100
- Les playbooks Ansible de MGMTCLT sont stockés dans /home/devops/playbooks
