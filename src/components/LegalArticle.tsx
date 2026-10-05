import { createElement, type JSX } from "react";
import ReactMarkdown, { type Components, type ExtraProps } from "react-markdown";
import remarkGfm from "remark-gfm";
import rehypeSlug from "rehype-slug";
import type { LegalDocument } from "@/lib/legal";

/**
 * Long-form legal document renderer. Server component: the markdown is
 * trusted repo content rendered to static HTML on the server.
 *
 * Security: no `rehype-raw`, so raw HTML in the markdown is never
 * parsed into the DOM, and react-markdown's default URL transform
 * strips unsafe protocols (javascript: etc.) from links. remark-gfm
 * provides tables and autolinks; rehype-slug gives every heading an id
 * so in-page anchors work (headings carry scroll margin to clear the
 * sticky header).
 *
 * Styling uses only existing tokens: `body-lg` is the primary reading
 * surface per the type scale, and the column is capped at a prose
 * measure for readability.
 */
function withClass<T extends keyof JSX.IntrinsicElements>(tag: T, className: string) {
  return function MarkdownElement({ node, ...props }: JSX.IntrinsicElements[T] & ExtraProps) {
    void node; // react-markdown's AST node — never forwarded to the DOM.
    return createElement(tag, { ...(props as JSX.IntrinsicElements[T]), className });
  };
}

const markdownComponents: Components = {
  h1: withClass("h1", "mt-10 scroll-mt-24 text-title text-text-primary"),
  h2: withClass("h2", "mt-10 scroll-mt-24 text-title text-text-primary"),
  h3: withClass("h3", "mt-8 scroll-mt-24 text-heading text-text-primary"),
  h4: withClass("h4", "mt-6 scroll-mt-24 text-body-lg font-semibold text-text-primary"),
  p: withClass("p", "mt-4 text-body-lg text-text-primary"),
  ul: withClass("ul", "mt-4 list-disc space-y-2 pl-6 text-body-lg text-text-primary"),
  ol: withClass("ol", "mt-4 list-decimal space-y-2 pl-6 text-body-lg text-text-primary"),
  li: withClass("li", "text-body-lg text-text-primary"),
  a: withClass("a", "text-accent underline underline-offset-2"),
  strong: withClass("strong", "font-semibold"),
  em: withClass("em", "italic"),
  blockquote: withClass(
    "blockquote",
    "mt-4 border-l-2 border-border-strong pl-4 text-body-lg text-text-secondary",
  ),
  hr: withClass("hr", "my-8 border-border"),
  code: withClass("code", "rounded-sm bg-surface-raised px-1 font-mono"),
  table: ({ node, ...props }) => {
    void node;
    return (
      <div className="mt-4 overflow-x-auto">
        <table className="w-full border-collapse text-body" {...props} />
      </div>
    );
  },
  th: withClass(
    "th",
    "border-b border-border-strong px-3 py-2 text-left text-label text-text-primary",
  ),
  td: withClass("td", "border-b border-border px-3 py-2 align-top text-body text-text-primary"),
};

export function LegalArticle({ doc }: { doc: LegalDocument }) {
  const dates = [
    doc.effectiveDate ? `Effective ${doc.effectiveDate}` : null,
    doc.lastUpdated ? `Last updated ${doc.lastUpdated}` : null,
  ].filter((part): part is string => part !== null);

  return (
    <article className="mx-auto flex w-full max-w-prose flex-col py-4">
      <header className="flex flex-col gap-2">
        <h1 className="text-display text-text-primary">{doc.title}</h1>
        {dates.length > 0 ? (
          <p className="text-caption text-text-tertiary">{dates.join(" · ")}</p>
        ) : null}
      </header>
      <div>
        <ReactMarkdown
          remarkPlugins={[remarkGfm]}
          rehypePlugins={[rehypeSlug]}
          components={markdownComponents}
        >
          {doc.body}
        </ReactMarkdown>
      </div>
    </article>
  );
}
