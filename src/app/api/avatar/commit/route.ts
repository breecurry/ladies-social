import { randomBytes } from "node:crypto";
import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { requireUser, rpcError } from "@/lib/api";
import {
  AVATAR_MAX_BYTES,
  AVATAR_MAX_PIXELS,
  AVATAR_MIN_DIM,
  AVATAR_REJECTION_MESSAGE,
} from "@/lib/media/avatar";
import { processAvatar } from "@/lib/media/ingest";
import {
  deleteMediaVariants,
  deleteStagingObject,
  fetchStagingObject,
  putMediaObject,
} from "@/lib/media/r2";

const bodySchema = z.object({ ticketId: z.string().uuid() });

/**
 * POST /api/avatar/commit — turn a staged upload into the member's
 * avatar (architecture section 3.2 steps 3-4, minus any scan step:
 * detection is Cloudflare's zone-level tool, out of band, no code).
 *
 * The server is the authority for everything that matters (spec 2.1,
 * 7.3): the real bytes are sniffed, decoded under the bomb ceiling,
 * auto-oriented FIRST, re-encoded with every scrap of metadata gone,
 * written to the media bucket under a fresh opaque key, and only then
 * recorded. The staging object is deleted either way. The previous
 * avatar's objects are deleted ONLY when the database — which owns
 * every retention decision — answers that no hold applies.
 */
export async function POST(request: NextRequest): Promise<NextResponse> {
  const auth = await requireUser();
  if ("response" in auth) return auth.response;

  const parsed = bodySchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ ok: false, error: "Invalid request." }, { status: 400 });
  }

  // Single-consume: a replayed ticket dies here before any fetch.
  const { data: stagingKey, error: consumeError } = await auth.supabase.rpc(
    "avatar_ticket_consume",
    { p_ticket: parsed.data.ticketId },
  );
  if (consumeError) return rpcError(consumeError);
  if (!stagingKey) {
    return NextResponse.json({ ok: false, error: "Invalid request." }, { status: 400 });
  }

  try {
    const staged = await fetchStagingObject(stagingKey, AVATAR_MAX_BYTES);
    if (staged === null) {
      return NextResponse.json(
        { ok: false, error: AVATAR_REJECTION_MESSAGE.unreadable },
        { status: 400 },
      );
    }
    if (staged === "too_large") {
      return NextResponse.json(
        { ok: false, error: AVATAR_REJECTION_MESSAGE.too_large },
        { status: 400 },
      );
    }

    const outcome = await processAvatar(staged, {
      minDim: AVATAR_MIN_DIM,
      maxPixels: AVATAR_MAX_PIXELS,
    });
    if (!outcome.ok) {
      return NextResponse.json(
        { ok: false, error: AVATAR_REJECTION_MESSAGE[outcome.reason] },
        { status: 400 },
      );
    }

    // A fresh opaque key per upload — never derived, never reused.
    const key = randomBytes(24).toString("hex");
    for (const variant of outcome.variants) {
      await putMediaObject(`av/${key}/${variant.size}.webp`, variant.data);
    }

    const { data: committed, error: commitError } = await auth.supabase.rpc(
      "avatar_commit_record",
      { p_ticket: parsed.data.ticketId, p_key: key, p_blurhash: outcome.blurhash },
    );
    if (commitError) {
      // The DB refused after the objects were written: remove them so
      // nothing orphaned lives in the media bucket.
      await deleteMediaVariants(key).catch(() => undefined);
      return rpcError(commitError);
    }

    // Clean up the superseded avatar's objects — only when the
    // database says no report hold or retention duty pins them.
    const previous = committed?.[0];
    if (previous?.old_key && previous.old_purgeable) {
      try {
        await deleteMediaVariants(previous.old_key);
        await auth.supabase.rpc("avatar_mark_purged", { p_key: previous.old_key });
      } catch {
        // Best-effort: a missed purge is storage noise, never a leak —
        // the resolver stopped returning the key the moment it was
        // superseded, and the key is unguessable.
      }
    }

    return NextResponse.json({ ok: true, key, blurhash: outcome.blurhash });
  } finally {
    await deleteStagingObject(stagingKey).catch(() => undefined);
  }
}
