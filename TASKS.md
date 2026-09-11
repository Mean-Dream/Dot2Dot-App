# Tasks

## Active
- [ ] **Apple Developer Program enrollment is done (paid, official, confirmed by Sam 2026-09-11)** - see `docs/apple-developer-enrollment.md`. Not past payment yet though - still need: App Store Connect API key (Users & Access → Keys), Codemagic → Team → Integrations → Apple Developer Portal connection, and the WonderDot iOS app record created in App Store Connect. `codemagic.yaml`'s `ios-release → TestFlight` workflow needs all three before it can run.
- [ ] **[CHECK] Pan mode may not work in the dot editor** - found 2026-09-08. Selecting Pan (hand icon) in the editor, then dragging on the canvas, did not visibly pan and the toolbar snapped back to pencil/draw mode afterward. Could be a real bug (TC-039) or could be an artifact of automated-drag not matching Flutter's gesture recognizer - worth a 2-minute manual check (real mouse/touch drag in Pan mode) before treating as confirmed.
- [ ] **Finish the WonderDot pre-launch UX test plan - 95% done per Sam (2026-09-11), only P2s remain.** No longer at risk of the Sun 2026-09-13 deadline. 79 test cases (TC-001-TC-079) across 12 areas.
  - Plan: https://claude.ai/code/artifact/3a11de29-b4b8-40a5-81f0-eab708ce3e99
  - Could not update the pass/fail checkboxes in the tracker artifact itself - its embedded page didn't respond to scroll via browser automation. Results below are tracked here instead; ask Claude to bake them into the artifact as defaults (non-destructive merge with your existing marks) if useful, or mark them in the tracker directly.
  - Two items below (TC-063 paywall CTA, and the sample-gallery copyright check) are carved out as their own launch-blocking tasks even though they're part of this plan, since they feed directly into the launch sequence.

  **2026-09-08 automated pass results** (Claude, Mean-Dream browser, localhost:61394; Sam signed in manually since Claude does not enter credentials):

  Confirmed PASS: TC-001 (clean load, no console errors), TC-002 (onboarding slides advance via Next, progress dots update), TC-003 ("Get Started" -> consent screen), TC-006 (Analytics + Crash reports both default OFF), TC-007 (Save preferences w/ both off reaches home; only Supabase requests seen afterward, no Amplitude/Sentry), TC-023 (cosmic gradient home background), TC-024 (email shown in top bar), TC-025 (mode cards navigate correctly), TC-028 (gallery shows thumbnails + correct dot counts, no blank/spinner cards), TC-030 (dot counts correct on all visible projects - the old "0 Dots" bug was NOT seen, looks fixed), TC-035 (tapping a project opens the editor cleanly), TC-037 (background image visible under dots), TC-038 (numbered dots correctly positioned), TC-042/043/044 (Insert After: enters insert mode, shows amber ring + "After #N" label, inserts and advances anchor correctly), TC-045/046 (toolbar mode switching shows clear active/inactive state), TC-049 (difficulty picker not cut off, Play button reachable), TC-050 (correct dot count shown, e.g. "Connect 59 dots"), TC-051 (Easy mode starts, dot 1 highlighted as target), TC-052 (tapping dots in sequence advances progress), TC-057 (locked Medium tab shows "Medium Locked" dialog with clear reason + Upgrade CTA), TC-061 (upgrade copy names the difficulty and prerequisite specifically), TC-062 ("Not now" dismisses cleanly, picker still usable).

  TC-019 (forgot password crash) - was FAIL, now fixed and confirmed by Sam as of 2026-09-11 (see Done section).

  Borderline / worth a look: TC-013 - "Accept all" is a solid bright button, "Save my preferences" is outlined/less prominent on the consent screen - arguably nudges toward accepting all, worth a quick look for the dark-pattern check.

  Left a small test artifact: while testing Insert After on the "Design1" puzzle (T-Rex), added one extra dot (145 -> 146 dots) that wasn't cleanly undone - harmless but worth a glance if that puzzle's dot count looks off.

  Not yet tested (didn't get to these in this pass, still open): TC-004, TC-005, TC-008-012 (remaining consent combos + privacy policy link), TC-014-018/020-022 (auth flows needing real credentials - Claude won't type passwords), TC-020-022, TC-026/027 (console checks on home specifically), TC-029/031-034/036 (upload pipeline - needs real file picker), TC-039 (pan - see check item above), TC-040/041 (eraser, reveal mode), TC-047/048 (zoom, show-lines), TC-053-056/058-060 (wrong-dot flash, hints, completion state, pen-lift indicator, Hard-locked, small-screen scroll, exit-mid-game), TC-063 (upgrade CTA tap), TC-064-066 (network loss, rate limiting, empty-dots edge case), TC-067-076 (cross-browser/cross-device/performance/accessibility), TC-077-079 (smoke regression).

- [ ] **Remove/replace copyrighted sample puzzles in the starter gallery** - found during 2026-09-08 testing: a "Batman" puzzle (and likely other third-party-IP characters) is present in the sample/pre-made gallery. This is a real risk if it ships to app store reviewers or the public - both Apple and Google reject listings using unlicensed third-party IP, independent of any UX test case. Needs a review pass of every pre-made puzzle before step 1 (starter gallery) ships. Feeds into the launch plan below.
- [ ] **Paywall: verify store-side config + test the actual purchase flow end to end** - `purchases_flutter` (RevenueCat) is already integrated in `pubspec.yaml` (confirmed in code, 2026-09-11), which is the right approach - it wraps StoreKit/Play Billing so Apple/Google's IAP requirements are satisfied without custom payment code. But two things are NOT yet verified: (1) products/entitlements/offerings actually configured in App Store Connect + Play Console + the RevenueCat dashboard (lives outside the repo, can't be checked from code), (2) the purchase CTA itself (TC-063, "Upgrade to Premium" tap) was only tested as far as the locked-difficulty dialog UI - no real purchase was ever run end to end (needs a sandbox/test purchase, which needs real device + store test account). Do not treat "paywall done" as true until both are checked.
- [ ] **Google Play closed testing - sequence this early, it's not a one-shot step.** New/personal Play Console developer accounts require a closed test with 12 testers opted in continuously for 14 days before Production track access unlocks. This should start as soon as there's an installable build, in parallel with other launch prep, not after "everything else is ready" - otherwise it becomes the critical path.

## Launch plan (reviewed 2026-09-11, amending Sam's proposal - Sam confirmed 2026-09-11, working through it 1 by 1)
Sam proposed: 1) starter gallery (easy/medium/hard) 2) paywall setup 3) App Store setup + publish 4) Play Store setup + publish 5) advertising. Reviewed and amended - see chat for full reasoning. Amended sequence:
- [x] 1a. Apple Developer Program enrollment - done, paid, official (2026-09-11). Follow-up steps (API key, Codemagic connection, app record) tracked as their own item above.
- [ ] 1b. Kick off Play Store closed-testing enrollment now, in parallel with everything else - it has a 14-day clock that shouldn't sit on the critical path (see item above).
- [ ] 2. Build the starter gallery (easy/medium/hard) - AND screen every sample puzzle for third-party IP (Batman etc.) before it ships, since this content goes straight to app reviewers and the public.
- [ ] 3. Paywall - confirm store-side product/entitlement config in ASC + Play Console + RevenueCat dashboard, then run one real end-to-end test purchase (sandbox) before trusting it's "in place."
- [ ] 4. App Store: app record, metadata, screenshots, privacy nutrition label, age rating, submit for review. (Enrollment itself is no longer the blocker here - see 1a - but the ASC/Codemagic setup steps still are.)
- [ ] 5. Play Store: app listing, data safety form, content rating, submit closed test (see 1b), then promote to Production once the 14-day window is satisfied.
- [ ] 6. Final smoke-regression pass (test plan section 12, TC-077-079) on the actual release build right before each submission, not just the dev build.
- [ ] 7. Advertising - after both stores are live, ideally with a short staged-rollout / soft-launch window first rather than turning on spend the moment either app is approved.

## Waiting On

## Someday

## Done
- [x] ~~[P0 BUG] Fix "Send Reset Link" crash on the auth screen~~ (fixed and confirmed by Sam, 2026-09-11) - was: app crashed to a Flutter red error screen ("TextEditingController used after disposed") when sending a password reset link from the auth screen. TC-019.
