#!/usr/bin/env bash
#
# provision.sh — one-command Supabase provisioning for United Feminist.
#
# Given a Supabase personal access token (PAT) and a handful of values, this
# creates the project, applies the migrations, turns on every security setting
# the product requires (30-minute JWTs, refresh-token rotation, mandatory email
# confirmation, TOTP + WebAuthn MFA, pg_cron), writes the app keys to
# .env.local, and seeds the Owner + system account via `npm run bootstrap`.
#
# It is idempotent: re-running reuses the existing project, skips already-applied
# migrations, re-asserts config (a no-op if already set) and skips the bootstrap
# if the Owner already exists.
#
# WHAT IT CANNOT DO (no API exists): put the organization on the Pro plan. That
# is a one-time card-on-file step in the dashboard. See docs/provisioning.md.
#
# SECURITY: no secret value is ever printed. Credentials are read from the
# environment only; API responses are written to a 0600 temp file that is shred
# on exit; the generated keys go to .env.local (0600). stdout gets fingerprints
# (length / prefix / present-absent) and never values.
#
# Verified against the live Supabase Management API OpenAPI spec and the CLI
# reference on 2026-10-02. See docs/provisioning.md for the cited endpoints.

set -euo pipefail

# ----------------------------------------------------------------------------
# Small helpers
# ----------------------------------------------------------------------------
API_BASE="https://api.supabase.com"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

c_red=$'\033[31m'; c_grn=$'\033[32m'; c_yel=$'\033[33m'; c_dim=$'\033[2m'; c_off=$'\033[0m'
step() { printf '\n%s==>%s %s\n' "$c_grn" "$c_off" "$*" >&2; }
info() { printf '    %s\n' "$*" >&2; }
warn() { printf '%sWARN:%s %s\n' "$c_yel" "$c_off" "$*" >&2; }
die()  { printf '%sERROR:%s %s\n' "$c_red" "$c_off" "$*" >&2; exit 1; }

# Redact the PAT from any text we ever print (belt and braces; we try never to).
redact() { sed -e "s/${SUPABASE_ACCESS_TOKEN:-__nope__}/[REDACTED-PAT]/g" \
               -e "s/${SUPABASE_DB_PASSWORD:-__nope__}/[REDACTED-DBPASS]/g"; }

# Fingerprint a value without revealing it.
# SECURITY: a 4-char prefix is safe for tokens whose prefix is a PUBLIC namespace
# (e.g. "sbp_"), but it is NOT safe for passwords — those 4 characters are real
# secret material, they get printed to a terminal, and terminals get screenshotted
# and pasted into chat. Pass "secret" as $3 to suppress the prefix entirely.
fp() {
  local name="$1" val="${2:-}" mode="${3:-}"
  if [[ -z "$val" ]]; then printf '    %-28s absent\n' "$name:" >&2; return; fi
  local len=${#val}
  if [[ "$mode" == "secret" ]]; then
    printf '    %-28s present (len=%s, value hidden)\n' "$name:" "$len" >&2
  else
    printf '    %-28s present (len=%s, prefix=%s…)\n' "$name:" "$len" "${val:0:4}" >&2
  fi
}

# Secure scratch file for API bodies; one file, reused, shred on exit.
RESP="$(mktemp)"; chmod 600 "$RESP"
BODY="$(mktemp)"; chmod 600 "$BODY"
cleanup() {
  local f
  for f in "$RESP" "$BODY"; do
    [[ -n "${f:-}" && -f "$f" ]] && { shred -u "$f" 2>/dev/null || rm -f "$f"; }
  done
  return 0   # never let trap cleanup change the script's exit status
}
trap cleanup EXIT

# node is guaranteed (this is a Node project) — use it for all JSON work so we
# need no `jq`. jget FILE 'JS-expr on d' ; the expr is evaluated with d = parsed JSON.
jget() {
  node -e 'const fs=require("fs");let d;try{d=JSON.parse(fs.readFileSync(process.argv[1],"utf8"))}catch(e){d=null};const v=(new Function("d","return ("+process.argv[2]+")"))(d);process.stdout.write(v==null?"":String(v));' "$1" "$2"
}

# api METHOD PATH [BODY_FILE] -> echoes HTTP status; response left in $RESP.
api() {
  local method="$1" path="$2" body="${3:-}" code
  if [[ -n "$body" ]]; then
    code="$(curl -sS -X "$method" "$API_BASE$path" \
      -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
      -H "Content-Type: application/json" \
      --data "@$body" -o "$RESP" -w '%{http_code}')" \
      || die "network error on $method $path"
  else
    code="$(curl -sS -X "$method" "$API_BASE$path" \
      -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
      -o "$RESP" -w '%{http_code}')" \
      || die "network error on $method $path"
  fi
  printf '%s' "$code"
}

api_ok() { # fail loudly unless status is one of the expected codes
  local code="$1"; shift
  local want
  for want in "$@"; do [[ "$code" == "$want" ]] && return 0; done
  die "API returned HTTP $code — $(cat "$RESP" | redact | head -c 500)"
}

# ----------------------------------------------------------------------------
# 0. Preflight — tools, required inputs, fingerprints
# ----------------------------------------------------------------------------
step "Preflight"

for bin in curl node supabase npm; do
  command -v "$bin" >/dev/null 2>&1 || die "'$bin' is required but not on PATH. See docs/provisioning.md."
done
info "tooling: curl, node $(node -v), supabase $(supabase --version 2>/dev/null | head -1), npm present"

: "${SUPABASE_ACCESS_TOKEN:?set SUPABASE_ACCESS_TOKEN (your Supabase personal access token)}"
: "${SUPABASE_DB_PASSWORD:?set SUPABASE_DB_PASSWORD (the Postgres password to assign)}"
: "${OWNER_EMAIL:?set OWNER_EMAIL}"
: "${OWNER_PASSWORD:?set OWNER_PASSWORD}"
: "${OWNER_HANDLE:?set OWNER_HANDLE}"
: "${OWNER_LEGAL_NAME:?set OWNER_LEGAL_NAME}"
: "${OWNER_DOB:?set OWNER_DOB (YYYY-MM-DD)}"

# Optional inputs with sensible, product-correct defaults.
PROJECT_NAME="${SUPABASE_PROJECT_NAME:-United Feminist}"
REGION="${SUPABASE_REGION:-us-east-1}"               # US-only launch
INSTANCE_SIZE="${SUPABASE_INSTANCE_SIZE:-micro}"     # Pro includes one Micro
SITE_URL="${SITE_URL:-https://unitedfeminist.com}"
WEBAUTHN_RP_ID="${WEBAUTHN_RP_ID:-unitedfeminist.com}"
OWNER_PHONE="${OWNER_PHONE:-}"

[[ ${#SUPABASE_DB_PASSWORD} -ge 12 ]] || die "SUPABASE_DB_PASSWORD must be at least 12 characters."

info "inputs (fingerprints only — no values are printed):"
fp "SUPABASE_ACCESS_TOKEN" "$SUPABASE_ACCESS_TOKEN"
fp "SUPABASE_DB_PASSWORD"  "$SUPABASE_DB_PASSWORD" secret
fp "OWNER_EMAIL"           "$OWNER_EMAIL"
fp "OWNER_PASSWORD"        "$OWNER_PASSWORD" secret
fp "OWNER_HANDLE"          "$OWNER_HANDLE"
fp "OWNER_PHONE"           "$OWNER_PHONE"
info "project=\"$PROJECT_NAME\" region=$REGION size=$INSTANCE_SIZE site=$SITE_URL rp_id=$WEBAUTHN_RP_ID"

SMTP_CONFIGURED="no"
if [[ -n "${SMTP_HOST:-}" && -n "${SMTP_USER:-}" && -n "${SMTP_PASS:-}" ]]; then
  SMTP_CONFIGURED="yes"
  info "custom SMTP: will be configured (host=$SMTP_HOST port=${SMTP_PORT:-587})"
else
  warn "custom SMTP not supplied. Email confirmation stays REQUIRED, but the default"
  warn "Supabase mailer sends only to org-team addresses at ~2/hour. Set SMTP_* (Resend)"
  warn "before real signups, or confirmation emails will not arrive. (See docs/provisioning.md.)"
fi

# ----------------------------------------------------------------------------
# 1. Resolve the organization
# ----------------------------------------------------------------------------
step "Resolving organization"
code="$(api GET /v1/organizations)"; api_ok "$code" 200
if [[ -n "${SUPABASE_ORG_SLUG:-}" ]]; then
  ORG_SLUG="$SUPABASE_ORG_SLUG"
  found="$(jget "$RESP" "d.some(o=>o.slug===$(node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$ORG_SLUG"))")"
  [[ "$found" == "true" ]] || die "SUPABASE_ORG_SLUG=$ORG_SLUG not found among your organizations."
else
  n="$(jget "$RESP" 'Array.isArray(d)?d.length:0')"
  [[ "$n" -ge 1 ]] || die "Your account has no organizations. Create one in the dashboard first."
  if [[ "$n" -gt 1 ]]; then
    die "You belong to $n organizations — set SUPABASE_ORG_SLUG to pick one. Slugs: $(jget "$RESP" 'd.map(o=>o.slug).join(", ")')"
  fi
  ORG_SLUG="$(jget "$RESP" 'd[0].slug')"
fi
ORG_PLAN="$(jget "$RESP" "d.find(o=>o.slug===$(node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$ORG_SLUG"))?.plan?.id || d.find(o=>o.slug===$(node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$ORG_SLUG"))?.plan || ''")"
info "organization: $ORG_SLUG (plan: ${ORG_PLAN:-unknown})"
if [[ "$INSTANCE_SIZE" != "nano" && "$ORG_PLAN" == "free" ]]; then
  warn "org plan looks like Free; instance size '$INSTANCE_SIZE' needs Pro and project creation may fail."
  warn "Upgrade the org to Pro in the dashboard (Billing), or set SUPABASE_INSTANCE_SIZE=nano for a Free trial."
fi

# ----------------------------------------------------------------------------
# 2. Create the project (or reuse an existing one with the same name)
# ----------------------------------------------------------------------------
step "Creating project (idempotent)"
code="$(api GET /v1/projects)"; api_ok "$code" 200
PROJECT_NAME_JSON="$(node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$PROJECT_NAME")"
REF="$(jget "$RESP" "d.find(p=>p.name===$PROJECT_NAME_JSON && (p.organization_slug===$(node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$ORG_SLUG")))?.ref || ''")"

if [[ -n "$REF" ]]; then
  info "reusing existing project \"$PROJECT_NAME\" (ref: $REF)"
else
  SB_NAME="$PROJECT_NAME" SB_ORG="$ORG_SLUG" SB_REGION="$REGION" SB_SIZE="$INSTANCE_SIZE" \
  node -e 'const fs=require("fs");const b={name:process.env.SB_NAME,organization_slug:process.env.SB_ORG,db_pass:process.env.SUPABASE_DB_PASSWORD,region:process.env.SB_REGION,desired_instance_size:process.env.SB_SIZE};fs.writeFileSync(process.argv[1],JSON.stringify(b),{mode:0o600});' "$BODY"
  code="$(api POST /v1/projects "$BODY")"; api_ok "$code" 200 201
  REF="$(jget "$RESP" 'd.ref')"
  [[ -n "$REF" ]] || die "project created but no ref returned"
  info "created project (ref: $REF)"
fi
PROJECT_URL="https://${REF}.supabase.co"

# ----------------------------------------------------------------------------
# 3. Wait until the database + auth are healthy
# ----------------------------------------------------------------------------
step "Waiting for services to come up (ACTIVE_HEALTHY)"
deadline=$(( $(date +%s) + 600 ))
fails=0
while :; do
  code="$(api GET "/v1/projects/${REF}/health?services=db,auth,rest&timeout_ms=5000")" || true
  if [[ "$code" == "200" ]]; then
    fails=0
    unhealthy="$(jget "$RESP" 'Array.isArray(d)?d.filter(s=>s.status!=="ACTIVE_HEALTHY").map(s=>s.name).join(",")  : "all"')"
    [[ -z "$unhealthy" ]] && { info "all services healthy"; break; }
    info "waiting on: $unhealthy"
  else
    # NEVER swallow the response body here. A bare status code cannot distinguish
    # "still booting" from "this project was never finished being created" or
    # "this organisation is on the wrong plan" — and guessing "still booting"
    # actively sends the operator looking in the wrong place for ten minutes.
    fails=$(( fails + 1 ))
    info "health check HTTP $code — $(redact < "$RESP" | tr -d '\n' | head -c 300)"
    if (( fails == 4 )); then
      warn "Four consecutive failed health checks. This is usually NOT a slow boot."
      warn "Read the message above, then check the Supabase dashboard:"
      warn "  1. Is the project actually finished being created?"
      warn "  2. Is the ORGANISATION that owns it on the plan you expect?"
    fi
  fi
  [[ $(date +%s) -lt $deadline ]] || die "timed out waiting for project $REF to become healthy — last response: $(redact < "$RESP" | tr -d '\n' | head -c 300)"
  sleep 15
done

# ----------------------------------------------------------------------------
# 4. Enable pg_cron BEFORE migrations (migration 0010 schedules a job only if present)
# ----------------------------------------------------------------------------
step "Enabling pg_cron extension"
printf '{"query":"create extension if not exists pg_cron;"}' > "$BODY"
code="$(api POST "/v1/projects/${REF}/database/query" "$BODY")"; api_ok "$code" 200 201
info "pg_cron ready"

# ----------------------------------------------------------------------------
# 5. Apply migrations with the Supabase CLI (history-tracked, idempotent)
# ----------------------------------------------------------------------------
step "Applying migrations (supabase db push)"
export SUPABASE_ACCESS_TOKEN SUPABASE_DB_PASSWORD
# link reads SUPABASE_DB_PASSWORD from the env so there is no interactive prompt.
supabase link --project-ref "$REF" 2> >(redact >&2) \
  || die "supabase link failed. If this is a pooler/SASL error, see the --db-url fallback in docs/provisioning.md."
supabase db push --linked --yes 2> >(redact >&2) \
  || die "supabase db push failed — migrations were NOT fully applied."
info "migrations applied"

# ----------------------------------------------------------------------------
# 6. Configure Auth: the required security posture (idempotent PATCH)
# ----------------------------------------------------------------------------
step "Configuring Auth security settings"
SB_SITE="$SITE_URL" SB_RPID="$WEBAUTHN_RP_ID" SB_SMTP="$SMTP_CONFIGURED" \
node -e '
const fs=require("fs");
const b={
  site_url: process.env.SB_SITE,
  uri_allow_list: process.env.SB_SITE,
  disable_signup: false,
  external_email_enabled: true,
  jwt_exp: 1800,                               // 30-minute access tokens
  refresh_token_rotation_enabled: true,        // rotate refresh tokens
  security_refresh_token_reuse_interval: 10,   // reuse-detection window (seconds)
  mailer_autoconfirm: false,                   // REQUIRE email confirmation
  mailer_secure_email_change_enabled: true,
  mfa_max_enrolled_factors: 10,
  mfa_totp_enroll_enabled: true,
  mfa_totp_verify_enabled: true,
  mfa_web_authn_enroll_enabled: true,          // WebAuthn factor for the Owner
  mfa_web_authn_verify_enabled: true,
  webauthn_rp_id: process.env.SB_RPID,
  webauthn_rp_origins: process.env.SB_SITE,
  webauthn_rp_display_name: "United Feminist",
};
if(process.env.SB_SMTP==="yes"){
  b.smtp_host=process.env.SMTP_HOST;
  b.smtp_port=String(process.env.SMTP_PORT||"587");
  b.smtp_user=process.env.SMTP_USER;
  b.smtp_pass=process.env.SMTP_PASS;
  b.smtp_admin_email=process.env.SMTP_ADMIN_EMAIL||"no-reply@unitedfeminist.com";
  b.smtp_sender_name=process.env.SMTP_SENDER_NAME||"United Feminist";
}
fs.writeFileSync(process.argv[1],JSON.stringify(b),{mode:0o600});
' "$BODY"
code="$(api PATCH "/v1/projects/${REF}/config/auth" "$BODY")"; api_ok "$code" 200
info "auth config written (30m JWT, refresh rotation, email confirmation, TOTP + WebAuthn)"

# ----------------------------------------------------------------------------
# 7. Retrieve API keys + URL, write them to .env.local (0600) — never to stdout
# ----------------------------------------------------------------------------
step "Retrieving API keys and writing .env.local"
code="$(api GET "/v1/projects/${REF}/api-keys?reveal=true")"; api_ok "$code" 200
ANON_KEY="$(jget "$RESP" 'd.find(o=>o.type==="publishable")?.api_key || d.find(o=>o.type==="legacy"&&o.name==="anon")?.api_key || ""')"
SECRET_KEY="$(jget "$RESP" 'd.find(o=>o.type==="secret")?.api_key || d.find(o=>o.type==="legacy"&&o.name==="service_role")?.api_key || ""')"
[[ -n "$ANON_KEY" ]]   || die "could not find a publishable/anon API key in the response"
[[ -n "$SECRET_KEY" ]] || die "could not find a secret/service_role API key in the response"

SB_URL="$PROJECT_URL" SB_ANON="$ANON_KEY" SB_SECRET="$SECRET_KEY" \
node -e '
const fs=require("fs");
const path=".env.local";
let txt = fs.existsSync(path) ? fs.readFileSync(path,"utf8")
        : (fs.existsSync(".env.example") ? fs.readFileSync(".env.example","utf8") : "");
const set={
  NEXT_PUBLIC_SUPABASE_URL: process.env.SB_URL,
  NEXT_PUBLIC_SUPABASE_ANON_KEY: process.env.SB_ANON,
  SUPABASE_SERVICE_ROLE_KEY: process.env.SB_SECRET,
};
for(const [k,v] of Object.entries(set)){
  const re=new RegExp("^"+k+"=.*$","m");
  if(re.test(txt)) txt=txt.replace(re,k+"="+v);
  else txt+=(txt===""||txt.endsWith("\n")?"":"\n")+k+"="+v+"\n";
}
fs.writeFileSync(path,txt,{mode:0o600});
'
info "wrote NEXT_PUBLIC_SUPABASE_URL + anon + service-role key to .env.local (chmod 600)"
fp "NEXT_PUBLIC_SUPABASE_URL" "$PROJECT_URL"
fp "NEXT_PUBLIC_SUPABASE_ANON_KEY" "$ANON_KEY"
fp "SUPABASE_SERVICE_ROLE_KEY" "$SECRET_KEY" secret

# ----------------------------------------------------------------------------
# 8. Seed the Owner + system account (guarded so a re-run is a no-op)
# ----------------------------------------------------------------------------
step "Seeding Owner + system account (npm run bootstrap)"
printf '{"query":"select count(*)::int as n from auth.users;"}' > "$BODY"
code="$(api POST "/v1/projects/${REF}/database/query" "$BODY")"; api_ok "$code" 200 201
USERS="$(jget "$RESP" 'Array.isArray(d)?(d[0]?.n ?? 0):(d?.result?.[0]?.n ?? d?.n ?? 0)')"
if [[ "${USERS:-0}" -gt 0 ]]; then
  info "auth.users already has $USERS user(s) — bootstrap already done, skipping."
else
  NEXT_PUBLIC_SUPABASE_URL="$PROJECT_URL" \
  SUPABASE_SERVICE_ROLE_KEY="$SECRET_KEY" \
  OWNER_EMAIL="$OWNER_EMAIL" OWNER_PASSWORD="$OWNER_PASSWORD" OWNER_HANDLE="$OWNER_HANDLE" \
  OWNER_LEGAL_NAME="$OWNER_LEGAL_NAME" OWNER_DOB="$OWNER_DOB" OWNER_PHONE="$OWNER_PHONE" \
    npm run bootstrap 2> >(redact >&2) \
    || die "npm run bootstrap failed (see message above)."
  info "Owner and system account seeded"
fi

# ----------------------------------------------------------------------------
# 9. Verify the posture actually took (fail loudly on drift)
# ----------------------------------------------------------------------------
step "Verifying"
code="$(api GET "/v1/projects/${REF}/config/auth")"; api_ok "$code" 200
check() { # label  js-bool-expr
  local ok; ok="$(jget "$RESP" "$2")"
  if [[ "$ok" == "true" ]]; then info "ok  — $1"; else die "verification FAILED — $1"; fi
}
check "jwt_exp == 1800"                       'd.jwt_exp===1800'
check "refresh_token_rotation_enabled"        'd.refresh_token_rotation_enabled===true'
check "email confirmation required"           'd.mailer_autoconfirm===false'
check "TOTP MFA enabled"                       'd.mfa_totp_verify_enabled===true'
check "WebAuthn MFA enabled"                   'd.mfa_web_authn_verify_enabled===true'

printf '{"query":"select exists(select 1 from pg_extension where extname='"'"'pg_cron'"'"') as ok;"}' > "$BODY"
code="$(api POST "/v1/projects/${REF}/database/query" "$BODY")"; api_ok "$code" 200 201
cron_ok="$(jget "$RESP" 'Array.isArray(d)?(d[0]?.ok):(d?.result?.[0]?.ok ?? d?.ok)')"
[[ "$cron_ok" == "true" ]] && info "ok  — pg_cron installed" || die "verification FAILED — pg_cron not installed"

step "Done"
cat >&2 <<SUMMARY

  Project ref : $REF
  Project URL : $PROJECT_URL
  App env     : .env.local (Supabase URL + anon + service-role key, chmod 600)
  Security    : 30-minute JWTs · refresh rotation · email confirmation required
                TOTP + WebAuthn MFA · pg_cron scheduled
  Owner       : $OWNER_EMAIL — sign in and ENROLL MFA immediately. Privileged
                actions (role grants, audit reads, contact-info views) refuse to
                run below AAL2, enforced in the database.
SUMMARY
if [[ "$SMTP_CONFIGURED" == "no" ]]; then
  warn "ACTION: configure custom SMTP (Resend) before public signups — see docs/provisioning.md."
fi
if [[ "$ORG_PLAN" == "free" ]]; then
  warn "ACTION: upgrade the organization to Pro in the dashboard for production."
fi
exit 0
