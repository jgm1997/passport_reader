#!/usr/bin/env bash
# Production PKI. Run on a trusted machine and keep <ca-dir> OFFLINE (e.g. an
# encrypted USB drive). Never inside the repository.
#   scripts/prod_pki.sh <ca-dir> ca primary|backup     create a CA (once each)
#   scripts/prod_pki.sh <ca-dir> server <hostname>     issue the server certificate
set -euo pipefail
[[ $# -eq 3 ]] || { echo "usage: $0 <ca-dir> ca primary|backup | server <hostname>" >&2; exit 2; }
dir=$1; cmd=$2; arg=$3
umask 077                    # everything this script creates is readable by you only
mkdir -p "$dir" && cd "$dir"

case "$cmd" in
  ca)
    [[ "$arg" == primary || "$arg" == backup ]] || { echo "CA must be primary or backup" >&2; exit 2; }
    [[ ! -e "$arg-ca.key" ]] || { echo "$arg CA already exists: refusing to overwrite" >&2; exit 1; }
    echo "Choose a strong passphrase for the $arg CA key (store it in your password manager):"
    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -aes-256-cbc -out "$arg-ca.key"
    openssl req -x509 -new -key "$arg-ca.key" -out "$arg-ca.pem" -days 3650 -sha256 \
      -subj "/CN=Passport Reader $arg CA" \
      -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
      -addext "keyUsage=critical,keyCertSign,cRLSign"
    openssl x509 -in "$arg-ca.pem" -noout -fingerprint -sha256
    ;;
  server)
    openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
      -keyout "$arg.key" -out "$arg.csr" -subj "/CN=$arg"
    openssl x509 -req -in "$arg.csr" -CA primary-ca.pem -CAkey primary-ca.key -CAcreateserial \
      -out "$arg.pem" -days 397 -sha256 -extfile <(printf '%s\n' \
        "basicConstraints=critical,CA:FALSE" \
        "keyUsage=critical,digitalSignature" \
        "extendedKeyUsage=serverAuth" \
        "subjectAltName=DNS:$arg")
    rm "$arg.csr"
    openssl verify -CAfile primary-ca.pem "$arg.pem"
    ;;
  *) echo "unknown command: $cmd" >&2; exit 2 ;;
esac