# 📋 RÉSUMÉ RAPIDE - Vérification SAE 501

> **Document de référence rapide** pour répondre aux questions des professeurs.
> Pas de procédures, juste les informations : "Où est quoi ?"

---

## 🔑 CREDENTIALS PAR DÉFAUT

| Service | Utilisateur | Mot de passe |
|---------|-------------|--------------|
| **Tous les équipements réseau** | `admin` | `P@ssw0rd` |
| **Domaine AD (root)** | `WSL2025\Administrateur` | `P@ssw0rd` |
| **Domaine AD (HQ)** | `HQ\Administrateur` | `P@ssw0rd` |
| **Domaine AD (REM)** | `REM\Administrateur` | `P@ssw0rd` |
| **Linux (root)** | `root` | `P@ssw0rd` |
| **Linux (admin)** | `admin` | `P@ssw0rd` |

> ⚠️ **Note** : Le zéro (0) est entre le "w" et le "r" → `P@ssw0rd`

---

## 🌐 DOMAINES ACTIVE DIRECTORY

```
wsl2025.org              (Forest Root - DCWSL - 10.4.10.4)
├── hq.wsl2025.org       (Child Domain - HQDCSRV - 10.4.10.1)
└── rem.wsl2025.org      (Child Domain - REMDCSRV - 10.4.100.1)
```

| Domaine | Serveur DC | IP | NetBIOS |
|---------|------------|------|---------|
| `wsl2025.org` | DCWSL | 10.4.10.4 | WSL2025 |
| `hq.wsl2025.org` | HQDCSRV | 10.4.10.1 | HQ |
| `rem.wsl2025.org` | REMDCSRV | 10.4.100.1 | REM |

---

## 🏢 INVENTAIRE DES MACHINES

### Site HQ (Siège - 10.4.10.0/24)

| Machine | IP | OS | Rôles principaux |
|---------|------|-----|------------------|
| **HQDCSRV** | 10.4.10.1 | Win Server 2022 | AD Child DC, DNS, ADCS (Sub CA), GPO, RAID-5, Partages |
| **HQINFRASRV** | 10.4.10.2 | Debian 13 | DHCP Primary, VPN OpenVPN, NTP, Samba, iSCSI Target |
| **HQMAILSRV** | 10.4.10.3 | Debian 13 | Mail (Postfix/Dovecot), Webmail, ZFS RAID-Z, DHCP Failover |
| **DCWSL** | 10.4.10.4 | Win Server 2022 | Forest Root DC, DNS wsl2025.org, Global Catalog |
| **HQFWSRV** | 217.4.160.1 / 10.4.10.5 | pfSense | Firewall, NAT/PAT |
| **HQWEBSRV** | 217.4.160.2 | Win Server 2022 | IIS, RDS (RemoteApp Word/Excel) |
| **MGMTCLT** | 10.4.99.1 | Debian 13 GUI | Client Ansible, SSH management |
| **HQCLT** | DHCP | Windows 11 | Client test |

### Site Remote (WSFR - 10.4.100.0/25)

| Machine | IP | OS | Rôles principaux |
|---------|------|-----|------------------|
| **REMFW** | 10.4.100.126 / 10.116.4.1 | Cisco CSR1000v | Routeur/Firewall ACL, OSPF |
| **REMDCSRV** | 10.4.100.1 | Win Server 2022 | AD Child DC, DNS, DHCP, DFS |
| **REMINFRASRV** | 10.4.100.2 | Win Server 2022 | DFS Failover, DHCP Failover |
| **REMCLT** | DHCP | Windows 11 | Client test |

### Zone Internet (8.8.4.0/29)

| Machine | IP | OS | Rôles principaux |
|---------|------|-----|------------------|
| **DNSSRV** | 8.8.4.1 | Debian 13 | DNS Public (BIND9), Root CA, DNSSEC |
| **INETSRV** | 8.8.4.2 | Debian 13 | Web HA (Docker), FTPS |
| **VPNCLT** | 8.8.4.3 | Windows 11 | Client VPN test |
| **INETCLT** | 8.8.4.4 | Debian 13 GUI | Client Internet test |
| **WANRTR** | 8.8.4.6 | Cisco | Gateway VRF INET/MAN |

---

## 🔒 PKI / CERTIFICATS

### Hiérarchie PKI

```
WSFR-ROOT-CA (DNSSRV - 8.8.4.1)
└── WSFR-SUB-CA (HQDCSRV - 10.4.10.1)
```

| CA | Serveur | Type | Chemin CRL |
|----|---------|------|------------|
| **WSFR-ROOT-CA** | DNSSRV | Root CA (OpenSSL) | `http://pki.hq.wsl2025.org/WSFR-ROOT-CA.crl` |
| **WSFR-SUB-CA** | HQDCSRV | Enterprise Sub CA (ADCS) | `http://pki.hq.wsl2025.org/WSFR-SUB-CA.crl` |

### Templates de certificats (sur HQDCSRV)

| Template | Usage | Auto-enrollment |
|----------|-------|-----------------|
| `WSFR_Services` | Web, VPN, Services | Non (on-demand) |
| `WSFR_Machines` | Ordinateurs du domaine | ✅ Oui |
| `WSFR_Users` | Utilisateurs du domaine | ✅ Oui |

### Certificat Wildcard

| Fichier | Emplacement | Usage |
|---------|-------------|-------|
| `wildcard-wsl2025.pfx` | HQINFRASRV `/root/` | VPN OpenVPN, autres services |
| Couvre: `*.wsl2025.org` | Émis par WSFR-SUB-CA | |

### Site PKI (IIS)

- **URL** : `http://pki.hq.wsl2025.org`
- **Dossier** : `C:\inetpub\PKI` (sur HQDCSRV)
- **Contenu** : CRL du Root CA + Sub CA, certificats CA

---

## 📂 PARTAGES RÉSEAU

### Partages sur HQDCSRV (Windows)

| Partage | Chemin UNC | Chemin local | Description |
|---------|------------|--------------|-------------|
| `users$` | `\\hq.wsl2025.org\users$` | `D:\shares\datausers` | Home drives utilisateurs (caché) |
| `Department$` | `\\HQDCSRV\Department$` | `D:\shares\Department` | Dossiers par département (caché) |
| `Public$` | `\\HQDCSRV\Public$` | `D:\shares\Public` | Dossiers publics par département (caché) |

**Sous-dossiers par département** : `IT`, `Direction`, `Factory`, `Sales`

**Restrictions** :
- Quota : 20 Mo par utilisateur (HardLimit)
- Blocage : fichiers `.exe`, `.com`, `.bat`, `.cmd`, `.msi`, `.vbs`, `.ps1`, `.scr`

### Partages sur HQINFRASRV (Samba)

| Partage | Chemin | Description |
|---------|--------|-------------|
| `Public` | `/srv/datastorage/shares/public` | Lecture seule, accès guest |
| `Private` | `/srv/datastorage/shares/private` | Caché, RW Tom/Emma, RO Jean |

**Utilisateurs Samba** : `jean`, `tom`, `emma` (ou AD : `vtim`, `estique`, `jticipe`)

### Lecteurs réseau mappés (GPO)

| Lettre | Chemin | Description |
|--------|--------|-------------|
| **U:** | `\\hq.wsl2025.org\users$\%USERNAME%` | Home drive personnel |
| **S:** | `\\HQDCSRV\Department$` | Dossier département |
| **P:** | `\\HQDCSRV\Public$` | Dossier public |

---

## 📧 SERVICE MAIL

### Configuration (HQMAILSRV - 10.4.10.3)

| Service | Port | Protocole |
|---------|------|-----------|
| SMTP (Postfix) | 465 | SMTPS (TLS obligatoire) |
| IMAP (Dovecot) | 993 | IMAPS (TLS obligatoire) |
| Webmail (Roundcube) | 443 | HTTPS |

### URLs

| Service | URL Interne | URL Externe (NAT) |
|---------|-------------|-------------------|
| Webmail | `https://webmail.wsl2025.org` | `https://191.4.157.33` |

### Utilisateurs mail

| Login | Email | Département |
|-------|-------|-------------|
| `vtim` | vtim@wsl2025.org | IT |
| `npresso` | npresso@wsl2025.org | Direction |
| `jticipe` | jticipe@wsl2025.org | Factory |
| `rola` | rola@wsl2025.org | Sales |
| `estique` | estique@wsl2025.org | - |
| `rtaha` | rtaha@wsl2025.org | - |
| `dpeltier` | dpeltier@wsl2025.org | - |

### Aliases

| Alias | Destinataires |
|-------|---------------|
| `all@wsl2025.org` | Tous les utilisateurs |
| `admin@wsl2025.org` | vtim, dpeltier |

---

## 🔐 VPN OPENVPN

### Configuration (HQINFRASRV - 10.4.10.2)

| Paramètre | Valeur |
|-----------|--------|
| Port | 4443/UDP |
| Mode | TAP Bridge (clients obtiennent IP DHCP) |
| IP Publique | 191.4.157.33:4443 (NAT) |
| Authentification | Certificat + Login AD (LDAP) |
| Certificat serveur | Wildcard `*.wsl2025.org` (WSFR-SUB-CA) |

### Fichier client

| Fichier | Emplacement |
|---------|-------------|
| `wsl2025-client.ovpn` | HQINFRASRV `/root/` |
| Téléchargement | `http://8.8.4.1/wsl2025.ovpn` (DNSSRV) |

### Test VPN

- Client : VPNCLT (8.8.4.3)
- Login : Utilisateur AD (ex: `vtim` / `P@ssw0rd`)

---

## 🕐 SERVICE DHCP

### DHCP HQ (Failover)

| Serveur | Rôle | IP d'écoute |
|---------|------|-------------|
| HQINFRASRV | Primary (Mère) | 10.4.20.1 |
| HQMAILSRV | Secondary (Fille) | 10.4.20.2 |

**Plage VLAN 20** : `10.4.20.10` → `10.4.21.200`
**Lease** : 2 heures
**DNS** : 10.4.10.1 (hqdcsrv)
**NTP** : 10.4.10.2 (hqinfrasrv)

### DHCP Remote

| Serveur | Plage | Lease |
|---------|-------|-------|
| REMDCSRV | 10.4.100.10 → 10.4.100.120 | 2 heures |

---

## 🌐 ENREGISTREMENTS DNS

### Zone wsl2025.org (DCWSL - 10.4.10.4)

| Type | Nom | Valeur |
|------|-----|--------|
| A | `dcwsl` | 10.4.10.4 |
| A | `hqinfrasrv` | 10.4.10.2 |
| A | `hqmailsrv` | 10.4.10.3 |
| A | `hqfwsrv` | 217.4.160.1 |
| A | `vpn` | 191.4.157.33 |
| CNAME | `www` | hqfwsrv.wsl2025.org |
| CNAME | `webmail` | hqmailsrv.wsl2025.org |
| A | `accsw1` | 10.4.99.11 |
| A | `accsw2` | 10.4.99.12 |
| A | `coresw1` | 10.4.99.253 |
| A | `coresw2` | 10.4.99.252 |
| A | `edge1` | 10.4.254.1 |
| A | `edge2` | 10.4.254.5 |

### Zone hq.wsl2025.org (HQDCSRV - 10.4.10.1)

| Type | Nom | Valeur |
|------|-----|--------|
| A | `hqdcsrv` | 10.4.10.1 |
| CNAME | `pki` | hqdcsrv.hq.wsl2025.org |
| CNAME | `hqwebsrv` | hqfwsrv.wsl2025.org |

### Zone rem.wsl2025.org (REMDCSRV - 10.4.100.1)

| Type | Nom | Valeur |
|------|-----|--------|
| A | `remdcsrv` | 10.4.100.1 |
| A | `reminfrasrv` | 10.4.100.2 |

### Zones publiques (DNSSRV - 8.8.4.1)

**Zone worldskills.org** :

| Type | Nom | Valeur |
|------|-----|--------|
| A | `dnssrv` | 8.8.4.1 |
| A | `inetsrv` | 8.8.4.2 |
| CNAME | `www` | inetsrv.worldskills.org |
| CNAME | `ftp` | inetsrv.worldskills.org |

**Zone wsl2025.org (vue publique)** :

| Type | Nom | Valeur |
|------|-----|--------|
| A | `vpn` | 191.4.157.33 |
| A | `webmail` | 191.4.157.33 |
| A | `hqfwsrv` | 217.4.160.1 |
| CNAME | `www` | hqfwsrv.wsl2025.org |
| CNAME | `authentication` | hqfwsrv.wsl2025.org |

---

## 📊 STRUCTURE AD (HQDCSRV)

### OUs

```
DC=hq,DC=wsl2025,DC=org
├── OU=HQ
│   ├── OU=Users
│   │   ├── OU=IT          → vtim
│   │   ├── OU=Direction   → npresso
│   │   ├── OU=Factory     → jticipe
│   │   ├── OU=Sales       → rola
│   │   └── OU=AUTO        → wslusr001 à wslusr1000
│   ├── OU=Computers
│   └── OU=Groups          → IT, Direction, Factory, Sales
├── OU=Groups              → FirstGroup, LastGroup
└── OU=Shadow groups       → OU_Shadow
```

### Groupes importants

| Groupe | Membres | Usage |
|--------|---------|-------|
| `IT` | vtim | Admins, pas de blocage Control Panel |
| `Direction` | npresso | - |
| `Factory` | jticipe | - |
| `Sales` | rola | - |
| `FirstGroup` | wslusr001 à wslusr500 | Provisioning |
| `LastGroup` | wslusr501 à wslusr1000 | Provisioning |
| `OU_Shadow` | Tous users de OU=HQ | Synchro auto |

### Utilisateurs principaux

| Login | Nom complet | Département | Email |
|-------|-------------|-------------|-------|
| `vtim` | Vincent TIM | IT | vtim@wsl2025.org |
| `npresso` | Ness PRESSO | Direction | npresso@wsl2025.org |
| `jticipe` | Jean TICIPE | Factory | jticipe@wsl2025.org |
| `rola` | Rick OLA | Sales | rola@wsl2025.org |

---

## 📜 GPOs

| GPO | Liée à | Description |
|-----|--------|-------------|
| `Deploy-Certificates` | DC=hq,DC=wsl2025,DC=org | Déploie Root CA + Sub CA |
| `Certificate-Autoenrollment` | DC=hq,DC=wsl2025,DC=org | Active auto-enrollment |
| `Edge-Homepage-Intranet` | DC=hq,DC=wsl2025,DC=org | Homepage = webmail |
| `Block-ControlPanel` | OU=Users,OU=HQ | Bloque Panneau de config (sauf IT) |
| `Enterprise-Logo` | DC=hq,DC=wsl2025,DC=org | Logo écran de verrouillage |
| `Drive-Mappings` | OU=Users,OU=HQ | Lecteurs U:, S:, P: |

---

## 💾 STOCKAGE

### HQDCSRV - RAID-5

| Volume | Taille | Type | Contenu |
|--------|--------|------|---------|
| D: | ~2 Go | RAID-5 (3 disques) | Partages (users$, Department$, Public$) |
| Déduplication | Activée | - | - |

### HQINFRASRV - LVM

| LV | Taille | Montage | Usage |
|----|--------|---------|-------|
| `lvdatastorage` | 2 Go | `/srv/datastorage` | Partages Samba |
| `lviscsi` | 2 Go | (iSCSI export) | Backup HQMAILSRV |

### HQMAILSRV - ZFS

| Pool | Type | Montage | Chiffré |
|------|------|---------|---------|
| `zfspool` | RAID-Z (3 disques) | `/zfspool` | ✅ Oui |
| `zfspool/data` | Dataset | `/data` | ✅ Oui |

**iSCSI Target** (depuis HQINFRASRV) :
- IQN : `iqn.2025-01.org.wsl2025:storage.lun1`
- User : `iscsiuser` / `P@ssw0rd`
- Monté sur : `/mnt/backup` (HQMAILSRV)

---

## 🔄 SERVICES RÉSEAU

### NTP

| Serveur | Rôle | Stratum |
|---------|------|---------|
| HQINFRASRV | Serveur NTP principal | 10 (horloge locale) |
| Autres machines | Clients | 11+ |

### NAT (sur EDGE1/EDGE2)

| Service | IP Publique | IP Privée | Port |
|---------|-------------|-----------|------|
| VPN | 191.4.157.33:4443 | 10.4.10.2:4443 | UDP |
| Webmail HTTP | 191.4.157.33:80 | 10.4.10.3:80 | TCP |
| Webmail HTTPS | 191.4.157.33:443 | 10.4.10.3:443 | TCP |

### HSRP (Gateways virtuelles)

| VLAN | VIP | Active | Standby |
|------|-----|--------|---------|
| 10 (Servers) | 10.4.10.254 | CORESW1 | CORESW2 |
| 20 (Clients) | 10.4.20.254 | CORESW1 | CORESW2 |
| 99 (Mgmt) | 10.4.99.254 | CORESW1 | CORESW2 |
| 30 (DMZ) | 217.4.160.254 | EDGE1 | EDGE2 |

---

## 🌍 SITES WEB

### Internes

| URL | Serveur | Service |
|-----|---------|---------|
| `http://pki.hq.wsl2025.org` | HQDCSRV | CRL/Certificats CA |
| `https://webmail.wsl2025.org` | HQMAILSRV | Roundcube |
| `http://www.wsl2025.org` | HQFWSRV → HQWEBSRV | Site intranet |
| `https://authentication.wsl2025.org` | HQFWSRV → HQWEBSRV | Portail auth |

### Publics (Internet)

| URL | Serveur | Service |
|-----|---------|---------|
| `http://www.worldskills.org` | INETSRV (8.8.4.2) | Web Docker HA |
| `ftp://ftp.worldskills.org` | INETSRV | FTPS (user: devops) |

---

## 🖥️ ACCÈS AUX ÉQUIPEMENTS

### SSH (Linux)

| Machine | IP | Commande |
|---------|------|----------|
| HQINFRASRV | 10.4.10.2 | `ssh root@10.4.10.2` |
| HQMAILSRV | 10.4.10.3 | `ssh root@10.4.10.3` |
| DNSSRV | 8.8.4.1 | `ssh root@8.8.4.1` |
| INETSRV | 8.8.4.2 | `ssh root@8.8.4.2` |
| MGMTCLT | 10.4.99.1 | `ssh root@10.4.99.1` |

### RDP (Windows)

| Machine | IP | Compte |
|---------|------|--------|
| DCWSL | 10.4.10.4 | `Administrateur` |
| HQDCSRV | 10.4.10.1 | `HQ\Administrateur` |
| HQWEBSRV | 217.4.160.2 | `HQ\Administrateur` |
| REMDCSRV | 10.4.100.1 | `REM\Administrateur` |

### Console Cisco

| Équipement | IP Mgmt | Type |
|------------|---------|------|
| CORESW1 | 10.4.99.253 | SSH/Console |
| CORESW2 | 10.4.99.252 | SSH/Console |
| ACCSW1 | 10.4.99.11 | SSH/Console |
| ACCSW2 | 10.4.99.12 | SSH/Console |
| EDGE1 | 10.4.254.1 | SSH/Console |
| EDGE2 | 10.4.254.5 | SSH/Console |

---

## 🧪 COMMANDES DE VÉRIFICATION RAPIDE

### Vérifier les services (Linux)

```bash
# HQINFRASRV
systemctl is-active isc-dhcp-server smbd tgt openvpn@server ntpsec

# HQMAILSRV
systemctl is-active postfix dovecot isc-dhcp-server apache2

# DNSSRV
systemctl is-active bind9

# INETSRV
docker ps
```

### Vérifier AD (Windows)

```powershell
# Domaine
Get-ADDomain | Select Name, DNSRoot

# Utilisateurs
(Get-ADUser -Filter *).Count

# GPO
Get-GPO -All | Select DisplayName
```

### Vérifier les services (PowerShell)

```powershell
# HQDCSRV
Get-Service CertSvc, W3SVC, DNS | Select Name, Status

# Partages
Get-SmbShare | Where Name -in @("users$","Department$","Public$")
```

### Vérifier le réseau

```bash
# Ping inter-sites
ping 10.4.100.1    # HQ → Remote

# Résolution DNS
nslookup vpn.wsl2025.org 10.4.10.4
```

---

## 📚 FICHIERS DE CONFIGURATION IMPORTANTS

### Linux

| Fichier | Machine | Service |
|---------|---------|---------|
| `/etc/dhcp/dhcpd.conf` | HQINFRASRV, HQMAILSRV | DHCP |
| `/etc/openvpn/server.conf` | HQINFRASRV | VPN |
| `/etc/samba/smb.conf` | HQINFRASRV | Samba |
| `/etc/postfix/main.cf` | HQMAILSRV | Mail SMTP |
| `/etc/dovecot/` | HQMAILSRV | Mail IMAP |
| `/etc/bind/named.conf.local` | DNSSRV | DNS |
| `/etc/ssl/CA/` | DNSSRV | Root CA |

### Windows

| Emplacement | Machine | Service |
|-------------|---------|---------|
| `C:\inetpub\PKI\` | HQDCSRV | CRL/Certificats |
| `D:\shares\` | HQDCSRV | Partages fichiers |
| `C:\Windows\SYSVOL\domain\scripts\` | HQDCSRV | Scripts GPO |

---

## ⚡ RAPPELS IMPORTANTS

1. **Gateway par défaut** = VIP HSRP (pas les IPs des switches)
2. **DNS primaire** = Serveur DC local (puis Forest Root)
3. **DHCP Relay** = `ip helper-address` sur les VLANs
4. **NAT VPN** = Port 4443 UDP (pas TCP !)
5. **Certificats** = Root CA sur DNSSRV, Sub CA sur HQDCSRV
6. **Failover DHCP** = Primary sur HQINFRASRV, Secondary sur HQMAILSRV
7. **Groupe IT** = Exempté du blocage Control Panel

