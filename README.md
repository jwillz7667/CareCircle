# CareCircle

iOS family-caregiving coordination app. SwiftUI + SwiftData + CloudKit.

## Specs

- Product spec — [`docs/CARECIRCLE_SPEC.md`](docs/CARECIRCLE_SPEC.md)
- Phased build plan — [`docs/CARECIRCLE_BUILD_PROMPT.md`](docs/CARECIRCLE_BUILD_PROMPT.md)
- Backend alternative (not in v1 scope) — [`docs/CARECIRCLE_DATABASE_SPEC.md`](docs/CARECIRCLE_DATABASE_SPEC.md)

## Build

```bash
xcodebuild -project CareCircle.xcodeproj -scheme CareCircle \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' build
```

Or open `CareCircle.xcodeproj` in Xcode 26 and press ⌘R.

## Status

Phase 0 scaffolding complete. `ContentView.swift` and `Item.swift` are Xcode template stubs that Phase 1 will replace with the Sign-in-with-Apple + 4-tab interface.

## Project rules

See [`CLAUDE.md`](CLAUDE.md).
