# Vouby admin (web)

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
