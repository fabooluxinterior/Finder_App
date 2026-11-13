# Vouby admin (web)

**Published at https://fabooluxinterior.github.io/Finder_App/** by
`.github/workflows/admin-pages.yml` on every push that touches `admin/` or a
migration. It adds a website only; the Vouby app in this repo is unchanged.
One-time repo settings: **Pages → Source: GitHub Actions**, and **Environments
→ github-pages → Deployment branches** must allow the branch you publish from.
Without the `SUPABASE_URL` / `SUPABASE_ANON_KEY` repo secrets the site is a
sample-data preview; with them it's the live admin (also add
`https://fabooluxinterior.github.io` to `ALLOWED_ORIGINS` and Supabase Auth URL
configuration).

Staff-only web app for Vouby: Safety (reports, photo review, verification,
security overview), **Settings → Database & Data Migration** and **Settings →
Integrations & credentials**. It talks to the same Supabase project as the app
with the public anon key; every action is checked in the database (admin role +
two-step verification). It never holds or shows secrets.

```bash
# from the repo root
python3 tool/gen_admin_manifest.py            # refresh the migration list (CI checks it)
cd admin
flutter build web --release \
  --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon key>
# preview without a backend (sample data, clearly labelled):
flutter build web --release --dart-define=ADMIN_DEMO=true
```

Host `admin/build/web` on any static host (Netlify, Vercel, Cloudflare Pages,
GitHub Pages). Add its address to Supabase **Auth → URL configuration** and to
the `ALLOWED_ORIGINS` function secret. Staff sign in with their email code and
their authenticator app (set up in the Vouby app under You → Security).
