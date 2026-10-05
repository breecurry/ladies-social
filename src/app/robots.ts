import type { MetadataRoute } from "next";
import { SITE_INDEXABLE } from "@/lib/seo";

/**
 * While the site is shipped "dark" (SITE_INDEXABLE unset/false) this disallows
 * all crawlers for every path. Flip SITE_INDEXABLE=true (and redeploy) to open
 * crawling when moderation tooling lands. See src/lib/seo.ts.
 */
export default function robots(): MetadataRoute.Robots {
  if (SITE_INDEXABLE) {
    return { rules: { userAgent: "*", allow: "/" } };
  }
  return { rules: { userAgent: "*", disallow: "/" } };
}
