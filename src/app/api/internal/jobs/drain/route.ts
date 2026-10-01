import { NextResponse, type NextRequest } from "next/server";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { requireEnv } from "@/lib/env";

/**
 * POST /api/internal/jobs/drain — scheduled-work trigger for
 * environments without pg_cron (pg_cron runs the same function
 * directly when present). Protected by a shared secret.
 * Current jobs: lapse vouch requests past their 48h deadline.
 */
export async function POST(request: NextRequest): Promise<NextResponse> {
  const secret = request.headers.get("x-cron-secret");
  if (!secret || secret !== requireEnv("INTERNAL_CRON_SECRET")) {
    return NextResponse.json({ ok: false }, { status: 401 });
  }
  const admin = createSupabaseAdminClient();
  const { data, error } = await admin.rpc("lapse_expired_vouch_requests");
  if (error) {
    return NextResponse.json({ ok: false, error: error.message }, { status: 500 });
  }
  return NextResponse.json({ ok: true, lapsed: data ?? 0 });
}
