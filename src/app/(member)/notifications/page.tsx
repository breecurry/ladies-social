import type { Metadata } from "next";
import Link from "next/link";
import { Bell } from "@phosphor-icons/react/dist/ssr";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import type { NotificationItem } from "@/lib/database.types";
import { relativeTime } from "@/lib/format";
import { Avatar } from "@/components/Avatar";
import { MarkAllRead } from "@/components/notifications/MarkAllRead";

export const metadata: Metadata = { title: "Notifications" };

function describe(item: NotificationItem): string {
  switch (item.type) {
    case "follow":
      return "followed you";
    case "like":
      return "liked your post";
    case "reply":
      return "replied to your post";
    case "mention":
      return "mentioned you";
    case "message":
      return "sent you a message";
    case "system":
      return "Hersciety";
  }
}

export default async function NotificationsPage() {
  const supabase = await createSupabaseServerClient();
  const { data } = await supabase.rpc("get_notifications", { p_limit: 50 });
  const items = data ?? [];
  const hasUnread = items.some((item) => item.read_at === null);

  return (
    <div className="flex flex-col lg:mt-6 lg:overflow-hidden lg:rounded-lg lg:border lg:border-border lg:shadow-e1">
      <header className="border-b border-border bg-surface px-4 py-3">
        <h1 className="text-heading text-text-primary">Notifications</h1>
      </header>
      <MarkAllRead hasUnread={hasUnread} />
      {items.length === 0 ? (
        <div className="flex flex-col items-center gap-2 px-6 py-16 text-center">
          <Bell size={48} aria-hidden className="text-text-tertiary" />
          <h2 className="text-title text-text-primary">No notifications yet</h2>
          <p className="max-w-sm text-body text-text-secondary">
            When someone follows you, replies, or mentions you, it shows up here.
          </p>
        </div>
      ) : (
        items.map((item) => {
          const row = (
            <div
              className={`flex items-start gap-3 border-b border-border px-4 py-3 ${
                item.read_at === null ? "bg-accent-subtle/40" : "bg-surface"
              } transition-colors duration-(--duration-fast) hover:bg-surface-raised`}
            >
              {item.actor_handle !== "" ? (
                <Avatar handle={item.actor_handle} size={32} link={false} />
              ) : (
                <Bell size={24} aria-hidden className="mt-1 text-text-tertiary" />
              )}
              <div className="min-w-0 flex-1">
                <p className="text-body text-text-primary">
                  {item.actor_handle !== "" ? (
                    <span className="font-semibold">@{item.actor_handle}</span>
                  ) : null}{" "}
                  {describe(item)}
                  <span className="text-caption text-text-tertiary">
                    {" "}
                    · {relativeTime(item.created_at)}
                  </span>
                </p>
                {item.body ? (
                  <p className="whitespace-pre-wrap break-words text-body text-text-secondary">
                    {item.body}
                  </p>
                ) : null}
                {item.post_excerpt ? (
                  <p className="truncate text-caption text-text-tertiary">{item.post_excerpt}</p>
                ) : null}
              </div>
            </div>
          );
          return item.type === "message" ? (
            <Link key={item.id} href="/messages">
              {row}
            </Link>
          ) : item.post_id !== null ? (
            <Link key={item.id} href={`/post/${item.post_id}`}>
              {row}
            </Link>
          ) : item.actor_handle !== "" ? (
            <Link key={item.id} href={`/u/${item.actor_handle}`}>
              {row}
            </Link>
          ) : (
            <div key={item.id}>{row}</div>
          );
        })
      )}
    </div>
  );
}
