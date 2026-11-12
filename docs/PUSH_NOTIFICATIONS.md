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
