import { AwsClient } from "aws4fetch";
import { requireEnv } from "@/lib/env";
import { AVATAR_VARIANTS } from "@/lib/media/avatar";

/**
 * Cloudflare R2 access (S3 API via SigV4) — server only. Two buckets,
 * per the architecture document section 3.2:
 *
 *   - STAGING (`R2_STAGING_BUCKET`): raw client uploads land here via
 *     short-lived presigned PUTs. Never publicly served, never behind
 *     the media zone. Objects are deleted as soon as processing ends.
 *   - MEDIA (`R2_MEDIA_BUCKET`): only ever receives re-encoded,
 *     metadata-free output. Served publicly at media.hersciety.com
 *     through Cloudflare (where the zone-level CSAM scanning tool the
 *     owner enabled inspects what the cache carries — that tool is
 *     out of band and nothing here calls it).
 *
 * Objects are written immutable (new upload = new key), so the cache
 * header is forever.
 */

function r2(): AwsClient {
  return new AwsClient({
    accessKeyId: requireEnv("R2_ACCESS_KEY_ID"),
    secretAccessKey: requireEnv("R2_SECRET_ACCESS_KEY"),
    region: "auto",
    service: "s3",
  });
}

function objectUrl(bucket: string, key: string): string {
  return `${requireEnv("R2_ENDPOINT").replace(/\/$/, "")}/${bucket}/${key}`;
}

/** Presign a PUT into staging. Ten minutes is plenty for one photo. */
export async function presignStagingPut(stagingKey: string): Promise<string> {
  const url = new URL(objectUrl(requireEnv("R2_STAGING_BUCKET"), stagingKey));
  url.searchParams.set("X-Amz-Expires", "600");
  const signed = await r2().sign(new Request(url.toString(), { method: "PUT" }), {
    aws: { signQuery: true },
  });
  return signed.url;
}

/**
 * Fetch a staged upload for processing, refusing anything over the
 * byte cap before buffering it. Returns null when the object is
 * missing (the client never PUT it) and "too_large" when it is over
 * the cap — the ticket size check already refused honest clients, so
 * this is the backstop against a client that lied.
 */
export async function fetchStagingObject(
  stagingKey: string,
  maxBytes: number,
): Promise<Uint8Array | "too_large" | null> {
  const response = await r2().fetch(objectUrl(requireEnv("R2_STAGING_BUCKET"), stagingKey));
  if (!response.ok) {
    response.body?.cancel();
    return null;
  }
  const declared = Number(response.headers.get("content-length") ?? "0");
  if (declared > maxBytes) {
    response.body?.cancel();
    return "too_large";
  }
  const bytes = new Uint8Array(await response.arrayBuffer());
  return bytes.byteLength > maxBytes ? "too_large" : bytes;
}

/** Delete a staging object once processing is done (or has failed). */
export async function deleteStagingObject(stagingKey: string): Promise<void> {
  await r2().fetch(objectUrl(requireEnv("R2_STAGING_BUCKET"), stagingKey), { method: "DELETE" });
}

/** Write one immutable avatar variant to the media bucket. */
export async function putMediaObject(mediaKey: string, body: Uint8Array): Promise<void> {
  const payload = new Uint8Array(body).buffer as ArrayBuffer;
  const response = await r2().fetch(objectUrl(requireEnv("R2_MEDIA_BUCKET"), mediaKey), {
    method: "PUT",
    body: payload,
    headers: {
      "content-type": "image/webp",
      "cache-control": "public, max-age=31536000, immutable",
    },
  });
  if (!response.ok) {
    throw new Error(`Media write failed with status ${response.status}`);
  }
}

/** The media-bucket object keys for an avatar's variants. */
export function avatarObjectKeys(key: string): string[] {
  return AVATAR_VARIANTS.map((variant) => `av/${key}/${variant}.webp`);
}

/**
 * Delete the stored variants of a purgeable avatar. Only ever called
 * after the database has answered that no retention hold applies —
 * the database owns every preservation decision, this only executes it.
 */
export async function deleteMediaVariants(key: string): Promise<void> {
  for (const objectKey of avatarObjectKeys(key)) {
    await r2().fetch(objectUrl(requireEnv("R2_MEDIA_BUCKET"), objectKey), { method: "DELETE" });
  }
}
