import type { Metadata } from "next";
import { LEGAL_DOCS, loadLegalDocument } from "@/lib/legal";
import { LegalArticle } from "@/components/LegalArticle";
import { LegalInterimNotice } from "@/components/LegalInterimNotice";

export const metadata: Metadata = {
  title: "Privacy Policy",
  description: "The Privacy Policy for Hersciety, operated by Curry Co LLC.",
};

export default async function PrivacyPolicyPage() {
  // To publish the real document once counsel sign-off lands, flip
  // `published` for this slug in src/lib/legal.ts — nothing here changes.
  if (!LEGAL_DOCS["privacy-policy"].published) {
    return <LegalInterimNotice documentName="Privacy Policy" />;
  }
  return <LegalArticle doc={await loadLegalDocument("privacy-policy")} />;
}
