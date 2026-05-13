# Phase 4 — Activity Feed (text + photos, reactions, comments)

**Spec anchors:** §3.1 #2 (Shared activity feed), §4.3 (Voice handoff posts to feed), §5.2 (Activity model), §5.3 (CloudKit sharing).

**Build prompt anchor:** Phase 4 line 145.

**End state:** any active Circle member can post a text or text+photo Activity. It writes to SwiftData, syncs through the private CloudKit DB (and on through the Phase 3 CKShare to other members), and appears on the Home tab. Reactions (👍 ❤️ 🙏) and per-item comments work. Filters by author and type narrow the feed.

---

## Scope (in)

1. `Activity`, `ActivityReaction`, `ActivityComment` `@Model` types, all CloudKit-compatible (no `@Attribute(.unique)`, optional relationships, defaults on every stored property, enums persisted as raw `String`).
2. `Activity.type` covers `.textNote`, `.photo`, plus future-facing tags `.voiceNote`, `.medTaken`, `.visit`, `.appointment`, `.alert`, `.system` so later phases drop into the same feed.
3. `Circle.activities` inverse relationship.
4. `ActivityFeedView` rendering the active Circle's chronological feed on the Home tab.
5. `ActivityComposerView` sheet — text body + optional photo via `PhotosPicker`, posts on Send.
6. `ActivityRowView` and `ActivityDetailView` — row for the feed, detail with comment thread.
7. `ReactionsBar` — three-emoji toggle row with counts. Tap toggles the signed-in user's reaction for that emoji.
8. `CommentsList` + `CommentComposer` for the detail view.
9. `ActivityFilterBar` — chips for type + member; in-memory filtering over the active Circle's activities.
10. Photo handling: `@Attribute(.externalStorage)` so SwiftData spills large blobs to CKAsset transparently; JPEG-compress to ~1500px / quality 0.85 before persisting.
11. Permissions: any `Member` with `status == .active` (or the Circle owner) can post, react, and comment. Authors can delete their own posts and comments.

## Scope (out)

- Voice notes (Phase 5).
- AI entity extraction / chip rendering (Phase 6).
- Activity-tied medication scheduling (Phase 7).
- Push notifications for reactions/comments (revisit in Phase 10 alongside SOS push fan-out).
- Server-side moderation / report flow (post-v1).
- Edit-in-place after Send. Authors can delete-and-repost; no PATCH UI in v1.

## Schema additions

### `Activity` (new `@Model`)

```
id: UUID = UUID()                          // primary key (no unique attribute — CloudKit)
authorAppleUserID: String = ""             // matches Member.appleUserID; "" for system activities
authorDisplayName: String = ""             // snapshot at post time so deletions don't blank rows
createdAt: Date = .now
typeRaw: String = ActivityType.textNote.rawValue
body: String = ""                          // text body, may be empty when only a photo
photoData: Data? (@Attribute(.externalStorage))
circle: Circle?                            // inverse via Circle.activities
reactions: [ActivityReaction] = []         // .cascade
comments:  [ActivityComment]  = []         // .cascade

var type: ActivityType { computed via raw, default .textNote with persistence-log on miss }
```

### `ActivityReaction` (new `@Model`)

```
id: UUID = UUID()
emoji: String = "👍"                       // restricted to the 3-emoji set by the UI; stored raw
authorAppleUserID: String = ""
authorDisplayName: String = ""
createdAt: Date = .now
activity: Activity?
```

A reaction is unique-per-(activity, authorAppleUserID, emoji) by *application invariant*, not by DB constraint — toggling deletes and re-inserts.

### `ActivityComment` (new `@Model`)

```
id: UUID = UUID()
body: String = ""
authorAppleUserID: String = ""
authorDisplayName: String = ""
createdAt: Date = .now
activity: Activity?
```

### `ActivityType` (new `enum`)

```
case textNote        // raw "text_note"
case photo
case voiceNote       // raw "voice_note"   — Phase 5
case medTaken        // raw "med_taken"    — Phase 7
case visit
case appointment
case alert
case system          // owner-name / membership system messages
```

Persisted via `typeRaw: String`. Read accessor mirrors `Member.role` / `Member.status` pattern: log on unknown raw and fall back to `.system`.

### `Circle` migration

Add:

```
@Relationship(deleteRule: .cascade, inverse: \Activity.circle)
var activities: [Activity] = []
```

Register all three new `@Model` types in `CareCircleApp.init`'s `Schema([…])`.

## CloudKit topology

- All Activity records live in the same per-circle `CKRecordZone` that Phase 3 created (`CloudKitConfiguration.recordZoneID(for: circleID)`). SwiftData already routes everything that touches a `Circle` (or a model reachable from one) into the matching zone via the `cloudKitDatabase: .private(...)` configuration; we don't have to do anything beyond declaring the relationships.
- Members who accepted a CKShare on Phase 3 already see the Circle through their *shared* DB; the activities ride the same share, so the propagation is automatic.
- Photos: `@Attribute(.externalStorage)` is the magic incantation. SwiftData writes large `Data` to its external-files store, and the CloudKit mirror lifts those into `CKAsset`.

## UI flow

- **Home tab** drops the "No recent activity yet." placeholder and renders `ActivityFeedView(circle:signedInAppleUserID:signedInDisplayName:)` whenever an active Circle exists.
- `ActivityFeedView`:
  - top-of-list `CircleHero`
  - sticky `ActivityFilterBar` (Type · Member)
  - `LazyVStack` of `ActivityRowView`, each tappable into `ActivityDetailView`
  - floating `Post` button (bottom-trailing) opens `ActivityComposerView`
- `ActivityComposerView` (sheet):
  - large `TextEditor` for body
  - `PhotosPicker` button → preview + "remove" affordance
  - "Send" disabled when body+photo both empty
  - Inserts new `Activity` and saves
- `ActivityDetailView`:
  - full body + photo
  - `ReactionsBar` (👍 ❤️ 🙏)
  - comment thread + new-comment composer
  - author-only delete via destructive menu

## Permissions

- Posting / reacting / commenting: requires `Member.status == .active` for the signed-in user, OR Circle ownership. `CirclePermissions` already encodes ownership and roles — we'll add `canPostActivity`, `canReact`, `canComment` accessors.
- Delete: author-only for activities and comments; owner can also delete activities.

## Files to add

```
Sources/Models/Activity.swift
Sources/Models/ActivityReaction.swift
Sources/Models/ActivityComment.swift
Sources/Models/ActivityType.swift
Sources/Features/Activity/ActivityFeedView.swift
Sources/Features/Activity/ActivityComposerView.swift
Sources/Features/Activity/ActivityDetailView.swift
Sources/Features/Activity/ActivityRowView.swift
Sources/Features/Activity/ActivityFilterBar.swift
Sources/Features/Activity/ReactionsBar.swift
Sources/Features/Activity/CommentsList.swift
Sources/Features/Activity/ActivityComposerImagePipeline.swift  // pure JPEG compression helper
Sources/Features/Activity/ActivityAuthorContext.swift           // signed-in identity packet passed in via Environment / init
```

## Files to edit

- `CareCircle/Sources/Models/Circle.swift` — add `activities` inverse.
- `CareCircle/Sources/Features/Home/HomeView.swift` — replace placeholder with `ActivityFeedView`.
- `CareCircle/Sources/Features/Members/CirclePermissions.swift` — add `canPostActivity`, `canReact`, `canComment`.
- `CareCircle/Sources/App/CareCircleApp.swift` — register new model types in the schema.

## Build sequence

1. Models (`Activity`, `ActivityReaction`, `ActivityComment`, `ActivityType`). Wire `Circle.activities`. Register in Schema. `xcodebuild` checkpoint.
2. Permission accessors on `CirclePermissions`. `xcodebuild` checkpoint.
3. Helpers (`ActivityComposerImagePipeline`, `ActivityAuthorContext`). `xcodebuild` checkpoint.
4. Row + Feed + Filter bar. `xcodebuild` checkpoint.
5. Composer with `PhotosPicker`. `xcodebuild` checkpoint.
6. Detail + Reactions + Comments. `xcodebuild` checkpoint.
7. Wire Home tab. `xcodebuild` checkpoint.
8. swiftformat + swiftlint. Fix anything that surfaces.
9. Manual sanity in Simulator (sign in → create circle → post text → post photo → react → comment → filter).
10. Commit + push + schedule Phase 5.

## Risks

- **SwiftData inverse-relationship gotchas.** Adding a new optional inverse on `Circle` after CloudKit has live data risks a migration failure on existing simulators. Mitigation: simulators wipe is cheap; real-device migration risk is low because there is no production data yet.
- **Large photo payloads going through CloudKit private zone**: 1MB target keeps us well under the 50MB asset cap.
- **In-memory filter performance**: an active circle's feed is bounded by ~hundreds of rows; `LazyVStack` + Swift's lazy filtering is fine. If a circle ever held thousands, switch the body to a `FetchDescriptor` with a predicate. Not in scope for Phase 4.
- **Reactions duplication during sync**: two devices toggling the same emoji simultaneously could create two `ActivityReaction` rows. Mitigation: feed view groups by `(emoji, authorAppleUserID)` and dedupes; we don't display duplicates and a future cleanup pass can prune.
- **SwiftData.Circle vs SwiftUI.Circle**: still applies. Stick to `SwiftUI.Circle()` when drawing dots or rings.

## Definition of Done

- `xcodebuild` builds clean, zero warnings on iPhone 16 Pro Max simulator.
- `swiftformat` and `swiftlint --quiet` clean.
- Schema includes all three new model types; existing data on a fresh simulator install loads without error.
- HomeView shows the active Circle's feed; an empty state appears when there are zero posts.
- Composer round-trips text → row visible in feed.
- Composer round-trips text + photo → photo thumbnail in row, full photo in detail.
- Reactions toggle: tapping 👍 adds the row's signed-in user reaction, tapping again removes it. Count updates inline.
- Comments thread persists; visible to the same Circle.
- Filter bar narrows by type and by author independently.
- Phase 4 commit pushed to `origin/main`.
- Cron scheduled for Phase 5.

## Self-critique

- The 8-emoji-only restriction is a UX simplification, not a schema one; future phases can store any string. That's fine — `ActivityReaction.emoji` is just a `String`.
- Storing `authorDisplayName` denormalized on `Activity` instead of joining through `Member.displayName` means a member rename won't retroactively retitle past posts. That's the desired behavior — feed history is a record of "who said this when," not a live mirror of the current member list.
- Filters live as in-memory predicates instead of `Query` parameters because the active Circle's `activities` collection is already loaded as part of the Circle graph; reusing it avoids a duplicate query path. The trade-off is slightly more main-thread work on each filter toggle — negligible at v1 sizes.
- I am intentionally not adding push notifications for reactions/comments here. The spec puts that into Phase 10's notification work alongside SOS, and threading it through Phase 4 would force a half-baked APNs plumbing pass.
