# Vérification DNSSRV - Serveur DNS Public et Root CA

> **Serveur** : DNSSRV  
> **IP** : 8.8.4.1  
> **OS** : Debian 13  
> **Rôles** : DNS Public, Root CA, DNSSEC

---

## ✅ 1. Configuration de base

### Hostname

```bash
hostname
```

**Attendu** : `dnssrv`

### IP

```bash
ip addr show
```

**Attendu** : `8.8.4.1/29`

### SSH + Fail2Ban

```bash
systemctl status ssh
fail2ban-client status sshd
```

**Attendu** : Les deux services sont actifs

### Utilisateur admin

```bash
id admin
```

**Attendu** : Utilisateur existe avec groupe sudo

---

## ✅ 2. Service DNS (BIND9)

### Status BIND9

```bash
systemctl status bind9
```

**Attendu** : `active (running)`

### Zone worldskills.org

```bash
dig @localhost www.worldskills.org
dig @localhost ftp.worldskills.org
dig @localhost wanrtr.worldskills.org
```

**Attendu** :
| Nom | IP |
|-----|-----|
| www.worldskills.org | 8.8.4.2 (CNAME → inetsrv) |
| ftp.worldskills.org | 8.8.4.2 (CNAME → inetsrv) |
| wanrtr.worldskills.org | 8.8.4.6 |

### Zone wsl2025.org (vue publique)

```bash
dig @localhost www.wsl2025.org
dig @localhost vpn.wsl2025.org
dig @localhost hqfwsrv.wsl2025.org
```

**Attendu** :
| Nom | IP |
|-----|-----|
| www.wsl2025.org | CNAME → hqfwsrv (217.4.160.1) |
| vpn.wsl2025.org | 191.4.157.33 |
| hqfwsrv.wsl2025.org | 217.4.160.1 |

### DNSSEC

```bash
dig @localhost +dnssec www.worldskills.org | grep RRSIG
```

**Attendu** : Présence d'enregistrements RRSIG

---

## ✅ 3. Root CA (PKI)

### Certificat Root CA

```bash
openssl x509 -in /etc/ssl/CA/certs/ca.crt -text -noout | head -20
```

**Attendu** :

- Issuer : `CN=WSFR-ROOT-CA`
- Subject : `CN=WSFR-ROOT-CA`
- Organization : `Worldskills France`

### Extensions v3_intermediate_ca

```bash
grep -A10 "v3_intermediate_ca" /etc/ssl/CA/openssl.cnf
```

**Attendu** : Présence de :

```
crlDistributionPoints = URI:http://pki.hq.wsl2025.org/WSFR-ROOT-CA.crl
authorityInfoAccess = caIssuers;URI:http://pki.hq.wsl2025.org/WSFR-ROOT-CA.crt
```

### Certificat SubCA signé

```bash
openssl x509 -in /etc/ssl/CA/certs/SubCA.crt -text -noout | grep -A2 "CRL Distribution"
```

**Attendu** : URL `http://pki.hq.wsl2025.org/WSFR-ROOT-CA.crl`

### CRL générée

```bash
ls -la /etc/ssl/CA/crl/
```

**Attendu** : Fichier `ca.crl` présent

---

## ✅ 4. Serveur Web (optionnel)

```bash
curl -I http://localhost/pki/
```

**Attendu** : HTTP 200 OK (si Apache configuré)

---

## 📋 Checklist finale

| Test                 | Commande                  | Résultat         |
| -------------------- | ------------------------- | ---------------- |
| Hostname             | `hostname`                | ⬜ dnssrv        |
| IP                   | `ip addr`                 | ⬜ 8.8.4.1/29    |
| BIND9                | `systemctl status bind9`  | ⬜ active        |
| Zone worldskills.org | `dig www.worldskills.org` | ⬜ 8.8.4.2       |
| Zone wsl2025.org     | `dig vpn.wsl2025.org`     | ⬜ 191.4.157.33  |
| DNSSEC               | `dig +dnssec`             | ⬜ RRSIG présent |
| Root CA              | Certificat WSFR-ROOT-CA   | ⬜ OK            |
| Extensions CDP/AIA   | Dans openssl.cnf          | ⬜ OK            |
| SubCA signé          | Extensions présentes      | ⬜ OK            |
| CRL                  | Fichier ca.crl            | ⬜ OK            |

