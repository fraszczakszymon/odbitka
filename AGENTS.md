# AGENTS.md

## What is this?

**Pixport** — iPhone app that prepares photos for sending: HEIC → JPG/PNG, downscale,
strip metadata, batch-rename with a shared prefix, pack into ZIP, hand off to the share
sheet. Everything runs on-device; there is no server and nothing is uploaded. Polish and
English UI. Product spec in `SPEC.md` (Polish).

## Stack

SwiftUI + Swift 6 (strict concurrency), iOS 26 minimum. ImageIO + Core Graphics for
pixels, PhotoKit for the library. **No third-party dependencies** — the ZIP writer is
ours. Tests: `swift-testing`, engine only. No linter, no CI.

The Xcode project is **generated**, not checked in as the source of truth.

## Commands

```bash
xcodegen generate                              # regenerate Pixport.xcodeproj from project.yml
swift test --package-path Packages/PixportKit  # engine tests, run on macOS — no simulator needed
swift Tools/make-icon.swift Pixport/Assets.xcassets/AppIcon.appiconset/AppIcon.png

xcodebuild -project Pixport.xcodeproj -scheme Pixport \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Edit `project.yml` and re-run `xcodegen generate` after adding files — do not add targets
or build settings through the Xcode UI, they will be overwritten.

## Architecture

```
Packages/PixportKit/          local SPM package — the whole engine, zero UIKit/PhotoKit
  Model/                      ConversionSettings, MetadataPolicy, SourcePhoto, errors
  Naming/FileNamer            normalisation, ordering, numbering, dedup   (pure)
  Imaging/ImageConverter      the single ImageIO path: decode → scale → encode
  Imaging/MetadataSanitizer   builds output metadata from scratch          (pure)
  Imaging/BudgetSolver        what to tighten after missing a size budget  (pure)
  Imaging/SizeEstimator       sample-based estimate for the settings screen
  Packaging/ZipWriter         streaming STORE-only ZIP writer, ZIP64-aware
  Packaging/SplitPlanner      splitting files across size-limited parts    (pure)
  Pipeline/ConversionPipeline orchestration, concurrency, all-or-nothing
  Pipeline/Preflight          availability + disk space checks             (pure-ish)
  Pipeline/Workspace          tmp/ session dirs, cleanup, free space
  Handoff/                    App Group transfer between extension and app

Pixport/                      app target — thin SwiftUI layer
  Photos/PhotoAsset           the ONLY PHAsset ↔ SourcePhoto adapter
  Features/{Welcome,Library,Settings,Processing,Result,AppSettings}
  Shared/                     Localization, ErrorPresentation, ShareSheet, NetworkMonitor

PixportShare/                 share extension — its own self-contained SwiftUI screen
```

## Key conventions

- **The engine knows nothing about PhotoKit.** Everything goes through the `SourcePhoto`
  protocol. That is why the whole package tests with plain files on disk, on macOS, in
  under three seconds — no simulator, no permissions, no library.
- **Metadata is built from scratch, never copied-and-filtered.** `MetadataSanitizer`
  starts with an empty dictionary and adds back only what policy allows. With the
  opposite approach any key nobody thought about (Maker Notes, XMP, future Apple tags)
  would leak into a file sent to a stranger. Adding a field to preserve requires a
  deliberate change there — that is the point.
- **Share file `URL`s, never `UIImage`.** An app handed an image object may embed it in
  the message body and re-encode it. A file on disk becomes a Gmail attachment. This is
  the one lever we have over the receiving app.
- **Downscale via `CGImageSourceCreateThumbnailAtIndex`**, never by loading the full
  image. A 48 MP photo must never materialise as a ~190 MB bitmap — in the extension,
  with its ~120 MB budget, that is an instant kill.
- **All-or-nothing.** Any error or cancellation wipes partial outputs so an incomplete
  batch cannot be sent by accident. `Preflight` exists to make the typical failure happen
  in the first second instead of the tenth minute.
- **Nothing touches the photo library before the welcome screen** — not even reading the
  authorisation status or registering the change observer. Both can surface the system
  prompt, and the prompt fires exactly once in the app's lifetime.
- **Explicit localisation keys** (`library.title`) via `L.s(_:)` / `L.f(_:_:)`, not
  Polish sentences used as keys.
- **Polish UI wording is part of the product.** Never write "bez utraty jakości"
  (lossless) about downscaling, and never call ZIP "kompresja" — it compresses JPEGs by
  roughly nothing.

## Releasing to TestFlight

```bash
./Tools/release.sh --check-only   # preflight only — touches nothing
./Tools/release.sh                # archive + export → build/Pixport-<version>-<build>/*.ipa
./Tools/release.sh --upload       # …and send to App Store Connect
```

**Build number is the commit count** (`git rev-list --count HEAD`). It always grows,
never repeats, and identifies the exact source state. App Store Connect rejects a
repeated build number, and bumping it by hand is forgotten sooner or later.

`release.sh` runs a preflight before it builds anything. Each check corresponds to a
real validation error Apple bounces packages with — finding out from Apple costs a full
archive, export, upload and wait:

| Check | Error it prevents |
|---|---|
| App icon has no alpha channel | **90717** large app icon can't contain an alpha channel |
| `ITSAppUsesNonExemptEncryption` present | App Store Connect asks about export compliance on *every* build |
| Device family matches declared orientations | **90474** include all orientations to support iPad multitasking |
| Extension version/build match the app | mismatched versions bounce the package |

The checks are verified to fail, not just to pass — break one deliberately and
`--check-only` exits non-zero with a fix instruction.

### Gotchas that cost time elsewhere

- **`-allowProvisioningUpdates` is needed for the archive AND the export.** Without it
  on the export step, the archive succeeds and then the export dies with "No profiles
  for `pl.froncek.pixport` were found" — the distribution profile is only created at
  export time. The flag is not passive: it uses the Xcode Apple ID session and creates
  distribution certificates and profiles on the account.
- **The app is iPhone-only** (`TARGETED_DEVICE_FAMILY: "1"`). Deliberate: the UI was
  never designed for iPad, and the direction is only reversible one way — iPad can be
  *added* in an update, but never *removed* without taking the app away from people who
  already have it. If you widen it, you must also add
  `UISupportedInterfaceOrientations~ipad` with all four orientations.
- **The icon is generated** by `Tools/make-icon.swift`, which hard-fails if the result
  would carry an alpha channel. Do not hand-edit the PNG.
- **`LSApplicationCategoryType` is macOS-only.** The iOS app category is chosen in App
  Store Connect, not in `Info.plist`.

### What must exist before the first upload

- **An app record in App Store Connect** — My Apps → + → New App, platform iOS, bundle
  id `pl.froncek.pixport`, a name that is unique across the entire App Store.
- **An App Store Connect API key** for terminal uploads — Users and Access →
  Integrations → App Store Connect API (a fresh account must click "Request Access"
  first; the App Manager role is enough). `AuthKey_*.p8` downloads **once**; put it in
  `~/.appstoreconnect/private_keys/` and export `ASC_KEY_ID` and `ASC_ISSUER_ID`.
  Without a key, Apple's Transporter app takes the `.ipa` by drag and drop.
- **The trader / non-trader declaration (DSA)** in the Business tab. Without it Apple
  blocks distribution in the EU. A private app is non-trader.

### TestFlight facts worth knowing before promising anything

- **Internal testers must be App Store Connect users** — an arbitrary email address
  cannot be added. The weakest role that can test is Marketer.
- **External testers** can be any address, but the first build of each version goes
  through Beta App Review and needs Test Information filled in.
- **"Enable automatic distribution" cannot be changed later** for a group. Leave it off
  and add builds by hand in the Builds tab once processing finishes.
- **A build expires after 90 days.**

## Gotchas

- **`Pixport.xcodeproj` is generated.** Changes made in Xcode's project editor vanish on
  the next `xcodegen generate`. Edit `project.yml`.
- **The extension cannot use `UIApplication.shared`.** `project.yml` lists its sources
  file by file for that reason — do not point it at `Pixport/` wholesale. Its UI is
  deliberately duplicated rather than shared.
- **`Info.plist` must carry `CFBundleIdentifier`, `CFBundleVersion` and friends**
  explicitly (as `$(...)` variables). With a custom `INFOPLIST_FILE` Xcode does not
  inject them, and the app installs as "Missing bundle ID".
- **The package declares `.macOS`** purely so `swift test` runs on the host. Nothing in
  the engine is macOS-specific; do not add anything that is.
- **`PHAssetResource.fileSize` is KVC-only.** There is no public accessor for the
  original's size without reading it. `PhotoAsset.make` falls back to a pixel-count
  estimate if the key ever disappears.
- **`PHAssetResourceManager.requestData` calls both handlers.** The data handler and the
  completion handler can both fire, so the continuation is guarded by `SingleResume` —
  resuming a continuation twice is a hard crash.
- **A stuck system alert survives app uninstall in the simulator.** If a permission
  prompt appears to fire at the wrong moment, screenshot with the app uninstalled before
  blaming the code; `simctl shutdown` + `boot` clears it.
- **`xcrun simctl privacy grant photos` does not reliably stick** on iOS 26 simulators.
  Expect to tap the prompt.
- **`ByteCountFormatter` prints "Zero KB"** unless `allowsNonnumericFormatting = false`.
- **Typographic quotes in Swift string literals break the build.** `„…"` closes the
  literal on the straight quote. Fine in comments, never inside `"…"`.
