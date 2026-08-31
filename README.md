# Pointrans 2.0

Pointrans is a native macOS 26 menu-bar translator for English and Simplified Chinese. Hold the left Option key and pause over text; Pointrans detects the source language automatically. A concise base translation is resolved by on-device Foundation Models with a strict one-second priority window, then Apple Translation, then the bundled dictionary. Context insight is created only after an explicit click, using Foundation Models first and a privacy-limited Cloudflare fallback only when the user has consented.

Version 2.0 is an architectural rebuild. The application is an Xcode macOS App with Unit Test and UI Test targets, Swift 6 strict concurrency, Universal 2 output, a read-only SQLite dictionary, and an event-driven `CGEventTap`. It keeps the existing bundle identifier `com.tailcasso.Pointrans`, so established settings and macOS permission identity migrate in place.

## Product behavior

- Accessibility and Screen Recording are both mandatory before the application can become ready. Accessibility provides global input and text hit-testing; ScreenCaptureKit + Vision supplies the OCR fallback.
- The trigger is permanently the left Option key. There is no trigger-key or translation-direction setting, and Latin and Han tokens select English-to-Chinese or Chinese-to-English automatically.
- The interaction state machine is `idle → leftOptionDown → dwelling → extracting → detectingLanguage → resolvingTranslation → preview → pinned → closed`; revoked permissions stop listening immediately and transient event-tap failures use bounded recovery.
- Preview is transient and connected to the pointer by a short safe corridor. Clicking the card or requesting context insight pins it.
- The 175,157-entry SQLite dictionary is queried by primary-key index and is never loaded as one in-memory object.
- Context insight is manual. It uses structured output and displays only “On this Mac” or “Online”. Device-model unavailability, network failure, quota exhaustion, and an incompatible online-service contract remain distinct recovery states. Screenshots, application identity and hardware identity are never sent to the Worker.
- First launch is a mandatory five-stage flow: welcome, Accessibility, Screen Recording, automatic Apple language preparation, and one self-explanatory real interaction. The last stage uses the production floating Preview/Pinned card beside the pointer—there is no embedded imitation result page or manual finish button. Online explanation consent is requested in that card only if the Mac cannot produce the clicked result. A valid result automatically closes setup while keeping the real pinned card open.
- UI language and warm light/dark appearance follow macOS. The control center contains only status, pause/resume, hover delay, required permissions, built-in language readiness, cloud-context consent, version and quit. There is no model, provider, API key, AI, direction, language-pack or trigger configuration.
- The application owns its AppKit delegate for the entire process lifetime, so every successful launch creates exactly one retained status item before any model, dictionary, or window work. During setup the status item includes the visible `Pointrans` title; afterwards it becomes the compact symbol. Temporary menu-bar visibility changes never terminate the process, and reopening an already-running app reveals the independent control center even when the status item is hidden by macOS. Setup also exposes a standard red close control, a visible Quit button, and Command-Q; every exit path removes the status item and stops the listener.

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

Build the Universal 2 application, or build and verify the DMG:

```bash
./build.sh
./package.sh
```

`build.sh` writes and verifies `build/Artifacts.noindex/Pointrans.app`. `package.sh` writes and verifies the versioned `dist/Pointrans-<version>.dmg`; `dist` never retains a loose `.app`. Xcode DerivedData and the reviewable App artifact both live below `.noindex` directories, and packaging unregisters temporary build copies so Spotlight and Launchpad do not present them as installed applications. Neither command launches, terminates, installs, uninstalls, or changes `/Applications`; installation testing is deliberately user-operated. Build identity is embedded as `PointransSourceRevision`.

The approved v1.1 artwork lives in `Pointrans_Logo_Design_Files/`. The app icon is a native `AppIcon.icon` document: Icon Composer owns the macOS 26 enclosure and applies it once around a pure-black background plus the approved transparent white symbol. The legacy precomposed `AppIcon.appiconset` is deliberately absent, preventing macOS from wrapping an already-masked icon in a second compatibility container. Release builds run `scripts/generate_brand_assets.py` to validate this structure and the symbol safe area, while the supplied SVG symbol and horizontal lockup are copied losslessly into the asset catalog for the menu bar, onboarding, and control center.

After reviewing the artifact, a user may explicitly install it with `CONFIRM_INSTALL=YES ./scripts/install-latest.sh build/Artifacts.noindex/Pointrans.app`. The installer never launches by default; `LAUNCH_AFTER_INSTALL=1` remains an explicit user choice. Repository build cleanup is similarly opt-in with `CONFIRM_BUILD_CLEANUP=YES ./scripts/cleanup-pointrans-copies.sh` and never touches `/Applications` or user data. After dragging the App out of a DMG, eject the `Pointrans` volume so its read-only source copy is no longer discoverable.

For local installation testing, the build selects an available Apple Development identity (or accepts an explicit `POINTRANS_LOCAL_SIGN_IDENTITY`) so the application has a stable Team ID. It refuses to produce an installable ad-hoc candidate unless `ALLOW_ADHOC_SIGNING=YES` is deliberately set. For public distribution, set `DEVELOPER_ID_APPLICATION` to the exact signing identity and `NOTARY_PROFILE` to a `notarytool` Keychain profile before running `package.sh`; the script will submit, wait, staple, and validate the DMG.

## Cloudflare Worker

The Worker lives in `Worker/` and exposes:

- `GET /health` — reports route availability without exposing configuration.
- `GET /version` — reports the exact product SemVer and full source commit deployed to production; it fails closed when either identity is missing.
- `POST /v1/installations` — accepts only `{}`, creates a server-side random anonymous quota identity, and returns its signed bearer token. The app's existing Keychain installation UUID remains local and is never uploaded.
- `POST /v1/context` — validates the Bearer token, 100/600-character limits, and the selected word's exact UTF-16 range before returning structured `ContextInsight`.

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

Pointrans stores the pause state, hover delay, cloud-context consent and versioned onboarding progress in UserDefaults, while preserving the existing Keychain identity and bearer token. It does not use a hardware identifier. Accessibility extraction, OCR, dictionary lookups, Apple Translation, and supported Foundation Models inference remain on the Mac. Cloud fallback sends only the selected word, at most 600 UTF-16 code units of context, the exact target range, language direction, and a random request ID.

The first-run window is intentionally blocked until both required permissions and the two Apple Translation directions are ready. Later permission repair and automatic language-pack recovery are handled inside the control center; permission results themselves are never persisted.

## Manual acceptance matrix

Before public distribution, verify Safari, Chrome, Terminal, Preview/PDF, images, full-screen spaces, and horizontal/vertical Retina multi-display layouts. Repeat with no network, missing Accessibility, missing Screen Recording, and Apple Intelligence disabled. Confirm Preview latency, Pinned ownership, cancellation of older results, and absence of ongoing idle requests.
