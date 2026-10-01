import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getViewer } from "@/lib/auth";
import { Card } from "@/components/ui";
import { VouchActions } from "@/components/VouchActions";

export const metadata: Metadata = { title: "Vouch requests" };

export default async function VouchesPage() {
  const viewer = await getViewer();
  if (!viewer) redirect("/login");
  if (!viewer.isAdmitted) redirect("/pending");

  const supabase = await createSupabaseServerClient();
  const { data: requests } = await supabase.rpc("get_my_vouch_requests");

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-col gap-2">
        <h1 className="text-title">Vouch requests</h1>
        <p className="max-w-prose text-body text-text-secondary">
          Someone applying to join named you as the person who invited her. Confirm only if you
          personally know her and vouch for her good faith. Declining doesn&apos;t reject her — her
          application simply goes to review instead. Requests expire after 48 hours.
        </p>
      </div>

      {(requests ?? []).length === 0 ? (
        <Card>
          <p className="text-body text-text-secondary">No pending vouch requests.</p>
        </Card>
      ) : (
        (requests ?? []).map((request) => (
          <Card key={request.id} className="flex flex-col gap-4">
            <div className="flex flex-col gap-1">
              <h2 className="text-heading">
                {request.applicant_legal_name}{" "}
                <span className="text-caption text-text-tertiary">@{request.applicant_handle}</span>
              </h2>
              <p className="text-caption text-text-tertiary">
                Applied {new Date(request.created_at).toLocaleString()} · expires{" "}
                {new Date(request.deadline).toLocaleString()}
              </p>
            </div>
            <VouchActions requestId={request.id} />
          </Card>
        ))
      )}
    </div>
  );
}
