# Roadmap — Findly on the family's phones, via the stores

Written 2026-07-25. Goal: every family phone (Android + iPhone) installs Findly **through the store**, auto-updating. Detailed per-store checklists live in [`store-readiness.md`](store-readiness.md); this doc sequences everything into a critical path. Keep it updated as phases complete.

## Two milestones — the family doesn't wait for the public release

| Milestone | What it means | Store mechanism |
|---|---|---|
| **M1 — Family install** | Family phones install from the store infrastructure, before public release | iOS: **TestFlight** · Android: **Play internal/closed track** (a convenience for staged rollout — the 14-day closed-test obligation does **not** apply, the account is Organisation) |
| **M2 — Public release** | Production listings, anyone can install | App Store + Play production |

## Phase 0 — this week (human, ~1 h total)

1. ~~Commit specs/008~~ → PR + merge (spec commit before implementation, per process).
2. **Firebase tail on `findly-71f7b`** (the H2 pieces that didn't carry over in the rename, found during the 2026-07-25 smoke test): Blaze plan + budget alert (€5), SMS region allowlist **BE, NL** (family mode). Without this, real-number sign-in fails; test numbers work regardless.
3. ~~Check the Play account rule~~ **RESOLVED 2026-07-25:** `waldo1001` is an **Organisation** account under **Dynex bv** → **exempt** from the 12-tester/14-day closed-test requirement, and the required D-U-N-S already exists. The largest fixed delay to M2-Android is gone; the closed track is now purely an M1 convenience, not an obligation.
4. ~~Chase Apple enrollment~~ **RESOLVED 2026-07-25:** already complete (Team ID `92A2K3Q7NH`, verified live in the served AASA). Apple is not a blocker; see Phase 4.
5. **Google Maps API key** for Android (the `MAPS_API_KEY` plumbing already exists; mobile-native dynamic maps are $0 on Google's pricing — key restricted to the app's package + SHA-256). iOS needs nothing (MapKit, keyless).

## Phase 1 — device-runtime wave (the unscheduled gap; backlog A9–A12 / I9–I12)

**Finding (2026-07-25, verified in code):** all 001-contract and screen work is done, but the on-device runtime is scaffolded — the app cannot yet *track* on a real phone. This is the largest remaining coding block and gates *both* M1s. Runs in parallel with Phase 2; `/dev-loop` + Sonnet territory. Spec seams already exist (003 §9–§11, 004 §6–§7) — tasks reference them; pin any unpinned runtime detail in the spec first, per process.

| Task | Scope | Spec |
|---|---|---|
| A9 | Real FCM: `FirebaseMessagingService`, real `PushTokenProvider` (replaces stub), handlers for the four §8 push types, token-refresh re-registration | 003 §9, 001 §8 |
| A10 | Real tracking: fused location capture, WorkManager periodic wiring (§10.5 TODO), foreground service for 5/10-min intervals, Room-backed `FixQueueStore` (replaces in-memory) | 003 §10, 000 §O2 |
| A11 | Platform geofencing: `GeofencingClient` registration from synced config, transition → §7.3 reporting + `source:"geofence"` fix | 003 §11, 001 §7 |
| A12 | Real map renderer (Google Maps SDK) behind the existing `MapRenderer` seam (replaces `PlaceholderMapRenderer`) | 003 §12 |
| I9 | The `.xcodeproj` app target (long-standing item; `ios-build` CI stub becomes real) — everything iOS-on-device hangs on this | 004 §1.1 |
| I10 | Real location: `CLLocationManager` conformance to `LocationProviding`, background delivery, persistent fix store (replaces in-memory) | 004 §6–§7, 000 §O2 |
| I11 | Region monitoring (20-region cap) + transition reporting | 004 §7, 000 §O9 |
| I12 | Push registration + handling (FCM-routed APNs); Location Push token plumbing stays dormant until O1 | 004 §7, 001 §8 |

Estimate at the project's demonstrated pace: **1–3 weeks calendar**, Android and iOS parallelizable.

## Phase 2 — privacy wave (store hard gate; specs/008 — already authored)

`B17` (export) / `B19` (family delete) → `B18` (account delete, needs B19) → `W2` (web `/delete-account` page) + `A8`/`I8` (client UIs) + **H9** (human: Firebase web app, CORS, authorized domain). ~**1 week** of `/dev-loop`; independent of Phase 1. Play's data-safety form needs W2's live URL before submission.

## Phase 3 — Android store track (H5; starts now, human + waits)

1. Release keystore + **Play App Signing** enrollment; 4 GitHub secrets (store-readiness §1.3); app-signing SHA-256 → Firebase registration + `assetlinks.json`.
2. Upload the first release to the **internal test track** (instant, no review) and add the family as testers → **M1-Android reached here.** No minimum tester count, no waiting period — the Organisation account is exempt.
3. Background-location declaration + prominent-disclosure video; data-safety form (needs Phase 2's URL); content rating; listing assets; test-number sign-in notes for review.
4. Play review (the background-location declaration is the slow part) → promote to production → **M2-Android**.

## Phase 4 — Apple store track (H6; **startable now — enrollment is already complete**)

> Corrected 2026-07-25: earlier drafts of this roadmap (and H6/store-readiness §2) treated Apple enrollment as a pending wildcard. It is **done** — Team ID `92A2K3Q7NH`, verified live in the served AASA. Apple is no longer the schedule risk it was listed as; the iOS critical path is **I9 (`.xcodeproj` app target)** plus the portal tail below, all of which can start today.

1. ~~Team ID~~ **done**; AASA already complete and serving. Activate Associated Domains (I6 prepared it), **upload the APNs key to Firebase** (unblocks on-device iOS phone sign-in *and* iOS App Check → H8), register iOS App Check (App Attest).
2. **Apply for the Location Push entitlement immediately** (000 §O1) — independent Apple lead time; *not* an M1/M2 blocker (locate ships best-effort without it).
3. App Store Connect app + **TestFlight** upload (needs I9 + I10/I12 minimum) → family iPhones install → **M1-iOS reached here.**
4. Privacy nutrition labels (mirror data-safety), age rating, purpose strings, review notes → App Review → **M2-iOS**.

## Phase 5 — go live for the family

1. **Account reset** (006 §8, one-time): delete all Firebase test users, wipe test data in storage — *before* the family signs in for real.
2. Family onboarding: parent creates the family, invites via codes, geofences (Home, School…), per-device intervals.
3. H8 (App Check enforce → open SMS mode) is **not** on this roadmap — it gates convention/open-mode operation, not family use. Family mode's BE/NL allowlist suffices.

## Critical path & honest estimates

```
M1-Android =  Phase 1 (Android half) + keystore/closed-track upload          ≈ 2–4 weeks
M1-iOS     =  Phase 1 iOS (I9 .xcodeproj + I10/I12) + portal tail + TestFlight
                                                                             ≈ 2–4 weeks (enrollment DONE — not a blocker)
M2         =  M1 + Play 14-day clock (if applicable) + both store reviews    ≈ 4–8 weeks
```

Assumptions: current session pace continues; estimates are calendar, not effort. Everything schedulable-by-us lands in Phases 0–2 within ~2–3 weeks.

**Biggest schedule risks, in order:** (1) **Play's 12-tester/14-day closed-test rule** — applies to personal accounts created on/after 2023-11-13, and it is now the single largest fixed delay on the path to M2-Android; an **Organization** account is exempt but needs a D-U-N-S number (check whether the existing Apple enrollment is an Organization one — if so the D-U-N-S already exists and is reusable). (2) Play background-location review rejection — **the earlier mitigation here was false and is corrected**: it claimed "the 003 §11 / 009 §7 disclosure flow already matches policy", which was true of the *spec* and false of the *code* — no disclosure screen or denial banner existed on either platform until 2026-08-05, and both codebases admitted it in TODOs. The policy, storage and UI now exist; what remains is wiring them into each app's permission request path and recording the demo video of that flow. (3) Device-runtime wave hitting real-device surprises (battery/scheduling behavior no test suite catches) — mitigate: M1 on the family's own phones *is* the field test, weeks before M2. **No longer a risk:** Apple enrollment (complete).
