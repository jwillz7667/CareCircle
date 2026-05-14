# Security Policy

CareCircle handles health-adjacent data for vulnerable users. We take security reports seriously and follow a coordinated disclosure model.

## Reporting a vulnerability

**Do not file a public GitHub issue.**

Email `security@viral-ventures-llc.com` with the details below. If the vulnerability is sensitive enough that email is not appropriate, encrypt your report with the PGP key published at [`https://viral-ventures-llc.com/.well-known/security.asc`](https://viral-ventures-llc.com/.well-known/security.asc).

Please include:

- A description of the issue and its impact.
- The component, file, and line range affected (if known).
- A minimal proof of concept or reproduction steps.
- The version (commit SHA, release tag, App Store build number, or backend deploy ID).
- Your name and a contact channel for follow-up.
- Whether you intend to publish a write-up — if so, on what timeline.

## What to expect

| Step | Target |
|---|---|
| Acknowledgement | Within 2 business days |
| Initial triage and severity assessment | Within 5 business days |
| Status update | At least every 7 business days while the report is open |
| Fix released or mitigation in place | As fast as severity warrants |
| Public disclosure | Coordinated with reporter; not before a fix is deployed |

Reporters who follow this policy and act in good faith will not be subject to legal action by Viral Venture LLC for testing performed within the scope of this policy.

## Scope

In scope:

- The CareCircle iOS application (App Store + TestFlight builds).
- The CareCircle backend API (`api.viral-ventures-llc.com` and any subdomains used in production).
- WebSocket realtime endpoints.
- MinIO / object-storage endpoints under our control.
- Authentication, authorization, and tenancy boundaries — particularly Postgres Row-Level Security policies and per-circle data isolation.

Out of scope:

- Third-party dependencies, except where they expose a vulnerability through our integration.
- Apple infrastructure (CloudKit, APNs, HealthKit, App Store), Railway, and other upstream providers — please report those to their respective vendors.
- Findings that require physical access to an unlocked, signed-in device.
- Self-service account takeover by the device's iCloud-signed-in user (this is by design).
- Social engineering or phishing against our employees.
- Denial-of-service findings, unless they identify an unauthenticated amplification primitive.

## Out-of-scope testing prohibited

Even within the in-scope surfaces, you must not:

- Access, modify, exfiltrate, or destroy data belonging to other users.
- Run automated scanners that generate sustained traffic.
- Disrupt production service availability for users.
- Test on production data; use test accounts you control.
- Pivot to systems beyond the in-scope surfaces above.
- Make the vulnerability public before a coordinated disclosure date.

## Recognition

We maintain a private record of all reports. With your consent we will publicly credit you in the release notes of the fix, and at our discretion in a periodic security acknowledgements list.

We do not currently operate a paid bug-bounty program. Significant impactful reports may be eligible for a discretionary thank-you payment; see `security@viral-ventures-llc.com` for details.

## Defensive posture, in brief

- Sign in with Apple only — no password storage.
- 15-minute access tokens with rotating 30-day refresh tokens.
- Postgres FORCE RLS on every PHI table — tenant isolation enforced at the query layer.
- `pgcrypto` envelope encryption: master key wraps per-circle Data Encryption Keys.
- TLS 1.3 for transport, AES-256-GCM for at-rest E2EE document data (client-side keying via iCloud Keychain).
- Append-only audit log for every PHI mutation.
- Backend secrets sourced from environment variables only, validated at boot.
- Containerized backend with non-root execution, read-only filesystem where possible.

## Disclaimer

CareCircle is a record-keeping and coordination tool, not a medical device. It is not marketed as HIPAA-compliant. Implementers planning to use CareCircle in a regulated context must conduct their own compliance review and execute the appropriate agreements with Viral Venture LLC.

## Contact

- Security disclosure: `security@viral-ventures-llc.com`
- Legal: `legal@viral-ventures-llc.com`
- Company: Viral Venture LLC, Maple Grove, Minnesota, USA — [viral-ventures-llc.com](https://viral-ventures-llc.com)
