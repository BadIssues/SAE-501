# Guide Oral PKI - Ce que tu dois dire et comprendre

> **Durée totale** : 3 minutes  
> **Objectif** : Être confiant à l'oral en comprenant chaque concept

---

## SLIDE 1 - Titre (15 sec)

### Ce que tu dois comprendre

**PKI à 2 niveaux** signifie qu'on a 2 autorités de certification :

1. **Root CA** (niveau 1) = La "mère" qui signe
2. **Sub CA** (niveau 2) = La "fille" qui travaille au quotidien

**Pourquoi 2 niveaux ?**

- Si quelqu'un pirate la Sub CA, on la révoque et on en crée une nouvelle
- La Root CA reste intacte
- Si on avait qu'un seul niveau et qu'il est piraté, TOUT est compromis

### Ce que tu dis

> "Je vais vous présenter notre infrastructure PKI à 2 niveaux. C'est le système qui sécurise TOUTES nos communications : le web en HTTPS, les mails, et le VPN."

---

## SLIDE 2 - Comprendre la PKI (30 sec)

### Ce que tu dois comprendre

**PKI = Public Key Infrastructure** (Infrastructure à Clés Publiques)

Pense à une **mairie** :

| Concept        | Analogie mairie         | Dans notre projet                         |
| -------------- | ----------------------- | ----------------------------------------- |
| **CA**         | Le tampon officiel      | WSFR-ROOT-CA et WSFR-SUB-CA               |
| **Certificat** | La carte d'identité     | Certificat wildcard, certificats machines |
| **CRL**        | Liste des cartes volées | Liste sur pki.hq.wsl2025.org              |

**Sans PKI :**

- Ton navigateur ne peut pas vérifier si c'est le VRAI site
- Un pirate peut intercepter tes données
- Les mots de passe passent en clair

**Avec PKI :**

- Le certificat PROUVE que tu parles au bon serveur
- La connexion est chiffrée avec TLS
- Personne ne peut intercepter

### Ce que tu dis

> "Une PKI c'est comme une mairie numérique. La CA c'est le tampon officiel qui signe les certificats. Le certificat c'est la carte d'identité du serveur. Et la CRL c'est la liste des certificats révoqués. Sans PKI, impossible de vérifier qu'on parle au bon serveur. Avec PKI, on a du HTTPS de confiance et tout est chiffré."

---

## SLIDE 3 - WSFR-ROOT-CA (45 sec)

### Ce que tu dois comprendre

**Root CA = L'ancre de confiance = Le sommet de la pyramide**

Tout le monde fait confiance à la Root CA.

| Élément           | Signification                                         |
| ----------------- | ----------------------------------------------------- |
| **DNSSRV**        | Serveur Linux Debian côté Internet (IP 8.8.4.1)       |
| **OpenSSL**       | Outil en ligne de commande pour créer les certificats |
| **RSA 4096 bits** | Algorithme de chiffrement. 4096 = très sécurisé       |
| **SHA256**        | Algorithme de hachage pour la signature               |
| **20 ans**        | Durée de vie du certificat                            |

**Les commandes expliquées :**

```bash
# Génère une clé privée de 4096 bits
# -aes256 = chiffrée avec mot de passe
openssl genrsa -aes256 -out ca.key 4096

# Génère un certificat auto-signé
# x509 = format standard de certificat
# -days 7300 = valide 20 ans
openssl req -x509 -new -key ca.key -days 7300 -out ca.crt
```

**Pourquoi "hors ligne" en entreprise ?**

- La clé privée de la Root CA est ULTRA sensible
- Si elle est volée, un pirate peut créer des faux certificats
- En entreprise : on signe la Sub CA, puis on éteint la machine et on la met dans un coffre
- Dans notre projet : elle reste sur DNSSRV (contexte pédagogique)

### Ce que tu dis

> "La Root CA c'est l'ancre de confiance, le sommet de notre pyramide. Elle est sur DNSSRV, un serveur Linux. On l'a créée avec OpenSSL : une clé RSA 4096 bits et un certificat valable 20 ans. Son SEUL rôle c'est de signer la Sub CA. En entreprise réelle, cette machine serait éteinte dans un coffre. Mais dans notre projet pédagogique, elle reste accessible."

---

## SLIDE 4 - WSFR-SUB-CA (45 sec)

### Ce que tu dois comprendre

**Sub CA = Le coeur opérationnel = Elle travaille au quotidien**

| Élément           | Signification                                                                   |
| ----------------- | ------------------------------------------------------------------------------- |
| **HQDCSRV**       | Contrôleur de domaine Windows Server 2022 (IP 10.4.10.1)                        |
| **ADCS**          | Active Directory Certificate Services = rôle Windows pour gérer les certificats |
| **Enterprise CA** | Intégrée à Active Directory, permet l'auto-enrollment                           |
| **Subordinate**   | Elle est signée par une autre CA (la Root)                                      |

**Les 3 templates :**

| Template          | Usage                                  | Type                |
| ----------------- | -------------------------------------- | ------------------- |
| **WSFR_Services** | Certificats pour HTTPS, mail, VPN      | Demande manuelle    |
| **WSFR_Machines** | Certificats pour tous les PC Windows   | Automatique via GPO |
| **WSFR_Users**    | Certificats pour tous les utilisateurs | Automatique via GPO |

**Le processus de signature :**

1. Sur HQDCSRV, on installe ADCS qui génère un fichier `.req` (demande)
2. On copie ce `.req` vers DNSSRV (Root CA)
3. Sur DNSSRV, on signe avec OpenSSL ce qui génère `SubCA.crt`
4. On ramène `SubCA.crt` sur HQDCSRV
5. On l'importe et le service ADCS démarre

**La CRL :**

- CRL = Certificate Revocation List = Liste des certificats révoqués
- Publiée sur http://pki.hq.wsl2025.org
- Quand un client vérifie un certificat, il consulte cette URL
- Si le certificat est dans la liste, il est révoqué, donc pas de confiance

### Ce que tu dis

> "La Sub CA c'est le coeur opérationnel. Elle est sur HQDCSRV, notre contrôleur de domaine Windows avec le rôle ADCS. Pour la créer, on a généré une demande sur Windows, envoyée vers DNSSRV pour signature avec OpenSSL, puis réimportée. On a créé 3 templates : WSFR_Services pour les certificats manuels, et WSFR_Machines et Users pour l'inscription automatique via GPO. Les listes de révocation sont publiées sur pki.hq.wsl2025.org."

---

## SLIDE 5 - Certificat Wildcard (30 sec)

### Ce que tu dois comprendre

**Wildcard = Un certificat pour TOUS les sous-domaines**

- `*.wsl2025.org` couvre : mail.wsl2025.org, www.wsl2025.org, webmail.wsl2025.org, etc.
- Plus simple que de créer un certificat par service

**Les SANs (Subject Alternative Names) :**

- Le wildcard `*.wsl2025.org` ne couvre PAS `wsl2025.org` sans sous-domaine
- Donc on ajoute des SANs pour couvrir tous les noms

**Le format PFX (ou PKCS#12) :**

C'est un conteneur qui contient :

- Le certificat (partie publique)
- La clé privée (partie secrète)
- Protégé par mot de passe

**Pourquoi PFX ?**

- Windows génère le certificat
- Linux (HQMAILSRV) a besoin du certificat ET de la clé privée
- Le PFX permet de transporter les deux ensemble

**Extraction sur Linux :**

```bash
# Extraire le certificat
openssl pkcs12 -in wildcard.pfx -clcerts -nokeys -out mail.crt

# Extraire la clé privée
openssl pkcs12 -in wildcard.pfx -nocerts -nodes -out mail.key
```

### Ce que tu dis

> "On a créé un certificat wildcard qui couvre tous les sous-domaines de wsl2025.org. Il sécurise le web, le mail SMTPS et IMAPS, le webmail, et le VPN. On l'a exporté en PFX depuis Windows. C'est un conteneur avec le certificat ET la clé privée. On l'a copié sur HQMAILSRV sous Linux, puis extrait le .crt et le .key avec OpenSSL pour configurer Postfix et Dovecot."

---

## SLIDE 6 - Chaîne de confiance (15 sec)

### Ce que tu dois comprendre

**La chaîne de confiance :**

```
Root CA (WSFR-ROOT-CA)
    |
    └── signe --> Sub CA (WSFR-SUB-CA)
                      |
                      └── émet --> Certificat wildcard (*.wsl2025.org)
                                        |
                                        └── protège --> HTTPS, SMTPS, IMAPS, VPN
```

**Quand un client se connecte :**

1. Le serveur présente son certificat
2. Le client vérifie : "Qui a signé ?" --> WSFR-SUB-CA
3. Le client vérifie : "Qui a signé WSFR-SUB-CA ?" --> WSFR-ROOT-CA
4. Le client vérifie : "Est-ce que je fais confiance à WSFR-ROOT-CA ?" --> OUI (déployé via GPO)
5. Connexion établie

**Les GPO :**

| GPO                            | Ce qu'elle fait                                        |
| ------------------------------ | ------------------------------------------------------ |
| **Deploy-Certificates**        | Installe Root CA et Sub CA sur tous les postes Windows |
| **Certificate-Autoenrollment** | Active la demande automatique de certificats           |

### Ce que tu dis

> "En résumé : une architecture PKI à 2 niveaux. La Root CA signe la Sub CA, qui émet tous les certificats. Grâce aux GPO, les certificats sont déployés automatiquement sur tous les postes Windows. L'auto-enrollment permet aux machines d'obtenir leurs certificats sans intervention. Résultat : tous nos services sont sécurisés par TLS."

---

## SLIDE 7 - Résumé (15-20 sec)

### Ce que tu dois comprendre

Les 4 points clés à retenir :

1. **PKI à 2 niveaux** = Sécurité (Root CA protégée)
2. **Déploiement automatisé** = Efficacité (GPO + auto-enrollment)
3. **Wildcard** = Simplicité (1 certificat pour tout)
4. **Chaîne de confiance** = Fiabilité (vérification possible)

### Ce que tu dis

> "Notre PKI à 2 niveaux assure une sécurité robuste. Le déploiement est automatisé grâce à Active Directory. Le certificat wildcard protège tous nos services. Et la chaîne de confiance garantit que toutes les identités sont vérifiables."

---

## Questions possibles et réponses

| Question                                       | Réponse                                                                                                |
| ---------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| **C'est quoi une PKI ?**                       | "Un système pour gérer les certificats numériques, comme une mairie qui délivre des cartes d'identité" |
| **Pourquoi 2 niveaux ?**                       | "Pour protéger la Root CA. Si la Sub CA est compromise, on la révoque. La Root reste intacte"          |
| **C'est quoi un PFX ?**                        | "Un conteneur avec le certificat ET la clé privée, protégé par mot de passe"                           |
| **C'est quoi la CRL ?**                        | "La liste des certificats révoqués, les clients la consultent avant de faire confiance"                |
| **Pourquoi wildcard ?**                        | "Un seul certificat pour tous les sous-domaines, plus simple à gérer"                                  |
| **C'est quoi l'auto-enrollment ?**             | "Les machines obtiennent leur certificat automatiquement via GPO"                                      |
| **Pourquoi la Root CA n'est pas hors ligne ?** | "C'est un projet pédagogique. En entreprise elle serait éteinte dans un coffre"                        |

---

## Timing

| Slide        | Durée  | Total |
| ------------ | ------ | ----- |
| 1 - Titre    | 15 sec | 0:15  |
| 2 - PKI      | 30 sec | 0:45  |
| 3 - Root CA  | 45 sec | 1:30  |
| 4 - Sub CA   | 45 sec | 2:15  |
| 5 - Wildcard | 30 sec | 2:45  |
| 6 - Chaîne   | 15 sec | 3:00  |
| 7 - Résumé   | 15 sec | 3:15  |
