"use client";

import { useEffect, useReducer } from "react";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";
import type { AvatarMedia } from "@/lib/media/avatar";

/**
 * Client-side avatar resolution, batched and cached per page load.
 *
 * Every photo an avatar circle shows goes through the avatar_keys RPC —
 * the block-aware, status-aware SECURITY DEFINER resolver — never
 * through a raw profile read. The resolver enforces the mutual-hard
 * block rule (blocked_either, both directions), the suspended/banned
 * placeholder rule and the removed/purged rules at the database, so a
 * key that must not reach this client simply never arrives; this module
 * only remembers answers and coalesces lookups (one RPC per render
 * burst instead of one per avatar on screen).
 *
 * A missing media zone (NEXT_PUBLIC_MEDIA_URL unset) disables
 * resolution entirely: everything renders the letter placeholder and
 * no RPC is spent. RPC failures (including the migration not yet being
 * applied) cache as "no photo" — the letter placeholder is always the
 * safe answer.
 */

const MEDIA_ENABLED = Boolean(process.env.NEXT_PUBLIC_MEDIA_URL);
const BATCH_LIMIT = 200; // avatar_keys caps its input array at 200

const cache = new Map<string, AvatarMedia | null>();
const pending = new Set<string>();
const listeners = new Set<() => void>();
let flushScheduled = false;

function notify(): void {
  for (const listener of listeners) listener();
}

async function flush(): Promise<void> {
  flushScheduled = false;
  const batch = [...pending].slice(0, BATCH_LIMIT);
  if (batch.length === 0) return;
  for (const id of batch) pending.delete(id);

  const supabase = createSupabaseBrowserClient();
  const { data, error } = await supabase.rpc("avatar_keys", { p_users: batch });
  const found = new Map<string, AvatarMedia>();
  if (!error) {
    for (const row of data ?? []) {
      found.set(row.user_id, { key: row.avatar_key, blurhash: row.blurhash });
    }
  }
  for (const id of batch) {
    cache.set(id, found.get(id) ?? null);
  }
  notify();
  if (pending.size > 0) scheduleFlush();
}

function scheduleFlush(): void {
  if (flushScheduled) return;
  flushScheduled = true;
  setTimeout(() => void flush(), 0);
}

/** Drop a member's cached entry (after she changes or removes her photo). */
export function invalidateAvatar(userId: string): void {
  cache.delete(userId);
  notify();
}

/**
 * Resolve one member's avatar. Returns null until (and unless) the
 * resolver answers with a key — null is the letter placeholder.
 */
export function useAvatarMedia(userId: string | null): AvatarMedia | null {
  const [, rerender] = useReducer((count: number) => count + 1, 0);

  useEffect(() => {
    if (!MEDIA_ENABLED || !userId) return;
    listeners.add(rerender);
    if (!cache.has(userId) && !pending.has(userId)) {
      pending.add(userId);
      scheduleFlush();
    }
    return () => {
      listeners.delete(rerender);
    };
  }, [userId]);

  if (!MEDIA_ENABLED || !userId) return null;
  return cache.get(userId) ?? null;
}
