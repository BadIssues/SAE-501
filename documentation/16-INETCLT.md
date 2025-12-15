# INETCLT - Client Internet

> **OS** : Debian 13 GUI  
> **IP** : 8.8.4.4 (Internet)  
> **Rôle** : Client Internet simulant un visiteur externe

---

## 🎯 Contexte (Sujet)

Ce poste simule un utilisateur externe sur Internet :

| Fonction | Description |
|----------|-------------|
| **Accès public** | Doit pouvoir accéder aux services publics : www.wsl2025.org, www.worldskills.org. |
| **DNS** | Utilise DNSSRV (8.8.4.1) comme serveur DNS. |
| **Tests** | Permet de valider l'accessibilité des services depuis l'extérieur. |

---

## 📋 Prérequis

- [ ] Debian 13 avec interface graphique
- [ ] Connecté au réseau Internet (8.8.4.0/29)

---

## 1️⃣ Configuration de base

### Hostname et réseau
```bash
hostnamectl set-hostname inetclt

cat > /etc/network/interfaces << 'EOF'
auto eth0
iface eth0 inet static
    address 8.8.4.4
    netmask 255.255.255.248
    gateway 8.8.4.6
    dns-nameservers 8.8.4.1
EOF
```

---

## 2️⃣ Installation des outils

```bash
apt update
apt install -y firefox-esr curl wget dnsutils netcat-openbsd
```

---

## 3️⃣ Tests d'accès aux services publics

### DNS
```bash
# Résolution des noms publics
dig @8.8.4.1 www.worldskills.org
dig @8.8.4.1 www.wsl2025.org
dig @8.8.4.1 vpn.wsl2025.org
dig @8.8.4.1 webmail.wsl2025.org
```

### Sites web WorldSkills
```bash
# Site WorldSkills
curl -I http://www.worldskills.org
curl -Ik https://www.worldskills.org

# Ouvrir dans Firefox
firefox https://www.worldskills.org &
```

### Sites web WSL2025 (via DMZ)
```bash
# Site principal (via HQFWSRV)
curl -I http://www.wsl2025.org
curl -Ik https://www.wsl2025.org

# Site authentication
curl -Ik https://authentication.wsl2025.org

# Webmail (via NAT sur 191.4.157.33)
curl -Ik https://webmail.wsl2025.org

firefox https://www.wsl2025.org &
```

### FTP WorldSkills
```bash
# Test FTP (FTPS)
apt install -y lftp

lftp -u devops,P@ssw0rd ftps://ftp.worldskills.org << 'EOF'
ls
bye
EOF
```

---

## 4️⃣ Tests de connectivité réseau

### Ping
```bash
# Serveurs Internet
ping -c 4 8.8.4.1   # DNSSRV
ping -c 4 8.8.4.2   # INETSRV
ping -c 4 8.8.4.6   # WANRTR

# DMZ WSL2025 (via routage public)
ping -c 4 217.4.160.1   # HQFWSRV
ping -c 4 191.4.157.33  # VPN/Webmail NAT IP
```

### Traceroute
```bash
traceroute www.wsl2025.org
traceroute www.worldskills.org
```

---

## 5️⃣ Tests de ports

### Vérifier les services accessibles
```bash
# Web WorldSkills
nc -zv 8.8.4.2 80
nc -zv 8.8.4.2 443

# Web WSL2025 (via DMZ)
nc -zv 217.4.160.1 80
nc -zv 217.4.160.1 443

# VPN (port 4443)
nc -zvu 191.4.157.33 4443

# Webmail (via NAT)
nc -zv 191.4.157.33 80
nc -zv 191.4.157.33 443

# FTP
nc -zv 8.8.4.2 21
```

---

## 6️⃣ Ce qui doit fonctionner

| Service | URL/IP | Attendu |
|---------|--------|---------|
| www.worldskills.org | 8.8.4.2 | ✅ Accessible |
| ftp.worldskills.org | 8.8.4.2:21 | ✅ Accessible (FTPS) |
| www.wsl2025.org | 217.4.160.1 | ✅ Accessible |
| webmail.wsl2025.org | 191.4.157.33 | ✅ Accessible |
| vpn.wsl2025.org:4443 | 191.4.157.33:4443 | ✅ Accessible |

---

## 7️⃣ Ce qui ne doit PAS fonctionner

| Service | IP | Attendu |
|---------|-----|---------|
| Serveurs internes HQ | 10.4.10.X | ❌ Non accessible |
| Serveurs Remote | 10.4.100.X | ❌ Non accessible |
| Switches/Routeurs | 10.4.99.X | ❌ Non accessible |
| SSH vers serveurs internes | 10.4.X.X:22 | ❌ Non accessible |

```bash
# Ces commandes doivent échouer (timeout)
ping -c 2 -W 2 10.4.10.1   # Doit timeout
ping -c 2 -W 2 10.4.100.1  # Doit timeout
nc -zv -w 2 10.4.10.1 22   # Doit échouer
```

---

## 8️⃣ Test du webmail

### Accès au webmail (sans compte)
```bash
firefox https://webmail.wsl2025.org &
```

L'accès à la page de login doit fonctionner, mais la connexion nécessite un compte AD valide.

---

## ✅ Vérification Finale

> **Instructions** : Exécuter ces commandes sur INETCLT pour valider l'accès aux services publics.

### 1. Résolution DNS
```bash
dig @8.8.4.1 www.worldskills.org +short
dig @8.8.4.1 www.wsl2025.org +short
dig @8.8.4.1 vpn.wsl2025.org +short
```
✅ Doivent résoudre : 8.8.4.2, 217.4.160.1, 191.4.157.33

### 2. Accès site www.worldskills.org
```bash
curl -k -s https://www.worldskills.org | head -5
```
✅ Doit afficher du contenu HTML

### 3. Accès site www.wsl2025.org
```bash
curl -k -s https://www.wsl2025.org | head -5
```
✅ Doit afficher du contenu HTML

### 4. Accès webmail
```bash
curl -k -s -o /dev/null -w "%{http_code}" https://webmail.wsl2025.org
```
✅ Doit retourner `200`

### 5. Port VPN ouvert
```bash
nc -zvu 191.4.157.33 4443 2>&1 | head -1
```
✅ Doit indiquer le port ouvert/accessible

### 6. Pas d'accès aux réseaux privés
```bash
ping -c 1 -W 2 10.4.10.1 2>/dev/null && echo "ERREUR: Accessible!" || echo "OK: Non accessible"
```
✅ Doit afficher "OK: Non accessible"

### Tableau récapitulatif

| Test | Commande | Résultat attendu |
|------|----------|------------------|
| DNS worldskills | `dig www.worldskills.org +short` | `8.8.4.2` |
| DNS wsl2025 | `dig www.wsl2025.org +short` | `217.4.160.1` |
| Web worldskills | `curl -k https://www.worldskills.org` | HTML |
| Web wsl2025 | `curl -k https://www.wsl2025.org` | HTML |
| Webmail | `curl -k https://webmail.wsl2025.org` | HTTP 200 |
| VPN port | `nc -zvu 191.4.157.33 4443` | Ouvert |
| Privé bloqué | `ping 10.4.10.1` | Timeout |

