# Apple Developer Program Enrollment — WonderDot

**Status:** Enrollment is official and paid for (confirmed by Sam, 2026-09-11). Nothing done past payment yet — App Store Connect API key, Codemagic Apple Developer Portal connection, and the WonderDot iOS app record still need to be created.
**Apple case number:** 102934635272 (Shanda, Developer Support) — presumably moot now enrollment went through, but kept here for reference.
**Enrolling account:** `sam@mean-dream.com`

---

## Why this blocks the repo

`codemagic.yaml` has an `ios-release → TestFlight` workflow that cannot run until this enrollment completes. Its prerequisites all depend on an active membership:

- App Store Connect API key (Users & Access → Keys)
- Codemagic → Team → Integrations → Apple Developer Portal connection
- The WonderDot iOS app record created in App Store Connect
- iOS distribution signing (`distribution_type: app_store`)

Android is unaffected. iOS builds stay blocked until membership is active.

---

## Root cause (diagnosed 1 Aug 2026)

Enrollment failed repeatedly with:

> We are unable to process your request. An unknown error occurred.

**The account region did not match the phone number.** `sam@mean-dream.com` was created in France, so its region was **France**, while the phone number is Dutch (**+31 6 43060702**). Apple requires the trusted phone number's country code to match the account region, and returns a silent 403 rendered as a generic error rather than saying so.

Two red herrings along the way:

- *"I can't add my phone number, it's already used by my other account."* — Not a duplicate-number rule. A number **can** be trusted on multiple Apple Accounts. It was the region check rejecting a +31 number on a France-region account. Once the region was NL, the number was accepted immediately.
- *The driving licence.* Old French paper licences routinely fail automated ID checks. Use the **passport**.

Deliberately **not** solved by enrolling with `samuel@emilefoundation.org` — that account is NL-region and holds the same number, but Emile Foundation must stay separate from Mean-Dream.

---

## Done

- [x] Region changed France → **Netherlands**
- [x] Account balance zero, no subscriptions, no purchases since 2024
- [x] `sam@mean-dream.com` removed from Family Sharing
- [x] **+31 6 43060702 added as trusted phone number** — accepted, confirming the diagnosis

## Remaining

- [x] Wait for `developer.apple.com` maintenance to end
- [x] Sign in as **`sam@mean-dream.com`** — *not* the foundation ID
- [x] Payment and shipping: **NL address + NL payment method**
- [x] `developer.apple.com/programs/enroll` — agreements accepted
- [x] Enrolled as **Individual**, **passport** as ID, **no VPN** — membership is active and paid
- [ ] Create App Store Connect API key (Users & Access → Keys)
- [ ] Connect Codemagic → Team → Integrations → Apple Developer Portal
- [ ] Create the WonderDot iOS app record in App Store Connect
- [ ] Confirm `codemagic.yaml`'s `ios-release → TestFlight` workflow actually runs end to end now that the prerequisites above are in place

---

## Enrollment type decision

**Individual, not Organization.** Apple only accepts Organization enrollment from a legal entity; a sole proprietorship isn't one, so an eenmanszaak must enroll as an Individual (and needs no D-U-N-S number).

**Consequence:** the App Store seller name will be *Samuel Lambert*, not *Mean-Dream*. App name, branding, website and marketing are unaffected.

**Reversible later.** Apple supports conversion via `developer.apple.com/contact/request/migrate-individual-account` — supply a D-U-N-S number, possibly business documents, then a verification call. Days to ~2 weeks. **It converts the same account**, so app listing, reviews, ratings and users are preserved. No reason to incorporate a BV before launch.

*Open question:* whether Apple allows an individual account to display a trade name. Unconfirmed — worth asking Support.

---

## If enrollment still fails

Don't retry blindly. Reply on case **102934635272** with the specifics, which is what escalates past the boilerplate:

> Region is Netherlands, trusted phone number +31 matches the region, billing address and payment method are both NL, no VPN, no pending agreements on the enrollment page — and I still get "We are unable to process your request. An unknown error occurred."

Fallback if the trusted number ever becomes contested again: a Dutch eSIM or VoIP number that can receive SMS, a few euros.

---

## References

- [Apple – Change your Apple Account country or region](https://support.apple.com/en-us/118283)
- [Apple – About trusted phone numbers and trusted devices](https://support.apple.com/en-us/122621)
- [Apple – D-U-N-S Number requirements](https://developer.apple.com/help/account/membership/D-U-N-S)
- [Cem Kiray – Fixing the Apple Developer "unknown error"](https://www.cemkiray.com/posts/how-to-fix-apple-developer-unknown-error-occured/)
