/**
 * Ingestion gate for the avatar pipeline — runs under plain Node:
 *   node --experimental-strip-types scripts/avatar-pipeline-test.ts
 *
 * Proves the server-side safety properties of src/lib/media/ingest.ts
 * (spec 2.1, 6.3-6.6): a photo carrying EXIF (camera make/model,
 * software, GPS coordinates, orientation) and an ICC profile comes out
 * the other side as square WebP variants with NO metadata of any kind
 * surviving — checked both through sharp's own parser and by scanning
 * the raw output bytes — plus the stated-reason rejections: wrong
 * format, too small, decompression bomb, undecodable. This is a
 * developer gate, not part of next build.
 */

import sharp from "sharp";
import { processAvatar, sniffImageType } from "../src/lib/media/ingest.ts";
import { blurhashAverageColor } from "../src/lib/media/avatar.ts";

let failures = 0;

function check(name: string, condition: boolean): void {
  if (condition) {
    process.stdout.write(`  ok: ${name}\n`);
  } else {
    failures += 1;
    console.error(`  FAIL: ${name}`);
  }
}

async function main(): Promise<void> {
  // ----------------------------------------------------------------
  // 1. A JPEG loaded with the exact metadata a stalker wants: device
  //    make and model, software, a capture timestamp, GPS coordinates,
  //    and a non-upright EXIF orientation.
  // ----------------------------------------------------------------
  process.stdout.write("1. metadata strip by re-encode\n");
  const spyPhoto = await sharp({
    create: { width: 600, height: 400, channels: 3, background: { r: 180, g: 40, b: 90 } },
  })
    .jpeg({ quality: 90 })
    .withExif({
      IFD0: {
        Make: "TestCamCorp",
        Model: "SpyPhone 9 Pro",
        Software: "LeakSuite 2.0",
        DateTime: "2026:10:05 12:00:00",
      },
      IFD3: {
        GPSLatitudeRef: "N",
        GPSLatitude: "51/1 30/1 3230/100",
        GPSLongitudeRef: "W",
        GPSLongitude: "0/1 7/1 4366/100",
      },
    })
    .withMetadata({ orientation: 6 })
    .toBuffer();

  const inputMeta = await sharp(spyPhoto).metadata();
  check("fixture really carries EXIF", inputMeta.exif !== undefined);
  check("fixture really carries a non-upright orientation", inputMeta.orientation === 6);

  const result = await processAvatar(new Uint8Array(spyPhoto));
  check("a valid photo ingests", result.ok);
  if (result.ok) {
    check("three variants produced", result.variants.length === 3);
    check(
      "blurhash computed and decodable to an average color",
      /^#[0-9a-f]{6}$/.test(blurhashAverageColor(result.blurhash) ?? ""),
    );
    for (const variant of result.variants) {
      const label = `variant ${variant.size}`;
      const bytes = new Uint8Array(variant.data);
      const meta = await sharp(variant.data).metadata();
      check(`${label} is WebP`, sniffImageType(bytes) === "webp" && meta.format === "webp");
      check(
        `${label} is square at its size`,
        meta.width === variant.size && meta.height === variant.size,
      );
      check(`${label} has NO EXIF`, meta.exif === undefined);
      check(`${label} has NO XMP`, meta.xmp === undefined);
      check(`${label} has NO ICC profile`, meta.icc === undefined);
      check(`${label} has NO orientation tag`, meta.orientation === undefined);
      const raw = variant.data.toString("latin1");
      check(`${label} bytes contain no device make`, !raw.includes("TestCamCorp"));
      check(`${label} bytes contain no device model`, !raw.includes("SpyPhone"));
      check(`${label} bytes contain no software tag`, !raw.includes("LeakSuite"));
      check(`${label} bytes contain no EXIF block`, !raw.includes("Exif\u0000"));
      check(`${label} bytes contain no GPS tag names`, !raw.includes("GPSLatitude"));
      check(`${label} bytes contain no capture timestamp`, !raw.includes("2026:10:05"));
    }
  }

  // ----------------------------------------------------------------
  // 2. An ICC color profile does not survive either (it is a
  //    fingerprinting and payload channel; spec 2.1).
  // ----------------------------------------------------------------
  process.stdout.write("2. ICC profile strip\n");
  const profiled = await sharp({
    create: { width: 400, height: 400, channels: 3, background: { r: 10, g: 120, b: 200 } },
  })
    .withIccProfile("p3")
    .png()
    .toBuffer();
  check("fixture really carries ICC", (await sharp(profiled).metadata()).icc !== undefined);
  const profiledResult = await processAvatar(new Uint8Array(profiled));
  check("profiled photo ingests", profiledResult.ok);
  if (profiledResult.ok) {
    for (const variant of profiledResult.variants) {
      const meta = await sharp(variant.data).metadata();
      check(`variant ${variant.size} ICC gone`, meta.icc === undefined);
    }
  }

  // ----------------------------------------------------------------
  // 3. Rejections, each with its machine reason (the API maps these to
  //    the spec 6.5 member-facing messages).
  // ----------------------------------------------------------------
  process.stdout.write("3. rejections\n");

  const tiny = await sharp({
    create: { width: 100, height: 100, channels: 3, background: "#808080" },
  })
    .png()
    .toBuffer();
  const tinyResult = await processAvatar(new Uint8Array(tiny));
  check("under 256px rejected as too_small", !tinyResult.ok && tinyResult.reason === "too_small");

  const notAnImage = new TextEncoder().encode(
    "<svg xmlns='http://www.w3.org/2000/svg'><script>alert(1)</script></svg>",
  );
  const svgResult = await processAvatar(notAnImage);
  check(
    "SVG (and any non-JPEG/PNG/WebP bytes) rejected as wrong_format",
    !svgResult.ok && svgResult.reason === "wrong_format",
  );

  const bombResult = await processAvatar(new Uint8Array(spyPhoto), {
    minDim: 256,
    maxPixels: 100_000,
  });
  check(
    "a raster over the pixel ceiling rejected as too_large (bomb guard)",
    !bombResult.ok && bombResult.reason === "too_large",
  );

  const truncated = new Uint8Array(spyPhoto.subarray(0, 220));
  const truncatedResult = await processAvatar(truncated);
  check(
    "a truncated file rejected rather than half-decoded",
    !truncatedResult.ok &&
      (truncatedResult.reason === "unreadable" || truncatedResult.reason === "wrong_format"),
  );

  // ----------------------------------------------------------------
  if (failures > 0) {
    console.error(`${failures} FAILURES`);
    process.exit(1);
  }
  process.stdout.write("ALL AVATAR PIPELINE CHECKS PASSED\n");
}

void main();
