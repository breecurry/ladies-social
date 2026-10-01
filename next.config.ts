import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Media bytes must never flow through the app host (cost rule in
  // docs/architecture.md §1.4). Disabling the image optimizer enforces it.
  images: { unoptimized: true },
  poweredByHeader: false,
};

export default nextConfig;
