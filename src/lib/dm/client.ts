"use client";

/**
 * Browser-side orchestration of the DM protocol: device lifecycle,
 * session management, encrypt-send, fetch-decrypt-store, and evidence
 * collection for report-with-evidence.
 *
 * Everything crosses the network through /api/dm/* routes; the crypto
 * lives in ./crypto and the local plaintext store in ./store. Nothing
 * in this module ever sends plaintext or secret key material to the
 * server — the single deliberate exception is reportEvidence(), where
 * the REPORTER chooses to reveal specific messages (plaintext plus
 * franking key) to the safety team, and the UI says so in plain words.
 */

import {
  generateDeviceKeys,
  generateOneTimePrekeys,
  identityPublic,
  x3dhInitiate,
  x3dhReceive,
  initiatorSession,
  receiverSession,
  encryptMessage,
  decryptMessage,
  serializeState,
  deserializeState,
  safetyNumber,
  bytesToHex,
  hexToBytes,
  toBytea,
  type DeviceKeyPairs,
  type MessageHeader,
  type PrekeyBundle,
} from "@/lib/dm/crypto";
import {
  loadDevice,
  saveDevice,
  loadSession,
  saveSession,
  deleteSession,
  loadMessage,
  saveMessage,
  messageKey,
  loadConversationMessages,
  deleteConversationMessages,
  loadMeta,
  saveMeta,
  type StoredDevice,
  type StoredMessage,
} from "@/lib/dm/store";

const PREKEY_BATCH = 50;
const PREKEY_LOW_WATER = 10;

interface ApiError {
  ok: false;
  error: string;
}

async function api<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(path, {
    headers: { "Content-Type": "application/json" },
    ...init,
  });
  const body = (await response.json().catch(() => null)) as (T & { ok: true }) | ApiError | null;
  if (!body || body.ok !== true) {
    throw new Error((body as ApiError | null)?.error ?? "Something went wrong. Try again.");
  }
  return body;
}

function deviceToKeys(device: StoredDevice): DeviceKeyPairs {
  return {
    dhSecret: hexToBytes(device.dhSecret),
    dhPublic: hexToBytes(device.dhPublic),
    signSecret: hexToBytes(device.signSecret),
    signPublic: hexToBytes(device.signPublic),
    signedPrekeySecret: hexToBytes(device.signedPrekeySecret),
    signedPrekeyPublic: hexToBytes(device.signedPrekeyPublic),
    signedPrekeySig: hexToBytes(device.signedPrekeySig),
  };
}

/**
 * Make sure this browser has a registered, active device whose private
 * keys we actually hold. Registers a fresh device (revoking any
 * previous one — old history becomes unreadable, by design) when the
 * server knows no device or knows one whose keys we do not have.
 * Replenishes one-time prekeys when they run low.
 */
export async function ensureDevice(): Promise<StoredDevice> {
  const local = await loadDevice();
  const mine = await api<{
    ok: true;
    device: { deviceId: string; identityKey: string; prekeysRemaining: number } | null;
  }>("/api/dm/devices");

  if (local && mine.device && mine.device.deviceId === local.deviceId) {
    if (mine.device.prekeysRemaining < PREKEY_LOW_WATER) {
      const fresh = generateOneTimePrekeys(PREKEY_BATCH);
      await api("/api/dm/prekeys", {
        method: "POST",
        body: JSON.stringify({ prekeys: fresh.map((p) => toBytea(p.public)) }),
      });
      for (const p of fresh) local.oneTimePrekeySecrets[bytesToHex(p.public)] = bytesToHex(p.secret);
      await saveDevice(local);
    }
    return local;
  }

  // New browser, cleared storage, or revoked device: register fresh.
  const keys = generateDeviceKeys();
  const prekeys = generateOneTimePrekeys(PREKEY_BATCH);
  const registered = await api<{ ok: true; deviceId: string }>("/api/dm/devices", {
    method: "POST",
    body: JSON.stringify({
      deviceName: "Browser",
      identityKey: toBytea(identityPublic(keys)),
      signedPrekey: toBytea(keys.signedPrekeyPublic),
      signedPrekeySig: toBytea(keys.signedPrekeySig),
      prekeys: prekeys.map((p) => toBytea(p.public)),
    }),
  });
  const device: StoredDevice = {
    deviceId: registered.deviceId,
    dhSecret: bytesToHex(keys.dhSecret),
    dhPublic: bytesToHex(keys.dhPublic),
    signSecret: bytesToHex(keys.signSecret),
    signPublic: bytesToHex(keys.signPublic),
    signedPrekeySecret: bytesToHex(keys.signedPrekeySecret),
    signedPrekeyPublic: bytesToHex(keys.signedPrekeyPublic),
    signedPrekeySig: bytesToHex(keys.signedPrekeySig),
    oneTimePrekeySecrets: Object.fromEntries(
      prekeys.map((p) => [bytesToHex(p.public), bytesToHex(p.secret)]),
    ),
  };
  await saveDevice(device);
  return device;
}

interface BundleResponse {
  ok: true;
  bundle: {
    deviceId: string;
    identityKey: string;
    signedPrekey: string;
    signedPrekeySig: string;
    prekey: string | null;
  };
}

/** Open a fresh outgoing session with the peer's current device. */
async function createSession(
  device: StoredDevice,
  peerId: string,
): Promise<{ peerDeviceId: string }> {
  const { bundle } = await api<BundleResponse>(
    `/api/dm/bundle?userId=${encodeURIComponent(peerId)}`,
  );
  const parsed: PrekeyBundle = {
    identityKey: hexToBytes(bundle.identityKey),
    signedPrekey: hexToBytes(bundle.signedPrekey),
    signedPrekeySig: hexToBytes(bundle.signedPrekeySig),
    oneTimePrekey: bundle.prekey ? hexToBytes(bundle.prekey) : null,
  };
  const keys = deviceToKeys(device);
  const { sharedKey, init } = x3dhInitiate(keys, parsed);
  const state = initiatorSession(sharedKey, parsed, init);
  await saveSession({
    peerId,
    peerDeviceId: bundle.deviceId,
    state: serializeState(state),
    updatedAt: Date.now(),
  });
  return { peerDeviceId: bundle.deviceId };
}

export interface SendResult {
  conversationId: string;
  state: "request" | "accepted";
  messageId: number;
}

/**
 * Encrypt and send one text message. Handles the peer's device having
 * changed (fetches a fresh bundle and retries once, and records a
 * key-change line in the local thread).
 */
export async function sendDm(
  myId: string,
  myHandle: string,
  peerId: string,
  text: string,
): Promise<SendResult> {
  const device = await ensureDevice();
  let session = await loadSession(peerId);
  if (!session) {
    await createSession(device, peerId);
    session = await loadSession(peerId);
  }
  if (!session) throw new Error("Could not open a secure session.");

  for (let attempt = 0; attempt < 2; attempt++) {
    const state = deserializeState(session.state);
    const sealed = encryptMessage(state, myId, peerId, text);
    try {
      const sent = await api<{
        ok: true;
        messageId: number;
        conversationId: string;
        state: "request" | "accepted";
        sentAt: string;
      }>("/api/dm/messages", {
        method: "POST",
        body: JSON.stringify({
          recipientId: peerId,
          recipientDeviceId: session.peerDeviceId,
          header: sealed.header,
          ciphertext: toBytea(sealed.ciphertext),
          frankHash: toBytea(sealed.frankHash),
        }),
      });
      // Commit the ratchet step only after the server accepted it.
      session.state = serializeState(state);
      session.updatedAt = Date.now();
      await saveSession(session);
      await saveMessage({
        key: messageKey(sent.conversationId, sent.messageId),
        conversationId: sent.conversationId,
        serverId: sent.messageId,
        senderId: myId,
        senderHandle: myHandle,
        kind: "message",
        plaintext: text,
        sentAt: sent.sentAt,
        frankKey: bytesToHex(sealed.frankKey),
        frank: bytesToHex(sealed.frank),
        frankVerified: true,
      });
      return {
        conversationId: sent.conversationId,
        state: sent.state,
        messageId: sent.messageId,
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : "";
      if (message.includes("RECIPIENT_DEVICE_CHANGED") && attempt === 0) {
        // Her security code changed (usually a new device). Start a
        // fresh session against the new bundle and retry once.
        await deleteSession(peerId);
        await createSession(device, peerId);
        session = await loadSession(peerId);
        if (!session) throw new Error("Could not open a secure session.");
        continue;
      }
      throw error;
    }
  }
  throw new Error("Could not send. Tap to retry.");
}

interface WireMessage {
  id: number;
  sender_id: string;
  sender_handle: string;
  sender_device_id: string;
  recipient_device_id: string;
  header: MessageHeader;
  ciphertext: string;
  frank_hash: string;
  sent_at: string;
}

/**
 * Pull new ciphertext rows for one conversation, decrypt what is
 * addressed to this device, verify franking, detect identity-key
 * changes, and persist plaintext locally. Returns the stored thread.
 */
export async function syncConversation(
  myId: string,
  conversationId: string,
): Promise<StoredMessage[]> {
  const device = await ensureDevice();
  const meta = await loadMeta(conversationId);
  const after = meta?.lastFetchedId ?? 0;
  const { messages } = await api<{ ok: true; messages: WireMessage[] }>(
    `/api/dm/messages?conversationId=${encodeURIComponent(conversationId)}&afterId=${after}`,
  );

  let lastId = after;
  for (const row of messages) {
    lastId = Math.max(lastId, row.id);
    const existing = await loadMessage(conversationId, row.id);
    if (existing) continue;

    if (row.sender_id === myId) {
      // Our own ciphertext is addressed to the peer's device; if this
      // device did not send it (another session did), it cannot be
      // read here. Honest placeholder, never a fake body.
      await saveMessage({
        key: messageKey(conversationId, row.id),
        conversationId,
        serverId: row.id,
        senderId: myId,
        senderHandle: row.sender_handle,
        kind: "undecryptable",
        plaintext: "",
        sentAt: row.sent_at,
        frankKey: null,
        frank: null,
        frankVerified: false,
      });
      continue;
    }

    const stored = await decryptIncoming(device, myId, conversationId, row);
    await saveMessage(stored);
  }

  if (lastId !== after) {
    await saveMeta({ conversationId, lastFetchedId: lastId });
  }
  return loadConversationMessages(conversationId);
}

async function decryptIncoming(
  device: StoredDevice,
  myId: string,
  conversationId: string,
  row: WireMessage,
): Promise<StoredMessage> {
  const base = {
    key: messageKey(conversationId, row.id),
    conversationId,
    serverId: row.id,
    senderId: row.sender_id,
    senderHandle: row.sender_handle,
    sentAt: row.sent_at,
  };
  if (row.recipient_device_id !== device.deviceId) {
    // Addressed to a previous device of ours; its keys are gone.
    return {
      ...base,
      kind: "undecryptable",
      plaintext: "",
      frankKey: null,
      frank: null,
      frankVerified: false,
    };
  }
  try {
    let session = await loadSession(row.sender_id);
    let keyChanged = false;

    if (row.header.x3dh) {
      const initIdentity = row.header.x3dh.ik;
      if (session && session.state.peerIdentity !== initIdentity) {
        // The peer's identity key changed (new device, reinstall, or —
        // rarely — interception). Surface it; do not block.
        keyChanged = true;
        session = null;
      }
      if (!session) {
        const keys = deviceToKeys(device);
        const opkPub = row.header.x3dh.opk;
        const opkSecretHex = opkPub ? device.oneTimePrekeySecrets[opkPub] : undefined;
        const sharedKey = x3dhReceive(
          keys,
          {
            identityKey: hexToBytes(initIdentity),
            ephemeralKey: hexToBytes(row.header.x3dh.ek),
            signedPrekeyUsed: hexToBytes(row.header.x3dh.spk),
            oneTimePrekeyUsed: opkPub ? hexToBytes(opkPub) : null,
          },
          opkSecretHex ? hexToBytes(opkSecretHex) : null,
        );
        const state = receiverSession(keys, sharedKey, hexToBytes(initIdentity));
        session = {
          peerId: row.sender_id,
          peerDeviceId: row.sender_device_id,
          state: serializeState(state),
          updatedAt: Date.now(),
        };
        if (opkPub && opkSecretHex) {
          delete device.oneTimePrekeySecrets[opkPub];
          await saveDevice(device);
        }
      }
    }
    if (!session) {
      return {
        ...base,
        kind: "undecryptable",
        plaintext: "",
        frankKey: null,
        frank: null,
        frankVerified: false,
      };
    }

    const state = deserializeState(session.state);
    const opened = decryptMessage(
      state,
      row.header,
      hexToBytes(row.ciphertext),
      row.sender_id,
      myId,
      row.frank_hash,
    );
    session.state = serializeState(state);
    session.peerDeviceId = row.sender_device_id;
    session.updatedAt = Date.now();
    await saveSession(session);

    if (keyChanged) {
      await saveMessage({
        key: `${messageKey(conversationId, row.id)}:keychange`,
        conversationId,
        serverId: row.id,
        senderId: row.sender_id,
        senderHandle: row.sender_handle,
        kind: "key_change",
        plaintext: "",
        sentAt: row.sent_at,
        frankKey: null,
        frank: null,
        frankVerified: false,
      });
    }

    return {
      ...base,
      kind: "message",
      plaintext: opened.plaintext,
      frankKey: bytesToHex(opened.frankKey),
      frank: bytesToHex(opened.frank),
      frankVerified: opened.frankVerified,
    };
  } catch {
    return {
      ...base,
      kind: "undecryptable",
      plaintext: "",
      frankKey: null,
      frank: null,
      frankVerified: false,
    };
  }
}

/** The locally stored thread (already decrypted on this device). */
export async function localThread(conversationId: string): Promise<StoredMessage[]> {
  return loadConversationMessages(conversationId);
}

/** "Delete for me": clear the local plaintext copy of a thread. */
export async function clearLocalThread(conversationId: string): Promise<void> {
  await deleteConversationMessages(conversationId);
}

/**
 * Collect evidence for a report: the plaintext plus franking key of
 * exactly the messages the reporter selected. This is the one place
 * the member chooses to reveal message content to the safety team.
 */
export async function collectEvidence(
  conversationId: string,
  serverIds: number[],
): Promise<Array<{ messageId: number; plaintext: string; frankKey: string }>> {
  const out: Array<{ messageId: number; plaintext: string; frankKey: string }> = [];
  for (const id of serverIds) {
    const stored = await loadMessage(conversationId, id);
    if (stored && stored.kind === "message" && stored.frankKey) {
      out.push({ messageId: id, plaintext: stored.plaintext, frankKey: stored.frankKey });
    }
  }
  return out;
}

/** The safety number for the verification screen (design §13). */
export async function conversationSafetyNumber(peerId: string): Promise<string | null> {
  const device = await loadDevice();
  const session = await loadSession(peerId);
  if (!device || !session) return null;
  const mine = hexToBytes(device.dhPublic + device.signPublic);
  return safetyNumber(mine, hexToBytes(session.state.peerIdentity));
}
