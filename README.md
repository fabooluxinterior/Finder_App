# Finder

A private social connection network for Kerala: Bumble-style swiping on top of Instagram-style private profiles. Built with Flutter, Supabase and RevenueCat.

- **Swipe right** sends a follow request. **Swipe left** hides the profile for 7 days. **Swipe up** (or tap ⭐) attaches a 100-character Direct DM Invite (Fast-Track only).
- Public cards show name, age, city, bio and the primary photo. The photo grid and interests stay locked until the request is accepted. RLS enforces this, not just the UI.
- Chat (text + 45 s voice notes) unlocks only after the receiver taps **Accept Follow**, or when both people request each other.
- `FLAG_SECURE` is set on the Android window, so screenshots, screen recording and Recents previews are blocked everywhere in the app.
- Phone numbers, @handles and URLs are stripped from bios, notes and opening messages on the client. The database rejects them in bios and notes too.

## Try it on your phone (no store publishing)

The app runs in a **demo mode** with offline sample data whenever it's built without Supabase keys. Any 6-digit code logs you in, and the ₹79 purchase is simulated.

1. **Android APK:** every push runs the `Android APK` workflow (`.github/workflows/android-apk.yml`). Open the run under **Actions**, download the `finder-apk` artifact, unzip it, and install `finder-demo-arm64.apk`. Your phone will ask you to allow installs from your browser or file manager. Use `finder-demo-armv7.apk` on older 32-bit phones.
2. **Locally:** `flutter run` with a phone plugged in (USB debugging on), or `flutter build apk --release`.

## Project layout

```
lib/
  main.dart                    picks the Supabase or demo backend
  app.dart                     auth gate: login → profile setup → home
  providers.dart               Riverpod providers (feed, requests, premium, chat)
  core/                        config, theme, contact sanitizer, shared widgets
  models/                      PublicProfile, PrivateProfile, FollowRequest, ChatMessage
  data/
    backend.dart               FinderBackend interface
    supabase_backend.dart      production: RPCs, RLS-backed queries, Realtime, signed Storage URLs
    demo_backend.dart          offline demo that mirrors the server rules
    media_service.dart         WebP compression (800×800, q70, ≤100 KB) and AAC-LC voice recorder
    purchases_service.dart     RevenueCat (fast_track_79_monthly), plus a demo stub
  features/
    auth/                      phone / email OTP
    onboarding/                profile setup (primary photo, locked grid, interests)
    deck/                      swipe deck, card, Direct DM Invite sheet
    requests/                  Pending Requests (blurred for free users) and Mutual Connections
    chat/                      real-time thread, voice recorder with waveform, playback
    paywall/                   ₹79 Fast-Track bottom sheet
    profile/                   private profile view, own profile
supabase/
  migrations/20261107000000_init_finder.sql   schema, RLS, RPCs, storage, realtime
  functions/revenuecat-webhook/index.ts       keeps profiles.is_premium in sync
android/app/src/main/kotlin/com/finderapp/finder/MainActivity.kt   FLAG_SECURE
```

## Going live

### 1. Supabase

```bash
supabase link --project-ref <ref>
supabase db push                                    # applies the migration
supabase functions deploy revenuecat-webhook --no-verify-jwt
supabase secrets set REVENUECAT_WEBHOOK_AUTH=<random string>
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

These were checked against Postgres 16 with Supabase's `auth` / `storage` schemas stubbed.

### Note on voice-note size

45 s of AAC-LC at 32 kbps is about 176 KB, so it can't also stay under 120 KB. The recorder uses the requested 32 kbps / 45 s, and the `voice_notes` bucket limit is 192 KB. If the 120 KB cap matters more, set `AppConfig.voiceBitRate` to `20000` and the bucket limit to `122880`.
