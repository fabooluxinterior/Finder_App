# Vouby

*(Codebase name: Finder. The app ships as **Vouby**: Android label, launcher icon, splash and in-app copy.)*

A private social connection network for Kerala: Bumble-style swiping on top of Instagram-style private profiles. Built with Flutter, Supabase and RevenueCat.

- **Swipe right** (or tap **Request +**) sends a follow request. **Swipe left** (or ✕) hides the profile for 7 days.
- **Free:** browse every profile, pass, and send unlimited follow requests. There is no free trial.
- **Fast-Track (₹79/month):** see who requested you and accept them, message your connections, and Kerala City Boost. A mutual request is an instant match for anyone, but chatting needs Fast-Track.
- **Open profiles:** every signed-in user (unless blocked) sees the full profile: all photos, bio and interests. Phone numbers, email, date of birth, exact location and social media details are never shown, and the database rejects phone numbers, @handles and links in names, bios and interests. Location is district/city only.
- **Trust & compliance:**
  - Sign-up requires ticking "I'm 18+ and agree to the Terms, Community Guidelines and Privacy Policy"; the acceptance is recorded with its policy version.
  - The date of birth is private, locked, and checked for 18+ in the database.
  - Optional selfie verification is reviewed by staff and earns a blue Verified badge.
  - An "Appears under 18" report hides the profile from Discover until a moderator reviews it.
- Chat (text + 45 s voice notes) opens only between connections (accepted or mutual requests), and only for Fast-Track members.
- `FLAG_SECURE` is set on the Android window, so screenshots, screen recording and Recents previews are blocked everywhere in the app.
- Phone numbers, @handles and URLs are stripped from bios and opening messages on the client. The database rejects them in bios too.
- **Design:** Geist type, Phosphor icons, light and dark themes, a frosted profile card, iOS-style transitions, and short UI sounds with paired haptics (they follow silent mode and can be turned off under You → Sounds). It respects the system "remove animations" setting.
- **Chats are end-to-end encrypted** (Olm / Double Ratchet via the audited `vodozemac` Rust library). Photos are validated, stripped of EXIF/GPS, moderated, and stored AES-256-GCM encrypted. Two-step verification, device and session management, block/report with consent-based evidence, and a staff dashboard with an audit trail are included. See **[SECURITY.md](SECURITY.md)** for the full architecture, its known limitations, and the tests. It has not yet been independently audited.

## Try it on your phone (no store publishing)

**Demo mode** runs offline with sample data: any 6-digit code logs you in, and the ₹79 purchase and selfie review are simulated. It's compiled in only when you pass `--dart-define=DEMO=true` (Android: `--flavor demo`). Production builds (`--flavor prod`) contain neither the demo code nor the sample photos.

1. **Android APK:** every push runs the `Android APK` workflow (`.github/workflows/android-apk.yml`). Open the run under **Actions**, download the `finder-apk` artifact, unzip it, and install `finder-demo-arm64.apk`. Your phone will ask you to allow installs from your browser or file manager. Use `finder-demo-armv7.apk` on older 32-bit phones.
2. **Locally:** `flutter run --flavor demo --dart-define=DEMO=true` with a phone plugged in (USB debugging on), or `flutter build apk --release --flavor demo --dart-define=DEMO=true`.
3. **Web demo:** `tool/build_web_demo.sh` (web builds have no flavors, so the script includes the demo photos for that build only).

### Demo photos

`assets/demo/` holds the sample portraits and scenery used only by demo mode. **They must be licensed or AI-generated; never use photos of real people without a release.**
- The current portraits are illustrations generated with the DiceBear "Lorelei" style (CC0).
- The scenery images are procedurally generated.

They're bundled only in the `demo` flavor (`pubspec.yaml` asset `flavors:`), so `prod` release builds don't contain them.

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
    deck/                      swipe deck and frosted profile card
    requests/                  received requests (blurred count without Fast-Track)
    chats/                     connections list (locked without Fast-Track)
    match/                     "It's mutual" moment
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
  migrations/20261109000000_subscription_model.sql   free requests; requests inbox + messaging need Fast-Track
  functions/process-image/                    upload validation, EXIF strip, moderation, encryption
  functions/media/                            authorised, decrypting image delivery
  functions/delete-account/, media-maintenance/, revenuecat-webhook/
  tests/                                      SQL attack-scenario suites (run.sh)
  config.toml                                 auth hardening: token TTL, rotation, MFA, rate limits
android/app/src/main/kotlin/com/finderapp/finder/MainActivity.kt   FLAG_SECURE
```

## Going live

### 1. Supabase

> **Existing users' data is production data.** Database changes are additive
> migrations only. Follow [`docs/MIGRATIONS.md`](docs/MIGRATIONS.md) (backup
> check → `supabase db push` → `tool/verify_migration.sh`). **Never run
> `supabase db reset` against the linked project.** Project rules: `CLAUDE.md`.

```bash
supabase link --project-ref <ref>
supabase db push                                    # applies only migrations not yet applied, in order
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
   **Don't add a free-trial or introductory offer** to the base plan. The app always buys the plain base plan (`PurchaseParams.subscriptionOption` with `isBasePlan`), so a trial offer wouldn't be used anyway.
2. In RevenueCat, add the Play app, create the entitlement **`fast_track`**, attach the product, and put it in the current offering.
3. Webhook: URL `https://<ref>.supabase.co/functions/v1/revenuecat-webhook`, with Authorization header `Bearer <REVENUECAT_WEBHOOK_AUTH>`.

The app calls `Purchases.logIn(<supabase user id>)`, so webhook events map straight to `profiles.id`.

### 3. Policies

- Fill every `<FILL: …>` placeholder in `TERMS_OF_SERVICE.md`, `PRIVACY_POLICY.md` and `COMMUNITY_GUIDELINES.md`. The app shows these files as-is.
- When a policy changes materially, bump `AppConfig.policyVersion` (`lib/core/config.dart`, format `YYYY-MM-DD`). Users who accepted an older version see a blocking re-consent screen.

### 4. Build

```bash
flutter build apk --release --flavor prod \
  --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<publishable key> \
  --dart-define=REVENUECAT_ANDROID_KEY=<goog_...>
```

Add the same three values as repository secrets (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `REVENUECAT_ANDROID_KEY`) and the workflow also produces `finder-live-arm64.apk`.

Before a Play Store release, replace the debug signing config in `android/app/build.gradle.kts` with your upload key.

## How the rules are enforced

| Rule | Where |
|---|---|
| Sending requests is free and unlimited (rate-limited against abuse) | `swipe_profile`, `tg_swipes_rate_limit` |
| Accepting a request needs Fast-Track | `respond_to_request` (`hint = SUBSCRIPTION_REQUIRED`); direct updates revoked |
| Sending messages needs Fast-Track | `send_message`, `claim_device_keys` (`hint = SUBSCRIPTION_REQUIRED`) |
| Pass hides a profile for 7 days | `get_feed` filter; `swipe_profile` clears expired passes |
| Free users can't see who requested them | `swipes_select` policy hides pending rows unless `is_premium()` |
| Mutual swipe = instant match | `swipe_profile` accepts the reverse request |
| Only the receiver can accept/reject, only once | `respond_to_request` + `tg_swipes_before_update` |
| Chat only between accepted connections | `messages_*` policies via `is_connected()` |
| Locked grid and interests | `profile_private` RLS + `avatars/<uid>/gallery/*` storage policy |
| Users can't grant themselves premium | column-level `UPDATE` grant excludes `is_premium` |
| Kerala City Boost | `get_feed` ordering: premium + same city first |
| Full profiles visible to signed-in users, never to blocked ones | `profile_private_select`, `can_view_media` (selfies: owner only) |
| No phone numbers / handles / links in names, bios, interests; city is a district name | `contains_contact_info` checks + `profiles_city_district` |
| Policy acceptance recorded per version | `user_consents`, `record_consent`, `accepted_policy_version` (app compares with `POLICY_VERSION`) |
| 18+ from a private, locked date of birth; age computed server-side | `profile_dob` + `set_dob` + `tg_profiles_age` + `profile_dob_locked` trigger |
| Verified badge set only by staff review | `verification_requests`, `mod_review_verification`; `is_verified` not client-writable |
| "Appears under 18" report hides from Discover until reviewed | `submit_report` → `hidden_pending_review`; `mod_resolve_report` unhides on dismissal |
| Selfies purged 30 days after review | `run_retention` (daily via `pg_cron`) + `media-maintenance` purge |

These rules and the security layer are covered by the SQL suites in `supabase/tests/`, which run against Postgres 16 with Supabase's `auth` / `storage` schemas stubbed. CI runs them on every push.

### Note on voice-note size

45 s of AAC-LC at 32 kbps is about 176 KB, so it can't also stay under 120 KB. The recorder uses the requested 32 kbps / 45 s, and the `voice_notes` bucket limit is 192 KB. If the 120 KB cap matters more, set `AppConfig.voiceBitRate` to `20000` and the bucket limit to `122880`.

## Profile builder

**First run: a 7-stage setup** (`lib/features/onboarding/onboarding_flow.dart`), saved after every stage in `profiles.onboarding_stage` so it resumes where you left off:
1. **Community standards**: four original principles, explicit "I agree" (stored with the other consents).
2. **About you**: name, birthdate (locked; age derived), gender, height (cm), work, education, district.
3. **Your everyday**: drawers for what you're looking for, exercise, drinking, smoking, star sign, background, languages.
4. **Interests**: categorised chips (creative arts, food, active & sports, gaming, reading), at least 5.
5. **Photos**: the 6-slot grid, at least 4.
6. **Prompts**: at least 2 from the original catalog, answers up to 150 characters with a writing tip under the active one.
7. **Music + completion**: Spotify tile and the profile-strength ring, then `complete_onboarding()` flags the profile live.

The server decides "live": `complete_onboarding()` checks every requirement, and Discover only shows onboarded profiles with 4+ photos.

**Photos are optimised on the device** (`lib/core/image_optimizer.dart`): JPEG, PNG, HEIC or WebP in → WebP out, fitted inside 1080 px (aspect ratio kept) and stepped down in quality, then size, until it's under 100 KB. Mobile uses the native encoder; the web build draws into an HTML5 canvas and exports WebP (JPEG on browsers without a WebP encoder; the server converts it). The server still validates every upload: a WebP within limits keeps its pixels but loses EXIF/XMP/ICC chunks; anything else is re-encoded. Replacing or removing a photo deletes the stored object immediately (`process-image`, `photo-remove`), with `media-maintenance` as a backstop.

**Profile strength (0–100)**: photos 7.5 each up to 4 (30), work + education (10), lifestyle selections (20), interests (15), bio of 20+ characters (10), two prompts (10), Spotify linked (5). Computed by a trigger (`profile_completion`) and mirrored in `lib/models/profile_completion.dart`; tests check they agree.

**Prompts and icebreakers**: on Discover, prompt cards sit between photos (tap the sides to move through them). Tapping an answer opens a reply sheet; the reply goes with a follow request and becomes the opening context of the chat if accepted. Chat itself stays locked until then, and the UI says the reply isn't end-to-end encrypted.

**Spotify** (`music-connect`, `music-callback`, `music-sync`): Authorization Code flow with scope `user-top-read`. The code exchange, client secret and tokens stay in edge functions; the refresh token is stored AES-256-GCM encrypted in the service-only `music_accounts` table and rotated when Spotify issues a new one. The top 10 artists (id, name, medium image, genres) are re-imported at most every 12 hours; swipes and feeds read stored data and never call Spotify. A revoked token marks the account "reconnect"; zero listening history is a normal, empty list. Users can hide any artist: `profiles.music_artist_ids` (GIN-indexed) holds visible artists only, so shared-artist matching (`array intersect`, in `get_feed` and `music_affinity`) can never reveal a hidden one.

To enable Spotify: create an app at developer.spotify.com, add the deployed `music-callback` URL as a redirect URI, and set `SPOTIFY_CLIENT_ID`, `SPOTIFY_CLIENT_SECRET`, `SPOTIFY_REDIRECT_URI` (and optionally `MUSIC_RETURN_URL`) as edge-function secrets. New Spotify apps start in development mode (25 allow-listed users) until Spotify approves an extension.

## Spotify card and Suggestions (updates 01–02)

**Spotify card** (`lib/features/profile_builder/spotify_card.dart`): heading, top artists as pills with round photos, "Most played" (Spotify's top-tracks ranking with artwork and 01, 02… ranks; five, then "See all") and "Recently played" (latest five with "10 min ago"). Scopes `user-top-read user-read-recently-played`; imports run in `music-sync` at most hourly when the owner opens the app, never on other people's views or swipes. Connections made before recently-played was requested keep working and show "Reconnect to show recently played". Owners can hide either section and any artist.

**Suggestions** (tab "Suggestions", `lib/features/suggestions/`): "People you might like" plus a "You may like" row. Ranking runs in the database (`get_suggestions`, `suggestion_score`) from explainable signals with configurable weights in `recommendation_config` (defaults: interests 35%, music 20%, lifestyle 15%, hobbies 15%, location 10%, completeness 5%); music only counts when both people linked Spotify, and signals that don't apply are left out of the average. Limits are server-side: 10 per load, 20 per page, 50 new per day; a refresh returns today's people and never resets the allowance; `recommendation_history` avoids repeats for 7 days. Excluded: yourself, blocked, unfinished or hidden profiles, people outside either person's discovery preferences (age range, who to show), and people you already swiped. Location is the district only; there's no GPS.

## Design

The UI follows the Vouby design canvas: near-black ground (`#0B0B0C`), cards on `#161618` with `#28282A` hairlines, one orange (`#FF5A3D`) for everything you can act on, gold for Fast-Track and a blue tick for Verified. Type is Geist.

- `lib/core/brand.dart`: the bubble mark, the `vouby.` wordmark, tab and line icons, the opening animation and typing dots. Shapes are drawn from the design's SVG path data via `lib/core/svg_path.dart`.
- `lib/core/illustrations.dart`: the illustrated people from the design, used for the sign-in card fan in release builds and for locked request placeholders (no real person is depicted).
- Launcher icons, web icons and the favicon are rendered from the design's app-icon artwork.

