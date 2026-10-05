# Provisioning a Supabase project for Hersciety

Nothing in this product runs until a Supabase project exists. This document
describes the **one-command** path to a fully configured project, and — honestly
— the small number of things that still require a human in the Supabase
dashboard because Supabase provides no API for them.

The whole flow is driven by `scripts/provision.sh` (wired up as
`npm run provision`). It is **idempotent**: run it again and it reuses the
existing project, skips already-applied migrations, re-asserts configuration,
and skips bootstrapping if the Owner already exists. It finds the project by
`SUPABASE_PROJECT_REF` when given (preferred — refs are immutable), falling
back to an exact-name match on `SUPABASE_PROJECT_NAME`; when neither matches
anything it **stops with an error** instead of creating a project, unless you
explicitly pass `SUPABASE_ALLOW_CREATE=yes` for a first-time setup.

> **Secrets:** the script reads every credential from environment variables,
> writes the app keys to `.env.local` (mode `600`), and prints only
> fingerprints (length / prefix / present-absent) — never a secret value.

---

## 1. Before you run it (prerequisites)

1. **Install the Supabase CLI** — <https://supabase.com/docs/guides/local-development/cli/getting-started>
   The script calls `supabase` directly, so you need a **global** install:
   - macOS / Linux: `brew install supabase/tap/supabase`
   - Windows: `scoop install supabase`

   ⚠️ **Do NOT install it as a project dependency** (`npm install supabase --save-dev`).
   That method deliberately provides **no global `supabase` command** — you would have
   to run `npx supabase` — and this script's preflight check will fail with
   "'supabase' is required but not on PATH".
   Docker is **not** required: `supabase db push` talks to the hosted project
   directly. You only need a container runtime for `supabase start` (the local
   stack), which this flow never uses.
   *(Install methods verified against the official CLI docs 2026-10-02.)*
2. **Install Node.js** (already required to build the app) and run `npm install`.
3. **Create a Supabase account and an organization**, and **put that
   organization on the Pro plan** — this is a dashboard-only step, see
   [§4](#4-what-still-needs-the-dashboard-and-why).
4. **Generate a personal access token (PAT)**: dashboard → **Account →
   Access Tokens → Generate new token**
   (<https://supabase.com/dashboard/account/tokens>). Copy it once; you cannot
   see it again.

---

## 2. Environment variables the script reads

Set these in your shell before running. **Values are never committed or printed.**

| Variable | Required | Where to get it / what it is |
| --- | --- | --- |
| `SUPABASE_ACCESS_TOKEN` | **yes** | The PAT from Account → Access Tokens. This is the single trigger. |
| `SUPABASE_DB_PASSWORD` | **yes** | A strong Postgres password **you choose** (≥12 chars). The script assigns it at project creation; keep it in your password manager — Supabase cannot show it to you later. |
| `OWNER_EMAIL` | **yes** | The founder/Owner login email. |
| `OWNER_PASSWORD` | **yes** | The Owner's initial password (change + add MFA right after). |
| `OWNER_HANDLE` | **yes** | The Owner's public @handle. |
| `OWNER_LEGAL_NAME` | **yes** | The Owner's verified legal name (stored privately). |
| `OWNER_DOB` | **yes** | Owner date of birth, `YYYY-MM-DD` (18+). |
| `OWNER_PHONE` | no | Owner phone in E.164 (`+1…`), optional. |
| `SUPABASE_ORG_SLUG` | no | Which organization to create the project in. Auto-detected if you belong to exactly one; required if you belong to several. Find it in the dashboard org URL `…/org/<slug>`. |
| `SUPABASE_PROJECT_REF` | no, but preferred | The live project's ref — the 20-character id in the dashboard URL (currently `hiphjzhlwiztqgezzipf`). When set, the script uses the project directly and never matches by name. |
| `SUPABASE_PROJECT_NAME` | no | Defaults to `Hersciety`, the hosted project's exact current name (renamed 2026-10-06). Only consulted when no ref is given; if nothing matches, the script stops rather than creating a project. |
| `SUPABASE_ALLOW_CREATE` | no | Set to exactly `yes` to allow creating a brand-new project (first-time setup only). This is deliberately not the default: silent project creation on a name mismatch is how the original project got duplicated and then deleted by accident on 2026-10-06. |
| `SUPABASE_REGION` | no | Defaults to `us-east-1` (US launch). |
| `SUPABASE_INSTANCE_SIZE` | no | Defaults to `micro` (the compute the Pro plan includes). Needs a Pro org. |
| `SITE_URL` | no | Defaults to `https://hersciety.com` (the canonical domain). Sets the auth Site URL and redirect allow-list. |
| `WEBAUTHN_RP_ID` | no | Defaults to `hersciety.com`. The WebAuthn Relying-Party ID — **permanent once members hold passkeys** (changing it then invalidates all of them). |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, `SMTP_ADMIN_EMAIL`, `SMTP_SENDER_NAME` | strongly recommended | Custom SMTP (Resend). Without these, email confirmation stays **on** (as required) but the built-in mailer only sends to org-team addresses at ~2/hour — fine for your own first login, useless for public signups. Create a Resend SMTP credential in the Resend dashboard. |

Run it:

```bash
npm run provision
# or:  ./scripts/provision.sh
```

---

## 3. What the script automates (in order)

Each step below is done by the Management API with your PAT, or by the Supabase
CLI, with **no dashboard clicking**:

1. **Preflight.** Verifies `curl`, `node`, `supabase`, `npm` are installed and
   that all required env vars are present; prints fingerprints only.
2. **Resolve the organization.** `GET /v1/organizations`; auto-selects your only
   org or uses `SUPABASE_ORG_SLUG`.
3. **Resolve the project.** Uses `SUPABASE_PROJECT_REF` directly when given;
   otherwise matches `SUPABASE_PROJECT_NAME` exactly. When nothing matches it
   stops with instructions; only with `SUPABASE_ALLOW_CREATE=yes` does it
   `POST /v1/projects` with `name`, `organization_slug`, `db_pass`, `region`,
   `desired_instance_size`.
4. **Wait for health.** Polls `GET /v1/projects/{ref}/health` until the db, auth
   and rest services report `ACTIVE_HEALTHY`.
5. **Enable `pg_cron`** via `POST /v1/projects/{ref}/database/query`
   (`create extension if not exists pg_cron;`) — done **before** migrations so
   migrations that manage scheduled jobs can run. (Migration 0010's vouch-lapse
   job is removed again by migration 0011 now that admission is gone; pg_cron
   stays for the job load of later phases.)
6. **Apply migrations** with `supabase link --project-ref … && supabase db push
   --linked` (history-tracked in `supabase_migrations.schema_migrations`;
   re-runs skip applied migrations; no Docker needed for push).
7. **Configure Auth** via `PATCH /v1/projects/{ref}/config/auth`:
   - `jwt_exp = 1800` — **30-minute** access tokens
   - `refresh_token_rotation_enabled = true` + `security_refresh_token_reuse_interval = 10`
   - `mailer_autoconfirm = false` — **email confirmation required**
   - `mfa_totp_enroll_enabled` / `mfa_totp_verify_enabled = true` — **TOTP**
   - `mfa_web_authn_enroll_enabled` / `mfa_web_authn_verify_enabled = true` — **WebAuthn**
   - `webauthn_rp_id`, `webauthn_rp_origins`, `site_url`, `uri_allow_list`
   - custom SMTP (if `SMTP_*` supplied)
8. **Retrieve API keys** (`GET /v1/projects/{ref}/api-keys?reveal=true`) and the
   project URL, and write `NEXT_PUBLIC_SUPABASE_URL`,
   `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` into `.env.local`
   (mode `600`), preserving any other lines already there.
9. **Seed the Owner + system account** by running `npm run bootstrap` — but only
   if `auth.users` is empty (so a re-run is a no-op).
10. **Verify** the posture actually took: re-reads the auth config and asserts
    the 30-minute JWT, rotation, email confirmation, TOTP and WebAuthn are all
    on, and that `pg_cron` is installed. Any drift fails loudly.

After it finishes: **sign in as the Owner and enrol MFA immediately.** Role
grants, audit reads and contact-info views refuse to run below AAL2 — that is
enforced in the database, not the UI.

---

## 4. What still needs the dashboard (and why)

These cannot be automated with a PAT because Supabase exposes no API for them.
Click-paths are written for a non-technical person.

### A. Put the organization on the **Pro** plan — *required for production*

The project-creation API **ignores** the plan field: the plan is a property of
the **organization**, and there is no public billing/subscription endpoint, so a
card has to go on file by hand.

1. Go to <https://supabase.com/dashboard>.
2. In the top-left project/org switcher, choose your organization.
3. In the left sidebar click **Billing** (or **Settings → Billing**).
4. Click **Change subscription / Upgrade**, choose **Pro ($25/mo)**.
5. Enter your card details and confirm.

Do this **before** running the script if you want the project created on Pro
with a `micro` instance. (On a Free org the script can still create a project if
you set `SUPABASE_INSTANCE_SIZE=nano`, but a Free project pauses after 7 days of
inactivity and is not suitable for launch.)

### B. Generate the **personal access token** — *required, one time*

A token cannot create a token, so the first PAT is minted by hand.

1. Go to <https://supabase.com/dashboard/account/tokens>.
2. Click **Generate new token**, name it (e.g. "provisioning"), **Generate**.
3. Copy it immediately into `SUPABASE_ACCESS_TOKEN`. You cannot view it again.

### C. (If you use Resend for email) create the **Resend SMTP credential**

Email confirmation is deliberately **on**, and the built-in Supabase mailer is
rate-limited to a few messages/hour and only to your org-team addresses — not
viable for public signups. The fix is custom SMTP, which the script *will*
configure automatically, but the Resend credential itself is created in Resend:

1. Log in at <https://resend.com> → **API Keys** (and verify your sending
   domain under **Domains**).
2. Create a key; use Resend's SMTP settings
   (`host = smtp.resend.com`, `port = 465`, `user = resend`, `pass = <the key>`)
   as `SMTP_HOST` / `SMTP_PORT` / `SMTP_USER` / `SMTP_PASS`.

> Everything else — every security setting in [§3](#3-what-the-script-automates-in-order) —
> is done by the script. Do **not** "fix" email delivery by turning on
> auto-confirm; that disables the required email-confirmation step.

---

## 5. AUTOMATABLE vs DASHBOARD-ONLY — the verified reference

Verified **2026-10-02** against the live Management API OpenAPI spec
(<https://api.supabase.com/api/v1-json>) and the cited docs.

| Capability | Verdict | How |
| --- | --- | --- |
| Create project in an org (name, region, db password) | **AUTOMATABLE** | `POST /v1/projects` — <https://supabase.com/docs/reference/api/v1-create-a-project> |
| Set the project to the **Pro** tier | **DASHBOARD-ONLY** | Plan is org-level; `plan` on create is deprecated and **ignored** ("Subscription Plan is now set on organization level"). No billing API. See create-project doc above; Billing in the dashboard. |
| 30-minute JWT / access-token expiry | **AUTOMATABLE** | `PATCH …/config/auth` `jwt_exp:1800` — <https://supabase.com/docs/reference/api/v1-update-auth-service-config> |
| Refresh-token rotation | **AUTOMATABLE** | same PATCH: `refresh_token_rotation_enabled`, `security_refresh_token_reuse_interval` |
| Require email confirmation | **AUTOMATABLE** | same PATCH: `mailer_autoconfirm:false` — shown in <https://supabase.com/docs/guides/auth/auth-smtp> |
| MFA TOTP | **AUTOMATABLE** | same PATCH: `mfa_totp_enroll_enabled`, `mfa_totp_verify_enabled` |
| MFA WebAuthn | **AUTOMATABLE** | same PATCH: `mfa_web_authn_enroll_enabled`, `mfa_web_authn_verify_enabled` (+ `webauthn_rp_id`/`_origins`) |
| Enable `pg_cron` | **AUTOMATABLE** | `POST …/database/query` → `create extension if not exists pg_cron;` — <https://supabase.com/docs/guides/cron/install> (query endpoint is marked experimental) |
| Retrieve API keys | **AUTOMATABLE** | `GET …/api-keys?reveal=true` — <https://supabase.com/docs/reference/api/v1-get-project-api-keys> |
| Retrieve DB connection string | **AUTOMATABLE** | `GET …/config/database/pooler` (host/user/port; inject the password you set) — Management API reference |
| Run SQL / apply migrations | **AUTOMATABLE** | `supabase db push` — <https://supabase.com/docs/reference/cli/supabase-db-push> ; non-interactive env in <https://supabase.com/docs/guides/deployment/managing-environments> |

**Irreducible dashboard clicking:** (1) generate the first PAT, (2) upgrade the
org to Pro, (3) if using Resend, create the Resend API key. That's it.

---

## 6. Troubleshooting

- **`supabase link` fails with a SASL / pooler error.** This is a known
  intermittent CLI issue in some networks. Make sure your CLI is current, then
  apply migrations directly instead of via `link`:
  ```bash
  # session pooler (port 5432) — get host/user from: GET /v1/projects/<ref>/config/database/pooler
  supabase db push --db-url "postgresql://postgres.<ref>:<url-encoded-password>@<region>.pooler.supabase.com:5432/postgres"
  ```
  (Use the **session** pooler on 5432, not the transaction pooler on 6543.)
- **Project creation returns an error about the plan or instance size.** The org
  is probably still on Free — upgrade to Pro (§4A) or set
  `SUPABASE_INSTANCE_SIZE=nano`.
- **Confirmation emails never arrive.** You have not configured custom SMTP
  (§4C). Email confirmation is required by design; configure Resend rather than
  disabling it.
