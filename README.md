# Parish Census — Supabase + Vercel

Serverless parish census web app.

```
parish-census/
├─ index.html      # Public census form
├─ admin.html      # Password-protected admin dashboard
├─ config.js       # Supabase URL + anon key (edit before deploy)
├─ schema.sql      # Run in Supabase SQL editor to create tables + RLS
├─ vercel.json     # Static hosting config + security headers
└─ README.md
```

## 1. Supabase setup

1. Create a project at [supabase.com](https://supabase.com).
2. Open **SQL Editor → New Query**, paste the contents of `schema.sql`, click **Run**.
3. Open **Settings → API** and copy:
   - `Project URL`  → `SUPABASE_URL`
   - `anon public key` → `SUPABASE_ANON_KEY`
4. Paste those two values into `config.js`.
5. Open **Authentication → Users** and create at least one admin user (email + password). That user will be able to sign in on `/admin`.

Row-Level Security is enabled in the schema:
- anonymous visitors can **INSERT** submissions only
- signed-in users can **SELECT** everything (admin dashboard)

## 2. Deploy to Vercel

```bash
git init
git add .
git commit -m "Parish census app"
gh repo create parish-census --public --source=. --push   # or push manually
```

Then on [vercel.com](https://vercel.com):

1. **Add New → Project** → import the repo.
2. Framework preset: **Other** (it's a static site).
3. Deploy. Vercel serves `index.html` at `/` and `admin.html` at `/admin`.

That's it — the app is live.

## 3. Local preview

```bash
python3 -m http.server 3000
# → http://localhost:3000        (form)
# → http://localhost:3000/admin  (dashboard)
```
