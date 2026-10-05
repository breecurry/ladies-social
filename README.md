# Hersciety

A social platform built as a safe space for women and their allies.
Threads-like in function, its own thing in identity.

> `ladies-social` is the original repo name. The product is **Hersciety** —
> spelled H-E-R-S-C-I-E-T-Y, with an S.
> Three naming layers, deliberately distinct: **Hersciety** is the brand and
> the canonical domain (hersciety.com); **United Feminist** is the company,
> whose unitedfeminist.com is the secondary domain (it redirects to
> hersciety.com) and still owns all email addresses; **Curry Co LLC** is the
> legal entity. Do not "fix" one layer into another.
> ⚠️ **"Herciety" (no S) is a MISSPELLING, and herciety.com is a different
> domain owned by an unrelated third party. Never reference either; do not
> "correct" the spelling back.** The misspelled handle stays reserved in the
> database purely as an impersonation guard.

## What this is

Short posts, threaded replies, likes, resharing, follows, direct messages
with photos, and search. Mobile-first responsive web first; native iOS and
Android later off the same API.

Simple on the surface, genuinely sophisticated underneath. Safety is treated
as architecture rather than as a settings page.

## Core decisions

| Decision         | Choice                                                                                                                |
| ---------------- | --------------------------------------------------------------------------------------------------------------------- |
| Platform         | Mobile-first responsive **web** first; native later off the same API                                                  |
| Minimum age      | 18+                                                                                                                   |
| Admission        | **Open registration.** Everyone is welcome; there is no invite, vouch, or approval queue.                              |
| Gender screening | **None anywhere.** Membership is never based on appearance or identity.                                                |
| Identity         | Real name **required at signup**; public display is **opt-in**. The handle is shown by default.                        |
| Inclusivity      | Trans women are women and are fully included. Non-negotiable.                                                         |
| Removal          | Conduct-based, applied equally regardless of gender                                                                   |
| Direct messages  | In the first release, with photo attachments                                                                          |
| Encryption       | Encrypted in transit and at rest; reported messages reviewable via franking. Built on an end-to-end-ready foundation. |
| Moderation       | AI-first triage with human escalation where law and severity require it                                               |
| Legal entity     | Curry Co LLC — Tennessee                                                                                              |

## Why "allies"

This is a safe space for women not because only women are present, but
because only women's allies are present. Men who genuinely oppose patriarchy
are part of the work, and excluding them from it is counterproductive. The
standard is behaviour, not identity.

## Why names are collected but not displayed

Every member is known to the platform — real names are required at signup,
so nobody here is anonymous and ban evasion stays hard. What the
_public_ sees is a handle, unless a member chooses otherwise. This is
pseudonymity with accountability, and it matters because a member may be
hiding from someone specific.

## Status

Phase 1 (identity, open signup, roles, audit) is built, and the former
vouch/admission gate has been removed in favour of open registration.
See `PROGRESS.md`.

## Development

Next.js (App Router, TypeScript strict) + Supabase + Tailwind v4. The
design tokens in `src/app/globals.css` are the authoritative visual
system (light and dark).

```bash
npm install
cp .env.example .env.local   # fill in Supabase project values
npm run dev
```

Checks: `npm run typecheck` · `npm run lint` · `npm run build` ·
`npm run format:check`.

Database: SQL migrations live in `supabase/migrations/` (apply in order
with `supabase db push` or psql). `supabase/tests/` contains a local
smoke test of the security invariants — see its README.

First-run setup against a fresh Supabase project is a single command:

```bash
npm run provision
```

`scripts/provision.sh` finds the project (by `SUPABASE_PROJECT_REF`, preferred,
or exact name; creating a new one requires an explicit
`SUPABASE_ALLOW_CREATE=yes`), applies the migrations, enables
`pg_cron`, sets the required auth posture (30-minute JWTs, refresh-token
rotation, mandatory email confirmation, TOTP + WebAuthn MFA), writes the app
keys into `.env.local`, and runs `npm run bootstrap` to create the Owner and the
"Hersciety" system account. It is idempotent and never prints a secret.
The env vars it needs, and the few steps that are irreducibly manual (upgrading
the org to Pro, minting the access token), are documented in
[`docs/provisioning.md`](docs/provisioning.md).

After provisioning, **sign in as the Owner and enroll MFA immediately** — role
grants, audit reads and contact-info views refuse to run without a step-up
(AAL2), and that is enforced in the database, not the UI.

## On originality

Functionally comparable to Meta's Threads, which is fine — interaction
patterns are not protectable. Trade dress is. The design system deliberately
diverges on palette, typography, post card geometry, composer layout,
iconography, and the visual language of threaded replies.
