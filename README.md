# Pod Passport Scanner

iOS app that reads a passport's NFC chip (ICAO 9303 eMRTD) and hands the chip
bundle to the **Credential Issuer** web app, which performs passive
authentication and mints a verifiable credential into the user's Solid pod.

**Privacy:** chip data is sent **only** to the issuer endpoint encoded in the
QR code the user scans — nowhere else. No analytics, no persistence after the
flow completes.

## Flow

1. **Home** — explainer + privacy note.
2. **Scan QR** — VisionKit DataScanner reads the issuer's QR code (manual
   entry fallback for the same three fields).
3. **MRZ capture** — Vision OCR reads the printed machine-readable zone;
   document number / date of birth / expiry derive the BAC/PACE key (manual
   entry fallback). These values never leave the device.
4. **NFC read** — [NFCPassportReader](https://github.com/AndyQ/NFCPassportReader)
   performs PACE with BAC fallback and reads DG1, SOD and (when present on the
   chip) DG2, DG11, DG14.
5. **Review** — parsed MRZ fields, photo preview, the exact files to be sent
   and the destination endpoint.
6. **Upload** — `PUT` to the issuer endpoint (contract below), then
   "Return to your browser to continue."

## Hand-off contract (fixed — the issuer's `emrtd` adapter implements the other side)

QR code payload (JSON, also enterable manually):

```json
{"v": 1, "endpoint": "<absolute uploadUrl>", "sessionId": "...", "secret": "..."}
```

Upload request:

```
PUT <endpoint>
Authorization: Bearer <secret>
Content-Type: application/json

{"format": "icao-9303-lds1",
 "lds": {"dg1": "<b64>", "dg2": "<b64, optional>", "dg11": "<b64, optional>",
         "dg14": "<b64, optional>", "sod": "<b64>"}}
```

- `204` → success.
- `401` → invalid secret (terminal; rescan QR).
- `410` → session expired (terminal; refresh issuer page).
- Network errors / other statuses → retried with exponential backoff
  (3 attempts; PUT is idempotent).

The bundled sample passport (`Sources/Resources/SamplePassport/emrtd-bundle.json`)
has the same structure as the issuer-side test fixture
`apps/issuer/test/fixtures/emrtd-bundle.json` (synthetic: ICAO Doc 9303
specimen MRZ "ANNA MARIA ERIKSSON", placeholder DG2/DG11/DG14/SOD bytes —
fine for app-side flow testing; it will not pass passive authentication).

## Architecture

NFC and upload sit behind protocols so the **full flow runs in the Simulator**
(which has no NFC):

| Protocol | Real | Mock |
|---|---|---|
| `ChipReader` | `NFCChipReader` (NFCPassportReader) | `MockChipReader` (bundled sample bundle) |
| `BundleUploader` | `HTTPBundleUploader` | `MockBundleUploader` |

- In the Simulator the mock chip reader is always used; in DEBUG builds the
  Home screen has a **"Use sample passport"** toggle.
- Launch arguments: `--mock-chip`, `--mock-upload`, `--uitest` (both mocks +
  manual-entry paths + zero animation delays).
- Swift 6 language mode, strict concurrency `complete`, SwiftUI, iOS 17+.
- The Xcode project is generated from `project.yml` with
  [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`);
  the generated `.xcodeproj` is also checked in.

## Run in the Simulator

```sh
xcodegen generate   # optional; PodPassportScanner.xcodeproj is checked in
open PodPassportScanner.xcodeproj
```

Run the `PodPassportScanner` scheme on any iPhone simulator. Use **Get
started** → enter any issuer session manually (or scan from a second screen —
the simulator has no camera, so manual entry shows automatically) → enter any
valid MRZ values (specimen: document `L898902C3`, DOB `740812`, expiry
`120415`) → **Start reading** loads the sample passport → review → upload
(point the endpoint at a locally running issuer to exercise the real HTTP
path; the `--mock-upload` launch argument fakes it).

Tests:

```sh
xcodebuild -project PodPassportScanner.xcodeproj -scheme PodPassportScanner \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build test
```

## Run on a real iPhone (required for NFC)

NFC only exists on physical devices (iPhone 7+, iOS 17+). Human steps:

1. Open `PodPassportScanner.xcodeproj` in Xcode and select the
   `PodPassportScanner` target → **Signing & Capabilities**.
2. Set **Team** to your personal (or organisation) Apple Developer team —
   the project ships with an empty `DEVELOPMENT_TEAM` placeholder. Leave
   signing on **Automatic**. Xcode will provision the bundle id
   `org.jeswr.PodPassportScanner` (change it if it collides).
   - The **Near Field Communication Tag Reading** capability must be on the
     provisioning profile; Xcode adds it automatically from the checked-in
     entitlements (`com.apple.developer.nfc.readersession.formats: TAG`).
     A free personal team **does** support NFC tag reading.
3. Plug in the iPhone (or pair over Wi-Fi), pick it as the run destination,
   and press Run.
4. First launch on a free/personal team: on the phone go to
   **Settings → General → VPN & Device Management** and trust the developer
   profile.
5. Grant the camera permission when prompted (QR + MRZ scanning); the NFC
   sheet appears system-side during the chip read.

Tip: chip reading works with the passport **closed**; remove thick phone
cases and hold the top half of the phone flat on the front cover.

## CI

GitHub Actions (`.github/workflows/ci.yml`): macOS runner, XcodeGen generate,
then `xcodebuild build test` against an iPhone simulator (unit + UI tests,
mocks only — no NFC/camera needed).

## Licences

- [NFCPassportReader](https://github.com/AndyQ/NFCPassportReader) — MIT
  (verified 2026-06-10), © Andy Qua. Pulled via SwiftPM, pinned to 2.3.1
  (which itself depends on `krzyzanowskim/OpenSSL-Package`, Apache-style
  OpenSSL licence).

## Roadmap

- **Android** companion app next (same hand-off contract).
- **Native Solid login** in-app via `jeswr/solid-swift` once published, so the
  app can talk to the pod directly instead of handing off to the browser.
