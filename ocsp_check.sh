#!/bin/bash
# Gebruik: ./ocsp_crl_check.sh <domein> [poort]
# Voorbeeld: ./ocsp_crl_check.sh xxx.vanrodijnen.nl 443

set -uo pipefail

if [[ -z "${1:-}" ]]; then
  echo "Gebruik: $0 <domein> [poort]"
  exit 1
fi

DOMAIN="$1"
PORT="${2:-443}"

# Opruimen van eventuele bestanden uit een vorige run
rm -f cert*.pem harica.crl crl_text.txt

echo "=== 1. Certificaatketen ophalen van $DOMAIN:$PORT ==="
openssl s_client -connect "$DOMAIN:$PORT" -servername "$DOMAIN" -showcerts < /dev/null 2>/dev/null | \
  awk '/BEGIN CERTIFICATE/{n++} {print > "cert" n ".pem"}'

if [[ ! -f cert1.pem || ! -f cert2.pem ]]; then
  echo "Kon geen twee certificaten ophalen. Controleer of $DOMAIN:$PORT bereikbaar is."
  exit 1
fi

echo ""
echo "--- cert1.pem (servercertificaat) ---"
openssl x509 -in cert1.pem -noout -subject -issuer
echo ""
echo "--- cert2.pem (issuer/intermediate) ---"
openssl x509 -in cert2.pem -noout -subject -issuer
echo ""

SERIAL=$(openssl x509 -in cert1.pem -noout -serial | cut -d= -f2)
echo "Serienummer certificaat: $SERIAL"
echo ""

echo "=== 2. OCSP-URL zoeken ==="
OCSP_URL=$(openssl x509 -in cert1.pem -noout -ocsp_uri || true)

if [[ -n "$OCSP_URL" ]]; then
  echo "OCSP URL gevonden: $OCSP_URL"
  echo ""
  echo "--- OCSP resultaat ---"
  openssl ocsp -issuer cert2.pem -cert cert1.pem -url "$OCSP_URL" -text -noout
  exit 0
fi

echo "Geen OCSP-URL gevonden, val terug op CRL-check."
echo ""

echo "=== 3. CRL Distribution Point zoeken ==="
CRL_URL=$(openssl x509 -in cert1.pem -noout -text | \
  awk '/CRL Distribution Points/{found=1} found && /URI:/{print $0; exit}' | \
  sed 's/.*URI://')

if [[ -z "$CRL_URL" ]]; then
  echo "Geen CRL-URL gevonden in het certificaat. Kan revocatiestatus niet controleren."
  exit 1
fi

echo "CRL URL gevonden: $CRL_URL"
echo ""

echo "=== 4. CRL downloaden en controleren ==="
curl -s -o harica.crl "$CRL_URL"

# Probeer eerst DER, val terug op PEM als dat faalt
if ! openssl crl -inform DER -in harica.crl -text -noout > crl_text.txt 2>/dev/null; then
  openssl crl -inform PEM -in harica.crl -text -noout > crl_text.txt
fi

echo "--- Zoeken naar serienummer $SERIAL in CRL ---"
if grep -q -i "$SERIAL" crl_text.txt; then
  echo "GEVONDEN: certificaat staat op de CRL (dus revoked)."
  grep -i -B 1 -A 2 "$SERIAL" crl_text.txt
else
  echo "Niet gevonden in de CRL: certificaat lijkt niet revoked (volgens deze lijst)."
fi
