# WonderDot Web App — Pre-Launch Review
*First pass: localhost:8080, 1 Aug 2026. Re-tested: 2 Aug 2026, after fixes.*

## ✅ Fixed — verified on retest

**1. Layout overflow on the difficulty-picker "PLAY GAME" button — FIXED.**
Modal now renders clean, no `RenderFlex overflowed` error, button fully visible and clickable at the same viewport size that broke it before.

**2. Silent sign-in failure on wrong password — FIXED.**
Retested with a deliberately wrong password: now shows a clear red banner — "Wrong email or password. If you signed up with Google, use 'Continue with Google' instead." Good message, handles the OAuth case too.

**3. "Connect 0 dots" text bug — FIXED.**
Now correctly reads "Connect 104 dots to reveal the picture!" for the daily challenge.

**4. Locked "Hard" difficulty was a dead tap — FIXED.**
Now opens a proper "Hard Locked" modal: "Complete Medium first to unlock Hard, or go Premium to unlock all difficulties instantly," with an "Upgrade to Premium" CTA. Exactly what was missing — this is now doing real paywall-conversion work.

**5. Home screen visual inconsistency — FIXED.**
Editor Mode / Game Mode cards now use the same dark space theme as onboarding, with styled icon badges and descriptive subtext ("Create & edit puzzles" / "Play dot-to-dot puzzles"). No more jarring flip to flat white.

**6. Startup console errors — FIXED.**
No more `AuthException: No code detected in query parameters` or Flutter `Zone mismatch` on page load. Only remaining console noise is a Chrome-extension messaging error unrelated to your app — safe to ignore.

**8. GDPR pre-ticked consent toggles — FIXED (verified in code).**
Couldn't re-trigger the consent screen live (already granted for this test account), so I checked `consent_page.dart` directly: `_analytics` and `_crash` now both default to `false`. Opt-in behavior confirmed at the source.

## Still open (low priority)

**7. One puzzle in the gallery still shows "0 Dots."**
`peter-burdon-Co2_CN-10ks-unsplash` still sits in the "select puzzle to edit" list with 0 dots placed. This looks like leftover test data from manual editing rather than a code bug — worth a quick check that this can't happen from a real user's upload, then just delete the stray entry.

## Still not tested

**9. Photo-upload → puzzle-generation pipeline.** Still blocked by the native OS file picker, which browser automation can't drive. This is your core loop — please run it yourself end-to-end before submitting.

**10. Accessibility.** Not re-tested; still worth a future pass, not urgent for this timeline.

## Bottom line

Every blocker from the first pass is fixed and verified. Nothing left standing between here and store submission except the two items only you can test (#9, and Apple's approval). #7 is a five-minute cleanup whenever convenient.
