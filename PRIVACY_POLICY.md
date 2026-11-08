# Vouby Privacy Policy

**Version 2026-11-10.** Draft: have this reviewed by a lawyer before publishing (India's Digital Personal Data Protection Act, 2023, and Google Play's User Data policy).

Vouby ("we", "us") is operated by **<FILL: Company name>**, **<FILL: Registered address>**. This policy explains what we collect, how we protect it, and what control you have.

- **Grievance Officer:** <FILL: Grievance Officer name>, <FILL: Grievance Officer email>
- **Privacy requests:** <FILL: Privacy email>

## 1. What we collect

| Information | Why | Visible to |
|---|---|---|
| Phone number or email | Signing you in with one-time codes | Only you and our systems. Never shown to other users |
| Date of birth | Confirming you're 18 or older and showing your age | Only you. Other users see your age, never your date of birth |
| Name, age, district/city, bio, photos, interests | Your profile | Every signed-in Vouby user, except people you've blocked or who blocked you |
| Verification selfie and the pose you were asked to make | Confirming your photos are really you | Only our trained verification staff. Never other users |
| Follow requests, passes and matches | Running the app's core features | You and the other person |
| Messages and voice notes | Chat | **Only you and the other person** (end-to-end encrypted, see §3) |
| Message metadata: who messaged whom, when, read status | Delivering messages and unread counts | Our systems. Not readable by other users |
| Device keys (public) and device type | Making encryption work across your devices | People you're connected to (public keys only) |
| Policy acceptances (which version, when) | Keeping a record of your consent | You and our systems |
| Subscription status | The Fast-Track subscription | You. Payment details are handled by Google Play; we never see them |
| Security logs (sign-in events, rate-limit hits, failed access attempts) | Protecting accounts and detecting abuse | Our security staff |
| Reports you make or receive | Keeping Vouby safe | Our safety team |

**What we never show other users:** your phone number, your email, your date of birth, your exact location, or links to other social media. We block phone numbers, social media handles and links in names, bios and interests, and filter them from the first messages of every chat. Your location is only the district or city you choose; we never collect GPS location. We remove location data (GPS) and other hidden metadata from every photo before storing it.

## 2. How we store your photos

- Photos go into a private quarantine area first. We check they're real images, remove hidden metadata, and screen them automatically for nudity and violence. Google Cloud Vision processes the image only to return a safety rating. Some photos are reviewed by a person before they appear.
- Every stored photo is encrypted with its own key (AES-256-GCM). Those keys are themselves encrypted with a master key kept outside our database.
- Photos are never available at a public link. Each view checks that the viewer is signed in and allowed to see it, so a copied link doesn't work for anyone else.
- **Verification selfies** go through the same pipeline but are never shown on your profile. Only verification staff can view them, every view is logged, and they're deleted 30 days after the review.

## 3. How your conversations are protected

- Messages and voice notes are **end-to-end encrypted** on your phone before they're sent, using the Olm / Double Ratchet protocol (the protocol used by Matrix, via the independently audited `vodozemac` library). Only your devices and the other person's devices have the keys.
- **We can't read your messages or listen to your voice notes**, and we have no way to decrypt them. That includes our staff, our hosting providers, and anyone who obtains our servers' data.
- We can see that a message was sent, between whom, and when. We need this to deliver it.
- Encrypted copies are deleted from our servers once your device receives them, or after 30 days if a device never collects them.
- Your conversation history is stored on your phone, encrypted with a key held in your phone's secure hardware. Signing out deletes it from that phone.

## 4. Moderation and what moderators can see

Because chats are end-to-end encrypted, moderators can't see them unless **you choose to share them**.
- When you report someone, you can tick a box to include up to 20 of their recent messages. They're decrypted on your phone and sent with your report. We tell you this on the report screen before you send.
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
| Removed photos | Unavailable immediately; deleted from storage within 24 hours |
| Report evidence | 90 days after the report is resolved |
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
  - Google Cloud Vision: photo safety checks.
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
