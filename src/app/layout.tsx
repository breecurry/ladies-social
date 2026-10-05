import type { Metadata, Viewport } from "next";
import { Hanken_Grotesk } from "next/font/google";
import { headers } from "next/headers";
import { SITE_INDEXABLE } from "@/lib/seo";
import "./globals.css";

const hanken = Hanken_Grotesk({
  subsets: ["latin"],
  variable: "--font-hanken",
  weight: ["400", "500", "600", "700"],
});

export const metadata: Metadata = {
  metadataBase: new URL("https://www.hersciety.com"),
  title: {
    default: "Hersciety",
    template: "%s · Hersciety",
  },
  description:
    "A social platform built as a safe space for women and their allies. Open to everyone 18 and over; bullying and harassment are never tolerated.",
  // The icon and Open Graph image files (src/app/icon.png, apple-icon.png,
  // favicon.ico, opengraph-image.png) are wired automatically by the Next.js
  // file conventions; do not add `icons` or `openGraph.images` here.
  openGraph: {
    type: "website",
    siteName: "Hersciety",
    title: "Hersciety",
    description:
      "A social platform built as a safe space for women and their allies. Open to everyone 18 and over; bullying and harassment are never tolerated.",
    url: "https://www.hersciety.com",
    locale: "en_US",
  },
  twitter: {
    card: "summary_large_image",
    title: "Hersciety",
    description:
      "A social platform built as a safe space for women and their allies. Open to everyone 18 and over; bullying and harassment are never tolerated.",
  },
  // Search visibility is controlled by the single SITE_INDEXABLE flag
  // (src/lib/seo.ts), which also drives the X-Robots-Tag header and
  // /robots.txt. Default is noindex until moderation tooling ships.
  robots: SITE_INDEXABLE ? undefined : { index: false, follow: false },
};

export const viewport: Viewport = {
  // cover makes env(safe-area-inset-*) real values on notched phones;
  // without it every safe-area rule in the shell and dialogs is inert.
  viewportFit: "cover",
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#f4f0ea" },
    { media: "(prefers-color-scheme: dark)", color: "#16130f" },
  ],
};

// Applies a saved theme choice before first paint so there is no flash.
// "system" (the default) sets no attribute and the CSS media query rules.
// The script content must remain byte-for-byte stable: the CSP nonce in
// proxy.ts allows it by nonce, not by hash, so any content change only
// needs a proxy redeploy, not a hash rotation.
const themeInit = `try{var t=localStorage.getItem("uf-theme");if(t==="light"||t==="dark"){document.documentElement.dataset.theme=t;}}catch(e){}`;

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  // Read the per-request nonce generated in proxy.ts and forwarded via the
  // x-nonce request header. Falls back to '' when the proxy is not running
  // (e.g. unit test environments), meaning the inline script will be blocked
  // by CSP in those contexts — acceptable, since tests do not enforce CSP.
  const nonce = (await headers()).get("x-nonce") ?? "";

  return (
    <html lang="en" className={hanken.variable} suppressHydrationWarning>
      <head>
        <script nonce={nonce} dangerouslySetInnerHTML={{ __html: themeInit }} />
      </head>
      <body className="min-h-dvh bg-background font-sans text-text-primary antialiased">
        {children}
      </body>
    </html>
  );
}
