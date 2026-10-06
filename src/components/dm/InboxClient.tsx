"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { ChatCircle, NotePencil } from "@phosphor-icons/react";
import type { DmConversationRow } from "@/lib/database.types";
import { relativeTime } from "@/lib/format";
import { Avatar } from "@/components/Avatar";
import { DmDisclosure } from "@/components/dm/DmDisclosure";
import { NewMessageDialog } from "@/components/dm/NewMessageDialog";

type Tab = "primary" | "requests";

/**
 * The conversation list: Primary and Requests tabs, @handle-only rows,
 * previews served with the row (the server can read messages — the
 * disclosure banner above the list says exactly that). Requests carry
 * no badge anywhere; the count is visible only here, once the member
 * is already looking.
 */
export function InboxClient({
  viewerId,
  viewerHandle,
}: {
  viewerId: string;
  viewerHandle: string;
}) {
  const [tab, setTab] = useState<Tab>("primary");
  const [rows, setRows] = useState<DmConversationRow[] | null>(null);
  const [requestCount, setRequestCount] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [composeOpen, setComposeOpen] = useState(false);
  const seq = useRef(0);

  const load = useCallback(async (which: Tab) => {
    const mySeq = ++seq.current;
    try {
      const [primary, requests] = await Promise.all([
        fetch("/api/dm/conversations").then(
          (r) => r.json() as Promise<{ ok: boolean; conversations?: DmConversationRow[] }>,
        ),
        fetch("/api/dm/conversations?tab=requests").then(
          (r) => r.json() as Promise<{ ok: boolean; conversations?: DmConversationRow[] }>,
        ),
      ]);
      if (seq.current !== mySeq) return;
      if (!primary.ok || !requests.ok) {
        setError("Could not load your messages. Pull to retry.");
        return;
      }
      setError(null);
      setRequestCount((requests.conversations ?? []).length);
      setRows(which === "primary" ? (primary.conversations ?? []) : (requests.conversations ?? []));
    } catch {
      if (seq.current === mySeq) setError("Could not load your messages.");
    }
  }, []);

  useEffect(() => {
    const kick = setTimeout(() => void load(tab), 0);
    const interval = setInterval(() => void load(tab), 20000);
    const onFocus = () => void load(tab);
    window.addEventListener("focus", onFocus);
    return () => {
      clearTimeout(kick);
      clearInterval(interval);
      window.removeEventListener("focus", onFocus);
    };
  }, [load, tab]);

  return (
    <div className="flex flex-col lg:mt-6 lg:overflow-hidden lg:rounded-lg lg:border lg:border-border lg:shadow-e1">
      <header className="flex items-center justify-between border-b border-border bg-surface px-4 py-3">
        <h1 className="text-heading text-text-primary">Messages</h1>
        <button
          type="button"
          aria-label="New message"
          onClick={() => setComposeOpen(true)}
          className="flex size-11 items-center justify-center rounded-md text-accent hover:bg-accent-subtle"
        >
          <NotePencil size={22} aria-hidden />
        </button>
      </header>

      <DmDisclosure />

      <div role="tablist" aria-label="Inbox" className="flex border-b border-border bg-surface">
        <TabButton
          label="Primary"
          active={tab === "primary"}
          onClick={() => {
            setTab("primary");
            setRows(null);
          }}
        />
        <TabButton
          label={requestCount > 0 ? `Requests ${requestCount}` : "Requests"}
          active={tab === "requests"}
          onClick={() => {
            setTab("requests");
            setRows(null);
          }}
        />
      </div>

      {error ? (
        <p role="alert" className="px-4 py-3 text-body text-danger">
          {error}
        </p>
      ) : null}

      {rows === null ? (
        <InboxSkeleton />
      ) : rows.length === 0 ? (
        tab === "primary" ? (
          <EmptyPrimary onCompose={() => setComposeOpen(true)} />
        ) : (
          <EmptyRequests />
        )
      ) : (
        <ul className="flex flex-col">
          {rows.map((row) => (
            <li key={row.conversation_id}>
              <Link
                href={`/messages/${row.conversation_id}`}
                className="flex min-h-[72px] items-center gap-3 border-b border-border bg-surface px-4 py-3 transition-colors duration-(--duration-fast) hover:bg-surface-raised"
              >
                <Avatar
                  handle={row.correspondent_handle}
                  size={48}
                  link={false}
                  userId={row.correspondent_id}
                />
                <div className="min-w-0 flex-1">
                  <p className="flex items-center gap-1.5">
                    {row.unread_count > 0 ? (
                      <span aria-hidden className="size-2 shrink-0 rounded-full bg-accent" />
                    ) : null}
                    <span
                      className={`truncate text-label text-text-primary ${
                        row.unread_count > 0 ? "font-semibold" : "font-medium"
                      }`}
                    >
                      @{row.correspondent_handle}
                    </span>
                    {row.state === "request" && row.is_initiator ? (
                      <span className="shrink-0 text-caption text-text-tertiary">
                        · Waiting to be accepted
                      </span>
                    ) : null}
                  </p>
                  <p
                    className={`truncate text-body ${
                      row.unread_count > 0 ? "text-text-secondary" : "text-text-tertiary"
                    }`}
                  >
                    {row.last_body === null
                      ? ""
                      : (row.last_sender_id === viewerId ? "You: " : "") + row.last_body}
                  </p>
                </div>
                <span className="shrink-0 self-start pt-0.5 text-caption text-text-tertiary">
                  {relativeTime(row.last_message_at)}
                </span>
              </Link>
            </li>
          ))}
        </ul>
      )}

      <NewMessageDialog
        open={composeOpen}
        onClose={() => setComposeOpen(false)}
        viewerHandle={viewerHandle}
      />
    </div>
  );
}

function TabButton({
  label,
  active,
  onClick,
}: {
  label: string;
  active: boolean;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      role="tab"
      aria-selected={active}
      onClick={onClick}
      className={`relative min-h-11 flex-1 text-label transition-colors duration-(--duration-fast) ${
        active ? "text-accent" : "text-text-secondary hover:text-text-primary"
      }`}
    >
      {label}
      {active ? (
        <span aria-hidden className="absolute inset-x-6 bottom-0 h-0.5 rounded-full bg-accent" />
      ) : null}
    </button>
  );
}

function EmptyPrimary({ onCompose }: { onCompose: () => void }) {
  return (
    <div className="flex flex-col items-center gap-2 px-6 py-16 text-center">
      <ChatCircle size={48} aria-hidden className="text-text-tertiary" />
      <h2 className="text-title text-text-primary">No messages yet</h2>
      <p className="max-w-sm text-body text-text-secondary">
        Conversations with people you follow appear here. Requests from anyone else wait quietly in
        the Requests tab.
      </p>
      <button
        type="button"
        onClick={onCompose}
        className="mt-2 min-h-11 rounded-md px-4 text-label text-accent hover:bg-accent-subtle"
      >
        Start a conversation
      </button>
    </div>
  );
}

function EmptyRequests() {
  return (
    <div className="flex flex-col items-center gap-2 px-6 py-16 text-center">
      <h2 className="text-title text-text-primary">No message requests</h2>
      <p className="max-w-sm text-body text-text-secondary">
        Requests from people you do not follow appear here. They never notify you, and the sender is
        never told whether you saw them.
      </p>
    </div>
  );
}

function InboxSkeleton() {
  return (
    <div aria-hidden className="flex flex-col">
      {[0, 1, 2, 3].map((i) => (
        <div
          key={i}
          className="flex min-h-[72px] items-center gap-3 border-b border-border px-4 py-3"
        >
          <span className="size-12 shrink-0 rounded-full bg-(--skeleton-base)" />
          <div className="flex min-w-0 flex-1 flex-col gap-2">
            <span className="h-3.5 w-32 rounded bg-(--skeleton-base)" />
            <span className="h-3 w-56 rounded bg-(--skeleton-base)" />
          </div>
        </div>
      ))}
    </div>
  );
}
