"""Prints the CRL download addresses published in a country's CSCA certificates.

Usage:
    uv run python -m tools.crl_urls ES
"""

import sys

from app.config import load_settings
from app.trust_store import country_of
from cryptography import x509


def main() -> None:
    country = sys.argv[1].upper() if len(sys.argv) > 1 else "ES"
    urls: set[str] = set()
    for cert in load_settings().trust.certificates:
        if country_of(cert.subject) != country:
            continue
        try:
            points = cert.extensions.get_extension_for_class(
                x509.CRLDistributionPoints
            ).value
        except x509.ExtensionNotFound:
            continue
        for point in points:
            for name in point.full_name or []:
                if isinstance(name, x509.UniformResourceIdentifier):
                    urls.add(name.value)
    if not urls:
        print(f"No CRL addresses found in the {country} CSCA certificates.")
    for url in sorted(urls):
        print(url)


if __name__ == "__main__":
    main()
