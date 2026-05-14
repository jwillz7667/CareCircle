# Contributing to CareCircle

Thank you for your interest in CareCircle. This document covers how internal contributors and approved external collaborators submit changes to the project.

CareCircle is proprietary software owned by Viral Venture LLC. Read [LICENSE](LICENSE) before contributing. By submitting a Contribution you accept the Contribution License terms in [§9 below](#9-contribution-license-agreement).

---

## 1. Code of Conduct

All participation in this project is governed by the [Code of Conduct](CODE_OF_CONDUCT.md). Report concerns to `conduct@viral-ventures-llc.com`.

---

## 2. Filing issues

Issues are tracked privately. External collaborators should email `support@viral-ventures-llc.com` with:

- A short, specific title.
- The version (commit SHA or release tag) you observed the issue on.
- Steps to reproduce, expected behavior, actual behavior.
- Logs, screenshots, or recordings — with all personally identifiable health information redacted.
- For security vulnerabilities, **do not** file an issue or email `support@`. Follow [SECURITY.md](SECURITY.md).

---

## 3. Workflow

CareCircle follows **EXPLORE → PLAN → CODE → COMMIT** for every phase of work. For non-trivial changes:

1. **Explore.** Read the relevant feature folder, the [product spec](docs/CARECIRCLE_SPEC.md), and any prior phase plans under [`docs/phases/`](docs/phases/).
2. **Plan.** Write a short plan to `docs/phases/PHASE_<N>_PLAN.md` (or attach a plan to your PR description for ad-hoc work). State the scope, the files you intend to touch, and the verification steps.
3. **Code.** One logical change per commit. Keep commits reviewable.
4. **Commit.** Run lint + the iOS build + the backend tests locally before pushing. Red CI is never merged.

Trivial changes (typo fixes, minor doc edits) may skip the planning step. Use judgment.

---

## 4. Branch and commit conventions

### Branch names

| Prefix | Use |
|---|---|
| `feat/<slug>` | New feature |
| `fix/<ticket>-<slug>` | Bug fix |
| `refactor/<slug>` | Code restructuring with no behavior change |
| `perf/<slug>` | Performance work |
| `docs/<slug>` | Documentation only |
| `chore/<slug>` | Tooling, dependencies, repo housekeeping |

### Commit messages

[Conventional Commits](https://www.conventionalcommits.org/) format. Scopes are optional but encouraged.

```
feat(meds): support liquid-form dose calculations

The prior implementation rounded ml dosages to nearest whole number,
which over-rounded sub-1ml pediatric doses. Switch to two-decimal
precision matching the prescriber input on the add screen.
```

- Imperative subject, ≤ 72 characters.
- Body explains **why**, not **what** — the diff already shows what.
- One logical change per commit. Refactors and behavior changes never share a commit.
- **Do not** add AI-assistant attribution lines (e.g. `Co-Authored-By: Claude …`, `🤖 Generated with …`) — see [CLAUDE.md](CLAUDE.md).

---

## 5. Pull requests

- Open against `main`.
- Title uses the same Conventional Commits prefix.
- PR description includes a **Summary** (3 bullets max) and a **Test plan** (bulleted checklist).
- Link relevant issue, spec section, or phase plan.
- Keep PRs small. > 600 changed lines is a smell; split it.
- Self-review the diff before requesting review.
- All conversations resolved + green CI required for merge.
- **Squash-merge only.** The squashed commit message should be the PR title; the body should be the PR Summary.

PRs touching the following surfaces require additional review:

| Surface | Additional reviewer |
|---|---|
| `CareCircle.entitlements`, `Info.plist` | Maintainer + on-call iOS owner |
| Database migrations (`backend/packages/db/prisma/`) | Maintainer + backend lead |
| Sign in with Apple, auth, key handling | Security reviewer |
| Anything touching SOS or Critical Alerts | Maintainer (Critical Alert entitlement is in production review with Apple) |

---

## 6. Code style

### Swift / iOS

- Swift 6 with strict concurrency. Use `async/await`, `@Observable`, and structured concurrency. Avoid bare `DispatchQueue` outside of CoreLocation / HealthKit delegate bridging.
- Prefer value types (`struct`, `enum`) over classes. Reference types only where reference semantics are required.
- No singletons in production code paths. Inject services through the SwiftUI `Environment` or initializers.
- No force unwraps (`!`) outside of tests.
- No defensive checks for impossible states. Trust your own types.
- `@MainActor` is the project-wide default actor (`SWIFT_DEFAULT_ACTOR_ISOLATION`). Mark pure value types `nonisolated` if they don't touch UI state.
- File names are PascalCase and match the primary exported type. One primary type per file.
- Use `// MARK: -` to organize files > 100 lines.
- Triple-slash docs (`///`) on public API only. No noise comments.
- Run `swiftformat .` and `swiftlint --strict` before committing.

### TypeScript / Backend

- Strict TypeScript. No `any`, no `as` casts unless unavoidable.
- Zod at every external boundary — HTTP body, query, headers, env, file input.
- `const` over `let`. Never `var`.
- `async`/`await` over raw promises or callbacks.
- Feature-first folders (`features/<domain>/`). Each feature owns routes, service, repo, schema, and tests, co-located.
- Strict layer direction: UI → application → domain → infrastructure. The domain layer must not import framework, transport, or persistence concerns.
- Run `pnpm run lint` and `pnpm run typecheck` before pushing.

### Naming

- Booleans read as questions: `isLoading`, `hasCompleted`, `shouldRetry`, `canEdit`.
- Functions read as verbs: `fetchUser`, `parseToken`, `validatePayload`.
- Types are PascalCase nouns. Suffix only when disambiguating: `UserDTO`, `UserEntity`, `UserVM`.
- Constants are `SCREAMING_SNAKE_CASE` only for true compile-time constants, otherwise camelCase / PascalCase.
- Errors are typed enums or named error classes — `AuthError.invalidToken`, never bare strings.

### Inline comments

Write comments for **why**, not **what**. The code already tells a reader what it does. Comment when:

- A constraint, invariant, or workaround would surprise a future reader.
- A non-obvious external requirement (Apple review, regulatory) shaped the design.
- A reference to a ticket, doc, or external spec is load-bearing.

Don't comment what well-named identifiers already convey.

---

## 7. Testing

Pyramid: many fast unit tests, fewer integration, fewest e2e.

| Layer | What goes here |
|---|---|
| Unit (`*Tests.swift`, `*.test.ts`) | Pure functions, domain logic, parsers, reducers. No I/O. |
| Integration (`backend/.../*.test.ts` under `test/integration/`) | Real Postgres via testcontainers, real Prisma client, real Fastify routes. Mocks reserved for third-party APIs. |
| End-to-end | Reserved for late-phase critical user flows. XCUITest will be introduced when explicitly approved. |

- Coverage target ≥ 80% on `domain/` and feature services.
- Test names describe behavior, not implementation: `it("returns 409 when email already exists")`.
- Arrange / Act / Assert blocks with a blank line between them.
- iOS uses Swift Testing framework. XCUITest is gated and not allowed without explicit approval.

---

## 8. Dependencies

Adding a new third-party dependency requires:

1. A justification in the PR description (why it's needed, what it replaces, why we can't use the platform).
2. License compatibility — incompatible licenses (e.g. AGPL on iOS / linked code) are not allowed. Server-only AGPL components require approval.
3. Bundle/binary size review — > 50 KB transitive must be justified.
4. Adding an entry to `NOTICE` and (where applicable) a copy of the license to `docs/third-party-licenses/`.

---

## 9. Contribution License Agreement

By submitting a Contribution (any code, documentation, design, or other materials) to this repository, You represent and warrant that:

1. **Originality.** The Contribution is Your original work, or You have the right to submit it under the terms below; if any portion is not Your original work, You have clearly identified its source and the license under which it is provided, and that source license is compatible with this project.
2. **Authority.** You have the legal right and authority to grant the rights in this section. If You are submitting on behalf of Your employer, You have obtained the necessary approvals.
3. **No third-party claims.** To Your knowledge, the Contribution does not infringe the intellectual property rights, privacy rights, or other rights of any third party.

You hereby grant to **Viral Venture LLC** a perpetual, irrevocable, worldwide, royalty-free, transferable, sublicensable license, with the right to grant further sublicenses, to use, reproduce, modify, prepare derivative works of, publicly display, publicly perform, distribute, and otherwise exploit the Contribution and any derivative works thereof, in any form and through any medium now known or later developed, in connection with the Software and any successor product or service.

To the maximum extent permitted by law, You waive (and agree not to assert) any moral rights, rights of publicity, or similar rights in the Contribution.

You retain ownership of Your Contribution; this section grants a license, not a transfer of ownership, except where required by law to give effect to the rights granted.

---

## 10. Working with AI-assisted tooling

This repository is set up for AI-assisted development (see [CLAUDE.md](CLAUDE.md)). When using such tooling:

- You remain responsible for every line you commit. AI suggestions are starting points, not authority.
- Do not paste production data, secrets, customer information, or unpublished design documents into third-party AI services.
- Do not add `Co-Authored-By: <AI>`, "Generated with …", or similar attribution to commits or PR bodies.
- Verify generated code against the project's style guide and run the build + lint locally before pushing.

---

## 11. Contact

| Topic | Address |
|---|---|
| General | `support@viral-ventures-llc.com` |
| Security disclosure | `security@viral-ventures-llc.com` |
| Licensing | `licensing@viral-ventures-llc.com` |
| Code of Conduct | `conduct@viral-ventures-llc.com` |

Thank you for helping make CareCircle better.
