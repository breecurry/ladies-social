import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { rpcError } from "@/lib/api";
import { requireDm, isBytea } from "@/lib/dm/api";

/**
 * GET /api/dm/devices — the caller's own active device (or null), so
 * the client can tell whether the keys it holds locally are current.
 */
export async function GET(): Promise<NextResponse> {
  const auth = await requireDm();
  if ("response" in auth) return auth.response;

  const { data, error } = await auth.supabase.rpc("dm_my_device");
  if (error) return rpcError(error);
  const device = data?.[0] ?? null;
  return NextResponse.json({
    ok: true,
    device: device
      ? {
          deviceId: device.device_id,
          identityKey: device.identity_key,
          prekeysRemaining: device.prekeys_remaining,
        }
      : null,
  });
}

const registerSchema = z.object({
  deviceName: z.string().trim().min(1).max(80),
  identityKey: z.string(),
  signedPrekey: z.string(),
  signedPrekeySig: z.string(),
  prekeys: z.array(z.string()).min(1).max(200),
});

/**
 * POST /api/dm/devices — register this browser as the member's active
 * device (revoking any previous one; single active device per account
 * in this release). Public keys only — secrets never leave the device.
 */
export async function POST(request: NextRequest): Promise<NextResponse> {
  const auth = await requireDm();
  if ("response" in auth) return auth.response;

  const parsed = registerSchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ ok: false, error: "Invalid request." }, { status: 400 });
  }
  const { deviceName, identityKey, signedPrekey, signedPrekeySig, prekeys } = parsed.data;
  if (
    !isBytea(identityKey, 64) ||
    !isBytea(signedPrekey, 32) ||
    !isBytea(signedPrekeySig, 64) ||
    !prekeys.every((p) => isBytea(p, 32))
  ) {
    return NextResponse.json({ ok: false, error: "Invalid request." }, { status: 400 });
  }

  const { data: deviceId, error } = await auth.supabase.rpc("dm_register_device", {
    p_device_name: deviceName,
    p_identity_key: identityKey,
    p_signed_prekey: signedPrekey,
    p_signed_prekey_sig: signedPrekeySig,
    p_prekeys: prekeys,
  });
  if (error) return rpcError(error);
  return NextResponse.json({ ok: true, deviceId });
}
