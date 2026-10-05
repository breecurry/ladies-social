import sharp from "sharp";
import { encode } from "blurhash";

/**
 * Server-side avatar ingestion — the authoritative control (spec 2.1,
 * 7.3). Whatever the client did or did not do, every served byte comes
 * out of this full decode + re-encode:
 *
 *   1. the actual bytes are sniffed (never the filename, never the
 *      declared content type) — static JPEG, PNG or WebP only;
 *   2. the raster is decoded under a hard pixel ceiling (decompression
 *      bombs are refused, not survived);
 *   3. AUTO-ORIENT FIRST — orientation lives in EXIF and must be
 *      applied before the EXIF is thrown away;
 *   4. square variants are re-encoded from the oriented raster with no
 *      metadata carried over: no EXIF, no GPS, no XMP, no IPTC, no
 *      embedded thumbnail, no ICC profile (pixels are converted to
 *      sRGB; sharp embeds nothing unless asked, and it is not asked);
 *   5. a blurhash is computed so the UI can paint the image's own
 *      average color while it loads.
 *
 * An animated WebP is flattened to its first frame (the spec's stated
 * default): avatars are static, deliberately.
 *
 * The uploaded filename never reaches this module at all — nothing in
 * the upload path accepts one.
 */

export const AVATAR_VARIANT_SIZES = [96, 192, 400] as const;

export interface IngestLimits {
  minDim: number;
  maxPixels: number;
}

export type IngestOutcome =
  | {
      ok: true;
      variants: { size: number; data: Buffer }[];
      blurhash: string;
    }
  | { ok: false; reason: "too_small" | "too_large" | "wrong_format" | "unreadable" };

/** Sniff the real image format from magic bytes. Null = not accepted. */
export function sniffImageType(bytes: Uint8Array): "jpeg" | "png" | "webp" | null {
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
    return "jpeg";
  }
  if (
    bytes.length >= 8 &&
    bytes[0] === 0x89 &&
    bytes[1] === 0x50 &&
    bytes[2] === 0x4e &&
    bytes[3] === 0x47 &&
    bytes[4] === 0x0d &&
    bytes[5] === 0x0a &&
    bytes[6] === 0x1a &&
    bytes[7] === 0x0a
  ) {
    return "png";
  }
  if (
    bytes.length >= 12 &&
    bytes[0] === 0x52 && // R
    bytes[1] === 0x49 && // I
    bytes[2] === 0x46 && // F
    bytes[3] === 0x46 && // F
    bytes[8] === 0x57 && // W
    bytes[9] === 0x45 && // E
    bytes[10] === 0x42 && // B
    bytes[11] === 0x50 // P
  ) {
    return "webp";
  }
  return null;
}

export async function processAvatar(
  input: Uint8Array,
  limits: IngestLimits = { minDim: 256, maxPixels: 50_000_000 },
): Promise<IngestOutcome> {
  if (sniffImageType(input) === null) {
    return { ok: false, reason: "wrong_format" };
  }

  // Decode once to learn dimensions, under the bomb ceiling. `pages`
  // is left at sharp's default (first frame only), which flattens an
  // animated WebP to a static image.
  let width: number | undefined;
  let height: number | undefined;
  try {
    const metadata = await sharp(input, { limitInputPixels: limits.maxPixels }).metadata();
    // Orientation 5-8 transposes the raster; use the post-orient axes.
    const transposed = (metadata.orientation ?? 1) >= 5;
    width = transposed ? metadata.height : metadata.width;
    height = transposed ? metadata.width : metadata.height;
    if (!width || !height) {
      return { ok: false, reason: "unreadable" };
    }
    if (width * height > limits.maxPixels) {
      return { ok: false, reason: "too_large" };
    }
    if (width < limits.minDim || height < limits.minDim) {
      return { ok: false, reason: "too_small" };
    }
  } catch (error) {
    return {
      ok: false,
      reason: error instanceof Error && /pixel/i.test(error.message) ? "too_large" : "unreadable",
    };
  }

  try {
    // Auto-orient from EXIF FIRST, then every output is re-encoded from
    // the oriented raster. No withMetadata / keepMetadata call anywhere:
    // the encoded WebP carries no EXIF, XMP, ICC or thumbnail.
    const oriented = sharp(input, { limitInputPixels: limits.maxPixels }).rotate();

    const variants: { size: number; data: Buffer }[] = [];
    for (const size of AVATAR_VARIANT_SIZES) {
      const data = await oriented
        .clone()
        .resize(size, size, { fit: "cover" })
        .webp({ quality: 82 })
        .toBuffer();
      variants.push({ size, data });
    }

    const raw = await oriented
      .clone()
      .resize(32, 32, { fit: "cover" })
      .ensureAlpha()
      .raw()
      .toBuffer({ resolveWithObject: true });
    const blurhash = encode(
      new Uint8ClampedArray(raw.data.buffer, raw.data.byteOffset, raw.data.byteLength),
      raw.info.width,
      raw.info.height,
      4,
      4,
    );

    return { ok: true, variants, blurhash };
  } catch {
    return { ok: false, reason: "unreadable" };
  }
}
