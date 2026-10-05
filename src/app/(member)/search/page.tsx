import type { Metadata } from "next";
import { SearchClient } from "@/components/people/SearchClient";

export const metadata: Metadata = { title: "Search" };

export default function SearchPage() {
  return (
    <div className="flex flex-col lg:mt-6 lg:overflow-hidden lg:rounded-lg lg:border lg:border-border lg:shadow-e1">
      <h1 className="sr-only">Search</h1>
      <SearchClient />
    </div>
  );
}
