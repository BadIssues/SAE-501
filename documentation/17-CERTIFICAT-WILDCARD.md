# Certificat Wildcard *.wsl2025.org

> **Serveur** : HQDCSRV (10.4.10.1)  
> **CA** : WSFR-SUB-CA (Enterprise Subordinate CA)  
> **Clé** : RSA 2048 bits  
> **Services couverts** : HTTPS, SMTPS, IMAPS

---

## 🎯 Pourquoi un certificat wildcard ?

Un certificat wildcard `*.wsl2025.org` couvre **tous les sous-domaines** en un seul certificat :

| Service | Port | Nom DNS | Couvert |
|---------|------|---------|---------|
| **HTTPS** | 443 | www.wsl2025.org | ✅ |
| **SMTPS** | 465/587 | mail.wsl2025.org | ✅ |
| **IMAPS** | 993 | mail.wsl2025.org | ✅ |
| **Autres** | - | *.wsl2025.org | ✅ |

### Limitation du wildcard

Le wildcard ne couvre qu'un seul niveau de sous-domaine :

| Nom DNS | Couvert ? |
|---------|-----------|
| `mail.wsl2025.org` | ✅ Oui |
| `www.wsl2025.org` | ✅ Oui |
| `wsl2025.org` (racine) | ❌ Non* |
| `smtp.mail.wsl2025.org` | ❌ Non |

> *On ajoute `wsl2025.org` dans les SANs pour couvrir le domaine racine.

---

## 📋 Prérequis

- [ ] HQDCSRV opérationnel avec WSFR-SUB-CA fonctionnelle
- [ ] Template `WSFR_Services` publié sur la CA
- [ ] Connecté avec `WSL2025\Administrateur` ou `HQ\Administrateur`
- [ ] PowerShell en Administrateur

---

## Étape 1 : Se connecter à HQDCSRV

1. Ouvrir une session sur **HQDCSRV** (10.4.10.1)
2. Se connecter avec `WSL2025\Administrateur` ou `HQ\Administrateur`
3. Ouvrir **PowerShell en Administrateur**

---

## Étape 2 : Créer le fichier de configuration (INF)

```powershell
# Fichier de configuration pour certificat multi-services
$inf = @"
[Version]
Signature="`$Windows NT`$"

[NewRequest]
Subject = "CN=*.wsl2025.org, O=WSL2025, L=Paris, C=FR"
KeyLength = 2048
KeyAlgorithm = RSA
Exportable = TRUE
MachineKeySet = TRUE
RequestType = PKCS10
HashAlgorithm = SHA256
FriendlyName = "WSL2025 Wildcard Certificate"

[EnhancedKeyUsageExtension]
OID = 1.3.6.1.5.5.7.3.1  ; Server Authentication (HTTPS)

[Extensions]
; Subject Alternative Names (SAN)
2.5.29.17 = "{text}"
_continue_ = "dns=*.wsl2025.org&"
_continue_ = "dns=wsl2025.org&"
_continue_ = "dns=mail.wsl2025.org&"
_continue_ = "dns=www.wsl2025.org&"
_continue_ = "dns=hqmailsrv.wsl2025.org&"
_continue_ = "dns=hqwebsrv.wsl2025.org"
"@

# Sauvegarder le fichier
$inf | Out-File -FilePath "C:\cert-request.inf" -Encoding ASCII
Write-Host "Fichier créé : C:\cert-request.inf" -ForegroundColor Green
```

---

## Étape 3 : Générer la demande de certificat (CSR)

```powershell
# Générer le CSR à partir du fichier INF
certreq -new "C:\cert-request.inf" "C:\cert-request.csr"
```

✅ Résultat attendu : `CertReq: Request Created`

---

## Étape 4 : Soumettre la demande à la Sub CA

```powershell
# Soumettre la demande à WSFR-SUB-CA avec le template WSFR_Services
certreq -submit -attrib "CertificateTemplate:WSFR_Services" -config "HQDCSRV.hq.wsl2025.org\WSFR-SUB-CA" "C:\cert-request.csr" "C:\cert-wildcard.cer"
```

### Si la demande est en attente (pending)

La demande doit être approuvée manuellement :

```powershell
# Ouvrir la console de la CA
certsrv.msc
```

1. Développer **WSFR-SUB-CA**
2. Cliquer sur **Demandes en attente**
3. Clic droit sur la demande → **Toutes les tâches** → **Délivrer**

Puis récupérer le certificat :

```powershell
# Lister les demandes pour trouver le RequestID
certutil -view -restrict "CommonName=*.wsl2025.org" -out "RequestID,CommonName,Disposition"

# Récupérer le certificat (remplacer XX par le numéro)
certreq -retrieve XX "C:\cert-wildcard.cer"
```

---

## Étape 5 : Installer le certificat

```powershell
# Installer le certificat dans le magasin local
certreq -accept "C:\cert-wildcard.cer"

Write-Host "Certificat installé !" -ForegroundColor Green
```

---

## Étape 6 : Vérifier le certificat

```powershell
# Afficher le certificat installé
Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -like "*wsl2025.org*" } | Format-List Subject, Thumbprint, NotAfter, EnhancedKeyUsageList

# Vérifier les SANs (Subject Alternative Names)
$cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -like "*wsl2025.org*" }
$cert.DnsNameList
```

✅ Résultat attendu : Liste de tous les noms DNS (*.wsl2025.org, mail.wsl2025.org, etc.)

---

## Étape 7 : Exporter le certificat en PFX

Pour déployer le certificat sur d'autres serveurs (mail, web), exporter avec la clé privée :

```powershell
# Trouver le certificat
$cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -like "CN=\*.wsl2025.org*" }

# Définir le mot de passe d'export
$password = ConvertTo-SecureString -String "P@ssw0rd" -Force -AsPlainText

# Exporter en PFX
Export-PfxCertificate -Cert $cert -FilePath "C:\wildcard-wsl2025.pfx" -Password $password

Write-Host "Certificat exporté : C:\wildcard-wsl2025.pfx" -ForegroundColor Green
```

---

## Étape 8 : Déployer sur les serveurs

### Copier le certificat vers HQMAILSRV (Linux)

```powershell
# Depuis HQDCSRV
scp C:\wildcard-wsl2025.pfx root@10.4.10.2:/etc/ssl/certs/
```

### Sur HQMAILSRV : Convertir le PFX

```bash
cd /etc/ssl/certs

# Extraire le certificat
openssl pkcs12 -in wildcard-wsl2025.pfx -clcerts -nokeys -out wildcard.crt

# Extraire la clé privée
openssl pkcs12 -in wildcard-wsl2025.pfx -nocerts -nodes -out wildcard.key

# Sécuriser la clé
chmod 600 wildcard.key
```

### Configuration Postfix (SMTPS)

```bash
# /etc/postfix/main.cf
smtpd_tls_cert_file = /etc/ssl/certs/wildcard.crt
smtpd_tls_key_file = /etc/ssl/certs/wildcard.key
smtpd_tls_security_level = may
```

Redémarrer Postfix :

```bash
systemctl restart postfix
```

### Configuration Dovecot (IMAPS)

```bash
# /etc/dovecot/conf.d/10-ssl.conf
ssl = required
ssl_cert = </etc/ssl/certs/wildcard.crt
ssl_key = </etc/ssl/certs/wildcard.key
```

Redémarrer Dovecot :

```bash
systemctl restart dovecot
```

---

## Étape 9 : Vérification finale

### Tester HTTPS

```powershell
# Depuis un client Windows
Invoke-WebRequest -Uri "https://www.wsl2025.org" -UseBasicParsing
```

### Tester SMTPS (port 465)

```bash
# Depuis Linux
openssl s_client -connect mail.wsl2025.org:465 -showcerts
```

### Tester IMAPS (port 993)

```bash
# Depuis Linux
openssl s_client -connect mail.wsl2025.org:993 -showcerts
```

✅ Le certificat doit s'afficher avec le CN=*.wsl2025.org

---

## 📁 Récapitulatif des fichiers

| Fichier | Description | Emplacement |
|---------|-------------|-------------|
| `cert-request.inf` | Configuration de la demande | `C:\` sur HQDCSRV |
| `cert-request.csr` | Demande de certificat (CSR) | `C:\` sur HQDCSRV |
| `cert-wildcard.cer` | Certificat signé | `C:\` sur HQDCSRV |
| `wildcard-wsl2025.pfx` | Certificat + clé privée | `C:\` sur HQDCSRV |
| `wildcard.crt` | Certificat (format PEM) | `/etc/ssl/certs/` sur Linux |
| `wildcard.key` | Clé privée (format PEM) | `/etc/ssl/certs/` sur Linux |

---

## 🔧 Troubleshooting

### Erreur "Template not found"

```powershell
# Vérifier les templates disponibles
certutil -CATemplates

# S'assurer que WSFR_Services est publié
certsrv.msc
# → WSFR-SUB-CA → Modèles de certificats
```

### Erreur "Access Denied"

- Se connecter avec `WSL2025\Administrateur` (Enterprise Admin)
- Vérifier les permissions sur le template WSFR_Services

### Certificat non reconnu par les clients

1. Vérifier que le Root CA (WSFR-ROOT-CA) est dans les "Autorités racines de confiance"
2. Vérifier que la CRL est accessible : `http://pki.hq.wsl2025.org/WSFR-ROOT-CA.crl`

---

## ✅ Checklist

- [ ] Fichier INF créé avec les bons SANs
- [ ] CSR généré
- [ ] Demande soumise à WSFR-SUB-CA
- [ ] Certificat délivré et installé
- [ ] Export PFX effectué
- [ ] Certificat déployé sur HQMAILSRV
- [ ] Postfix configuré pour SMTPS
- [ ] Dovecot configuré pour IMAPS
- [ ] Tests de connexion TLS réussis

