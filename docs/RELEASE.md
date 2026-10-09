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

Archive + upload from Xcode, or extend Fastlane deliver when ASC API keys are configured (see Empires / Numo `.env` pattern).
