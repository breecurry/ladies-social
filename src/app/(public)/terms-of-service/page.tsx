import type { Metadata } from "next";
import { loadLegalDocument } from "@/lib/legal";
import { LegalArticle } from "@/components/LegalArticle";

export const metadata: Metadata = {
  title: "Terms of Service",
  description: "The Terms of Service for Hersciety, operated by Curry Co LLC.",
};

export default async function TermsOfServicePage() {
  return <LegalArticle doc={await loadLegalDocument("terms-of-service")} />;
}
