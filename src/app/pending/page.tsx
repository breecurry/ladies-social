import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { Alert, Card } from "@/components/ui";
import { InfoResponseForm } from "@/components/InfoResponseForm";

export const metadata: Metadata = { title: "Your application" };

/**
 * Applicant status page. Deliberately shows ONE collapsed "pending"
 * state whether the application is awaiting a vouch or sitting in the
 * review queue — an applicant can never learn from this page whether
 * the handle she named belongs to a member.
 */
export default async function PendingPage() {
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const { data } = await supabase.rpc("my_application_status");
  const application = data?.[0] ?? null;

  if (!application) {
    return (
      <div className="mx-auto flex max-w-md flex-col gap-6">
        <h1 className="text-title">Your application</h1>
        <Alert tone="info">
          We couldn&apos;t find an application for this account. If you just confirmed your email,
          try refreshing in a moment.
        </Alert>
      </div>
    );
  }

  if (application.status === "admitted") redirect("/home");

  return (
    <div className="mx-auto flex max-w-md flex-col gap-6">
      <h1 className="text-title">Your application</h1>

      {application.status === "pending" ? (
        <Card className="flex flex-col gap-3">
          <h2 className="text-heading">Under review</h2>
          <p className="text-body text-text-secondary">
            Your application is being reviewed. You&apos;ll be able to sign in and participate as
            soon as it&apos;s approved — check back here any time.
          </p>
        </Card>
      ) : null}

      {application.status === "info_requested" ? (
        <Card className="flex flex-col gap-4">
          <h2 className="text-heading">We need a little more information</h2>
          {application.message ? <Alert tone="info">{application.message}</Alert> : null}
          <InfoResponseForm />
        </Card>
      ) : null}

      {application.status === "rejected" ? (
        <Card className="flex flex-col gap-3">
          <h2 className="text-heading">Application not approved</h2>
          <p className="text-body text-text-secondary">
            Your application was not approved. If you believe this was a mistake, contact{" "}
            <a className="text-accent underline" href="mailto:appeals@unitedfeminist.com">
              appeals@unitedfeminist.com
            </a>
            .
          </p>
        </Card>
      ) : null}
    </div>
  );
}
