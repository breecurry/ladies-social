import type { Metadata } from "next";
import { LEGAL_DOCS, loadLegalDocument } from "@/lib/legal";
import { LegalArticle } from "@/components/LegalArticle";
import { LegalInterimNotice } from "@/components/LegalInterimNotice";

export const metadata: Metadata = {
  title: "Community Guidelines",
  description:
    "The Community Guidelines for Hersciety: what we expect from members, what members can expect from us, and how enforcement works.",
};

export default async function CommunityGuidelinesPage() {
  if (!LEGAL_DOCS["community-guidelines"].published) {
    return <LegalInterimNotice documentName="Community Guidelines" />;
  }
  return <LegalArticle doc={await loadLegalDocument("community-guidelines")} />;
}
