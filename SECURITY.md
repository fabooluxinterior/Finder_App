# Finder security architecture

One architecture serves the Android app and the web app. The server never trusts the client: every rule below is enforced in Postgres (RLS, privileges, `SECURITY DEFINER` functions) or in Edge Functions, and the UI only reflects it.

> **Status.** This design and code have **not yet been independently audited or penetration-tested.** The automated tests below show the controls behave as designed. They don't replace a review by an independent security firm against OWASP ASVS L2, the OWASP API Security Top 10 and OWASP MASVS. Don't advertise "end-to-end encrypted" publicly until that review is done.

## 1. What the server can and cannot see

| Data | Stored on the server as | Readable by Finder staff/servers? |
|---|---|---|
| Chat text, voice notes | Per-device Olm ciphertext; voice audio as AES-256-GCM ciphertext | **No.** Keys exist only on users' devices |
| Who messaged whom, when, read flag, message count | Plain metadata (`messages` row) | Yes. Needed for delivery, unread counts and rate limits |
| Profile photos, gallery photos | AES-256-GCM ciphertext; data keys wrapped by a server-held KEK | Only through the authorised `media` function; staff views are audit-logged |
| Name, age, district/city, bio, interests, photos | Postgres rows / encrypted media; visible to every signed-in user who isn't blocked | Yes |
| Date of birth | `profile_dob` (owner-only RLS, locked by trigger) | Yes (staff via SQL); never to other users |
| Verification selfies | Encrypted media, kind `selfie`; owner-only, staff views audit-logged; purged 30 days after review | Verification staff only |
| Consent records | `user_consents` (owner-only) | Yes |
| Reports | Reason, optional details, and messages the reporter **chose** to share | Moderators only, every access audit-logged |
| Phone/email | Supabase Auth | Yes (needed for sign-in); never exposed to other users |

## 2. End-to-end encrypted chat

**Library.** [`vodozemac`](https://github.com/matrix-org/vodozemac) 0.11.1 (Apache-2.0). This is Matrix.org's Rust implementation of Olm, the Double Ratchet with X3DH-style 3DH key agreement, Curve25519, Ed25519, AES-256-CBC and HMAC-SHA-256. It was independently audited by Least Authority (2022). We use the audited Olm v1 session configuration. No cryptographic algorithm or protocol is implemented in this repository. `rust/src/api/crypto.rs` is a thin, stateless wrapper exposed to Flutter through `flutter_rust_bridge`. Android loads it as a native library; web loads it as WebAssembly.

**Devices.** Each install creates its own Curve25519 identity key and Ed25519 signing key (`register_device`). Only public keys go to the `devices` table. A user can have at most 5 active devices. If MFA is enrolled, adding a device requires an MFA-verified (AAL2) session.

**Key exchange.** Each device publishes 50 one-time keys plus a fallback key. Each key is signed with the device's Ed25519 key. `claim_device_keys` hands out one key per device atomically, deletes it on claim, and only works between accepted, unblocked connections. The sender **verifies every key's signature** before using it, so a server that swaps in its own one-time key is rejected (tested).

**Sending.** The payload (text, or a voice-note reference with its file key) is encrypted separately for every active device of the recipient **and** the sender's other devices. `send_message` stores one ciphertext envelope per device and checks:
- the users are connected and not blocked;
- the sending device belongs to the caller;
- every envelope targets a device of the sender or the receiver;
- the 40 messages/minute rate limit.

Envelopes are deleted as soon as the recipient device acknowledges them, and after 30 days if never collected.

**Properties.**
- **Forward secrecy.** Message keys are derived and discarded by the ratchet.
- **Post-compromise recovery.** Every reply performs a new Diffie–Hellman ratchet step.
- **Tamper detection.** Every message is MAC-authenticated.
- **Replay protection.** A used one-time key is removed, and a used message key can't decrypt twice. The client also drops duplicate client message ids, which are bound inside the ciphertext.

All of these are covered by `rust/tests/protocol.rs` and `test/e2ee_engine_test.dart`.

**Attachments.** Voice notes are encrypted on the device with a fresh AES-256-GCM key per file. The associated data is bound to the storage path, and a SHA-256 of the ciphertext is checked before decryption. Only ciphertext is uploaded. The key travels inside the E2EE message.

**Verification.** *Verify encryption* in a chat shows a 60-digit safety number derived from both users' device signing keys, to compare in person. It changes when either person adds or removes a device. Without that comparison, trust is trust-on-first-use.

**Local storage.** Account and session state is pickled and encrypted with a random 256-bit key. That key, the pickles and the decrypted history live in `flutter_secure_storage`:
- **Android:** encrypted with a Keystore-held key (hardware-backed where available). Excluded from cloud backup and device transfer.
- **iOS:** Keychain, this-device-only.
- **Web:** no hardware keystore. Values are AES-GCM encrypted with a WebCrypto key in the same origin's storage. That protects against casual inspection, but not against XSS or a compromised browser profile. Mobile gives stronger protection; the web app warns users about this.

**Known limitations (to fix or accept before launch).**
- Metadata (who talks to whom, and when) is visible to the server.
- A new device does not receive old history (same as Signal). History is per-device.
- Reports carry messages *as the reporter's device decrypted them*. There is no cryptographic "message franking" yet, so moderators should treat evidence as reporter-attested.
- `flutter_rust_bridge` web builds need cross-origin isolation (COOP/COEP headers, already set in `web/_headers`).

## 3. Message history: block, unmatch, deletion, lost devices

| Event | Server | Your devices | Their devices |
|---|---|---|---|
| **Unmatch** | Connection ended; message metadata and undelivered ciphertext for the pair deleted | Local history deleted | Their local copy stays until they delete it or unmatch. We can't reach into their phone |
| **Block** | As unmatch, and the blocked user can't see your profile, request you, claim your keys or send to you (enforced in SQL) | Local history deleted | As above |
| **Report** | Report stored; optional shared messages kept until 90 days after resolution | Unchanged (and the user is blocked by default) | Unchanged |
| **Sign out** | This device's keys revoked, so new messages aren't encrypted to it; session ended | Keys and decrypted history wiped | Unchanged |
| **Remove a device** (security settings) | Device revoked; its pending envelopes and one-time keys deleted | That device can't decrypt anything new | Unchanged |
| **Lost/stolen phone** | Sign in elsewhere → *Privacy & security* → remove the device and sign out its session | The lost phone keeps whatever was already on it, protected by the phone's lock screen and Keystore | Unchanged |
| **Delete account** | Profile, photos (purged from storage), devices, keys, connections, message metadata, envelopes and voice ciphertext deleted immediately. Provider backups age out within 7 days (daily backups) or the PITR window | Wiped | Copies already on other people's phones remain |

## 4. Images

Upload pipeline (`supabase/functions/process-image`):
1. The client compresses to JPEG ≤1600 px without EXIF, then uploads over TLS into the private `uploads_quarantine` bucket. Users can only write their own folder, and nobody can read the bucket.
2. The server sniffs the **real** type from magic bytes. Only JPEG and PNG are accepted, whatever the name or MIME type says. It also checks size (≤8 MB) and dimensions (≥200 px, ≤40 MP decompression-bomb guard).
3. The image is fully decoded to pixels with Google Squoosh codecs (jSquash, WebAssembly), centre-cropped, resized to 800×800 and **re-encoded** as a new WebP (≤100 KB). The original bytes are never stored or served, which drops EXIF/GPS/XMP and neutralises payloads hidden in the file.
4. Moderation runs before publishing: Google Cloud Vision SafeSearch on the clean image. Likely nudity, or very likely racy or violent content, is rejected. Borderline images, or any image when no API key is configured, are held for manual review.
5. Encryption: a random 256-bit data key per image, AES-256-GCM with the media id as associated data. The data key is wrapped with the active KEK and stored as `wrapped_dek` + `kek_id`. Only ciphertext goes into the private `media_encrypted` bucket.
6. Only approved images are attached to a profile, by the server. Clients can't write photo ids.
7. The quarantine copy is deleted in every outcome.

Delivery (`supabase/functions/media`): there are **no public or signed storage URLs**. Each request carries the user's 15-minute access token. `can_view_media` decides access:
- primary and gallery photos: any signed-in user who isn't blocked;
- verification selfies: the owner only;
- pending images: the owner only (plus moderators on an MFA session, audit-logged).

The function then decrypts and returns the image with `Cache-Control: private, max-age=300`. A copied URL is useless without a live session. Each user is limited to 600 image fetches per hour; spikes create a `media_download_spike` security event.

Deletion: removed photos are marked `deleted` immediately (unservable) and purged from storage by the `media-maintenance` job (`purge`).

## 5. Keys and secrets

| Key | Where it lives | Rotation / recovery |
|---|---|---|
| E2EE device keys | Only on the device (Keystore/Keychain) | New device = new keys. Lost device: remove it from another session. No server recovery by design |
| Media KEKs (`MEDIA_KEKS`, `MEDIA_KEK_ACTIVE`) | Supabase Edge Function secrets (encrypted at rest, never in the DB, client or git) | Add `v2`, set it active, run `media-maintenance` `rewrap` until `remaining = 0`, then remove `v1`. Covered by tests |
| Supabase service role key | Supabase-managed; used only inside Edge Functions | Rotate in the dashboard (JWT signing keys) |
| Google Vision / RevenueCat secrets | Edge Function secrets | Rotate at the provider, then `supabase secrets set` |
| Backups | Supabase daily backups / PITR, encrypted at rest (AES-256) by the provider | Provider-managed keys |

**Stronger option for production:** keep the KEK in a cloud KMS (Google Cloud KMS in `asia-south1`, or AWS KMS in `ap-south-1`) and replace `wrap`/`unwrap` in `_shared/media_crypto.ts` with KMS `encrypt`/`decrypt` calls, so the KEK never leaves the HSM. The interface is already isolated for this swap.

Never commit secrets. `.env*` is git-ignored and `.env.example` holds placeholders only. The app binary contains only public values (Supabase URL, publishable key, RevenueCat public SDK key).

## 6. Database

- RLS on every table.
- Internal tables (`staff_roles`, `security_events`, `access_audit_log`, `rate_limits`, `media_objects`, `one_time_keys`) have **all client privileges revoked**.
- Column-level grants stop users from changing `is_premium`, photo ids, gallery ids or report evidence.
- Privileged operations go through `SECURITY DEFINER` functions with a pinned `search_path`. Each one authorises `auth.uid()` itself, and `EXECUTE` is revoked from `anon` and `public`.
- Every client call is parameterised through PostgREST/RPC. There is no string-built SQL.
- Internal ids (device ids, media ids) are random UUIDs, and nothing exposes sequential ids.
- The audit log is append-only: a trigger blocks `UPDATE`/`DELETE` even for the table owner.
- Retention runs daily via `pg_cron` (`run_retention`): rate-limit windows, stale envelopes, report evidence 90 days after resolution, and security events after 1 year.

## 7. Authentication and sessions

- Sign-in is by phone/email **OTP only**, so no passwords are stored and there is nothing to hash. Argon2id would apply only if passwords were added; Supabase Auth itself uses bcrypt.
- 15-minute access tokens. Refresh tokens rotate on every use, and reuse detection revokes the session family (`supabase/config.toml`).
- Optional **TOTP two-step verification** (Supabase MFA). Once enrolled, it is required at sign-in and for adding devices, removing devices and deleting the account. All staff functions require it.
- *Privacy & security* screen: list and revoke sessions, sign out everywhere else, list and remove devices, delete the account.
- Rate limits:
  - **Auth:** OTP send and verify, sign-ups and token refresh, per IP.
  - **Database:** swipes, messages, key claims, device registration, reports, uploads and image fetches, per user.
- Suspicious activity becomes `security_events`: a new device added to an existing account, denied key claims or sends, rate-limit hits, staff access denials, upload rejections and download spikes.
- **Mobile:** session tokens are stored via a custom Supabase `LocalStorage` backed by the Keystore/Keychain (`lib/security/secure_session_storage.dart`), not SharedPreferences. Release builds are obfuscated, and no message content or keys are logged.
- **Web, a known gap:** Supabase's Flutter SDK keeps the session in browser storage, not in an `HttpOnly` cookie. HttpOnly + SameSite cookies with CSRF protection need a backend-for-frontend (a small server that holds the refresh token in an `HttpOnly; Secure; SameSite=Strict` cookie and proxies auth). Until one is added, the web app relies on:
  - a strict CSP (`web/_headers`): no third-party scripts, `frame-ancestors 'none'`;
  - 15-minute tokens with rotation;
  - MFA.

  Users should prefer the mobile app.

## 8. Platform protections

- **Android:**
  - `FLAG_SECURE` on the window blocks screenshots, screen recording, casting and Recents thumbnails.
  - HTTPS only, trusting system CAs only (`network_security_config.xml`).
  - `allowBackup=false` with data-extraction rules excluding everything.
  - Keystore-backed secure storage.
- **Web** (`web/_headers`): CSP, HSTS, COOP/COEP (required for the WebAssembly crypto), `X-Frame-Options: DENY`, `nosniff`, no-referrer and a restrictive Permissions-Policy. Screenshots can't be blocked in browsers; the web app says so.

## 9. Moderation alongside E2EE

There is **no backdoor**: servers and moderators can't read chats.
- **Profile and gallery photos** are moderated before they're published (§4).
- **Bios and Direct DM notes** aren't end-to-end encrypted. The database rejects phone numbers, @handles and links in them.
- **Inside chats**, the client strips contact details from each person's first 5 messages before encryption.
- **Reports:** a user can choose to share up to 20 of the reported person's recent messages. They're decrypted on the reporter's phone after an explicit consent screen explaining who will see them. Only staff with an MFA session can open evidence; they must enter an access reason, and each access is written to the append-only audit log.
- **Gaps:** server-side scanning of chat images isn't possible with E2EE. Chat images aren't supported yet; when they are, run an on-device classifier before encryption. Malicious-link warnings in chats would also need to run on the device.

## 10. Monitoring and the admin dashboard

`Profile → Privacy & security → Safety & security dashboard` (visible only to staff, and every call is re-authorised server-side) shows:
- event counts and critical events for the last 24 hours;
- the latest security events;
- open reports with audited evidence access and resolution;
- the photo review queue;
- the staff access log.

Grant roles with SQL as the database owner:

```sql
insert into public.staff_roles (user_id, role) values ('<uuid>', 'admin');
```

For alerting, add a Supabase log drain or a `pg_cron` job that notifies on `severity = 'critical'`.

## 11. Infrastructure

- **DDoS and abuse:** Supabase's API gateway sits behind Cloudflare. For the web app, also serve it from Cloudflare (or similar) with WAF rules and bot protection, and enable Supabase network restrictions for direct database access.
- **CORS:** Edge Functions only answer browser origins in `ALLOWED_ORIGINS`. Mobile apps send no Origin header.
- **SSRF:** no endpoint fetches user-supplied URLs. The only outbound calls go to fixed hosts (Google Vision, RevenueCat).
- **Errors:** user-facing messages are generic. Functions log error names only, never payloads.

## 12. Security tests

Automated, run in CI on every push (`.github/workflows/android-apk.yml`):

| Suite | What it proves |
|---|---|
| `rust/tests/protocol.rs` | Key exchange, signed one-time keys, replay rejection, tamper rejection, wrong pickle key, AES-GCM attachment tamper/context, safety-number symmetry |
| `test/e2ee_engine_test.dart` | Multi-device fan-out and decryption, replies, replay/tamper rejection, **server-substituted key refused**, strangers can't claim keys |
| `supabase/functions/_shared/tests` | EXIF/GPS removed, disguised and truncated files rejected, media encryption tamper and id-swap fail, KEK rotation works and retired keys fail, moderation thresholds |
| `supabase/tests/*.sql` (34 attack cases) | Cross-user reads, IDOR on devices/keys/messages/envelopes/sessions/reports/media, spoofed senders, envelopes to outsider devices, blocked users, self-granted premium or photos, MFA gates, staff without MFA, audit-log tampering, rate limits |

Mapping to the 15 tests you listed (✅ automated · 🟡 partly automated · 🔲 needs manual or pen-test work):

1. ✅ Unauthorised profile image access: SQL `can_view_media` cases. The media function's auth path still needs a live pen-test.
2. ✅ Unauthorised chat history access.
3. 🟡 API authentication bypass: RLS and grants are tested. Pen-test the deployed functions with and without tokens.
4. ✅ IDOR.
5. 🟡 SQL injection: no dynamic SQL exists. Run sqlmap or Burp against the deployment.
6. 🔲 XSS: Flutter renders text, not HTML, and CSP is set. Verify on the deployed web app.
7. 🔲 CSRF: bearer-token APIs aren't CSRF-able. Re-test once cookie auth (a backend-for-frontend) exists.
8. 🟡 Brute force: OTP limits are in `config.toml` and app limits are tested. Verify against the hosted project.
9. ✅ Malicious file uploads: disguised and truncated files are covered. Add fuzzing.
10. 🔲 Session hijacking: rotation and reuse detection are configured. Test on the hosted project.
11. 🟡 Encryption key exposure: no server holds E2EE keys, and keys are wiped on sign-out. Do MASVS storage testing on a rooted device.
12. ✅ Message tampering.
13. ✅ Expired signed URLs: there are none; access requires a live token, so test that expired tokens get 401.
14. ✅ Cross-user data access.
15. 🔲 Backup security: review Supabase backup and PITR settings and access.

Run them locally:

```bash
(cd rust && cargo test)
(cd rust && cargo build) && flutter test
(cd supabase/functions && deno test --allow-read --allow-env _shared/tests/)
PGURL=postgres://postgres:postgres@localhost:5432/postgres supabase/tests/run.sh
```

## 13. Pre-launch checklist

- [ ] Independent penetration test and code review (ASVS L2, API Top 10, MASVS-L2), including the Rust and Dart E2EE glue.
- [ ] Generate the KEK with `openssl rand -base64 32`; set `MEDIA_KEKS`, `MEDIA_KEK_ACTIVE`, `ALLOWED_ORIGINS`, `GOOGLE_VISION_API_KEY`.
- [ ] Mirror `supabase/config.toml` auth settings in the hosted dashboard (JWT expiry, refresh rotation, rate limits, MFA, session timebox).
- [ ] Enable `pg_cron`; schedule `media-maintenance` `purge` daily and `rewrap` after any KEK rotation.
- [ ] Enable PITR and decide backup retention; document it in the privacy policy.
- [ ] Replace the debug signing key with a Play upload key; enable Play App Signing and Play Integrity.
- [ ] Deploy the web app with `web/_headers` (or equivalent) and confirm the headers.
- [ ] Have the privacy policy reviewed by a lawyer (India DPDP Act 2023).

## 14. Trust & compliance controls (migration `20261110000000_compliance.sql`)

- **Consent:** sign-up requires the 18+ / Terms / Guidelines / Privacy checkbox, and the OTP can't be requested without it. Acceptance is recorded server-side per policy and version (`record_consent`). A newer `POLICY_VERSION` forces a blocking re-consent.
- **Age:** the date of birth lives in `profile_dob`, readable only by its owner. It can be set once (`set_dob`, which rejects under-18 and future dates), after which an `UPDATE` trigger blocks every change, including service-role writes. Profile ages are computed from it at insert and refreshed daily. Accounts without a DOB keep their age until they add one at next login.
- **Verification:** the server picks a random pose and the selfie must be uploaded within 15 minutes through the normal image pipeline. Only staff on an MFA session can see it, and each view is audit-logged. `is_verified` changes only through `mod_review_verification`. Selfies are purged 30 days after review.
- **Under-18 reports** set `hidden_pending_review`, which removes the profile from `get_feed` until a moderator resolves the report. "Actioned" keeps it hidden; "dismissed" restores it if no other under-18 report is open. Abuse is limited by the 10-reports-per-day rate limit.
- **Contact details:** the database refuses phone numbers, @handles, links and "my insta is …" phrases in names, bios and interests, and restricts `city` to a district name.
- **Demo isolation:** demo code is compiled only with `--dart-define=DEMO=true`; the sample photos ship only in the `demo` Android flavor.

Tests: `supabase/tests/30_compliance_test.sql` and `test/compliance_test.dart`.

