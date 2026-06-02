# CareCircle Privacy Policy

**Effective date: June 2, 2026**

CareCircle ("the app") is operated by Viral Ventures LLC ("we," "us," or
"our"). This policy explains what information CareCircle collects, how it is
used, how it is stored and protected, and the choices you have. By using
CareCircle you agree to this policy.

If you have questions, contact us at **support@viral-ventures-llc.com**.

---

## 1. What CareCircle is — and is not

CareCircle is a family-caregiving coordination app. It helps a group of family
members and trusted caregivers (a "Circle") organize medications, appointments,
daily check-ins, vitals, documents, and emergency information for a person
receiving care (the "Care Recipient").

CareCircle is a **record-keeping and coordination tool**. It is **not** a medical
device, not a medical service, and not a substitute for professional medical
advice, diagnosis, or treatment. Nothing in the app is medical advice — always
consult a qualified healthcare provider. CareCircle is **not marketed as, and
does not claim to be, HIPAA-compliant.**

---

## 2. Information we collect

We collect only what the app needs to coordinate care. You provide most of it
directly; some is created as you use the app.

**Account and authentication.** When you sign in we receive an identifier from
your chosen sign-in method:

- **Sign in with Apple** — a stable user identifier and, if you choose to share
  it, your name and email (which may be an Apple private-relay address).
- **Sign in with Google** — your Google account identifier, name, and email,
  obtained from a verified Google ID token.
- **Email and password** — your email address and a password, which we store
  only as a salted Argon2id hash. We never store your password in plain text.

**Care coordination data you enter.** Medications, doses, conditions, vitals,
appointments, daily journal/check-in entries (mood, symptoms, notes), care
minutes, and related notes about the Care Recipient.

**Contacts you enter.** Emergency contact names, phone numbers, and
relationships. These are entered manually; CareCircle does not import your phone
contacts.

**Content you create.** Activity-feed text, photos and documents you attach, and
voice handoff notes (the recorded audio and its transcript).

**Location — only when you use location features.** When you trigger an SOS,
the app captures your precise location (latitude, longitude, and accuracy) at
that moment so your Circle can reach you. Separately, you may opt in, per
Circle, to share live location; this is off by default and you can turn it off
at any time.

**Device permissions.** Depending on the features you use, the app may request
access to the microphone (voice notes), speech recognition (on-device
transcription), the camera (medication-label scanning), your calendar
(appointment mirroring), and location (SOS and opt-in live location). You can
grant or deny each of these in iOS Settings.

**What we do not collect.** CareCircle does not include third-party advertising
or analytics SDKs. We do not collect product-usage analytics, and we do not use
any third-party tracking. We do not collect identifiers for advertising.

---

## 3. How we use your information

We use your information solely to provide and operate CareCircle:

- To coordinate care within your Circle — show medications, schedules,
  appointments, vitals, journal entries, and activity to the members you share
  a Circle with.
- To send notifications you rely on, including medication reminders and SOS
  alerts.
- To authenticate you and keep your account secure.
- To generate on-device summaries and insights (see Section 5).

We do **not** sell your information, use it for advertising, or use it to build
advertising or marketing profiles.

---

## 4. How your information is stored and protected

**Apple CloudKit.** Your Circle's data is stored in Apple's CloudKit using your
iCloud account — in your private database, and, for shared Circles, in a shared
database that other Circle members can access. Each Circle is isolated in its
own record zone.

**Encryption.** Sensitive documents are encrypted on your device with AES-256-GCM
before they are uploaded, using a per-Circle key kept in your iCloud Keychain.
Data in transit is protected with TLS.

**Backend of record.** We operate a backend (hosted on Railway, using
PostgreSQL) that serves as a durable system of record and supports
cross-device sync. PHI tables enforce row-level security and per-Circle
envelope encryption, and access is recorded in an append-only audit log.

**AI processing providers.** See Section 5.

No method of electronic storage or transmission is perfectly secure, but we use
the protections described here to safeguard your information.

---

## 5. On-device intelligence and AI processing

CareCircle runs intelligence features (such as transcribing voice notes and
summarizing activity) **on your device first** wherever your device supports it.

When on-device processing is not available — for example, on older devices —
some transcription or text analysis may be performed by third-party AI providers
(such as OpenAI and Deepgram). Before any such data leaves your device, the app
removes the Care Recipient's and caregivers' names and replaces them with
neutral placeholders (for example, `[RECIPIENT]` and `[CAREGIVER_1]`). These
providers process the de-identified text to return a result and do not use it to
build profiles about you.

---

## 6. When information is shared

- **Within your Circle.** Information you add to a Circle is visible to the
  members of that Circle, according to each member's role.
- **Service providers.** We rely on infrastructure providers — Apple (CloudKit,
  push notifications), Railway (backend hosting), and the AI providers described
  in Section 5 — strictly to operate the app.
- **Legal reasons.** We may disclose information if required by law or to protect
  the safety of a person.
- **We never sell your data** and we do not share it with advertisers.

---

## 7. The Care Recipient's data

The Care Recipient's information belongs to the Care Recipient, not to the
caregiver who entered it. CareCircle is built so that this data can be exported
and deleted, and so that sharing happens with appropriate consent. A Care
Recipient never pays for CareCircle.

---

## 8. Your rights and choices

- **Access and export.** You can view your data in the app and request an export.
- **Correction.** You can edit or delete entries you have permission to change.
- **Deletion.** You can delete your account and associated data. Deleting your
  account removes your data from our backend of record; data stored in your own
  iCloud account is governed by Apple's CloudKit and your iCloud settings.
- **Permissions.** You can change microphone, speech, camera, calendar, and
  location permissions at any time in iOS Settings.
- **Notifications.** You can manage notification permissions in iOS Settings.

To make a request, contact **support@viral-ventures-llc.com**.

---

## 9. Data retention

We retain your information for as long as your account is active or as needed to
provide the app. When you delete your account, we delete the associated data
from our backend of record, except where we are required to retain certain
records by law. Audit-log records may be retained for security and integrity.

---

## 10. Children's privacy

CareCircle is intended for adults coordinating care. It is not directed to
children under 13, and we do not knowingly collect personal information from
children under 13. If you believe a child has provided us information, contact
us and we will delete it.

---

## 11. Tracking

CareCircle does not track you across apps or websites owned by other companies,
and does not share your information with third parties for tracking purposes.
Our app privacy manifest declares that the app does not use tracking.

---

## 12. International users

CareCircle is operated from the United States. If you use the app from outside
the United States, your information may be processed in the United States and in
the regions where our service providers operate.

---

## 13. Changes to this policy

We may update this policy from time to time. When we do, we will revise the
"Effective date" above and, for material changes, provide notice in the app.
Continued use of CareCircle after a change means you accept the updated policy.

---

## 14. Contact us

Viral Ventures LLC
Email: **support@viral-ventures-llc.com**
