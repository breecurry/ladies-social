/**
 * On-device storage for the DM feature (browser only): device keys,
 * ratchet sessions, and the decrypted message store. Under end-to-end
 * encryption the SERVER holds only ciphertext, so the member's own
 * device is where readable history lives. Clearing site data erases
 * it — that is the honest E2E trade, surfaced in the UI, never papered
 * over with a server-readable backup.
 *
 * IndexedDB, not localStorage: structured values and room for message
 * history. No key material ever goes to localStorage, cookies, or the
 * server.
 */

import type { SerializedRatchetState } from "@/lib/dm/crypto";

const DB_NAME = "hersciety-dm";
const DB_VERSION = 1;

export interface StoredDevice {
  deviceId: string;
  dhSecret: string;
  dhPublic: string;
  signSecret: string;
  signPublic: string;
  signedPrekeySecret: string;
  signedPrekeyPublic: string;
  signedPrekeySig: string;
  /** Unconsumed one-time prekey secrets, keyed by public hex. */
  oneTimePrekeySecrets: Record<string, string>;
}

export interface StoredSession {
  peerId: string;
  peerDeviceId: string;
  state: SerializedRatchetState;
  updatedAt: number;
}

export type StoredMessageKind = "message" | "undecryptable" | "key_change";

export interface StoredMessage {
  /** `${conversationId}:${serverId}` — unique, sortable per thread. */
  key: string;
  conversationId: string;
  serverId: number;
  senderId: string;
  senderHandle: string;
  kind: StoredMessageKind;
  plaintext: string;
  sentAt: string;
  frankKey: string | null;
  frank: string | null;
  frankVerified: boolean;
}

export interface ConversationMeta {
  conversationId: string;
  lastFetchedId: number;
}

function openDb(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains("device")) db.createObjectStore("device");
      if (!db.objectStoreNames.contains("sessions")) {
        db.createObjectStore("sessions", { keyPath: "peerId" });
      }
      if (!db.objectStoreNames.contains("messages")) {
        const store = db.createObjectStore("messages", { keyPath: "key" });
        store.createIndex("byConversation", "conversationId");
      }
      if (!db.objectStoreNames.contains("meta")) {
        db.createObjectStore("meta", { keyPath: "conversationId" });
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error ?? new Error("IndexedDB unavailable."));
  });
}

async function tx<T>(
  storeName: string,
  mode: IDBTransactionMode,
  run: (store: IDBObjectStore) => IDBRequest<T>,
): Promise<T> {
  const db = await openDb();
  try {
    return await new Promise<T>((resolve, reject) => {
      const transaction = db.transaction(storeName, mode);
      const request = run(transaction.objectStore(storeName));
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error ?? new Error("Storage error."));
    });
  } finally {
    db.close();
  }
}

export async function loadDevice(): Promise<StoredDevice | null> {
  const result = await tx<StoredDevice | undefined>("device", "readonly", (s) =>
    s.get("device") as IDBRequest<StoredDevice | undefined>,
  );
  return result ?? null;
}

export async function saveDevice(device: StoredDevice): Promise<void> {
  await tx("device", "readwrite", (s) => s.put(device, "device"));
}

export async function loadSession(peerId: string): Promise<StoredSession | null> {
  const result = await tx<StoredSession | undefined>("sessions", "readonly", (s) =>
    s.get(peerId) as IDBRequest<StoredSession | undefined>,
  );
  return result ?? null;
}

export async function saveSession(session: StoredSession): Promise<void> {
  await tx("sessions", "readwrite", (s) => s.put(session));
}

export async function deleteSession(peerId: string): Promise<void> {
  await tx("sessions", "readwrite", (s) => s.delete(peerId));
}

export async function saveMessage(message: StoredMessage): Promise<void> {
  await tx("messages", "readwrite", (s) => s.put(message));
}

export async function loadMessage(
  conversationId: string,
  serverId: number,
): Promise<StoredMessage | null> {
  const result = await tx<StoredMessage | undefined>("messages", "readonly", (s) =>
    s.get(`${conversationId}:${String(serverId).padStart(12, "0")}`) as IDBRequest<
      StoredMessage | undefined
    >,
  );
  return result ?? null;
}

export function messageKey(conversationId: string, serverId: number): string {
  return `${conversationId}:${String(serverId).padStart(12, "0")}`;
}

export async function loadConversationMessages(
  conversationId: string,
): Promise<StoredMessage[]> {
  const rows = await tx<StoredMessage[]>("messages", "readonly", (s) =>
    s.index("byConversation").getAll(conversationId) as IDBRequest<StoredMessage[]>,
  );
  return rows.sort((a, b) => a.serverId - b.serverId);
}

export async function deleteConversationMessages(conversationId: string): Promise<void> {
  const rows = await loadConversationMessages(conversationId);
  const db = await openDb();
  try {
    await new Promise<void>((resolve, reject) => {
      const transaction = db.transaction(["messages", "meta"], "readwrite");
      const store = transaction.objectStore("messages");
      for (const row of rows) store.delete(row.key);
      transaction.objectStore("meta").delete(conversationId);
      transaction.oncomplete = () => resolve();
      transaction.onerror = () => reject(transaction.error ?? new Error("Storage error."));
    });
  } finally {
    db.close();
  }
}

export async function loadMeta(conversationId: string): Promise<ConversationMeta | null> {
  const result = await tx<ConversationMeta | undefined>("meta", "readonly", (s) =>
    s.get(conversationId) as IDBRequest<ConversationMeta | undefined>,
  );
  return result ?? null;
}

export async function saveMeta(meta: ConversationMeta): Promise<void> {
  await tx("meta", "readwrite", (s) => s.put(meta));
}
