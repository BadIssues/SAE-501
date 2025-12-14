# 📋 Index des Vérifications

Ce dossier contient les procédures de vérification pour chaque serveur configuré.

---

## Serveurs vérifiés

| # | Serveur | Rôles | Fichier |
|---|---------|-------|---------|
| 03 | DCWSL | AD DS (Forest Root), DNS, GC | [03-DCWSL-verification.md](03-DCWSL-verification.md) |
| 04 | HQDCSRV | AD DS (Child), DNS, ADCS, File Server, GPO | [04-HQDCSRV-verification.md](04-HQDCSRV-verification.md) |
| 13 | DNSSRV | DNS Public, Root CA, DNSSEC | [13-DNSSRV-verification.md](13-DNSSRV-verification.md) |

---

## Comment utiliser

1. Ouvrir le fichier de vérification correspondant au serveur
2. Exécuter les commandes dans l'ordre
3. Cocher les cases ⬜ → ✅ au fur et à mesure
4. En cas d'échec, consulter la documentation correspondante

---

## Légende

- ⬜ = Non vérifié
- ✅ = OK
- ❌ = Échec (voir documentation)

---

## Liens vers la documentation

| Serveur | Documentation |
|---------|---------------|
| DCWSL | [../documentation/03-DCWSL.md](../documentation/03-DCWSL.md) |
| HQDCSRV | [../documentation/04-HQDCSRV.md](../documentation/04-HQDCSRV.md) |
| DNSSRV | [../documentation/13-DNSSRV.md](../documentation/13-DNSSRV.md) |
