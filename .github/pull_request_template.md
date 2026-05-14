<!--
  CareCircle pull-request template.
  Keep the description tight — reviewers scan, they don't read.
-->

## Summary

<!-- 1–3 bullets. State the change in product terms first, then implementation. -->
-
-

## Why

<!-- The motivation. Link to the spec section, phase plan, ticket, or incident. -->
- Spec / phase / ticket:

## How

<!-- Anything non-obvious about the implementation. Skip if the diff is clear. -->

## Test plan

<!--
  Checklist of what you actually verified, not what should hypothetically work.
  Be specific: device + iOS version, simulator name, backend env, test command.
-->
- [ ]
- [ ]

## Screenshots / recordings

<!-- For UI changes — before/after. Drag-drop here. -->

## Risk

<!-- Surface anything reviewers should poke at: migrations, auth changes, perf-sensitive paths, regulatory surfaces. -->
- Migration:    none / additive / destructive
- Auth path:    no change / change (describe)
- SOS / Critical Alert path: untouched / touched (describe)
- PHI surface:  untouched / touched (describe)

## Rollout

<!-- Feature flag? Phased deploy? Anything we'll need to monitor after merge? -->
- Feature flag:
- Monitoring:

## Pre-merge checklist

- [ ] Conventional Commit title (`feat:`, `fix:`, `refactor:`, …)
- [ ] One logical change in this PR
- [ ] Self-reviewed the diff
- [ ] `xcodebuild build` green locally (or backend tests green)
- [ ] `swiftlint --strict` + `swiftformat --lint .` clean (iOS)
- [ ] `pnpm run lint && pnpm run typecheck && pnpm run test` clean (backend)
- [ ] Docs / CHANGELOG updated if user-visible
- [ ] No AI-attribution lines in commits
