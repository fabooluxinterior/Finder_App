# Finder

A private social connection network for Kerala: Bumble-style swiping on top of Instagram-style private profiles. Built with Flutter, Supabase and RevenueCat.

- **Swipe right** sends a follow request. **Swipe left** hides the profile for 7 days. **Swipe up** (or tap ⭐) attaches a 100-character Direct DM Invite (Fast-Track only).
- Public cards show name, age, city, bio and the primary photo. The photo grid and interests stay locked until the request is accepted. RLS enforces this, not just the UI.
- Chat (text + 45 s voice notes) unlocks only after the receiver taps **Accept Follow**, or when both people request each other.
- `FLAG_SECURE` is set on the Android window, so screenshots, screen recording and Recents previews are blocked everywhere in the app.
- Phone numbers, @handles and URLs are stripped from bios, notes and opening messages on the client. The database rejects them in bios and notes too.
- **Chats are end-to-end encrypted** (Olm / Double Ratchet via the audited `vodozemac` Rust library). Photos are validated, stripped of EXIF/GPS, moderated, and stored AES-256-GCM encrypted. Two-step verification, device and session management, block/report with consent-based evidence, and a staff dashboard with an audit trail are included. See **[SECURITY.md](SECURITY.md)** for the full architecture, its known limitations, and the tests. It has not yet been independently audited.

## Try it on your phone (no store publishing)

The app runs in a **demo mode** with offline sample data whenever it's built without Supabase keys. Any 6-digit code logs you in, and the ₹79 purchase is simulated.

1. **Android APK:** every push runs the `Android APK` workflow (`.github/workflows/android-apk.yml`). Open the run under **Actions**, download the `finder-apk` artifact, unzip it, and install `finder-demo-arm64.apk`. Your phone will ask you to allow installs from your browser or file manager. Use `finder-demo-armv7.apk` on older 32-bit phones.
2. **Locally:** `flutter run` with a phone plugged in (USB debugging on), or `flutter build apk --release`.

## Building

You need Flutter 3.47 and a Rust toolchain (`rustup`). The Android build compiles the Rust crypto core automatically through cargokit (`rust_builder/`). For the web app, also run `flutter_rust_bridge_codegen build-web --release` and serve with the headers in `web/_headers`.

## Project layout

```
lib/
  main.dart                    picks the Supabase or demo backend
  app.dart                     auth gate: login → profile setup → home
  providers.dart               Riverpod providers (feed, requests, premium, chat)
  core/                        config, theme, contact sanitizer, shared widgets, media auth headers
  security/                    E2EE engine, keystore-backed storage, encrypted local message vault
  src/rust/                    generated Dart bindings for the Rust crypto core
  models/                      PublicProfile, PrivateProfile, FollowRequest, ChatMessage
  data/
    backend.dart               FinderBackend interface
    supabase_backend.dart      production: RPCs, RLS-backed queries, Realtime, E2EE messaging, secure uploads
    demo_backend.dart          offline demo that mirrors the server rules
    media_service.dart         JPEG pre-compression (server re-encodes to 800×800 WebP) and AAC-LC voice recorder
    purchases_service.dart     RevenueCat (fast_track_79_monthly), plus a demo stub
  features/
    auth/                      phone / email OTP
    onboarding/                profile setup (primary photo, locked grid, interests)
    deck/                      swipe deck, card, Direct DM Invite sheet
    requests/                  Pending Requests (blurred for free users) and Mutual Connections
    chat/                      real-time thread, voice recorder with waveform, playback
    paywall/                   ₹79 Fast-Track bottom sheet
    profile/                   private profile view, own profile
    security/                  MFA, devices & sessions, delete account, safety numbers
    safety/                    block, unmatch, report (with consent screen)
    admin/                     staff dashboard: security events, reports, photo review
rust/                          finder_crypto: vodozemac + AES-256-GCM wrapper (with tests)
supabase/
  migrations/20261107000000_init_finder.sql   schema, RLS, RPCs, storage, realtime
  migrations/20261108000000_security.sql      E2EE keys/envelopes, encrypted media, blocks, reports, staff, audit, rate limits
  functions/process-image/                    upload validation, EXIF strip, moderation, encryption
  functions/media/                            authorised, decrypting image delivery
  functions/delete-account/, media-maintenance/, revenuecat-webhook/
  tests/                                      SQL attack-scenario suites (run.sh)
  config.toml                                 auth hardening: token TTL, rotation, MFA, rate limits
android/app/src/main/kotlin/com/finderapp/finder/MainActivity.kt   FLAG_SECURE
```

## Going live

### 1. Supabase

```bash
supabase link --project-ref <ref>
supabase db push                                    # applies both migrations
supabase secrets set --env-file supabase/functions/.env   # values per .env.example
supabase functions deploy process-image
supabase functions deploy media
supabase functions deploy delete-account
supabase functions deploy media-maintenance
supabase functions deploy revenuecat-webhook --no-verify-jwt
```

In the dashboard: enable **Phone** (with an SMS provider such as Twilio or MSG91) and/or **Email OTP** under Auth → Providers. The email template must include `{{ .Token }}` so users get a 6-digit code.

### 2. Google Play + RevenueCat

1. In Play Console, create the subscription `fast_track_79_monthly` (₹79 / month). Play Billing offers UPI, Google Pay and cards automatically for INR.
2. In RevenueCat, add the Play app, create the entitlement **`fast_track`**, attach the product, and put it in the current offering.
3. Webhook: URL `https://<ref>.supabase.co/functions/v1/revenuecat-webhook`, with Authorization header `Bearer <REVENUECAT_WEBHOOK_AUTH>`.

The app calls `Purchases.logIn(<supabase user id>)`, so webhook events map straight to `profiles.id`.

### 3. Build

```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<publishable key> \
  --dart-define=REVENUECAT_ANDROID_KEY=<goog_...>
```

Add the same three values as repository secrets (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `REVENUECAT_ANDROID_KEY`) and the workflow also produces `finder-live-arm64.apk`.

Before a Play Store release, replace the debug signing config in `android/app/build.gradle.kts` with your upload key.

## How the rules are enforced

| Rule | Where |
|---|---|
| 10 follow requests / rolling 24 h for free users | `tg_swipes_before_insert` trigger (`hint = SWIPE_LIMIT`) |
| Direct note needs Fast-Track; ≤100 chars; no contact info | trigger + `swipes_note_clean` check |
| Pass hides a profile for 7 days | `get_feed` filter; `swipe_profile` clears expired passes |
| Free users can't see who requested them | `swipes_select` policy hides pending rows unless `is_premium()` |
| Mutual swipe = instant match | `swipe_profile` accepts the reverse request |
| Only the receiver can accept/reject, only once | update policy + `tg_swipes_before_update` |
| Chat only between accepted connections | `messages_*` policies via `is_connected()` |
| Locked grid and interests | `profile_private` RLS + `avatars/<uid>/gallery/*` storage policy |
| Users can't grant themselves premium | column-level `UPDATE` grant excludes `is_premium` |
| Kerala City Boost | `get_feed` ordering: premium + same city first |

These rules and the security layer are covered by the SQL suites in `supabase/tests/`, which run against Postgres 16 with Supabase's `auth` / `storage` schemas stubbed. CI runs them on every push.

### Note on voice-note size

45 s of AAC-LC at 32 kbps is about 176 KB, so it can't also stay under 120 KB. The recorder uses the requested 32 kbps / 45 s, and the `voice_notes` bucket limit is 192 KB. If the 120 KB cap matters more, set `AppConfig.voiceBitRate` to `20000` and the bucket limit to `122880`.
