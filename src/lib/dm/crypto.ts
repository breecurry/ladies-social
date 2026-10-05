/**
 * The Hersciety DM protocol: an X3DH-style key agreement plus a Double
 * Ratchet, implemented on independently audited, MIT-licensed
 * primitives (@noble/curves, @noble/ciphers, @noble/hashes). libsignal
 * is AGPLv3 and is deliberately NOT used, vendored, or ported.
 *
 * This module is pure protocol code: no DOM, no network, no storage.
 * It runs identically in the browser and under Node for the unit test
 * (scripts/dm-crypto-test.ts).
 *
 * Shapes on the wire (what the server ever sees):
 *   - identity key: 64 bytes = x25519 DH public (32) || ed25519
 *     signing public (32). Two independent keypairs, concatenated, so
 *     no Edwards↔Montgomery conversion subtleties.
 *   - signed prekey: x25519 public (32), signed by the ed25519
 *     identity signing key (64-byte signature).
 *   - one-time prekeys: x25519 publics (32 each). The receiver matches
 *     a consumed prekey by its PUBLIC bytes, so no id coordination.
 *   - message header (public values only): the current ratchet public
 *     key, the previous chain length, the message number, and — on
 *     session-opening messages — the X3DH init values.
 *   - ciphertext: XChaCha20-Poly1305 over (K_frank || plaintext),
 *     keyed per message from the ratchet. The server cannot read it.
 *   - frank hash: sha256(frank), the franking commitment.
 *
 * FRANKING (the salamander-safe HMAC-key construction — Grubbs, Lu &
 * Ristenpart CRYPTO 2017; never raw AES-GCM, which "invisible
 * salamanders" broke):
 *   frank = HMAC-SHA256(K_frank,
 *     "hersciety-dm-frank-v1" \n sender_uuid \n recipient_uuid \n plaintext)
 *   K_frank rides INSIDE the ciphertext; the server stores only
 *   sha256(frank). At report time the reporter reveals plaintext +
 *   K_frank for exactly the chosen messages and the server recomputes:
 *   match ⇒ the sender really sent exactly this; mismatch ⇒ fabricated.
 */

import { x25519, ed25519 } from "@noble/curves/ed25519.js";
import { xchacha20poly1305 } from "@noble/ciphers/chacha.js";
import { hkdf } from "@noble/hashes/hkdf.js";
import { hmac } from "@noble/hashes/hmac.js";
import { sha256 } from "@noble/hashes/sha2.js";
import { concatBytes, randomBytes } from "@noble/hashes/utils.js";

// ---------------------------------------------------------------
// Encoding helpers (hex is the storage/wire format in this codebase;
// PostgREST represents bytea as "\x"-prefixed hex).
// ---------------------------------------------------------------

export function bytesToHex(bytes: Uint8Array): string {
  let out = "";
  for (const b of bytes) out += b.toString(16).padStart(2, "0");
  return out;
}

export function hexToBytes(hex: string): Uint8Array {
  const clean = hex.startsWith("\\x") ? hex.slice(2) : hex;
  if (clean.length % 2 !== 0 || /[^0-9a-fA-F]/.test(clean)) {
    throw new Error("Invalid hex.");
  }
  const out = new Uint8Array(clean.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(clean.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

/** PostgREST wire format for a bytea parameter. */
export function toBytea(bytes: Uint8Array): string {
  return `\\x${bytesToHex(bytes)}`;
}

const utf8 = (s: string): Uint8Array => new TextEncoder().encode(s);

// ---------------------------------------------------------------
// Device keys.
// ---------------------------------------------------------------

export interface DeviceKeyPairs {
  /** x25519 identity (DH) keypair. */
  dhSecret: Uint8Array;
  dhPublic: Uint8Array;
  /** ed25519 identity (signing) keypair. */
  signSecret: Uint8Array;
  signPublic: Uint8Array;
  /** x25519 signed prekey, signed by the ed25519 identity key. */
  signedPrekeySecret: Uint8Array;
  signedPrekeyPublic: Uint8Array;
  signedPrekeySig: Uint8Array;
}

/** The 64-byte public identity key the server stores. */
export function identityPublic(keys: DeviceKeyPairs): Uint8Array {
  return concatBytes(keys.dhPublic, keys.signPublic);
}

export function generateDeviceKeys(): DeviceKeyPairs {
  const dhSecret = x25519.utils.randomSecretKey();
  const signSecret = ed25519.utils.randomSecretKey();
  const signedPrekeySecret = x25519.utils.randomSecretKey();
  const signedPrekeyPublic = x25519.getPublicKey(signedPrekeySecret);
  return {
    dhSecret,
    dhPublic: x25519.getPublicKey(dhSecret),
    signSecret,
    signPublic: ed25519.getPublicKey(signSecret),
    signedPrekeySecret,
    signedPrekeyPublic,
    signedPrekeySig: ed25519.sign(signedPrekeyPublic, signSecret),
  };
}

export interface OneTimePrekeyPair {
  secret: Uint8Array;
  public: Uint8Array;
}

export function generateOneTimePrekeys(count: number): OneTimePrekeyPair[] {
  const out: OneTimePrekeyPair[] = [];
  for (let i = 0; i < count; i++) {
    const secret = x25519.utils.randomSecretKey();
    out.push({ secret, public: x25519.getPublicKey(secret) });
  }
  return out;
}

// ---------------------------------------------------------------
// X3DH-style key agreement.
// ---------------------------------------------------------------

const X3DH_INFO = "hersciety-dm-x3dh-v1";
const F_PAD = new Uint8Array(32).fill(0xff);

export interface PrekeyBundle {
  /** 64 bytes: DH public || signing public. */
  identityKey: Uint8Array;
  signedPrekey: Uint8Array;
  signedPrekeySig: Uint8Array;
  oneTimePrekey: Uint8Array | null;
}

/** The session-opening values the initiator puts in message headers. */
export interface X3dhInit {
  /** Initiator's 64-byte identity public. */
  identityKey: Uint8Array;
  ephemeralKey: Uint8Array;
  /** The receiver's prekeys that were used, so she can look them up. */
  signedPrekeyUsed: Uint8Array;
  oneTimePrekeyUsed: Uint8Array | null;
}

function deriveSharedKey(dhParts: Uint8Array[]): Uint8Array {
  return hkdf(sha256, concatBytes(F_PAD, ...dhParts), new Uint8Array(32), utf8(X3DH_INFO), 32);
}

/**
 * Initiator side: agree a shared key with the receiver's bundle.
 * Throws if the signed prekey's signature does not verify against the
 * receiver's identity signing key.
 */
export function x3dhInitiate(
  keys: DeviceKeyPairs,
  bundle: PrekeyBundle,
): { sharedKey: Uint8Array; init: X3dhInit } {
  if (bundle.identityKey.length !== 64) throw new Error("Bad identity key.");
  const theirDh = bundle.identityKey.slice(0, 32);
  const theirSign = bundle.identityKey.slice(32);
  if (!ed25519.verify(bundle.signedPrekeySig, bundle.signedPrekey, theirSign)) {
    throw new Error("Signed prekey signature did not verify.");
  }
  const ephemeralSecret = x25519.utils.randomSecretKey();
  const ephemeralPublic = x25519.getPublicKey(ephemeralSecret);
  const parts = [
    x25519.getSharedSecret(keys.dhSecret, bundle.signedPrekey),
    x25519.getSharedSecret(ephemeralSecret, theirDh),
    x25519.getSharedSecret(ephemeralSecret, bundle.signedPrekey),
  ];
  if (bundle.oneTimePrekey) {
    parts.push(x25519.getSharedSecret(ephemeralSecret, bundle.oneTimePrekey));
  }
  return {
    sharedKey: deriveSharedKey(parts),
    init: {
      identityKey: identityPublic(keys),
      ephemeralKey: ephemeralPublic,
      signedPrekeyUsed: bundle.signedPrekey,
      oneTimePrekeyUsed: bundle.oneTimePrekey,
    },
  };
}

/**
 * Receiver side: recompute the shared key from the initiator's header
 * values and our own secrets. oneTimePrekeySecret is looked up by the
 * caller from the public bytes in the header.
 */
export function x3dhReceive(
  keys: DeviceKeyPairs,
  init: X3dhInit,
  oneTimePrekeySecret: Uint8Array | null,
): Uint8Array {
  if (init.identityKey.length !== 64) throw new Error("Bad identity key.");
  const theirDh = init.identityKey.slice(0, 32);
  const parts = [
    x25519.getSharedSecret(keys.signedPrekeySecret, theirDh),
    x25519.getSharedSecret(keys.dhSecret, init.ephemeralKey),
    x25519.getSharedSecret(keys.signedPrekeySecret, init.ephemeralKey),
  ];
  if (init.oneTimePrekeyUsed) {
    if (!oneTimePrekeySecret) throw new Error("Missing one-time prekey secret.");
    parts.push(x25519.getSharedSecret(oneTimePrekeySecret, init.ephemeralKey));
  }
  return deriveSharedKey(parts);
}

// ---------------------------------------------------------------
// Double Ratchet.
// ---------------------------------------------------------------

const ROOT_INFO = "hersciety-dm-ratchet-root-v1";
const MSG_INFO = "hersciety-dm-msg-v1";
const MAX_SKIP = 200;

export interface MessageHeader {
  /** Sender's current ratchet public key (hex). */
  dh: string;
  /** Length of the previous sending chain. */
  pn: number;
  /** Message number in the current sending chain. */
  n: number;
  /** Present on session-opening messages. */
  x3dh?: {
    ik: string;
    ek: string;
    spk: string;
    opk: string | null;
  };
}

export interface RatchetState {
  rootKey: Uint8Array;
  dhSelfSecret: Uint8Array;
  dhSelfPublic: Uint8Array;
  dhRemote: Uint8Array | null;
  sendChainKey: Uint8Array | null;
  recvChainKey: Uint8Array | null;
  sendN: number;
  recvN: number;
  prevSendN: number;
  /** Skipped message keys: `${remoteDhHex}:${n}` → message key. */
  skipped: Record<string, Uint8Array>;
  /** The peer's 64-byte identity public (for key-change detection). */
  peerIdentity: Uint8Array;
  /** Echoed in headers until the peer has spoken (session-opening). */
  pendingInit: X3dhInit | null;
}

function kdfRoot(rootKey: Uint8Array, dhOut: Uint8Array): [Uint8Array, Uint8Array] {
  const okm = hkdf(sha256, dhOut, rootKey, utf8(ROOT_INFO), 64);
  return [okm.slice(0, 32), okm.slice(32)];
}

function kdfChain(chainKey: Uint8Array): [Uint8Array, Uint8Array] {
  const messageKey = hmac(sha256, chainKey, Uint8Array.of(1));
  const nextChainKey = hmac(sha256, chainKey, Uint8Array.of(2));
  return [nextChainKey, messageKey];
}

/** AAD binds the public header to the ciphertext, deterministically. */
function headerAad(dhPublic: Uint8Array, pn: number, n: number): Uint8Array {
  const tail = new Uint8Array(8);
  new DataView(tail.buffer).setUint32(0, pn);
  new DataView(tail.buffer).setUint32(4, n);
  return concatBytes(dhPublic, tail);
}

function sealWithKey(
  messageKey: Uint8Array,
  payload: Uint8Array,
  aad: Uint8Array,
): Uint8Array {
  const okm = hkdf(sha256, messageKey, new Uint8Array(32), utf8(MSG_INFO), 56);
  return xchacha20poly1305(okm.slice(0, 32), okm.slice(32), aad).encrypt(payload);
}

function openWithKey(
  messageKey: Uint8Array,
  ciphertext: Uint8Array,
  aad: Uint8Array,
): Uint8Array {
  const okm = hkdf(sha256, messageKey, new Uint8Array(32), utf8(MSG_INFO), 56);
  return xchacha20poly1305(okm.slice(0, 32), okm.slice(32), aad).decrypt(ciphertext);
}

/** Initiator: a fresh session from an X3DH agreement with a bundle. */
export function initiatorSession(
  sharedKey: Uint8Array,
  bundle: PrekeyBundle,
  init: X3dhInit,
): RatchetState {
  const dhSelfSecret = x25519.utils.randomSecretKey();
  const dhSelfPublic = x25519.getPublicKey(dhSelfSecret);
  const [rootKey, sendChainKey] = kdfRoot(
    sharedKey,
    x25519.getSharedSecret(dhSelfSecret, bundle.signedPrekey),
  );
  return {
    rootKey,
    dhSelfSecret,
    dhSelfPublic,
    dhRemote: bundle.signedPrekey,
    sendChainKey,
    recvChainKey: null,
    sendN: 0,
    recvN: 0,
    prevSendN: 0,
    skipped: {},
    peerIdentity: bundle.identityKey,
    pendingInit: init,
  };
}

/** Receiver: a fresh session from the initiator's first header. */
export function receiverSession(
  keys: DeviceKeyPairs,
  sharedKey: Uint8Array,
  peerIdentity: Uint8Array,
): RatchetState {
  // Our signed prekey keypair is the initial ratchet keypair: the
  // initiator's first ratchet step ran against it.
  return {
    rootKey: sharedKey,
    dhSelfSecret: keys.signedPrekeySecret,
    dhSelfPublic: keys.signedPrekeyPublic,
    dhRemote: null,
    sendChainKey: null,
    recvChainKey: null,
    sendN: 0,
    recvN: 0,
    prevSendN: 0,
    skipped: {},
    peerIdentity,
    pendingInit: null,
  };
}

// ---------------------------------------------------------------
// Franking.
// ---------------------------------------------------------------

const FRANK_PREFIX = "hersciety-dm-frank-v1";

export function computeFrank(
  frankKey: Uint8Array,
  senderId: string,
  recipientId: string,
  plaintext: string,
): Uint8Array {
  return hmac(
    sha256,
    frankKey,
    utf8(`${FRANK_PREFIX}\n${senderId}\n${recipientId}\n${plaintext}`),
  );
}

export function frankCommitment(frank: Uint8Array): Uint8Array {
  return sha256(frank);
}

// ---------------------------------------------------------------
// Encrypt / decrypt.
// ---------------------------------------------------------------

export interface SealedMessage {
  header: MessageHeader;
  ciphertext: Uint8Array;
  frankKey: Uint8Array;
  frank: Uint8Array;
  frankHash: Uint8Array;
}

export function encryptMessage(
  state: RatchetState,
  senderId: string,
  recipientId: string,
  plaintext: string,
): SealedMessage {
  if (state.sendChainKey === null) {
    // We last received: a DH ratchet send step starts a new chain.
    if (state.dhRemote === null) throw new Error("Session has no remote key.");
    state.prevSendN = state.sendN;
    state.sendN = 0;
    state.dhSelfSecret = x25519.utils.randomSecretKey();
    state.dhSelfPublic = x25519.getPublicKey(state.dhSelfSecret);
    const [rootKey, sendChainKey] = kdfRoot(
      state.rootKey,
      x25519.getSharedSecret(state.dhSelfSecret, state.dhRemote),
    );
    state.rootKey = rootKey;
    state.sendChainKey = sendChainKey;
  }
  const [nextChainKey, messageKey] = kdfChain(state.sendChainKey);
  const header: MessageHeader = {
    dh: bytesToHex(state.dhSelfPublic),
    pn: state.prevSendN,
    n: state.sendN,
  };
  if (state.pendingInit) {
    header.x3dh = {
      ik: bytesToHex(state.pendingInit.identityKey),
      ek: bytesToHex(state.pendingInit.ephemeralKey),
      spk: bytesToHex(state.pendingInit.signedPrekeyUsed),
      opk: state.pendingInit.oneTimePrekeyUsed
        ? bytesToHex(state.pendingInit.oneTimePrekeyUsed)
        : null,
    };
  }
  const frankKey = randomBytes(32);
  const frank = computeFrank(frankKey, senderId, recipientId, plaintext);
  const payload = concatBytes(frankKey, utf8(plaintext));
  const ciphertext = sealWithKey(
    messageKey,
    payload,
    headerAad(state.dhSelfPublic, header.pn, header.n),
  );
  state.sendChainKey = nextChainKey;
  state.sendN += 1;
  return { header, ciphertext, frankKey, frank, frankHash: frankCommitment(frank) };
}

export interface OpenedMessage {
  plaintext: string;
  frankKey: Uint8Array;
  frank: Uint8Array;
  /** Did sha256(frank) match the commitment the server stored? */
  frankVerified: boolean;
}

function skipRecvKeys(state: RatchetState, until: number): void {
  if (state.recvChainKey === null) return;
  if (until - state.recvN > MAX_SKIP) throw new Error("Too many skipped messages.");
  const remoteHex = state.dhRemote ? bytesToHex(state.dhRemote) : "";
  while (state.recvN < until) {
    const [nextChainKey, messageKey] = kdfChain(state.recvChainKey);
    state.skipped[`${remoteHex}:${state.recvN}`] = messageKey;
    state.recvChainKey = nextChainKey;
    state.recvN += 1;
  }
  const keys = Object.keys(state.skipped);
  if (keys.length > MAX_SKIP) {
    for (const k of keys.slice(0, keys.length - MAX_SKIP)) delete state.skipped[k];
  }
}

export function decryptMessage(
  state: RatchetState,
  header: MessageHeader,
  ciphertext: Uint8Array,
  senderId: string,
  recipientId: string,
  storedFrankHashHex: string,
): OpenedMessage {
  const headerDh = hexToBytes(header.dh);
  const aad = headerAad(headerDh, header.pn, header.n);
  const skippedKey = `${header.dh}:${header.n}`;

  let messageKey: Uint8Array;
  const skipped = state.skipped[skippedKey];
  if (skipped) {
    messageKey = skipped;
    delete state.skipped[skippedKey];
  } else {
    const isNewRemote =
      state.dhRemote === null || bytesToHex(state.dhRemote) !== header.dh;
    if (isNewRemote) {
      // Close out the old receiving chain, then DH-ratchet.
      skipRecvKeys(state, header.pn);
      const [rootKey, recvChainKey] = kdfRoot(
        state.rootKey,
        x25519.getSharedSecret(state.dhSelfSecret, headerDh),
      );
      state.rootKey = rootKey;
      state.recvChainKey = recvChainKey;
      state.dhRemote = headerDh;
      state.recvN = 0;
      // Our sending chain is stale: the next send ratchets fresh.
      state.prevSendN = state.sendN;
      state.sendChainKey = null;
    }
    skipRecvKeys(state, header.n);
    if (state.recvChainKey === null) throw new Error("No receiving chain.");
    const [nextChainKey, mk] = kdfChain(state.recvChainKey);
    state.recvChainKey = nextChainKey;
    state.recvN += 1;
    messageKey = mk;
  }

  const payload = openWithKey(messageKey, ciphertext, aad);
  if (payload.length < 33) throw new Error("Message too short.");
  const frankKey = payload.slice(0, 32);
  const plaintext = new TextDecoder().decode(payload.slice(32));
  const frank = computeFrank(frankKey, senderId, recipientId, plaintext);
  const frankVerified =
    bytesToHex(frankCommitment(frank)) ===
    (storedFrankHashHex.startsWith("\\x")
      ? storedFrankHashHex.slice(2)
      : storedFrankHashHex
    ).toLowerCase();
  // The peer has spoken: stop echoing the session-opening values.
  state.pendingInit = null;
  return { plaintext, frankKey, frank, frankVerified };
}

// ---------------------------------------------------------------
// Safety number (conversation verification, design §13).
// ---------------------------------------------------------------

/**
 * A 60-digit comparison code over both identities, order-independent,
 * shown as 12 groups of 5 digits. Two members compare out of band.
 */
export function safetyNumber(identityA: Uint8Array, identityB: Uint8Array): string {
  const [first, second] =
    bytesToHex(identityA) <= bytesToHex(identityB)
      ? [identityA, identityB]
      : [identityB, identityA];
  const digest = sha256(concatBytes(utf8("hersciety-dm-safety-v1"), first, second));
  const groups: string[] = [];
  for (let i = 0; i < 12; i++) {
    const a = digest[(i * 2) % 32] ?? 0;
    const b = digest[(i * 2 + 1) % 32] ?? 0;
    const c = digest[(i + 7) % 32] ?? 0;
    groups.push(String(((a << 16) | (b << 8) | c) % 100000).padStart(5, "0"));
  }
  return groups.join(" ");
}

// ---------------------------------------------------------------
// Session serialization (for IndexedDB).
// ---------------------------------------------------------------

export interface SerializedRatchetState {
  rootKey: string;
  dhSelfSecret: string;
  dhSelfPublic: string;
  dhRemote: string | null;
  sendChainKey: string | null;
  recvChainKey: string | null;
  sendN: number;
  recvN: number;
  prevSendN: number;
  skipped: Record<string, string>;
  peerIdentity: string;
  pendingInit: {
    identityKey: string;
    ephemeralKey: string;
    signedPrekeyUsed: string;
    oneTimePrekeyUsed: string | null;
  } | null;
}

export function serializeState(state: RatchetState): SerializedRatchetState {
  return {
    rootKey: bytesToHex(state.rootKey),
    dhSelfSecret: bytesToHex(state.dhSelfSecret),
    dhSelfPublic: bytesToHex(state.dhSelfPublic),
    dhRemote: state.dhRemote ? bytesToHex(state.dhRemote) : null,
    sendChainKey: state.sendChainKey ? bytesToHex(state.sendChainKey) : null,
    recvChainKey: state.recvChainKey ? bytesToHex(state.recvChainKey) : null,
    sendN: state.sendN,
    recvN: state.recvN,
    prevSendN: state.prevSendN,
    skipped: Object.fromEntries(
      Object.entries(state.skipped).map(([k, v]) => [k, bytesToHex(v)]),
    ),
    peerIdentity: bytesToHex(state.peerIdentity),
    pendingInit: state.pendingInit
      ? {
          identityKey: bytesToHex(state.pendingInit.identityKey),
          ephemeralKey: bytesToHex(state.pendingInit.ephemeralKey),
          signedPrekeyUsed: bytesToHex(state.pendingInit.signedPrekeyUsed),
          oneTimePrekeyUsed: state.pendingInit.oneTimePrekeyUsed
            ? bytesToHex(state.pendingInit.oneTimePrekeyUsed)
            : null,
        }
      : null,
  };
}

export function deserializeState(s: SerializedRatchetState): RatchetState {
  return {
    rootKey: hexToBytes(s.rootKey),
    dhSelfSecret: hexToBytes(s.dhSelfSecret),
    dhSelfPublic: hexToBytes(s.dhSelfPublic),
    dhRemote: s.dhRemote ? hexToBytes(s.dhRemote) : null,
    sendChainKey: s.sendChainKey ? hexToBytes(s.sendChainKey) : null,
    recvChainKey: s.recvChainKey ? hexToBytes(s.recvChainKey) : null,
    sendN: s.sendN,
    recvN: s.recvN,
    prevSendN: s.prevSendN,
    skipped: Object.fromEntries(
      Object.entries(s.skipped).map(([k, v]) => [k, hexToBytes(v)]),
    ),
    peerIdentity: hexToBytes(s.peerIdentity),
    pendingInit: s.pendingInit
      ? {
          identityKey: hexToBytes(s.pendingInit.identityKey),
          ephemeralKey: hexToBytes(s.pendingInit.ephemeralKey),
          signedPrekeyUsed: hexToBytes(s.pendingInit.signedPrekeyUsed),
          oneTimePrekeyUsed: s.pendingInit.oneTimePrekeyUsed
            ? hexToBytes(s.pendingInit.oneTimePrekeyUsed)
            : null,
        }
      : null,
  };
}
