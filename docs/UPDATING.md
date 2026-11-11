# How app updates work (installed from GitHub)

Each push builds the app in GitHub Actions. **Server changes** (database, server
functions, settings, photo approvals) reach every phone immediately. **App changes**
(screens, logic) need the new app installed:

1. When a build is signed with the permanent release key, CI publishes the live APK as a
   GitHub Release named `build-<number>` (the newest 5 are kept).
2. The app asks GitHub for the latest release (at launch, and when it returns after more
   than 6 hours) and shows **"A new version is available"** with an **Update** button.
   You > App version also checks on tap.
3. **Update** opens the download. Android asks to install it over the current app; the
   account and the chats on that phone are kept (same key, higher build number).

Direct link (always the newest):
`https://github.com/fabooluxinterior/Finder_App/releases/latest/download/finder-live-arm64.apk`

A silent background update is not possible for an app installed this way; Google Play
(testing track) is the route for that.

## One-time setup: the permanent signing key

Builds are only published as releases when these repository secrets exist
(GitHub > Settings > Secrets and variables > Actions):

| Secret | What |
|---|---|
| `KEYSTORE_BASE64` | the release keystore, base64 on one line |
| `KEYSTORE_PASSWORD` | keystore password |
| `KEY_ALIAS` | key alias (`vouby`) |
| `KEY_PASSWORD` | key password |

**Back the key up.** If it is lost, installed apps can no longer be updated (they must be
uninstalled). Never commit it. Without the secrets, CI still builds, signed with a
temporary debug key, and publishes no release.

The first time after switching to the permanent key, each phone must **uninstall the old
app once** (its signature differs). Later builds install over it.

## Build numbers
`--build-number=$GITHUB_RUN_NUMBER` sets the Android version code and
`--dart-define=BUILD_NUMBER` tells the app its own number. Local builds have number 0 and
never show the update banner.
