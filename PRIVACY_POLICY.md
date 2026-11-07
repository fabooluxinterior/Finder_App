# Finder Privacy Policy

**Draft. Have this reviewed by a lawyer before publishing** (India's Digital Personal Data Protection Act, 2023, plus Google Play's User Data policy). Fill in every `[bracketed]` item. Last updated: [date].

Finder ("we") is a private social connection app operated by [legal entity name, address]. This policy explains what we collect, how we protect it, and what control you have. Contact our Grievance Officer at [name, email, address].

## 1. What we collect

| Information | Why | Visible to |
|---|---|---|
| Phone number or email | Signing you in with one-time codes | Only you and our systems, never other users |
| Name, age, district/city, bio, main photo | Your public card in Discover | Signed-in Finder users who haven't blocked you or been blocked by you |
| Extra photos and interests | Your private profile | Only people whose follow request you accepted, or who accepted yours |
| Follow requests, passes, matches, Direct DM notes | Running the app's core features | You and the other person; notes only to the recipient |
| Messages and voice notes | Chat | **Only you and the other person** (end-to-end encrypted, see §3) |
| Message metadata: who messaged whom, when, read status | Delivering messages and unread counts | Our systems; not readable by other users |
| Device keys (public) and device type | Making encryption work across your devices | People you're connected to (public keys only) |
| Subscription status | The Fast-Track pass | You. Payment details are handled by Google Play; we never see them |
| Security logs (sign-in events, rate-limit hits, failed access attempts) | Protecting accounts and detecting abuse | Our security staff |
| Reports you make or receive | Keeping Finder safe | Our safety team |

We don't collect your precise location, contacts, or photos you don't upload. We strip location (GPS) and other hidden data from every photo before storing it.

## 2. How we store your photos

- Photos go to a private quarantine area, are checked to be real images, cleaned of hidden metadata, and screened automatically for nudity and violence (by Google Cloud Vision, which processes the image only to return a safety rating). Some are reviewed by a person before they appear.
- Every stored photo is encrypted with its own key (AES-256-GCM). Those keys are themselves encrypted with a master key kept outside our database.
- Photos are never available at a public link. Each view is checked against your permissions at that moment, so a copied link doesn't work for anyone else.

## 3. How your conversations are protected

- Messages and voice notes are **end-to-end encrypted** on your phone before they're sent, using the Olm / Double Ratchet protocol (the protocol used by Matrix, via the independently audited `vodozemac` library). Only your devices and the other person's devices have the keys.
- **We cannot read your messages or listen to your voice notes**, and we have no way to decrypt them. That includes our staff, our hosting providers, and anyone who obtains our servers' data.
- We can see that a message was sent, between whom, and when. We need this to deliver it.
- Encrypted copies are deleted from our servers once your device receives them, or after 30 days if a device never collects them.
- Your conversation history is stored on your phone, encrypted with a key held in your phone's secure hardware. Signing out deletes it from that phone.
- You can compare a *safety number* with the other person to confirm nobody is intercepting your chat.

## 4. Moderation and what moderators can see

Because chats are end-to-end encrypted, moderators can't see them unless **you choose to share them**.
- When you report someone, you can tick a box to include up to 20 of their recent messages. Those messages are decrypted on your phone and sent with your report. We tell you this on the report screen before you send.
- Only trained members of our safety team can open report evidence. They must verify their identity with two-step verification and record a reason, and every access is permanently logged.
- Photos are screened before they're published (see §2). Bios and request notes can't contain phone numbers, social media handles or links.
- Report evidence is deleted 90 days after the report is closed.

## 5. How long we keep information

| Data | Kept |
|---|---|
| Account and profile | Until you delete your account |
| Undelivered encrypted messages | Until delivered, or at most 30 days |
| Message metadata | Until you or the other person unmatches or blocks, or either account is deleted |
| Removed photos | Unavailable immediately; storage purged within [24 hours] |
| Report evidence | 90 days after the report is resolved |
| Security logs | 1 year |
| Backups | Rolling, up to 7 days ([or your PITR window]) |

## 6. Your choices and rights

- **Edit or remove** your profile, photos and interests at any time.
- **Unmatch or block** anyone. This ends the chat for both of you and deletes the conversation data on our servers. We can't delete copies already on the other person's phone.
- **Two-step verification, devices and sessions:** in *Profile → Privacy & security* you can turn on an authenticator app, see every signed-in session and device, and remove any of them.
- **Delete your account** in *Privacy & security*. We delete your profile, photos, encryption keys, connections and server-side message data immediately. Encrypted backups are overwritten within 7 days. Messages already delivered to other people's phones stay on their phones.
- Under the DPDP Act you may request access to, correction of, or erasure of your data, and nominate someone to act for you. Email [privacy@...]. We respond within [30] days.

## 7. Sharing

We don't sell your data or use it for advertising. We share only with:
- **Service providers** that process data for us under contract: Supabase (database, storage and authentication; region [ap-south-1 / Mumbai]), Google Cloud Vision (photo safety checks), RevenueCat and Google Play (subscriptions), and SMS/email providers (sign-in codes).
- **Authorities**, when the law requires it. We can only provide what we hold. We can't provide message contents because we don't have them.

## 8. Security

See §2 and §3. We also use:
- encrypted connections (TLS) for everything;
- short-lived sign-in tokens that rotate;
- optional two-step verification;
- strict access controls checked on our servers for every request;
- rate limits and security monitoring;
- screenshot blocking in the Android app.

No system is perfectly secure. If we learn of a breach affecting you, we'll notify you and the Data Protection Board of India as the law requires.

## 9. Age

Finder is only for people aged 18 and over. We delete accounts we find belong to anyone younger.

## 10. Changes

We'll notify you in the app before material changes take effect.
