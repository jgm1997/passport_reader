#!/usr/bin/env bash
# Throwaway TLS fixtures for test/pinned_client_test.dart. Not committed: CI runs this before `flutter test`.
set -euo pipefail
cd "$(dirname "$0")/.."
out=test/fixtures/tls
mkdir -p "$out"
cd "$out"

make_ca() { # name
  openssl req -x509 -new -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
    -keyout "$1-ca.key" -out "$1-ca.pem" -days 30 -subj "/CN=$1 test CA" \
    -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
    -addext "keyUsage=critical,keyCertSign" 2>/dev/null
}

make_leaf() { # name ca hostname
  openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
    -keyout "$1.key" -out "$1.csr" -subj "/CN=$3" 2>/dev/null
  openssl x509 -req -in "$1.csr" -CA "$2-ca.pem" -CAkey "$2-ca.key" -CAcreateserial \
    -out "$1.pem" -days 30 -extfile <(printf '%s\n' \
      "basicConstraints=critical,CA:FALSE" \
      "extendedKeyUsage=serverAuth" \
      "subjectAltName=DNS:$3") 2>/dev/null
  rm "$1.csr"
}

make_ca good
make_ca evil
make_leaf good-localhost good localhost        # the real server
make_leaf evil-localhost evil localhost        # a man in the middle with his own CA
make_leaf good-otherhost good other.example    # our CA, but a certificate for another host
rm -f ./*.srl
echo "TLS test fixtures written to $out"