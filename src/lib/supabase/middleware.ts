import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

const PROTECTED_PREFIXES = [
  "/home",
  "/search",
  "/notifications",
  "/messages",
  "/post",
  "/u",
  "/settings",
  "/owner",
];

/**
 * Session refresh + coarse auth gate. Role and account-status checks
 * happen server-side in each page (and, authoritatively, in RLS) —
 * middleware only keeps signed-out visitors away from member surfaces.
 *
 * requestHeaders — the Headers object built in proxy.ts, which already
 * includes x-nonce and the original request headers. Passing it here
 * ensures server components receive the nonce via the forwarded request,
 * even when Supabase refreshes session cookies mid-request (the setAll
 * branch below must rebuild headers so x-nonce is not lost when
 * NextResponse.next is re-called).
 */
export async function updateSession(
  request: NextRequest,
  requestHeaders: Headers,
): Promise<NextResponse> {
  let response = NextResponse.next({ request: { headers: requestHeaders } });

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !anonKey) {
    return response;
  }

  const supabase = createServerClient(url, anonKey, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet) {
        // Apply new cookie values to the request's cookie store so any
        // subsequent middleware reads see the updated session.
        cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));

        // Rebuild the forwarded request headers, carrying the updated Cookie
        // header so the refreshed session is visible to server components.
        // x-nonce is preserved because we start from requestHeaders.
        const withCookies = new Headers(requestHeaders);
        withCookies.set(
          "cookie",
          request.cookies
            .getAll()
            .map(({ name, value }) => `${name}=${value}`)
            .join("; "),
        );
        response = NextResponse.next({ request: { headers: withCookies } });

        // Send the new Set-Cookie headers to the browser.
        cookiesToSet.forEach(({ name, value, options }) =>
          response.cookies.set(name, value, options),
        );
      },
    },
  });

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const path = request.nextUrl.pathname;
  if (!user && PROTECTED_PREFIXES.some((p) => path === p || path.startsWith(`${p}/`))) {
    const redirect = request.nextUrl.clone();
    redirect.pathname = "/login";
    redirect.search = "";
    return NextResponse.redirect(redirect);
  }

  return response;
}
