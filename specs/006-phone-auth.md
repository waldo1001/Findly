# 006 — Phone-number-only sign-in (Firebase Phone Auth)

## Goal

Replace email/password sign-in entirely with **phone-number sign-in** (SMS one-time code): the phone number *is* the account, WhatsApp-style — no passwords, no email, no other providers. This spec owns the normative sign-in flow (state machine, normalization, error catalog), the dev-mode behavior, the Firebase project requirements, and the abuse/cost posture. Wire shapes stay in [001](001-api-contract.md) (this feature changes none); platform implementation detail lives in [003 §7](003-android-client.md) / [004 §4](004-ios-client.md), which reference this spec instead of duplicating it.

RFC 2119 keywords (MUST/SHOULD/MAY) are used normatively.

## 1. Product decision & scope

- **Providers, exhaustively: Phone.** Email/Password, Google, and every other Firebase sign-in provider MUST remain disabled in the Firebase project. There is exactly one way into the app.
- The backend is untouched: server-side verification (001 §2.2) checks `iss`/`aud`/signature/`exp`/`iat`/`sub` only, and Firebase Phone Auth issues ID tokens with the identical shape — **the sign-in provider is invisible to the wire contract**.
- The app is pre-launch; all existing accounts are developer test accounts. Switching providers is done as a one-time **account reset** (§8), not a migration. No email→phone migration path exists, and none may be built.
- A lost or changed phone number is a **new account** (new `uid`): the person is re-invited to their family/groups; data under the old `uid` is orphaned until normal retention/removal handles it. Accepted v1 behavior (product-owner decision, 2026-07-21); an account-linking/number-change flow would need its own spec (000 §Open Items).

## 2. Identity

- `userId` remains the opaque Firebase `uid` (001 §1.4). The ID token's `phone_number` claim is **not read, returned, or stored** server-side in v1 — no endpoint needs it (display identity comes from `displayName`; invites/joins use codes, not phone lookup), and phone numbers — including children's — are new PII with GDPR surface (000 §O7) for zero v1 feature benefit. Surfacing it later is purely additive (`VerifiedToken` gains an optional field; no wire change until an endpoint uses it) — tracked in 000 §Open Items.
- Phone numbers are **PII handled only by the Firebase SDK on-device**: clients MUST NOT send the phone number to the Findly backend, log it, or persist it outside what the Firebase SDK itself stores.

## 3. Phone-number normalization (E.164)

Normative rules, implemented as an identical pure function on each platform (`PhoneNumberNormalizer`, 003 §7 / 004 §4). Applied to user input before any provider call:

1. Strip spaces, dashes, dots, and parentheses.
2. A leading `00` becomes `+` (international dialing prefix).
3. A leading single `0` with no `+` becomes `+32` + rest — the **Belgium-centric convenience default** (the input field is prefilled with `+32`; there is no country picker — anyone abroad types their own `+xx`).
4. The result MUST match `^\+[1-9]\d{6,14}$` (E.164), else the input is rejected **client-side** with the `INVALID_PHONE_NUMBER` message (§4.2) and **no provider call is made**.

## 4. Sign-in flow

### 4.1 State machine (normative for both platforms)

Two-step, single screen: phone entry → code entry. Six-digit SMS code. Resend allowed only after a **30 s** cooldown, counted from `CodeSent`.

```
EnteringPhone(error?)                          ── initial state
  └─ submit → normalize (§3)
       ├─ invalid  → EnteringPhone(error = INVALID_PHONE_NUMBER)   [no provider call]
       └─ valid    → SendingCode(phone)         [provider: start verification]
SendingCode(phone)
  ├─ code sent            → EnteringCode(phone, resendSecondsLeft = 30)
  ├─ completed (Android instant verification, §4.3) → signed in
  └─ failed(error)        → EnteringPhone(error)
EnteringCode(phone, resendSecondsLeft, error?)
  ├─ submit code (6 digits) → ConfirmingCode(phone)   [provider: confirm code]
  ├─ resend (only at resendSecondsLeft == 0) → SendingCode(phone)   [same number ⇒ resend]
  ├─ completed (Android auto-retrieval, §4.3) → signed in
  └─ change number → EnteringPhone
ConfirmingCode(phone)
  ├─ success       → signed in
  ├─ INVALID_CODE  → EnteringCode(phone, error)       [stay; cooldown unaffected]
  ├─ CODE_EXPIRED  → EnteringPhone(error)             [must request a new code]
  └─ other error   → EnteringCode(phone, error)
```

"Signed in" means the platform auth state (003 `AuthState.SignedIn` / 004 `currentUserId != nil`) flips — navigation reacts to that, never to a screen-local success flag (existing pattern, 003 §7).

- Re-invoking "start verification" with the **same number** while a verification is in flight is a **resend**; the provider reuses its internal resend token. Verification session state (`verificationId`, resend token) is provider-internal and MUST NOT cross the platform `AuthProvider`/`AuthProviding` interface.
- The 30 s resend cooldown is UX pacing, **not** a security control (§7).

### 4.2 Error catalog (normative — raw SDK text never reaches a screen)

Each platform maps Firebase SDK failures onto this closed set; the v1 user-facing messages are fixed English (000 §O8):

| Error | Meaning | User message (v1) |
|---|---|---|
| `INVALID_PHONE_NUMBER` | Failed §3 validation, or provider rejected the number | "That doesn't look like a valid phone number." |
| `TOO_MANY_REQUESTS` | Firebase per-device/number throttling | "Too many attempts. Wait a while and try again." |
| `SMS_QUOTA_EXCEEDED` | Project SMS quota exhausted | "SMS limit reached for now. Try again later." |
| `APP_VERIFICATION_FAILED` | Play Integrity / App Attest / reCAPTCHA / APNs app verification failed | "Couldn't verify this device. Update the app and try again." |
| `INVALID_CODE` | Wrong SMS code | "That code isn't right. Check the SMS and try again." |
| `CODE_EXPIRED` | Verification session / code expired | "That code expired. Request a new one." |
| `NETWORK` | No connectivity to Firebase | "No connection. Check your network and try again." |
| `UNKNOWN` | Anything else | "Couldn't sign in. Try again." |

### 4.3 Platform asymmetry (normative)

- **Android** supports *instant verification / SMS auto-retrieval*: the provider MAY complete sign-in without the user typing a code, from either `SendingCode` or `EnteringCode`. Both transitions are mandatory in the Android state machine (003 §7).
- **iOS** has no instant verification; the code is always typed (autofill from the SMS via the system keyboard MAY fill it). iOS app verification uses **silent APNs push** with a reCAPTCHA web fallback — prerequisites in §6; on the simulator, only test phone numbers (§6) work.

## 5. Dev mode (`AUTH_MODE=insecure-local`)

The backend's insecure-local verifier (001 §2.3) is unchanged. The client dev providers (003 `DevAuthProvider`, 004 `StubAuthProvider`) MUST implement the same two-step shape so the phone UI is exercised locally:

- "Start verification" validates the normalized number (§3) and immediately reports code-sent (no SMS, no Firebase).
- "Confirm code" accepts **any non-blank code** and signs in with `uid = <normalized E.164 number>` (e.g. `+32470000001`) — the phone-shaped analogue of the previous "uid = email" dev shortcut.
- The bearer token stays an **unsigned JWT** with base64url JSON header/payload carrying `iss`/`aud`/`sub`/`iat`/`exp` (`sub` = the E.164 uid) and an empty signature — parseable by the backend's insecure-local verifier. (iOS note: `StubAuthProvider`'s previous non-JWT token shape is corrected to this as part of the same change — 004 §4.)

No literal token or real-looking phone number is ever committed; docs and tests use obviously fictional `+3247000000x` values.

## 6. Firebase project requirements (normative; runnable steps live in `docs/azure-setup.md` §3)

1. **Blaze plan** (pay-as-you-go) — Phone Auth SMS sending requires it. A Cloud Billing **budget alert** (e.g. €5/month) MUST be configured.
2. **Sign-in providers**: Phone **enabled**; Email/Password and all others **disabled**.
3. **SMS region policy — two operating modes** (product-owner decision, 2026-07-22; supersedes the fixed BE/NL/FR/DE/LU allowlist of 2026-07-21):
   - **Family mode** (launch default, in effect now): allow-list exactly the countries of current real users (initially BE, NL; others added only when a real user needs one, never preemptively). The allowlist is the primary SMS-pumping / toll-fraud guardrail in this mode.
   - **Open mode** (convention operation — attendees join from unpredictable countries, 007): **all regions allowed**. Entering open mode REQUIRES, in this order: (1) App Check enforcement (§6.5) is **ON — not monitor mode** — for Authentication on both platforms; (2) the Cloud Billing budget alert (§6.1) raised to **€25/month**. In open mode, device attestation replaces geography as the abuse control. Open mode is entered once and kept (no per-event toggling — a re-install or late sign-in must never mysteriously fail); re-narrowing to family mode is the **incident response** (§7), not routine operation.
   - Normative ordering: regions beyond family mode MUST NOT be opened while App Check is in monitor mode.
4. **Test phone numbers** (Authentication → Phone → testing): fictional numbers with fixed OTPs for dev, E2E, and store review. The enabled number/code pairs live **only in the Firebase console** — an enabled test pair is a working credential and MUST never be committed (docs use fictional placeholders).
5. **App Check**: Android → **Play Integrity** (requires debug + release SHA-256 fingerprints on the Firebase Android app registration; re-download `google-services.json` after adding them); iOS → **App Attest** (DeviceCheck fallback). Enforcement for Authentication is turned on only after both apps demonstrably sign in (monitor first, then enforce).
6. **iOS APNs**: the APNs auth key upload to Firebase is a **phone-auth prerequisite** (silent-push app verification), not only an FCM-routing step. The reCAPTCHA fallback additionally requires the `REVERSED_CLIENT_ID` custom URL scheme in the app target's Info.plist.

## 7. Abuse & cost posture

- **Server-side: nothing changes.** The backend never participates in the SMS flow; 001 §2 verification and the storage-read enforcement boundary (001 §1.5/§2.4) are the same for phone-auth tokens. `RATE_LIMITED` stays reserved.
- v1 relies on (and documents here as the deliberate posture): Firebase's built-in per-number/per-device/per-project SMS quotas and abuse detection; device attestation via App Check (§6.5); and the **SMS region policy** (§6.3) — the allowlist bounds the toll-fraud blast radius in family mode; in open mode that role passes to **enforced App Check** (which is why enforcement is a hard precondition). No additional client or server throttling is implemented; the §4.1 resend cooldown is UX, not security.
- **Open-mode incident runbook (normative SHOULD):** if the budget alert fires or Firebase Auth usage looks anomalous — (1) immediately re-narrow the SMS region policy to family mode (one console change); (2) inspect Firebase Authentication usage and App Check metrics to identify the vector; (3) re-open only together with a further mitigation. Re-narrowing strands no one already signed in (refresh tokens keep working); it only pauses *new* sign-ins from outside the family allowlist.
- **Cost:** SMS verifications are billed per message (order of $0.01 US / $0.06+ Belgium-EU). Sign-ins are rare — Firebase refresh tokens keep a device signed in indefinitely until sign-out or uninstall — so family-and-friends-scale cost is cents/month, and a convention of ~200 worldwide sign-ins is a one-time ~$2–12. The 000 cost target ("a few euros/month") is unaffected. The region policy and the (open-mode: €25) budget alert are the guardrails.

## 8. Account reset (pre-launch, one-time)

The app has never launched; every existing account is a developer test account. Switching the identity provider migrates nothing: uids minted by email/password sign-in become permanently unreachable once that provider is disabled. Rather than mapping accounts, we reset: delete all users in Firebase Console → Authentication, and wipe all test data in the storage account (all rows in the 002 §2 tables and all `history/`/`events/` blobs; deleting and recreating tables/containers is the fastest honest way). No code supports, and no code should ever support, an email→phone migration path.

Note: the `emailHint` field on family invites (001 §3.3) deliberately keeps its name — it is optional, recorded-only (000 §O5), and renaming it would be a wire change for cosmetics.

## 9. Error cases

No new 001 §10 error codes: the sign-in flow fails **client-side against Firebase**, before any Findly API call. The closed client-side error set is §4.2. Backend auth errors (`AUTH_MISSING_TOKEN`, `AUTH_INVALID_TOKEN`, `AUTH_TOKEN_EXPIRED`) keep their existing 001 §10 semantics and client handling (refresh-and-retry-once, 001 §2.1).

## 10. Test checklist (conforming clients — pure-logic tests, no Firebase SDK in unit tests)

- Normalizer (§3, per platform): separators stripped; `00` → `+`; bare `0…` → `+32…`; already-`+` input untouched; E.164 regex acceptance/rejection edge cases; invalid input produces `INVALID_PHONE_NUMBER` **without any provider call**.
- State machine (§4.1, per platform): every transition, including happy path phone → code-sent → code → signed-in; every §4.2 error landing in its specced state with its specced message; `INVALID_CODE` stays on code entry; `CODE_EXPIRED` returns to phone entry; change-number returns to phone entry.
- Resend: blocked until the 30 s cooldown reaches 0 (virtual-time tested), then re-invokes start-verification exactly once with the same number.
- Android only: instant-verification completion from both `SendingCode` and `EnteringCode`.
- Dev providers: two-step shape; any non-blank code signs in; `uid` = normalized E.164; emitted token is an unsigned JWT whose payload parses as base64url JSON with `sub` = the uid.
- Invariant: no unit test imports the Firebase SDK; no test or doc contains a real-looking phone number or a test-number/OTP pair.

## Open questions

None — residual product matters (phone-number surfacing on rosters, account-linking for number changes) are tracked in 000 §Open Items with v1 behavior fixed by this spec.
