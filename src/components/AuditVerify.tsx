"use client";

import { useState } from "react";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";
import { Alert, Button } from "@/components/ui";

/**
 * Walks the entire hash chain in the database and reports the first
 * broken link, if any. A clean result proves no audit row has been
 * altered or removed since the chain began.
 */
export function AuditVerify() {
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<string | null>(null);
  const [failed, setFailed] = useState(false);

  const verify = async () => {
    setBusy(true);
    setResult(null);
    const supabase = createSupabaseBrowserClient();
    const { data, error } = await supabase.rpc("verify_audit_chain");
    if (error) {
      setFailed(true);
      setResult(error.message);
    } else {
      const row = data?.[0];
      if (!row) {
        setFailed(true);
        setResult("Verification returned no result.");
      } else if (row.ok) {
        setFailed(false);
        setResult(`Chain intact: ${row.checked_rows} entries verified.`);
      } else {
        setFailed(true);
        setResult(`CHAIN BROKEN at entry #${row.broken_at_seq}. Treat the log as tampered.`);
      }
    }
    setBusy(false);
  };

  return (
    <div className="flex flex-col gap-3">
      <Button variant="secondary" disabled={busy} onClick={verify}>
        {busy ? "Verifying…" : "Verify hash chain"}
      </Button>
      {result ? <Alert tone={failed ? "danger" : "success"}>{result}</Alert> : null}
    </div>
  );
}
