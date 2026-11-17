# passport_reader

A cross-platform (Android/iOS) Flutter app that reads an ePassport's chip over NFC and verifies it, plus a Python server that checks the passport's digital signatures against the issuing country's certificates.

> ⚠️ **Educational project, not a production identity-verification system.**
> It was built step by step as a learning exercise in Flutter, NFC and PKI.
> It is **not affiliated with, endorsed by, or connected to** the UK Home Office, GOV.UK, or any government or passport authority. See [Known limitations](#known-limitations) before reusing any of it.

## What it does

1. **Scans the MRZ** (the two `<<<` lines on the photo page) with the camera, using on-device OCR, and validates every ICAO 9303 check digit.
2. **Unlocks the chip** over NFC with **PACE** when supported, falling back to **BAC**, using a key derived from the MRZ.
3. **Reads the data groups**: DG1 (holder's details), DG2 (face photo), DG14/DG15 when present, and the **SOD** (the issuing country's signature over all data group hashes).
4. **Decodes the photo**, including **JPEG2000**, with a pure-Dart decoder running in a background isolate.
5. **Verifies authenticity (Passive Authentication)** on the server: SOD signature → Document Signer certificate → trusted CSCA (from a master list whose own signature is verified against a pinned root) → data group hashes, plus optional CRL revocation checks.
6. **Verifies the photo on the phone.** The photo is **never uploaded**: the app hashes DG2 locally and compares it with the hash the issuing country signed, which the server returns only after verifying the whole chain.

```text
Phone (Flutter)                                     Server (Python / FastAPI)
───────────────                                     ─────────────────────────
Camera ─▶ MRZ ─▶ NFC (PACE/BAC) ─▶ DG1, DG2, SOD
SOD + DG1 (+ DG14/15)  ──── POST /v1/passive-auth ──▶ CMS signature, certificate chain,
                                                     validity, revocation, DG hashes
                       ◀── verdict + signed hashes ──
SHA(DG2) == signed DG2 hash?  → photo verified on-device
```

## Repository layout

```text
lib/
  core/            Logic with no UI: MRZ parsing, chip reading, image decoding,
                   verification client. Unit-tested.
  features/        Screens: home, MRZ scan, manual entry, NFC read, result.
test/              Flutter tests (ICAO sample passport and synthetic data only).
backend/
  app/             FastAPI server: Passive Authentication, trust store, CRLs.
  tests/           Pytest suite using fictional countries generated with OpenSSL.
  tools/           LDIF extraction (ICAO PKD) and CRL address lookup.
  scripts/         checkpoint.sh: one-command health check of the backend.
  anchors/         Pinned root certificate(s) trusted to sign master lists.
codemagic.yaml     Cloud iOS builds (no Mac required).
```

## Requirements

| Part   | Needs                                                                                                                     |
| ------ | ------------------------------------------------------------------------------------------------------------------------- |
| App    | Flutter (stable), an **NFC-capable Android phone** (Android 7+ / API 24+). Emulators have no NFC.                         |
| iOS    | iPhone 7 or newer, iOS 15.5+. Building needs a cloud Mac (Codemagic); installing needs a paid Apple Developer membership. |
| Server | [uv](https://docs.astral.sh/uv/), Python 3.14 (installed by uv), OpenSSL (used by the tests).                             |

Developed entirely on Windows with WSL; no Mac was used.

## Running the server

```bash
cd backend
uv python install 3.14
uv sync                       # creates .venv from uv.lock
uv run pytest -v              # all tests use fictional countries
```

### Trust anchors and master lists

The server only trusts CSCA certificates that come from a **master list whose signature it has verified**:

1. Download the root certificate of the master-list publisher (for example Germany's CSCA from the BSI website), **check its SHA-256 fingerprint against the value published on the official page**, and put it in `backend/anchors/`.

   ```bash
   openssl x509 -inform DER -in anchors/<file>.cer -noout -subject -fingerprint -sha256
   ```

2. Download the matching master list (`.ml`) into `backend/trust/`. ICAO PKD LDIF downloads can be unpacked with:

   ```bash
   uv run python -m tools.ldif_extract <file>.ldif --ml-dir trust --crl-dir crls
   ```

3. Optionally add CRLs to `backend/crls/` (`uv run python -m tools.crl_urls ES` lists a country's CRL addresses).

`trust/` and `crls/` are git-ignored: master lists and PKD data come with their own terms of use, so download them yourself.

### Start it

```bash
./scripts/checkpoint.sh       # environment, tests, trust store and /health in one go
TRUST_DIR=trust uv run uvicorn app.main:app --host 127.0.0.1 --port 8000
```

| Variable                        | Default   | Meaning                                                                      |
| ------------------------------- | --------- | ---------------------------------------------------------------------------- |
| `TRUST_DIR`                     | `trust`   | Master lists and CSCA certificates                                           |
| `ML_ANCHORS_DIR`                | `anchors` | Roots trusted to sign master lists                                           |
| `CRL_DIR`                       | `crls`    | Certificate revocation lists                                                 |
| `REQUIRE_CRL`                   | off       | `1` = fail when a CRL is missing or out of date (fail closed)                |
| `ALLOW_UNVERIFIED_MASTER_LISTS` | off       | `1` = accept master lists without checking their signature (not recommended) |

The server logs verification **outcomes only**, never names, numbers or raw data.

## Running the app

```bash
flutter pub get
flutter test

# Phone connected (USB or wireless debugging), server running locally:
adb reverse tcp:8000 tcp:8000
flutter run --dart-define=VERIFY_URL=http://localhost:8000
```

- Plain HTTP is allowed **only in debug builds and only for `localhost`** (`android/app/src/debug/`). Release builds refuse any non-HTTPS verification URL.
- **Wireless debugging from WSL:** `adb pair <ip:port>`, then `adb connect <ip:port>`. Re-run `adb reverse` after reconnecting.
- **Reading the chip:** remove thick or metal cases, open the passport at the photo page (some passports keep the chip in the cover), and hold the phone still until the read finishes.

## iOS builds without a Mac

`codemagic.yaml` contains two workflows:

- **`ios-compile-check`**: an unsigned build that confirms the iOS project compiles. It works on Codemagic's free tier.
- **`ios-testflight`**: a signed build uploaded to TestFlight. It needs a paid Apple Developer membership, an App ID with **NFC Tag Reading** enabled, and an App Store Connect API key. **Never commit the `.p8` key.**

## Security model

- **Authenticity is decided on the server**, never on the phone. The app's "Verified" badge is display only; a real system would act on the server's verdict.
- **Untrusted input is parsed defensively**: strict ASN.1 parsing, size limits on every field, memory-safe decoders, and one clear failure type per layer.
- **Minimum data leaves the phone**: SOD, DG1 and DG14/DG15 only. **DG2 (the face) is verified on-device.** Fingerprint and iris groups (DG3/DG4) are inaccessible to the app and refused by the server.
- **Secure defaults**: unverified master lists are refused, explicit-parameter EC keys are accepted only when they exactly match a vetted curve, and weak settings are announced at server start-up.
- **Passport data on the phone** is kept in memory only, byte buffers are zeroed when the result screen closes (best effort in a garbage-collected language), the photo is kept out of Flutter's global image cache, and camera frames are never written to disk.

## Known limitations

This is a learning project. Before relying on any part of it, note that:

- **No anti-cloning check yet.** Passive Authentication proves the data is genuine, but not that the chip isn't a copy (Active/Chip Authentication is the next step).
- **No TLS / certificate pinning** between app and server yet, so a network attacker could alter the server's answer.
- **CRL checking fails open by default** (`REQUIRE_CRL` off), and CRLs are not refreshed automatically.
- **PACE parsing in `dmrtd`** fails on some chips (`PACEInfo` without the optional `parameterId`); the app falls back to BAC.
- **Only Brainpool r1 curves** (256/384/512) are supported when certificates use explicit EC parameters.
- **6 CSCAs from the German master list are skipped** (Austria, United Arab Emirates and Japan) because their certificates have encoding errors. Each of these countries has other valid CSCAs in the list, so their passports can still be verified.
- **No liveness or face matching**: the app doesn't check that the person holding the phone is the passport holder.
- **Not reviewed** for production, legal or regulatory compliance (e.g. GDPR for biometric data, export-compliance rules for apps using encryption).

## Testing without personal data

All tests use either the **ICAO 9303 specimen passport** (`L898902C3`, "ANNA MARIA ERIKSSON") or **fictional countries** generated on the fly with OpenSSL ("Utopia", "Neverland", "Explicitland"). No real passport data is, or should ever be, committed to this repository. Please don't open issues containing MRZ lines, chip dumps or screenshots of real documents.

## Third-party components and licences

- [`dmrtd`](https://github.com/ZeroPass/dmrtd): ePassport chip access (BAC/PACE, data groups). **LGPL** (or a commercial licence). Distributing an app built with it carries LGPL obligations.
- [`j2k`](https://pub.dev/packages/j2k): pure-Dart JPEG 2000 decoder.
- [Google ML Kit text recognition](https://pub.dev/packages/google_mlkit_text_recognition): on-device OCR.
- `camera`, `http`, `crypto`: Flutter/Dart packages.
- Server: FastAPI, uvicorn, `asn1crypto`, `cryptography`.
- Master lists and PKD data (BSI, ICAO) are **not included** and are subject to their publishers' terms.

## Licence

The code in this repository is released under the MIT License. See [LICENSE](LICENSE).
Third-party components keep their own licences (see above).
