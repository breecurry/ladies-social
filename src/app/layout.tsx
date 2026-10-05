import type { Metadata, Viewport } from "next";
import { Hanken_Grotesk } from "next/font/google";
import { SITE_INDEXABLE } from "@/lib/seo";
import "./globals.css";

const hanken = Hanken_Grotesk({
  subsets: ["latin"],
  variable: "--font-hanken",
  weight: ["400", "500", "600", "700"],
});

export const metadata: Metadata = {
  title: {
    default: "Hersciety",
    template: "%s · Hersciety",
  },
  description:
    "A social platform built as a safe space for women and their allies. Open to everyone 18 and over; bullying and harassment are never tolerated.",
  // Search visibility is controlled by the single SITE_INDEXABLE flag
  // (src/lib/seo.ts), which also drives the X-Robots-Tag header and
  // /robots.txt. Default is noindex until moderation tooling ships.
  robots: SITE_INDEXABLE ? undefined : { index: false, follow: false },
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#f4f0ea" },
    { media: "(prefers-color-scheme: dark)", color: "#16130f" },
  ],
};

// Applies a saved theme choice before first paint so there is no flash.
// "system" (the default) sets no attribute and the CSS media query rules.
const themeInit = `try{var t=localStorage.getItem("uf-theme");if(t==="light"||t==="dark"){document.documentElement.dataset.theme=t;}}catch(e){}`;

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={hanken.variable} suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: themeInit }} />
      </head>
      <body className="min-h-dvh bg-background font-sans text-text-primary antialiased">
        {children}
      </body>
    </html>
  );
}
