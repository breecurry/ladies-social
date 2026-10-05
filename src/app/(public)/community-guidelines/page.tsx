import type { Metadata } from "next";
import { loadLegalDocument } from "@/lib/legal";
import { LegalArticle } from "@/components/LegalArticle";

export const metadata: Metadata = {
  title: "Community Guidelines",
  description:
    "The Community Guidelines for Hersciety: what we expect from members, what members can expect from us, and how enforcement works.",
};

export default async function CommunityGuidelinesPage() {
  return <LegalArticle doc={await loadLegalDocument("community-guidelines")} />;
}
