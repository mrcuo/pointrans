# Pointrans 2.0

Pointrans is a native macOS 26 menu-bar translator for English and Simplified Chinese. Hold a chosen modifier key, pause over text, and receive an indexed offline definition first. Apple Translation can enrich the result on device; context insight uses Apple Foundation Models when available and a privacy-limited Cloudflare fallback otherwise.

Version 2.0 is an architectural rebuild. The application is an Xcode macOS App with Unit Test and UI Test targets, Swift 6 strict concurrency, Universal 2 output, a read-only SQLite dictionary, and an event-driven `CGEventTap`. It keeps the existing bundle identifier `com.tailcasso.Pointrans`, so established settings and macOS permission identity migrate in place.

## Product behavior

- Accessibility performs the global trigger and accurate text hit-testing.
- Screen Recording is requested only for the ScreenCaptureKit + Vision OCR fallback.
- The trigger state machine is `idle → armed → dwelling → extracting → preview → pinned`; requests are immutable and new sessions cancel old work.
- Preview is transient and connected to the pointer by a short safe corridor. Clicking the card or requesting context insight pins it.
- The 175,157-entry SQLite dictionary is queried by primary-key index and is never loaded as one in-memory object.
- Context insight is manual. It uses structured output and displays only “On-device” or “Cloud”. Screenshots and application identity are never sent to the Worker.
- UI language and warm light/dark appearance follow macOS. Configuration lives in the menu-bar control center; there is no traditional Settings window or provider/API configuration.

## Requirements

- macOS 26 or later
- Xcode 26 or later
- Node.js 22 or later for Worker development

## Build and test

Generate the deterministic Xcode project after adding or removing source files:

```bash
python3 scripts/generate_xcode_project.py
```

Run the hostless Core tests. This scheme does not launch Pointrans:

```bash
xcodebuild \
  -project Pointrans.xcodeproj \
  -scheme PointransCoreTests \
  -destination 'platform=macOS' \
  test CODE_SIGN_IDENTITY=-
```

The hostless suite also renders the 360pt control center and Preview plus the 420pt Pinned card through an offscreen `NSHostingView`. It verifies production SwiftUI composition without creating an app process, status item, or visible window.

The `Pointrans` scheme also contains UI tests. Those intentionally launch the app and are reserved for an explicit interactive acceptance session; normal development and packaging never run them.

Run Worker validation:

```bash
cd Worker
npm ci
npm run check
npm test
```

Build and install the ad-hoc-signed Universal 2 application, or package, verify, and install the DMG:

```bash
./build.sh
./package.sh
```

Every successful `build.sh` or `package.sh` run validates the bundle identifier, Universal 2 slices, and code signature before atomically replacing `/Applications/Pointrans.app`. It does not launch the app or restart the Dock. The workflow removes duplicate application bundles outside Trash, temporary test data, mounted installer copies, and release DerivedData. Trashed copies are unregistered but never deleted or moved. UserDefaults, Keychain data, and macOS permission identity are preserved. `package.sh` keeps `dist/Pointrans-2.0.0.dmg` as the installable artifact; `dist/Pointrans.app` is transient and is removed after installation.

For CI or a build that must not modify `/Applications`, run with `AUTO_INSTALL_LATEST=0`. To inspect the transient app and DerivedData locally, use `KEEP_BUILD_ARTIFACTS=1`. An intentional rollback additionally requires `ALLOW_DOWNGRADE=1`. A deliberate manual workflow may opt into launching with `LAUNCH_AFTER_INSTALL=1`; it is off by default.

For a public distribution build, set `DEVELOPER_ID_APPLICATION` to the exact signing identity. Set `NOTARY_PROFILE` to a `notarytool` Keychain profile before running `package.sh`; the script will submit, wait, staple, and validate the DMG. The local 2.0 deliverable intentionally uses ad-hoc signing and is not notarized.

## Cloudflare Worker

The Worker lives in `Worker/` and exposes:

- `GET /health` — reports route availability without exposing configuration.
- `GET /version` — reports the exact product SemVer and full source commit deployed to production; it fails closed when either identity is missing.
- `POST /v1/installations` — signs a random Keychain-backed installation UUID.
- `POST /v1/context` — validates the Bearer token, enforces 100/600-character limits and returns structured `ContextInsight`.

Each installation receives 30 cloud fallbacks per UTC day. Durable Objects update quota atomically; IP issuance and burst limits provide an additional boundary. Upstream timeouts and 5xx responses refund quota. Logs contain only request ID, route, duration, status, and remaining quota.

Production secrets must be added through Wrangler and must never be stored in this repository:

```bash
cd Worker
openssl rand -base64 48 | npx wrangler secret put INSTALLATION_SECRET
npx wrangler secret put DEEPSEEK_API_KEY
npm run deploy
```

`npm run deploy` refuses a dirty worktree, injects the committed 40-character source revision and app marketing version, then verifies `/health` and `/version` against that exact identity. Run the full production contract probe with `node scripts/verify-production-worker.mjs` after deployment.

Set the deployed fixed URL in `Config/Base.xcconfig` before producing Release artifacts. The URL is compiled into the application and is not user editable.

## Dictionary rebuild

`Sources/Pointrans/local_dict.json` remains the deterministic source corpus and is not bundled. Rebuild the runtime database with:

```bash
python3 scripts/build_sqlite_dict.py
```

The generator writes sorted rows, separate English→Chinese and Chinese→English primary-key tables, source SHA-256 metadata, and an optimized read-only database at `Sources/Pointrans/Resources/Dictionary.sqlite3`.

## Privacy and permissions

Pointrans stores preferences in UserDefaults and a random installation UUID/token in Keychain. It does not use a hardware identifier. Offline definitions, Accessibility extraction, OCR, Apple Translation, and supported Foundation Models inference remain on the Mac. Cloud fallback sends only the selected word, its limited sentence context, language direction, and a random request ID.

The app does not show blocking permission alerts at launch. Permission repair and language-pack preparation are handled inside the menu-bar control center.

## Manual acceptance matrix

Before public distribution, verify Safari, Chrome, Terminal, Preview/PDF, images, full-screen spaces, and horizontal/vertical Retina multi-display layouts. Repeat with no network, missing Accessibility, missing Screen Recording, and Apple Intelligence disabled. Confirm Preview latency, Pinned ownership, cancellation of older results, and absence of ongoing idle requests.
