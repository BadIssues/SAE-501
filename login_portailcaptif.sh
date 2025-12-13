#!/usr/bin/env bash
set -euo pipefail
 
PORTAL_URL="http://192.168.33.2:8002/index.php?zone=portail_rt"
 
read -r -p "Utilisateur: " USER
read -r -s -p "Mot de passe: " PASS
echo
 
# Optionnel: URL de redirection après login
REDIRURL="http://neverssl.com/"
 
# Envoi du POST
RESP_HEADERS="$(mktemp)"
RESP_BODY="$(mktemp)"
 
curl -sS -L \
  -D "$RESP_HEADERS" \
  -o "$RESP_BODY" \
  -X POST "$PORTAL_URL" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "auth_user=$USER" \
  --data-urlencode "auth_pass=$PASS" \
  --data-urlencode "auth_user2=" \
  --data-urlencode "auth_pass2=" \
  --data-urlencode "redirurl=$REDIRURL" \
  --data-urlencode "accept=Login"
 
echo "=== Résumé ==="
echo "Code HTTP: $(awk 'NR==1{print $2}' "$RESP_HEADERS")"
 
# Indicateurs simples (à adapter selon ton portail)
if grep -qiE "error|invalid|incorrect|failed" "$RESP_BODY"; then
  echo "⚠️ Ça ressemble à un échec d'auth (message d'erreur détecté)."
else
  echo "✅ Requête envoyée. Si le portail valide la session par IP/MAC, tu devrais être connecté."
fi
 
rm -f "$RESP_HEADERS" "$RESP_BODY"