import type { Metadata } from "next";
import { loadLegalDocument } from "@/lib/legal";
import { LegalArticle } from "@/components/LegalArticle";

export const metadata: Metadata = {
  title: "Privacy Policy",
  description: "The Privacy Policy for Hersciety, operated by Curry Co LLC.",
};

export default async function PrivacyPolicyPage() {
  return <LegalArticle doc={await loadLegalDocument("privacy-policy")} />;
}
