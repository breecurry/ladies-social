import type { Metadata } from "next";
import { LEGAL_DOCS, loadLegalDocument } from "@/lib/legal";
import { LegalArticle } from "@/components/LegalArticle";
import { LegalInterimNotice } from "@/components/LegalInterimNotice";

export const metadata: Metadata = {
  title: "Terms of Service",
  description: "The Terms of Service for Hersciety, operated by Curry Co LLC.",
};

export default async function TermsOfServicePage() {
  // To publish the real document once counsel sign-off lands, flip
  // `published` for this slug in src/lib/legal.ts — nothing here changes.
  if (!LEGAL_DOCS["terms-of-service"].published) {
    return <LegalInterimNotice documentName="Terms of Service" />;
  }
  return <LegalArticle doc={await loadLegalDocument("terms-of-service")} />;
}
