import { NextResponse, type NextRequest } from "next/server";
import { rpcError } from "@/lib/api";
import { requireDm } from "@/lib/dm/api";

/**
 * GET /api/dm/bundle?userId= — a prekey bundle for opening a session.
 * The database function enforces the same permission rules as sending
 * (block, DMs off, request policy), so this cannot be used to probe.
 */
export async function GET(request: NextRequest): Promise<NextResponse> {
  const auth = await requireDm();
  if ("response" in auth) return auth.response;

  const userId = request.nextUrl.searchParams.get("userId") ?? "";
  if (!/^[0-9a-f-]{36}$/i.test(userId)) {
    return NextResponse.json({ ok: false, error: "Invalid request." }, { status: 400 });
  }

  const { data, error } = await auth.supabase.rpc("dm_prekey_bundle", { p_user: userId });
  if (error) return rpcError(error);
  const bundle = data?.[0];
  if (!bundle) {
    return NextResponse.json(
      { ok: false, error: "This member cannot receive messages yet." },
      { status: 400 },
    );
  }
  return NextResponse.json({
    ok: true,
    bundle: {
      deviceId: bundle.device_id,
      identityKey: bundle.identity_key,
      signedPrekey: bundle.signed_prekey,
      signedPrekeySig: bundle.signed_prekey_sig,
      prekey: bundle.prekey,
    },
  });
}
