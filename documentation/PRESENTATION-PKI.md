    # 🎯 ROADMAP PowerPoint - PKI & Certification WSL2025 (3 min)

    > **Durée totale** : 3 minutes
    > **Sujet** : Infrastructure PKI à 2 niveaux
    > **Projet** : SAE501 - WorldSkills Lyon 2025

    ---

    ## ⏱️ Structure temporelle

    | Slide | Durée  | Contenu                           |
    | ----- | ------ | --------------------------------- |
    | 1     | 15 sec | Titre + accroche                  |
    | 2     | 30 sec | C'est quoi une PKI + Pourquoi     |
    | 3     | 45 sec | Root CA sur DNSSRV (OpenSSL)      |
    | 4     | 45 sec | Sub CA sur HQDCSRV (ADCS Windows) |
    | 5     | 30 sec | Certificat Wildcard + Déploiement |
    | 6     | 15 sec | Schéma récap + Conclusion         |

    ---

    ## 📊 SLIDE 1 - Titre (15 sec)

    ### Ce que tu affiches

    **Titre :** "Infrastructure PKI à 2 niveaux - WSL2025"

    **Sous-titre :** Sécurisation de tous les services : HTTPS, Mail, VPN

    **Visuel :** Un cadenas ou une icône de certificat

    ### Ce que tu dis

    > "Je vais vous présenter notre infrastructure de certification, une PKI à 2 niveaux qui sécurise l'ensemble des communications de l'entreprise WSL2025."

    ---

    ## 📊 SLIDE 2 - C'est quoi une PKI ? (30 sec)

    ### Ce que tu affiches

    **Titre :** "🔐 PKI = Public Key Infrastructure"

    **Définition simple :**

    > Système qui gère les certificats numériques pour authentifier et chiffrer les communications.

    **Schéma simple :**

    ```
    PKI = "Mairie numérique"
    ├── CA = Le tampon officiel (qui signe)
    ├── Certificat = La carte d'identité numérique
    └── CRL = Liste des certificats révoqués
    ```

    **Pourquoi une PKI ?**

    | Sans PKI                  | Avec PKI                      |
    | ------------------------- | ----------------------------- |
    | ❌ HTTPS non vérifié      | ✅ HTTPS de confiance         |
    | ❌ Mots de passe en clair | ✅ Chiffrement TLS            |
    | ❌ Usurpation d'identité  | ✅ Authentification certifiée |

    ### Ce que tu dis

    > "Une PKI c'est comme une mairie numérique : elle délivre des cartes d'identité aux serveurs et aux utilisateurs. Le certificat prouve l'identité, et la CA c'est le tampon officiel qui le valide. Sans PKI, impossible de faire du HTTPS de confiance ou de sécuriser les mails."

    ---

    ## 📊 SLIDE 3 - Root CA (DNSSRV) (45 sec) ⭐

    ### Ce que tu affiches

    **Titre :** "🔒 WSFR-ROOT-CA - L'ancre de confiance"

    **Tableau récapitulatif :**

    | Élément        | Valeur dans notre projet |
    | -------------- | ------------------------ |
    | **Serveur**    | DNSSRV (Debian 13)       |
    | **IP**         | 8.8.4.1 (côté Internet)  |
    | **Outil**      | OpenSSL                  |
    | **Algorithme** | RSA 4096 bits + SHA256   |
    | **Durée**      | 20 ans (7300 jours)      |
    | **CN**         | WSFR-ROOT-CA             |

    **Commandes clés utilisées :**

    ```bash
    # Génération de la clé privée (protégée par mot de passe)
    openssl genrsa -aes256 -out ca.key 4096

    # Création du certificat auto-signé
    openssl req -x509 -new -key ca.key -days 7300 -out ca.crt \
        -subj "/CN=WSFR-ROOT-CA/O=Worldskills France"
    ```

    **Rôle unique :** Signer le certificat de la Sub CA _(rien d'autre !)_

    ### Ce que tu dis

    > "La Root CA, c'est notre ancre de confiance. Elle est hébergée sur DNSSRV, côté Internet. On l'a créée avec OpenSSL, une clé RSA 4096 bits protégée par mot de passe. Son SEUL rôle : signer le certificat de la Sub CA. En entreprise réelle, elle serait hors ligne dans un coffre-fort, mais dans notre projet pédagogique elle reste accessible sur le serveur."

    ---

    ## 📊 SLIDE 4 - Sub CA (HQDCSRV) (45 sec) ⭐

    ### Ce que tu affiches

    **Titre :** "🏢 WSFR-SUB-CA - Le cœur opérationnel"

    **Tableau récapitulatif :**

    | Élément             | Valeur dans notre projet         |
    | ------------------- | -------------------------------- |
    | **Serveur**         | HQDCSRV (Windows Server 2022)    |
    | **IP**              | 10.4.10.1 (VLAN Servers)         |
    | **Type**            | Enterprise Subordinate CA (ADCS) |
    | **Intégration**     | Active Directory                 |
    | **CRL publiée sur** | http://pki.hq.wsl2025.org        |

    **Templates créés :**

    | Template          | Usage                           | Type               |
    | ----------------- | ------------------------------- | ------------------ |
    | **WSFR_Services** | HTTPS, SMTPS, IMAPS, VPN        | On-demand (manuel) |
    | **WSFR_Machines** | Tous les PC/serveurs du domaine | Auto-enrollment    |
    | **WSFR_Users**    | Tous les utilisateurs AD        | Auto-enrollment    |

    **Processus de signature :**

    ```
    1️⃣ HQDCSRV génère un fichier .req (demande)
    2️⃣ On envoie le .req vers DNSSRV (Root CA)
    3️⃣ DNSSRV signe → génère SubCA.crt
    4️⃣ On importe SubCA.crt dans HQDCSRV
    5️⃣ Le service ADCS démarre ✅
    ```

    ### Ce que tu dis

    > "La Sub CA est hébergée sur HQDCSRV, notre contrôleur de domaine Windows. C'est une CA d'entreprise intégrée à Active Directory. Elle a été signée par la Root CA : on a généré une demande .req sur Windows, envoyée vers DNSSRV pour signature avec OpenSSL, puis réimportée. On a créé 3 templates : WSFR_Services pour les certificats manuels des serveurs, et WSFR_Machines/Users pour l'inscription automatique via GPO. Les CRL sont publiées sur un site IIS à l'adresse pki.hq.wsl2025.org."

    ---

    ## 📊 SLIDE 5 - Certificat Wildcard & Déploiement (30 sec)

    ### Ce que tu affiches

    **Titre :** "📜 Certificat Wildcard \*.wsl2025.org"

    **Caractéristiques :**

    | Élément      | Valeur                                                         |
    | ------------ | -------------------------------------------------------------- |
    | **CN**       | \*.wsl2025.org                                                 |
    | **Clé**      | RSA 2048 bits                                                  |
    | **SANs**     | \*.wsl2025.org, wsl2025.org, mail.wsl2025.org, www.wsl2025.org |
    | **Émis par** | WSFR-SUB-CA                                                    |

    **Services sécurisés :**

    | Service                  | Port | Serveur               |
    | ------------------------ | ---- | --------------------- |
    | **HTTPS** (web)          | 443  | HQWEBSRV              |
    | **SMTPS** (mail sortant) | 465  | HQMAILSRV (Postfix)   |
    | **IMAPS** (mail entrant) | 993  | HQMAILSRV (Dovecot)   |
    | **Webmail**              | 443  | HQMAILSRV (Roundcube) |
    | **VPN**                  | 4443 | HQINFRASRV (OpenVPN)  |

    **Export et déploiement :**

    ```
    Windows (HQDCSRV)          Linux (HQMAILSRV)
    ──────────────────         ─────────────────
    1. Demande CSR
    2. Signature Sub CA
    3. Export → .PFX ─────────► 4. Import PFX
    (cert + clé privée)      5. Extraction :
                                - mail.crt (certificat)
                                - mail.key (clé privée)
                                6. Config Postfix/Dovecot
    ```

    ### Ce que tu dis

    > "Avec le template WSFR_Services, on a généré un certificat wildcard qui couvre tous les sous-domaines de wsl2025.org. On l'a exporté en PFX depuis Windows, c'est un conteneur qui contient le certificat ET la clé privée, protégé par mot de passe. Ensuite on l'a copié sur HQMAILSRV sous Linux, et on a extrait le .crt et le .key avec OpenSSL pour configurer Postfix et Dovecot. Maintenant tous nos mails sont chiffrés en SMTPS et IMAPS."

    ---

    ## 📊 SLIDE 6 - Récapitulatif & Conclusion (15 sec)

    ### Ce que tu affiches

    **Titre :** "✅ Chaîne de confiance complète"

    **Schéma final :**

    ```
                        ┌──────────────────────┐
                        │    WSFR-ROOT-CA      │
                        │  (DNSSRV - Linux)    │
                        │  OpenSSL • RSA 4096  │
                        │  Durée: 20 ans       │
                        └──────────┬───────────┘
                                │ signe
                                ▼
                        ┌──────────────────────┐
                        │    WSFR-SUB-CA       │
                        │ (HQDCSRV - Windows)  │
                        │  ADCS • RSA 2048     │
                        │  Durée: 10 ans       │
                        └──────────┬───────────┘
                                │ émet
                ┌──────────────────┼──────────────────┐
                ▼                  ▼                  ▼
        ┌───────────────┐  ┌───────────────┐  ┌───────────────┐
        │ WSFR_Services │  │ WSFR_Machines │  │  WSFR_Users   │
        │   (manuel)    │  │ (auto-enroll) │  │ (auto-enroll) │
        └───────┬───────┘  └───────────────┘  └───────────────┘
                │
                ▼
        *.wsl2025.org → HTTPS • SMTPS • IMAPS • VPN
    ```

    **GPO de déploiement :**

    - `Deploy-Certificates` : Déploie Root CA et Sub CA sur tous les postes Windows
    - `Certificate-Autoenrollment` : Active l'inscription automatique

    ### Ce que tu dis

    > "En résumé : une architecture PKI à 2 niveaux. La Root CA signe la Sub CA, qui elle-même émet tous les certificats de l'infrastructure. Grâce aux GPO, les certificats sont déployés automatiquement sur tous les postes Windows, et l'auto-enrollment permet aux machines et utilisateurs d'obtenir leurs certificats sans intervention manuelle. Résultat : tous nos services sont sécurisés par TLS."

    ---

    ## 💡 Questions anticipées (à préparer)

    | Question                                            | Réponse                                                                                                                                                              |
    | --------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
    | **Pourquoi 2 niveaux ?**                            | "Si la Sub CA est compromise, on la révoque et on en génère une nouvelle. La Root CA reste protégée."                                                                |
    | **C'est quoi un PFX ?**                             | "Un conteneur chiffré (PKCS#12) qui contient le certificat ET la clé privée. On l'exporte depuis Windows pour le déployer sur Linux."                                |
    | **Pourquoi wildcard ?**                             | "Un seul certificat pour tous les sous-domaines : mail, www, webmail... Plus simple à gérer."                                                                        |
    | **Comment les postes Windows ont le Root CA ?**     | "Via GPO Deploy-Certificates : on importe le certificat dans le magasin Autorités racines de confiance."                                                             |
    | **Que se passe-t-il si on révoque un certificat ?** | "On le publie dans la CRL sur pki.hq.wsl2025.org. Les clients vérifient la CRL avant de faire confiance."                                                            |
    | **Pourquoi la Root CA n'est pas hors ligne ?**      | "Dans notre projet pédagogique, elle reste sur DNSSRV pour simplifier. En entreprise réelle, elle serait sur une machine dédiée, éteinte et stockée dans un coffre." |

    ---

    ## 📝 Conseils pour l'oral

    1. **Durée** : Chronomètre-toi ! 3 min = très court, pas de temps pour hésiter
    2. **Ne lis pas** : Les slides sont un support visuel, pas un script
    3. **Vocabulaire clé** : PKI, Root CA, Sub CA, CRL, auto-enrollment, wildcard, PFX, ADCS
    4. **Insiste sur le POURQUOI** : "Pourquoi 2 niveaux ? Pour protéger la Root CA"
    5. **Montre que tu maîtrises** : "Dans notre projet la Root CA est sur DNSSRV, mais en entreprise elle serait hors ligne"
    6. **Gestes** : Pointe les éléments du schéma quand tu parles

    ---

    ## 📚 Glossaire rapide

    | Terme               | Définition                                                     |
    | ------------------- | -------------------------------------------------------------- |
    | **PKI**             | Public Key Infrastructure - Système de gestion des certificats |
    | **CA**              | Certificate Authority - Autorité qui signe les certificats     |
    | **Root CA**         | CA racine, au sommet de la chaîne de confiance                 |
    | **Sub CA**          | CA subordonnée, signée par la Root CA                          |
    | **CRL**             | Certificate Revocation List - Liste des certificats révoqués   |
    | **CSR**             | Certificate Signing Request - Demande de signature (.req)      |
    | **PFX/PKCS#12**     | Format de fichier contenant certificat + clé privée            |
    | **Wildcard**        | Certificat couvrant tous les sous-domaines (\*.domaine.org)    |
    | **Auto-enrollment** | Inscription automatique des certificats via GPO                |
    | **ADCS**            | Active Directory Certificate Services (rôle Windows)           |

    ---

    ## 🔗 Références du projet

    | Serveur   | Rôle PKI                   | Documentation               |
    | --------- | -------------------------- | --------------------------- |
    | DNSSRV    | Root CA (WSFR-ROOT-CA)     | `13-DNSSRV.md`              |
    | HQDCSRV   | Sub CA (WSFR-SUB-CA)       | `04-HQDCSRV.md`             |
    | HQMAILSRV | Certificat wildcard (mail) | `02-HQMAILSRV.md`           |
    | -         | Certificat wildcard        | `17-CERTIFICAT-WILDCARD.md` |
