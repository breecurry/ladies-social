import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { rpcError } from "@/lib/api";
import { requireDm, isBytea } from "@/lib/dm/api";

const schema = z.object({ prekeys: z.array(z.string()).min(1).max(200) });

/** POST /api/dm/prekeys — replenish one-time prekeys (public keys). */
export async function POST(request: NextRequest): Promise<NextResponse> {
  const auth = await requireDm();
  if ("response" in auth) return auth.response;

  const parsed = schema.safeParse(await request.json().catch(() => null));
  if (!parsed.success || !parsed.data.prekeys.every((p) => isBytea(p, 32))) {
    return NextResponse.json({ ok: false, error: "Invalid request." }, { status: 400 });
  }

  const { data: added, error } = await auth.supabase.rpc("dm_add_prekeys", {
    p_prekeys: parsed.data.prekeys,
  });
  if (error) return rpcError(error);
  return NextResponse.json({ ok: true, added });
}
