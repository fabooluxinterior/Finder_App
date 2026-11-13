# Popup notifications (push)

Admins send a custom popup from the web dashboard (Messaging → Notifications) to everyone, free users,
trial/Fast-Track users, or one user by mobile number. Each send is logged (`push_campaigns`), recorded as a
security event, and also added to the users' in-app notification list.

How it works: the phone registers its Firebase token (`register_push_token`); the `push-send` edge function
checks admin + two-step verification in the database (`mod_push_prepare`), then sends through Firebase
Cloud Messaging. Users can switch popups off in You → Popup notifications.

## One-time setup (owner)
1. Firebase console → create a project → add an Android app with package `com.finderapp.finder`.
2. Public values go into GitHub → Settings → Secrets → Actions (they are only identifiers): `FIREBASE_API_KEY`,
   `FIREBASE_APP_ID`, `FIREBASE_SENDER_ID`, `FIREBASE_PROJECT_ID` (all in the Firebase project settings /
   `google-services.json`).
3. Project settings → Service accounts → Generate new private key. Put the whole JSON in the Supabase function
   secret `FCM_SERVICE_ACCOUNT`. Never commit it. The admin app shows only "Configured / Not configured".

Without step 2 the app shows no popups; without step 3 sends are saved in-app only and the dashboard says so.

## Chat message alerts (app closed)
When a message is stored, a database trigger (pg_net) calls the `push-message` function, which sends
"<first name>: Sent you a message" to the receiver's phones. Messages are end-to-end encrypted, so the server never
sees the content. Needs the same Firebase setup as above plus two private settings (already set on the live
project): `push_webhook_url` and `push_webhook_secret` in `app_private_settings`, and the function secret
`PUSH_WEBHOOK_SECRET` (same value). With the app open, messages arrive live through realtime and no notification is shown.

## What gets a phone notification
| Event | Notification text | Notes |
|---|---|---|
| New chat message | "Anil: Sent you a message" | Content is end-to-end encrypted, so the server cannot show it |
| New request | "Meera sent you a request" | Free plan: "You have a new request" (the sender is never named) |
| Request accepted | "You're connected with Meera" | Sent to the person who asked. Declines are silent |
| Suggestions | "New people to meet" | Daily at 18:00 IST, only if Suggestions wasn't opened that day |
| Moderation, tickets, trial reminders | their own title and text | Written to the in-app notification list first |
| Dashboard message | your title and text | Sent from Messaging → Notifications |

A blocked person is never notified (and cannot send a request). Pushes use three high-importance Android channels
(Messages, Requests and updates, Announcements). `pg_cron` runs the daily suggestion nudge and hourly trial reminders.
