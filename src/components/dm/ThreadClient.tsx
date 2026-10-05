"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import {
  DotsThree,
  LockSimple,
  PaperPlaneTilt,
  Prohibit,
  ShieldCheck,
  SpeakerSimpleSlash,
  Trash,
  User,
  Flag,
} from "@phosphor-icons/react";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";
import type { DmConversationRow } from "@/lib/database.types";
import { Avatar } from "@/components/Avatar";
import { ConfirmDialog } from "@/components/ConfirmDialog";
import { useToast } from "@/components/shell/ToastProvider";
import { sendDm, syncConversation, clearLocalThread } from "@/lib/dm/client";
import type { StoredMessage } from "@/lib/dm/store";
import { VerifyDialog } from "@/components/dm/VerifyDialog";
import { DmReportDialog } from "@/components/dm/DmReportDialog";

type Route = "inbox" | "request" | "none";

interface ThreadState {
  conversation: DmConversationRow | null;
  peerId: string;
  peerHandle: string;
}

/**
 * One conversation (design §11-§14): @handle-only header, the honest
 * encryption line, asymmetric bubbles, a composer that cannot lie —
 * request states, the waiting state, and the indistinguishable
 * can-no-longer-reply state all say exactly what is true.
 */
export function ThreadClient(props: {
  viewerId: string;
  viewerHandle: string;
  conversationId?: string;
  peerId?: string;
  peerHandle?: string;
}) {
  const { viewerId, viewerHandle } = props;
  const router = useRouter();
  const { showToast } = useToast();

  const [thread, setThread] = useState<ThreadState | null>(null);
  const [messages, setMessages] = useState<StoredMessage[]>([]);
  const [route, setRoute] = useState<Route | null>(null);
  const [draft, setDraft] = useState("");
  const [sending, setSending] = useState(false);
  const [sendError, setSendError] = useState<string | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [menuOpen, setMenuOpen] = useState(false);
  const [verifyOpen, setVerifyOpen] = useState(false);
  const [reportOpen, setReportOpen] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [confirmBlock, setConfirmBlock] = useState(false);
  const [actionBusy, setActionBusy] = useState(false);

  const conversationIdRef = useRef<string | null>(props.conversationId ?? null);
  const bottomRef = useRef<HTMLDivElement>(null);
  const menuRef = useRef<HTMLDivElement>(null);
  const lastMarkedRef = useRef(0);

  const loadConversation = useCallback(async (): Promise<ThreadState | null> => {
    try {
      const [primary, requests] = await Promise.all([
        fetch("/api/dm/conversations").then(
          (r) => r.json() as Promise<{ ok: boolean; conversations?: DmConversationRow[] }>,
        ),
        fetch("/api/dm/conversations?tab=requests").then(
          (r) => r.json() as Promise<{ ok: boolean; conversations?: DmConversationRow[] }>,
        ),
      ]);
      const all = [...(primary.conversations ?? []), ...(requests.conversations ?? [])];
      const row = conversationIdRef.current
        ? all.find((c) => c.conversation_id === conversationIdRef.current)
        : all.find((c) => c.correspondent_id === props.peerId);
      if (row) {
        conversationIdRef.current = row.conversation_id;
        return {
          conversation: row,
          peerId: row.correspondent_id,
          peerHandle: row.correspondent_handle,
        };
      }
      if (props.peerId && props.peerHandle) {
        return { conversation: null, peerId: props.peerId, peerHandle: props.peerHandle };
      }
      return null;
    } catch {
      return null;
    }
  }, [props.peerId, props.peerHandle]);

  const refresh = useCallback(async () => {
    const state = await loadConversation();
    if (!state) {
      setLoadError("This conversation is unavailable.");
      return;
    }
    setThread(state);
    try {
      const response = await fetch(
        `/api/dm/can-message?userId=${encodeURIComponent(state.peerId)}`,
      );
      const body = (await response.json()) as { ok: boolean; route?: string };
      setRoute(
        body.ok && (body.route === "inbox" || body.route === "request")
          ? (body.route as Route)
          : "none",
      );
    } catch {
      setRoute(null);
    }
    if (conversationIdRef.current) {
      try {
        const stored = await syncConversation(viewerId, conversationIdRef.current);
        setMessages(stored);
        const newestIncoming = stored
          .filter((m) => m.senderId !== viewerId)
          .reduce((max, m) => Math.max(max, m.serverId), 0);
        if (newestIncoming > lastMarkedRef.current) {
          lastMarkedRef.current = newestIncoming;
          void fetch("/api/dm/conversations/action", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ action: "read", conversationId: conversationIdRef.current }),
          });
        }
      } catch {
        setLoadError("Could not load messages. We will keep trying.");
      }
    }
  }, [loadConversation, viewerId]);

  useEffect(() => {
    const kick = setTimeout(() => void refresh(), 0);
    const interval = setInterval(() => void refresh(), 5000);
    return () => {
      clearTimeout(kick);
      clearInterval(interval);
    };
  }, [refresh]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ block: "end" });
  }, [messages.length]);

  useEffect(() => {
    if (!menuOpen) return;
    const onPointerDown = (event: PointerEvent) => {
      if (menuRef.current && !menuRef.current.contains(event.target as Node)) setMenuOpen(false);
    };
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") setMenuOpen(false);
    };
    document.addEventListener("pointerdown", onPointerDown);
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.removeEventListener("pointerdown", onPointerDown);
      document.removeEventListener("keydown", onKeyDown);
    };
  }, [menuOpen]);

  const send = async () => {
    const text = draft.trim();
    if (text === "" || !thread || sending) return;
    if (text.length > 2000) {
      setSendError("Messages are limited to 2000 characters.");
      return;
    }
    setSending(true);
    setSendError(null);
    try {
      const result = await sendDm(viewerId, viewerHandle, thread.peerId, text);
      setDraft("");
      if (!props.conversationId && conversationIdRef.current === null) {
        conversationIdRef.current = result.conversationId;
        router.replace(`/messages/${result.conversationId}`);
      }
      await refresh();
    } catch (error) {
      // The typed text is preserved; the member retries, never retypes.
      setSendError(error instanceof Error ? error.message : "Could not send. Tap to retry.");
    } finally {
      setSending(false);
    }
  };

  const conversationAction = async (
    action: "accept" | "decline" | "delete" | "mute" | "unmute",
  ) => {
    if (!conversationIdRef.current || actionBusy) return;
    setActionBusy(true);
    try {
      const response = await fetch("/api/dm/conversations/action", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action, conversationId: conversationIdRef.current }),
      });
      const body = (await response.json()) as { ok: boolean; error?: string };
      if (!body.ok) {
        showToast(body.error ?? "Something went wrong. Try again.");
        return;
      }
      if (action === "delete") {
        await clearLocalThread(conversationIdRef.current);
        router.push("/messages");
        return;
      }
      if (action === "decline") {
        router.push("/messages");
        return;
      }
      if (action === "mute") showToast("You will not be notified about this conversation. It stays in your inbox.");
      if (action === "unmute") showToast("Notifications are back on for this conversation.");
      await refresh();
    } finally {
      setActionBusy(false);
    }
  };

  const blockPeer = async () => {
    if (!thread) return;
    const supabase = createSupabaseBrowserClient();
    const { error } = await supabase
      .from("blocks")
      .insert({ blocker_id: viewerId, blocked_id: thread.peerId });
    setConfirmBlock(false);
    if (error) {
      showToast(error.message);
      return;
    }
    showToast(`Blocked @${thread.peerHandle}`);
    await refresh();
  };

  if (loadError && !thread) {
    return (
      <p role="alert" className="px-4 py-16 text-center text-body text-text-secondary">
        {loadError}
      </p>
    );
  }
  if (!thread) {
    return <ThreadSkeleton />;
  }

  const conversation = thread.conversation;
  const isRequestToMe =
    conversation?.state === "request" && conversation.is_initiator === false;
  const isWaiting = conversation?.state === "request" && conversation.is_initiator === true;
  const canReply =
    !isRequestToMe && !isWaiting && (route === "inbox" || route === "request" || route === null);

  const lastOwn = [...messages].reverse().find((m) => m.senderId === viewerId);
  const peerReadAt = conversation?.peer_read_at ? new Date(conversation.peer_read_at) : null;
  const lastOwnRead =
    lastOwn && peerReadAt !== null && peerReadAt >= new Date(lastOwn.sentAt);

  return (
    <div className="flex min-h-[calc(100dvh-120px)] flex-col lg:mt-6 lg:min-h-0 lg:overflow-hidden lg:rounded-lg lg:border lg:border-border lg:shadow-e1">
      {/* Header: @handle only, never a legal name (design §0.1). */}
      <header className="sticky top-12 z-10 flex items-center gap-3 border-b border-border bg-surface px-4 py-2 lg:top-0">
        <Avatar handle={thread.peerHandle} size={32} userId={thread.peerId} />
        <Link
          href={`/u/${thread.peerHandle}`}
          className="min-w-0 flex-1 truncate text-heading text-text-primary"
        >
          @{thread.peerHandle}
        </Link>
        <div ref={menuRef} className="relative">
          <button
            type="button"
            aria-label="Conversation options"
            aria-haspopup="menu"
            aria-expanded={menuOpen}
            onClick={() => setMenuOpen((v) => !v)}
            className="flex size-11 items-center justify-center rounded-md text-text-secondary hover:bg-surface-raised"
          >
            <DotsThree size={22} weight="bold" aria-hidden />
          </button>
          {menuOpen ? (
            <div
              role="menu"
              aria-label="Conversation options"
              className="absolute right-0 top-full z-20 mt-1 w-64 rounded-md bg-surface-raised py-2 shadow-e2"
            >
              <MenuItem
                icon={<User size={20} aria-hidden />}
                label="View profile"
                onClick={() => {
                  setMenuOpen(false);
                  router.push(`/u/${thread.peerHandle}`);
                }}
              />
              <MenuItem
                icon={<ShieldCheck size={20} aria-hidden />}
                label={`Verify @${thread.peerHandle}`}
                onClick={() => {
                  setMenuOpen(false);
                  setVerifyOpen(true);
                }}
              />
              <MenuDivider />
              <MenuItem
                icon={<SpeakerSimpleSlash size={20} aria-hidden />}
                label={conversation?.muted ? "Unmute messages" : "Mute messages"}
                onClick={() => {
                  setMenuOpen(false);
                  void conversationAction(conversation?.muted ? "unmute" : "mute");
                }}
                disabled={!conversation}
              />
              <MenuDivider />
              <MenuItem
                icon={<Trash size={20} aria-hidden />}
                label="Delete conversation"
                danger
                onClick={() => {
                  setMenuOpen(false);
                  setConfirmDelete(true);
                }}
                disabled={!conversation}
              />
              <MenuItem
                icon={<Prohibit size={20} aria-hidden />}
                label={`Block @${thread.peerHandle}`}
                danger
                onClick={() => {
                  setMenuOpen(false);
                  setConfirmBlock(true);
                }}
              />
              <MenuItem
                icon={<Flag size={20} aria-hidden />}
                label="Report"
                danger
                onClick={() => {
                  setMenuOpen(false);
                  setReportOpen(true);
                }}
                disabled={!conversation || messages.every((m) => m.kind !== "message")}
              />
            </div>
          ) : null}
        </div>
      </header>

      {/* The honest encryption line (design §11). */}
      <button
        type="button"
        onClick={() => setVerifyOpen(true)}
        className="flex items-center justify-center gap-1.5 bg-background px-4 py-2 text-caption text-text-secondary"
      >
        <LockSimple size={14} aria-hidden />
        Messages are end-to-end encrypted. Hersciety cannot read them.
      </button>

      {/* The messages. */}
      <div className="flex flex-1 flex-col gap-0.5 overflow-y-auto bg-background px-4 py-3 lg:max-h-[60dvh]">
        {messages.map((message, index) => (
          <Bubble
            key={message.key}
            message={message}
            own={message.senderId === viewerId}
            showTime={
              index === messages.length - 1 ||
              messages[index + 1]?.senderId !== message.senderId
            }
          />
        ))}
        {lastOwn && conversation?.state === "accepted" ? (
          <p className="self-end text-caption text-text-tertiary">
            {lastOwnRead ? "Read" : "Sent"}
          </p>
        ) : null}
        <div ref={bottomRef} />
      </div>

      {/* The composer, or the honest state that replaces it. */}
      {isRequestToMe && conversation ? (
        <RequestBar
          handle={thread.peerHandle}
          busy={actionBusy}
          onAccept={() => void conversationAction("accept")}
          onDelete={() => void conversationAction("decline")}
          onBlock={() => setConfirmBlock(true)}
          onReport={() => setReportOpen(true)}
        />
      ) : isWaiting ? (
        <p className="border-t border-border bg-surface px-4 py-4 text-center text-caption text-text-tertiary">
          Waiting to be accepted. You can send more messages once @{thread.peerHandle} accepts.
        </p>
      ) : route === "none" ? (
        <p className="border-t border-border bg-surface px-4 py-4 text-center text-caption text-text-secondary">
          You can no longer reply to this conversation.
        </p>
      ) : (
        <div className="border-t border-border bg-surface p-3">
          {sendError ? (
            <p role="alert" className="mb-2 text-caption text-danger">
              {sendError}
            </p>
          ) : null}
          <div className="flex items-end gap-2">
            <textarea
              value={draft}
              onChange={(event) => setDraft(event.target.value)}
              onKeyDown={(event) => {
                // Enter sends on desktop; Shift+Enter inserts a newline.
                // On touch keyboards Enter inserts a newline (§12).
                if (event.key === "Enter" && !event.shiftKey && window.matchMedia("(min-width: 1024px)").matches) {
                  event.preventDefault();
                  void send();
                }
              }}
              rows={draft.includes("\n") || draft.length > 80 ? 3 : 1}
              maxLength={2000}
              placeholder="Message"
              aria-label={`Message @${thread.peerHandle}`}
              className="min-h-11 w-full resize-none rounded-[22px] border border-border-strong bg-surface px-4 py-2.5 text-body text-text-primary placeholder:text-text-tertiary"
            />
            <button
              type="button"
              aria-label="Send"
              disabled={draft.trim() === "" || sending}
              onClick={() => void send()}
              className="flex size-11 shrink-0 items-center justify-center rounded-full bg-accent-fill text-on-accent transition-opacity duration-(--duration-fast) hover:bg-accent-hover disabled:opacity-50"
            >
              <PaperPlaneTilt size={20} aria-hidden />
            </button>
          </div>
          {canReply && !conversation && route === "request" ? (
            <p className="mt-2 text-caption text-text-tertiary">
              @{thread.peerHandle} does not follow you, so this will arrive as a quiet request.
              You can send one message until they accept.
            </p>
          ) : null}
        </div>
      )}

      <VerifyDialog
        open={verifyOpen}
        onClose={() => setVerifyOpen(false)}
        peerId={thread.peerId}
        peerHandle={thread.peerHandle}
      />
      {conversation ? (
        <DmReportDialog
          open={reportOpen}
          onClose={() => setReportOpen(false)}
          conversationId={conversation.conversation_id}
          peerId={thread.peerId}
          peerHandle={thread.peerHandle}
          viewerId={viewerId}
          messages={messages}
        />
      ) : null}

      {/* Delete: the one unrecoverable DM action (design §19.3). */}
      <ConfirmDialog
        open={confirmDelete}
        title="Delete this conversation?"
        body={`This removes the conversation from your account and your devices. You cannot get it back. @${thread.peerHandle} will still have their copy of the conversation.`}
        cancelLabel="Keep conversation"
        confirmLabel="Delete for me"
        onCancel={() => setConfirmDelete(false)}
        onConfirm={() => {
          setConfirmDelete(false);
          void conversationAction("delete");
        }}
      />
      <ConfirmDialog
        open={confirmBlock}
        title={`Block @${thread.peerHandle}?`}
        body="They will not be able to message you, send you a request, see your profile or posts, or follow you. They will not be told."
        cancelLabel="Cancel"
        confirmLabel={`Block @${thread.peerHandle}`}
        onCancel={() => setConfirmBlock(false)}
        onConfirm={() => void blockPeer()}
      />
    </div>
  );
}

function Bubble({
  message,
  own,
  showTime,
}: {
  message: StoredMessage;
  own: boolean;
  showTime: boolean;
}) {
  if (message.kind === "key_change") {
    return (
      <p className="my-2 text-center text-caption text-text-tertiary">
        @{message.senderHandle}&apos;s security code changed. This usually means a new device —
        if you were not expecting it, verify before saying anything sensitive.
      </p>
    );
  }
  if (message.kind === "undecryptable") {
    return (
      <p className="my-1 text-center text-caption text-text-tertiary">
        A message sent before this device was set up cannot be shown here.
      </p>
    );
  }
  return (
    <div className={`flex flex-col ${own ? "items-end" : "items-start"}`}>
      <div
        className={`max-w-[85%] whitespace-pre-wrap break-words px-4 py-2.5 text-body-lg text-text-primary ${
          own
            ? "rounded-[14px] rounded-br-md bg-accent-subtle"
            : "rounded-[14px] rounded-bl-md bg-surface-raised"
        }`}
      >
        {/* Accessible sender prefix: never conveyed by bubble side alone. */}
        <span className="sr-only">{own ? "You said: " : `@${message.senderHandle} said: `}</span>
        {message.plaintext}
      </div>
      {showTime ? (
        <span className="mt-0.5 px-1 text-caption text-text-tertiary">
          {new Date(message.sentAt).toLocaleString(undefined, {
            day: "numeric",
            month: "short",
            hour: "2-digit",
            minute: "2-digit",
          })}
        </span>
      ) : null}
    </div>
  );
}

/** Accept / Delete / Block — distinct verbs and weights (design §10). */
function RequestBar({
  handle,
  busy,
  onAccept,
  onDelete,
  onBlock,
  onReport,
}: {
  handle: string;
  busy: boolean;
  onAccept: () => void;
  onDelete: () => void;
  onBlock: () => void;
  onReport: () => void;
}) {
  return (
    <div className="flex flex-col gap-3 border-t border-border bg-surface p-4">
      <p className="text-body text-text-secondary">
        @{handle} wants to send you messages. They will not know you have seen this until you
        accept, and they cannot send anything more unless you do.
      </p>
      <div className="flex flex-wrap items-center gap-2">
        <button
          type="button"
          disabled={busy}
          onClick={onAccept}
          className="min-h-11 rounded-md border border-border-strong bg-surface px-4 text-label text-text-primary hover:bg-surface-raised disabled:opacity-50"
        >
          Accept
        </button>
        <button
          type="button"
          disabled={busy}
          onClick={onDelete}
          className="ml-auto min-h-11 rounded-md px-4 text-label text-danger hover:bg-danger-subtle disabled:opacity-50"
        >
          Delete
        </button>
        <button
          type="button"
          disabled={busy}
          onClick={onBlock}
          className="min-h-11 rounded-md px-4 text-label text-danger hover:bg-danger-subtle disabled:opacity-50"
        >
          Block
        </button>
        <button
          type="button"
          disabled={busy}
          onClick={onReport}
          className="min-h-11 rounded-md px-4 text-label text-danger hover:bg-danger-subtle disabled:opacity-50"
        >
          Report
        </button>
      </div>
    </div>
  );
}

function MenuItem({
  icon,
  label,
  onClick,
  danger = false,
  disabled = false,
}: {
  icon: React.ReactNode;
  label: string;
  onClick: () => void;
  danger?: boolean;
  disabled?: boolean;
}) {
  return (
    <button
      type="button"
      role="menuitem"
      onClick={onClick}
      disabled={disabled}
      className={`flex min-h-11 w-full items-center gap-3 px-4 text-left text-body disabled:opacity-50 ${
        danger ? "text-danger hover:bg-danger-subtle" : "text-text-primary hover:bg-accent-subtle"
      }`}
    >
      {icon}
      {label}
    </button>
  );
}

function MenuDivider() {
  return <div aria-hidden className="my-1 border-t border-border" />;
}

function ThreadSkeleton() {
  return (
    <div aria-hidden className="flex flex-col gap-3 px-4 py-6 lg:mt-6">
      <div className="flex items-center gap-3">
        <span className="size-8 rounded-full bg-(--skeleton-base)" />
        <span className="h-4 w-28 rounded bg-(--skeleton-base)" />
      </div>
      <span className="h-10 w-48 self-start rounded-[14px] bg-(--skeleton-base)" />
      <span className="h-10 w-56 self-end rounded-[14px] bg-(--skeleton-base)" />
      <span className="h-10 w-40 self-start rounded-[14px] bg-(--skeleton-base)" />
    </div>
  );
}
