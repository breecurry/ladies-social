import { randomBytes } from "node:crypto";
import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { requireUser, rpcError } from "@/lib/api";
import {
  AVATAR_ACCEPTED_TYPES,
  AVATAR_MAX_BYTES,
  AVATAR_REJECTION_MESSAGE,
} from "@/lib/media/avatar";
import { presignStagingPut } from "@/lib/media/r2";

const bodySchema = z.object({
  size: z.number().int().positive(),
  type: z.string().max(100),
});

/**
 * POST /api/avatar/ticket — mint an upload ticket and a short-lived
 * presigned PUT into the STAGING bucket (never served; architecture
 * section 3.2 step 2). The declared size and type are checked here so
 * an honest client fails fast with a stated reason (spec 6.5); the
 * commit step re-checks the real bytes, trusting nothing.
 *
 * Deliberately absent from the request shape: the filename. It is
 * never sent, never read, never stored (spec 2.2). The staging key is
 * server-minted CSPRNG output with no user linkage (spec 2.3), and
 * the rate limit lives in the database (avatar_ticket_create).
 */
export async function POST(request: NextRequest): Promise<NextResponse> {
  const auth = await requireUser();
  if ("response" in auth) return auth.response;

  const parsed = bodySchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ ok: false, error: "Invalid request." }, { status: 400 });
  }
  if (!(AVATAR_ACCEPTED_TYPES as readonly string[]).includes(parsed.data.type)) {
    return NextResponse.json(
      { ok: false, error: AVATAR_REJECTION_MESSAGE.wrong_format },
      { status: 400 },
    );
  }
  if (parsed.data.size > AVATAR_MAX_BYTES) {
    return NextResponse.json(
      { ok: false, error: AVATAR_REJECTION_MESSAGE.too_large },
      { status: 400 },
    );
  }

  const stagingKey = `st/${randomBytes(24).toString("hex")}`;
  const { data: ticketId, error } = await auth.supabase.rpc("avatar_ticket_create", {
    p_staging_key: stagingKey,
  });
  if (error) return rpcError(error);

  const uploadUrl = await presignStagingPut(stagingKey);
  return NextResponse.json({ ok: true, ticketId, uploadUrl });
}
