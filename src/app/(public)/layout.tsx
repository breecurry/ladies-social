import { SiteHeader } from "@/components/SiteHeader";

/**
 * Public, signed-out surfaces: landing, log in, sign up. These keep the
 * simple marketing header and narrow reading column; the member app
 * lives in the (member) group inside the full application shell.
 */
export default function PublicLayout({ children }: { children: React.ReactNode }) {
  return (
    <>
      <SiteHeader />
      <main className="mx-auto w-full max-w-3xl px-4 py-8">{children}</main>
    </>
  );
}
