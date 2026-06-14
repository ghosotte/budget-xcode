# Budget — iOS app

Local-first budgeting app with optional cloud sync.

## Stack

- **iOS 17+**, Swift 5.9+, SwiftUI, SwiftData (`@Model`, `VersionedSchema`)
- **Networking**: `URLSession` + `OSLog`, custom `APIClient` with App Attest assertions
- **Auth**: email/password, Google Sign-In, Sign in with Apple via Symfony backend
- **Observability**: `os_log` (`AppLogger`) + `MetricKit`

## Setup

```bash
git clone <repo>
cd budget
open budget.xcodeproj
```

Build target: iOS 17+. No CocoaPods/Carthage; SPM resolves `GoogleSignIn-iOS` automatically on first build.

### Run on simulator

```bash
xcodebuild -project budget.xcodeproj -scheme budget \
  -destination 'platform=iOS Simulator,name=iPhone 15' build
```

Or open in Xcode → ⌘R.

### Run on device "Guilhem"

User memory: this project always deploys on physical device named "Guilhem". Use Xcode → choose Guilhem in run destination → ⌘R.

## Backend

API at `https://api.theapp.fr` (production). Override via:

- `Info.plist` key `API_BASE_URL` (build-time)
- `UserDefaults` key `apiBaseURL` (runtime debug)

Backend repo: `/Users/gui/Projects/symfony/theApp`, branch `API-budget`.

## Architecture

See `docs/ARCHITECTURE.md`.

Short version: `Domain/` (SwiftData models) → `Data/` (services, sync) → `Presentation/` (SwiftUI views).
Local-first: every mutation writes SwiftData immediately, push attempts run in background.

## Sync model

- **Cold start / login**: full bootstrap (foyers, categories, recurring)
- **On view display**: per-month pull (transactions + budget lines) via `MonthSyncService`
- **On reconnect**: auto `quickSync` (push pending offline ops)
- **On mutation**: `afterLocalChange` pushes immediately if online

## Test

```bash
xcodebuild -project budget.xcodeproj -scheme budget \
  -destination 'platform=iOS Simulator,name=iPhone 15' test
```

(Test coverage limited as of V1; see plan for Phase 3 roadmap.)
