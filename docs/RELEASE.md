# App Store release checklist

Ship version is **1.0.0 (1)** (`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`).

## Before archive

- [ ] `xcodegen generate` after `project.yml` changes
- [ ] Unit tests + crash smoke:

```sh
xcodebuild test -project Doodleoop.xcodeproj -scheme Doodleoop \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:DoodleoopTests

xcodebuild test -project Doodleoop.xcodeproj -scheme Doodleoop \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:DoodleoopUITests/CrashSmokeUITests
```

- [ ] Capture framed screenshots: `fastlane screenshots`
- [ ] Optional marketing sync: `fastlane sync_marketing`
- [ ] Multi-device smoke: 3 phones, join code, full round, leave, reconnect

## App Store Connect (first submit)

Metadata lives under `fastlane/metadata/` (description, URLs, review notes, age rating JSON).

| Field | Value |
|-------|--------|
| Privacy Policy | https://doodloop.f-90.co.uk/privacy/ |
| Support | https://doodloop.f-90.co.uk/support/ |
| Marketing | https://doodloop.f-90.co.uk/ |
| Export compliance | Uses non-exempt encryption? **No** (`ITSAppUsesNonExemptEncryption = false`) |
| Privacy Nutrition Labels | No data collected by the developer; peer-shared drawings/names are local-network only; on-device identifiers for multiplayer seats |
| Age Rating | See `fastlane/metadata/age_rating.json` — no public UGC feed; content stays in the room |

In-app Settings → About links the same Privacy / Support URLs.

## Upload

```sh
fastlane release
```

Uses the gitignored `.env` API key (same account as Empires / Numo). The lane runs unit tests and crash smoke, archives `1.0.0`, uploads the binary plus `fastlane/metadata` and framed screenshots, sets the app to free, publishes the privacy label, and submits for review.

The key can register the bundle ID but cannot create a brand-new App Store Connect app. If that step stops, add the iOS app in App Store Connect, then rerun with the archive already built:

```sh
SKIP_TESTS=1 SKIP_SCREENSHOT_CAPTURE=1 fastlane release
```

| Field | Value |
|-------|--------|
| Name | Doodleoop |
| Primary language | English (UK) |
| Bundle ID | `com.archgrovehouse.doodleoop` |
| SKU | `doodleoop-ios` |

App Privacy (Data Not Collected) is set in the App Store Connect website. The public API no longer exposes that questionnaire.
