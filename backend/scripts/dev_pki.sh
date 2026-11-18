#!/usr/bin/env bash
# Development PKI: a private CA (created once) and a localhost TLS certificate signed by it.
# Usage: scripts/dev_pki.sh        (run from backend/; re-run to renew the server certificate)
set -euo pipefail
# Git Bash / MSYS would otherwise rewrite "-subj /CN=..." into a Windows path.
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'
cd "$(dirname "$0")/.."
mkdir -p pki
chmod 700 pki
cd pki

if [[ ! -f ca.key || ! -f ca.pem ]]; then
  echo "Creating the development CA (once)…"
  openssl req -x509 -new -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
    -keyout ca.key -out ca.pem -days 3650 \
    -subj "/CN=Passport Reader Dev CA" \
    -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
    -addext "keyUsage=critical,keyCertSign,cRLSign"
fi

echo "Issuing the localhost server certificate…"
openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
  -keyout server.key -out server.csr -subj "/CN=localhost"
# A real file rather than <(...): native Windows openssl can't open /dev/fd/N.
printf '%s\n' \
  "basicConstraints=critical,CA:FALSE" \
  "keyUsage=critical,digitalSignature" \
  "extendedKeyUsage=serverAuth" \
  "subjectAltName=DNS:localhost,IP:127.0.0.1" > server.ext
openssl x509 -req -in server.csr -CA ca.pem -CAkey ca.key -CAcreateserial \
  -out server.pem -days 397 -extfile server.ext
rm server.csr server.ext
chmod 600 ca.key server.key

openssl verify -CAfile ca.pem server.pem
echo "SHA-256 fingerprint of the CA to pin:"
openssl x509 -in ca.pem -noout -fingerprint -sha256