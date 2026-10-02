import type { Metadata, Viewport } from "next";
import { Hanken_Grotesk } from "next/font/google";
import { SiteHeader } from "@/components/SiteHeader";
import "./globals.css";

const hanken = Hanken_Grotesk({
  subsets: ["latin"],
  variable: "--font-hanken",
  weight: ["400", "500", "600", "700"],
});

export const metadata: Metadata = {
  title: {
    default: "United Feminist",
    template: "%s · United Feminist",
  },
  description:
    "A social platform built as a safe space for women and their allies. Open to everyone 18 and over; bullying and harassment are never tolerated.",
  robots: { index: false, follow: false }, // member surfaces are never indexed
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#f4f0ea" },
    { media: "(prefers-color-scheme: dark)", color: "#16130f" },
  ],
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={hanken.variable}>
      <body className="min-h-dvh bg-background font-sans text-text-primary antialiased">
        <SiteHeader />
        <main className="mx-auto w-full max-w-3xl px-4 py-8">{children}</main>
      </body>
    </html>
  );
}
