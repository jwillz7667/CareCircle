# Phase 5 — Voice handoff notes

**Goal (from build prompt):** Tap mic in the Activity feed → SFSpeechRecognizer transcribes on-device → auto-stop on ~2s of silence (or manual stop) → post a `.voiceNote` Activity carrying both the transcript (body) and the audio file (externalStorage Data). Tap-to-posted under 90s on iPhone 13-class. Falls back gracefully when speech permission is denied (still records audio; body is "Voice note (no transcript)").

Spec references: §4.3 (voice handoff is the headline interaction), §5.4 (on-device first — Phase 5 only does transcription; Phase 6 layers AI extraction on top).

## Scope (do)

1. Add `audioData: Data?` with `@Attribute(.externalStorage)` to `Activity`. CloudKit-compatible (optional, defaults to nil). Add `audioDurationSeconds: Double = 0` for playback UI.
2. `VoiceCaptureService` (`@Observable`, MainActor): drives `AVAudioRecorder` + `SFSpeechRecognizer` together. Exposes state enum (`idle / requestingPermission / recording(transcript) / processing / completed / failed`). Owns silence detection by polling `recorder.averagePower(forChannel: 0)` every 100ms; auto-stop after 2s continuously below -50dB **plus** at least 1s elapsed.
3. Permission helper: `VoicePermissions` checks `AVAudioApplication.requestRecordPermission` and `SFSpeechRecognizer.requestAuthorization`. If speech denied, recording still works but transcript stays empty.
4. `VoiceComposerView` sheet: big circular mic button, live transcript preview, elapsed timer, Save/Discard. Uses the service via `@State`.
5. Feed entry: replace the single text-only FAB with a small overflow menu (Post note / Voice note) anchored to the same FAB position. Long-press is too discoverable-only; menu is more obvious.
6. Playback: `VoiceNoteRow` inside `ActivityDetailView` and `ActivityRowView` — play/pause icon, scrubber-less, duration label. Backed by `AVAudioPlayer`.

## Out of scope (Phase 5)

- AI entity extraction (Phase 6, Foundation Models).
- Background recording (the composer is foreground-only).
- Cloud transcription fallback (older devices get audio-only). Phase 6 introduces the PHI-stripped proxy.
- Waveform UI; just a power-pulse animation on the mic button.
- Edit transcript after capture; v1 is fire-and-forget.

## Files to add

```
CareCircle/Sources/Features/Activity/
  VoiceCaptureService.swift        // @Observable state machine
  VoiceCaptureState.swift          // enum + helpers
  VoicePermissions.swift           // permission probe + request
  VoiceComposerView.swift          // sheet UI
  VoiceNotePlayer.swift            // @Observable AVAudioPlayer wrapper
  VoiceNoteRow.swift               // play/pause row used in feed + detail
  PostMenuButton.swift             // overflow menu replacing the FAB label
```

## Files to edit

- `CareCircle/Sources/Models/Activity.swift` — add `audioData`, `audioDurationSeconds`; init param defaults nil/0.
- `CareCircle/Sources/Models/ActivityType.swift` — `voiceNote` already exists; confirm displayName "Voice note" and `waveform` icon.
- `CareCircle/Sources/Features/Activity/ActivityFeedView.swift` — swap FAB for `PostMenuButton`; present `VoiceComposerView` on selection.
- `CareCircle/Sources/Features/Activity/ActivityRowView.swift` — render `VoiceNoteRow` when `activity.type == .voiceNote && activity.audioData != nil`.
- `CareCircle/Sources/Features/Activity/ActivityDetailView.swift` — same.
- `CareCircle/Info.plist` — `NSMicrophoneUsageDescription` + `NSSpeechRecognitionUsageDescription` (done in EXPLORE step).

## Architecture notes

- **Audio file format:** `m4a` (AAC) at 44.1kHz mono, ~64kbps. Small enough that a 60s clip is well under 1MB — fine for CKAsset via `@Attribute(.externalStorage)`.
- **Recording path:** `FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID()).m4a")` while recording; on stop, `try Data(contentsOf:)` and discard the temp file.
- **Silence detection:** polling power every 100ms via `Timer.publish` on the MainActor (recorder must `isMeteringEnabled = true`). Below -50dB for 20 consecutive samples (2s) → stop. Guard against immediate stop by enforcing 1s minimum recording.
- **Speech recognition:** `SFSpeechAudioBufferRecognitionRequest` if we can install a tap; simpler MVP: use `SFSpeechURLRecognitionRequest` on the temp file after recording ends. Live transcript preview is *aspirational* — if buffer approach turns out fragile, ship with post-record transcription only; the UX still feels responsive because we show "Transcribing…" for ~1s on stop.
  - **Decision for this phase:** buffer-tap live preview (best UX) with the URL-based fallback wired in for failure.
- **Concurrency:** the service is MainActor; AVAudioRecorder delegate and SFSpeechRecognizer callbacks are bridged via `@MainActor` continuations. Recorder timer is invalidated in `deinit`.

## Build sequence

1. EDIT: Activity model + AudioComposerImagePipeline-style file structure → confirm build green.
2. ADD: VoicePermissions + VoiceCaptureService + VoiceCaptureState → confirm build green.
3. ADD: VoiceComposerView → confirm build green.
4. EDIT: ActivityFeedView (PostMenuButton) → confirm build green.
5. ADD: VoiceNotePlayer + VoiceNoteRow → wire into row + detail → confirm build green.
6. swiftformat + swiftlint clean.
7. Manual smoke: launch simulator (recording will fail since no mic but the UI path should be exercisable).
8. Commit + push.

## Risks / open questions

- **Simulator mic capture** is iffy; relies on host machine mic. Acceptable; ship code, defer device test to Phase 12 polish.
- **Live transcript on iOS 26** — `SFSpeechRecognizer` is being deprecated in favor of `SpeechAnalyzer` (iOS 26+). For v1 we stay on `SFSpeechRecognizer` since the deprecation is still warning-only and it's covered by every iPhone 11+ device. Note for Phase 12: migrate to `SpeechAnalyzer`.
- **Memory-mode m4a -> Data** is fine at our durations (≤ 90s); won't OOM.

## DoD

- Tap mic → recording starts within 500ms after permission grants.
- Live transcript visible during recording (if speech granted).
- Silence auto-stop fires after ~2s of quiet, with 1s lower bound.
- Saved Activity carries audio + transcript; CloudKit syncs it.
- Detail view plays back the audio.
- xcodebuild + swiftformat + swiftlint all green.
- No force unwraps, no singletons in production paths.
- Conventional Commits with no AI attribution.

## Self-critique

- Storing `audioData` inline (even externalStorage) doubles disk usage briefly during write. Acceptable for ≤90s clips.
- Transcript on the body field competes with text posts visually; mitigation: voice rows render the audio player above the transcript text and label "Transcript • on-device".
- If both buffer-tap and URL recognition fail (offline, language unavailable), user still has the audio; the row just shows "Tap to listen — transcript unavailable." That's the right product behavior.
