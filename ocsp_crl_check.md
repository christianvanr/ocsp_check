# OCSP/CRL Check Script

Bash-script om de revocatiestatus van een TLS-certificaat te controleren, via **OCSP** (met een fallback naar **CRL**) als OCSP niet beschikbaar is.

## Gebruik

```bash
./ocsp_crl_check.sh <domein> [poort]
```

**Voorbeeld:**

```bash
./ocsp_crl_check.sh pim-acc.vanrodijnen.nl 443
```

- `domein` — verplicht, het domein waarvan je het certificaat wilt controleren.
- `poort` — optioneel, standaard `443`.

## Wat doet het script?

Het script doorloopt de volgende stappen:

### 0. Input-validatie
Controleert of er een domein is meegegeven als argument. Zo niet, dan toont het de gebruiksinstructie en stopt (`exit 1`).

### 1. Opschonen van vorige runs
Verwijdert eventuele overgebleven bestanden (`cert*.pem`, `harica.crl`, `crl_text.txt`) van een vorige uitvoering, zodat er niet met verouderde data wordt gewerkt.

### 2. Certificaatketen ophalen
Maakt met `openssl s_client` verbinding met `domein:poort` en haalt de volledige certificaatketen op (`-showcerts`). De uitvoer wordt met `awk` gesplitst in losse bestanden:
- `cert1.pem` — het servercertificaat
- `cert2.pem` — het issuer/intermediate-certificaat

Als deze twee bestanden niet bestaan, kon de verbinding niet correct worden opgezet en stopt het script met een foutmelding.

Vervolgens worden `subject` en `issuer` van beide certificaten getoond, en wordt het **serienummer** van het servercertificaat uitgelezen (nodig om later in de CRL te zoeken).

### 3. OCSP-URL zoeken en controleren
Het script haalt de OCSP-URL uit het servercertificaat (`openssl x509 -ocsp_uri`).

- **Indien gevonden:** wordt direct een OCSP-request uitgevoerd met `openssl ocsp`, met `cert2.pem` als issuer-certificaat en `cert1.pem` als te controleren certificaat. Het resultaat (status: `good`, `revoked` of `unknown`) wordt getoond en het script stopt hier (`exit 0`).
- **Indien niet gevonden:** valt het script terug op de CRL-methode (stap 4).

### 4. CRL Distribution Point zoeken
Als er geen OCSP-URL is, doorzoekt het script de volledige tekstuele uitvoer van het certificaat op de sectie **"CRL Distribution Points"** en extraheert de eerste `URI:`-waarde daaruit.

Wordt er geen CRL-URL gevonden, dan kan de revocatiestatus niet worden gecontroleerd en stopt het script met een foutmelding.

### 5. CRL downloaden en controleren
- De CRL wordt gedownload met `curl` naar `harica.crl`.
- Het script probeert deze eerst als **DER**-formaat te parsen; lukt dat niet, dan wordt teruggevallen op **PEM**-formaat. De leesbare tekstweergave wordt opgeslagen in `crl_text.txt`.
- Tot slot wordt met `grep` gezocht of het serienummer van het servercertificaat in de CRL voorkomt:
  - **Gevonden** → het certificaat staat op de lijst en is dus **ingetrokken (revoked)**. De relevante regels worden getoond.
  - **Niet gevonden** → het certificaat lijkt (volgens deze CRL) **niet ingetrokken**.

## Vereisten

- `bash`
- `openssl`
- `curl`
- `awk`, `grep`, `sed` (standaard aanwezig op de meeste Linux/macOS-systemen)

## Opmerkingen

- Het script gebruikt `set -uo pipefail` voor iets robuustere foutafhandeling (stopt bij ongedefinieerde variabelen en geeft de juiste exitcode door in pipes). Let op: `-e` (stoppen bij elke fout) is bewust **niet** gezet, omdat sommige commando's (zoals `openssl ocsp` bij een `revoked`-status) een non-zero exitcode kunnen geven terwijl dat geen script-fout is.
- Het script controleert alléén de status van het **servercertificaat** (`cert1.pem`), niet van de tussenliggende (intermediate) of root-certificaten.
- Tijdelijke bestanden (`cert*.pem`, `harica.crl`, `crl_text.txt`) blijven na afloop in de werkmap staan totdat het script opnieuw wordt uitgevoerd (dan worden ze opgeruimd) — handig om na te kunnen kijken, maar ruim ze evt. handmatig op als je dat niet wilt.
