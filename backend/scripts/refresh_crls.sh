#!/usr/bin/env bash
# Downloads every CRL in crl_sources.txt into crls/. A download only replaces
# the current file if it parses as a CRL and is still current; otherwise the
# old file is kept and the problem is reported.
set -euo pipefail
cd "$(dirname "$0")/.."
out="${CRL_DIR:-crls}"
mkdir -p "$out"
status=0
while read -r name url; do
  [[ -z "${name:-}" || "$name" == \#* ]] && continue
  tmp=$(mktemp "$out/.download.XXXXXX")
  if curl -fsSL --max-time 30 -o "$tmp" "$url" \
     && next=$(openssl crl -inform DER -in "$tmp" -noout -nextupdate) \
     && (( $(date -d "${next#nextUpdate=}" +%s) > $(date +%s) )); then
    mv "$tmp" "$out/$name.crl"
    echo "updated $name ($next)"
  else
    rm -f "$tmp"
    echo "KEPT the previous $name: download failed, unparsable or expired" >&2
    status=1
  fi
done < crl_sources.txt
exit $status