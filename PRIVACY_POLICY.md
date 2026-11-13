# Vouby Privacy Policy

**Version 2026-11-19.** Draft: have this reviewed by a lawyer before publishing (India's Digital Personal Data Protection Act, 2023, and Google Play's User Data policy).

Vouby ("we", "us") is operated by **<FILL: Company name>**, **<FILL: Registered address>**. This policy explains what we collect, how we protect it, and what control you have.

- **Grievance Officer:** <FILL: Grievance Officer name>, <FILL: Grievance Officer email>
- **Privacy requests:** <FILL: Privacy email>

## 1. What we collect

| Information | Why | Visible to |
|---|---|---|
| Mobile number (or, for older accounts, email) | Signing you in with one-time codes | Only you and our systems. Never shown to other users |
| Contact email (you add it after signing up; we don't verify it) | Account and support notifications, and replies to your support tickets | Only you and our systems. Never shown to other users, and not used to sign in |
| Phone notification token (only if you allow notifications) | To show popup notifications from Vouby on your phone | Our systems and Google's Firebase Cloud Messaging, which delivers the popup. You can switch it off in You → Popup notifications |
| Date of birth | Confirming you're 18 or older and showing your age | Only you. Other users see your age, never your date of birth |
| Name, age, district/city, bio, photos, interests | Your profile | Every signed-in Vouby user, except people you've blocked or who blocked you |
| Gender, pronouns, height, work, education, languages, lifestyle answers (what you're looking for, exercise, drinking, smoking, star sign, background) | Optional profile details you choose to add | Every signed-in Vouby user, as above |
| Prompt answers (up to 3, 150 characters each) | Conversation starters on your profile | Every signed-in Vouby user, as above |
| A reply someone sends to one of your prompts, or you send to theirs | Starting a conversation; travels with the follow request | You and the other person. **Not end-to-end encrypted**, because it's sent before the chat opens |
| If you connect Spotify: your top 10 artists (name, picture, genres) | Showing your music taste and shared artists | Artists you leave visible: every signed-in Vouby user, as above. Hidden artists: only you |
| If you connect Spotify: your top 10 tracks (Spotify's ranking) and your last 10 plays with their times | The "Most played" and "Recently played" parts of your music card | Each section you leave on: every signed-in Vouby user, as above. Turned off: only you |
| Discovery preferences (age range, who you want to see) | Choosing who appears in Discover and Suggestions, both ways | Only you and our systems. Other users never see them |
| Who we suggested to you, when, and why (shared interests, artists, lifestyle answers, district) | Not repeating suggestions and keeping to the daily limit | Only you and our systems |
| If you connect Spotify: an access token from Spotify | Refreshing your top artists | Our systems only (encrypted, never shown to anyone) |
| Verification selfie and the pose you were asked to make | Confirming your photos are really you | Only our trained verification staff. Never other users |
| Follow requests, passes and matches | Running the app's core features | You and the other person |
| Messages, voice notes and photos you send in chat | Chat | **Only you and the other person** (end-to-end encrypted, see §3) |
| Message metadata: who messaged whom, when, read status | Delivering messages and unread counts | Our systems. Not readable by other users |
| Device keys (public) and device type | Making encryption work across your devices | People you're connected to (public keys only) |
| Policy acceptances (which version, when) | Keeping a record of your consent | You and our systems |
| Subscription status | The Fast-Track subscription | You. Payment details are handled by Google Play; we never see them |
| Free trial: when it started and ended, and a one-way fingerprint (salted hash) of your phone number or email | Giving each person one 7-day free trial; the fingerprint can't be turned back into your number or email and is kept after account deletion only to stop repeat trials | Our systems only |
| In-app notices (trial reminders, support updates, safety notices) | Telling you about your account | Only you |
| Support requests: category, subject, description, optional screenshot, your registered email and ticket history | Answering your request | You and our support staff |
| Security logs (sign-in events, rate-limit hits, failed access attempts) | Protecting accounts and detecting abuse | Our security staff |
| Reports you make or receive, with the evidence the reporter chose to share, moderation decisions and any account restrictions | Keeping Vouby safe and reviewing reports fairly | Our safety team. A restricted user is told the restriction and reason, never who reported them |

**What we never show other users:** your phone number, your email, your date of birth, your exact location, or links to other social media. We block phone numbers, social media handles and links in names, bios and interests, and filter them from the first messages of every chat. Your location is only the district or city you choose; we never collect GPS location. We remove location data (GPS) and other hidden metadata from every photo before storing it.

## 2. How we store your photos

- Photos go into a private quarantine area first. We check they're real images, remove hidden metadata, and screen them automatically for nudity and violence. An image-safety service (OpenAI Moderation, or Google Cloud Vision) receives the photo only to return a safety rating; we send nothing else with it. Some photos are reviewed by a person before they appear.
- Every stored photo is encrypted with its own key (AES-256-GCM). Those keys are themselves encrypted with a master key kept outside our database.
- Photos are never available at a public link. Each view checks that the viewer is signed in and allowed to see it, so a copied link doesn't work for anyone else.
- **Verification selfies** go through the same pipeline but are never shown on your profile. Only verification staff can view them, every view is logged, and they're deleted 30 days after the review.

**Photos are optimised on your phone.** Before any upload, the app resizes each photo to at most 1080 pixels and converts it to a compact WebP file (under 100 KB). When you replace or remove a photo, we delete the stored file straight away.

**Spotify.** Connecting Spotify asks Spotify for permission to read your top artists and top tracks (scope "user-top-read") and your recently played tracks (scope "user-read-recently-played"), and nothing else: we can't see your playlists, followers, email or account details. We refresh your music at most once an hour, only when you open the app. You can turn off "Most played" or "Recently played" at any time. You can hide any artist; hidden artists are never shown or used to find shared artists. Disconnecting deletes the token and every imported artist from our systems. You can also remove Vouby's access in your Spotify account under Apps.

**Suggestions.** We suggest people using shared interests, shared artists (only artists both of you left visible, and only if you both connected Spotify), matching lifestyle answers, being in the same district, and how complete their profile is. Each suggestion shows why. We never use your messages, your photos' content or your exact location for this.

## 3. How your conversations are protected

- Messages, voice notes and photos are **end-to-end encrypted** on your phone before they're sent (photos are also resized and compressed on your phone first), using the Olm / Double Ratchet protocol (the protocol used by Matrix, via the independently audited `vodozemac` library). Only your devices and the other person's devices have the keys.
- **We can't read your messages or listen to your voice notes**, and we have no way to decrypt them. That includes our staff, our hosting providers, and anyone who obtains our servers' data.
- We can see that a message was sent, between whom, and when. We need this to deliver it.
- Encrypted copies are deleted from our servers once your device receives them, or after 30 days if a device never collects them.
- Your conversation history is stored on your phone, encrypted with a key held in your phone's secure hardware. Signing out deletes it from that phone.

## 4. Moderation and what moderators can see

Because chats are end-to-end encrypted, moderators can't see them unless **you choose to share them**.
- When you report someone, you choose exactly which messages or photos to include (long-press them in the chat). You see a preview and confirm before anything is sent; they're decrypted on your phone and nothing else from the chat is shared. We never take screenshots of your screen or other apps.
- Every report is reviewed by a person. Accounts are never restricted automatically because of the number of reports; possible outcomes are no action, a warning, limits, suspension, a ban or content removal, and false reports are recorded.
- Only trained members of our safety team can open report evidence. They must use two-step verification and record a reason, and every access is permanently logged.
- If someone reports that a profile **appears to belong to someone under 18**, we hide that profile from Discover until a moderator reviews it.
- Report evidence is deleted 90 days after the report is closed.

## 5. How long we keep information

| Data | Kept |
|---|---|
| Account, profile, date of birth | Until you delete your account |
| Policy acceptances | For as long as your account exists, and up to the backup retention period afterwards |
| Verification selfies | 30 days after the review |
| Undelivered encrypted messages | Until delivered, or at most 30 days |
| Message metadata | Until you or the other person unmatches or blocks, or either account is deleted |
| Prompt replies sent with a request | Same as message metadata, or until the request is declined |
| Spotify token, imported artists and tracks | Until you disconnect Spotify or delete your account |
| Suggestion history | 90 days |
| Removed photos | Unavailable immediately; deleted from storage within 24 hours |
| Report evidence | 90 days after the report is resolved |
| Moderation decisions and restrictions | As long as the account exists, so repeated problems can be judged fairly |
| Support requests and screenshots | Until you delete your account, or 2 years after the ticket is closed |
| Free-trial record | Trial dates: until you delete your account. The one-way fingerprint: kept to prevent repeat trials |
| Security logs | 1 year |
| Backups | Rolling, up to <FILL: Backup retention> days |

## 6. Your choices and rights

- **Edit or remove** your profile, photos and interests at any time. Your date of birth can't be changed after sign-up; contact <FILL: Privacy email> if it's wrong.
- **Unmatch or block** anyone. This ends the chat for both of you and deletes the conversation data on our servers. We can't delete copies already on the other person's phone.
- **Two-step verification, devices and sessions:** in *You → Privacy & security* you can turn on an authenticator app, see every signed-in session and device, and remove any of them.
- **Delete your account** in *Privacy & security*. We delete your profile, photos, date of birth, encryption keys, connections and server-side message data immediately. Backups are overwritten within <FILL: Backup retention> days. Messages already delivered to other people's phones stay on their phones.
- Under the DPDP Act you may request access to, correction of, or erasure of your data, withdraw consent, and nominate someone to act for you. Email <FILL: Privacy email>. We respond within 30 days. If you're unhappy with our response, contact our Grievance Officer, and then the Data Protection Board of India.

## 7. Sharing

We don't sell your data or use it for advertising. We share only with:
- **Service providers** that process data for us under contract:
  - Supabase: database, storage and authentication, hosted in region <FILL: Supabase region>.
  - OpenAI (Moderation) or Google Cloud Vision: photo safety checks.
  - Spotify: only if you connect it. We receive your top artists; Spotify learns that you authorised Vouby.
  - RevenueCat and Google Play: subscriptions.
  - SMS and email providers: sign-in codes.
- **Authorities**, when the law requires it. We can only provide what we hold. We can't provide message contents because we don't have them.

## 8. Security

See §2 and §3. We also use:
- encrypted connections (TLS) for everything;
- short-lived sign-in tokens that rotate;
- optional two-step verification;
- access controls checked on our servers for every request;
- rate limits and security monitoring;
- screenshot blocking in the Android app.

No system is perfectly secure. If we learn of a breach affecting you, we'll notify you and the Data Protection Board of India as the law requires.

## 9. Age

Vouby is only for people aged 18 and over. We check your date of birth at sign-up, and our database refuses anyone younger. We remove accounts we find belong to anyone under 18.

## 10. Changes

When we change this policy in a way that matters, we update its version and ask you to review and accept it again in the app before you continue.
