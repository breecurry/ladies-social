/**
 * Protocol unit test for src/lib/dm/crypto.ts — runs under plain Node:
 *   node --experimental-strip-types scripts/dm-crypto-test.ts
 *
 * Exercises: X3DH agreement (both sides derive the same key, signature
 * verification refuses tampering), the Double Ratchet (round trips,
 * alternating senders, out-of-order delivery via skipped keys, state
 * serialization), and franking (verify + fabrication detection).
 * This is a developer gate, not part of next build.
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
  computeFrank,
  frankCommitment,
  bytesToHex,
  serializeState,
  deserializeState,
  safetyNumber,
  type PrekeyBundle,
} from "../src/lib/dm/crypto.ts";

function assert(cond: boolean, message: string): void {
  if (!cond) {
    console.error(`FAIL: ${message}`);
    process.exit(1);
  }
}

const ALICE_ID = "00000000-0000-0000-0000-00000000000a";
const BOB_ID = "00000000-0000-0000-0000-00000000000b";

// --- X3DH ---
const alice = generateDeviceKeys();
const bob = generateDeviceKeys();
const bobPrekeys = generateOneTimePrekeys(2);

const bundle: PrekeyBundle = {
  identityKey: identityPublic(bob),
  signedPrekey: bob.signedPrekeyPublic,
  signedPrekeySig: bob.signedPrekeySig,
  oneTimePrekey: bobPrekeys[0]!.public,
};

const { sharedKey: aliceShared, init } = x3dhInitiate(alice, bundle);
const bobShared = x3dhReceive(bob, init, bobPrekeys[0]!.secret);
assert(bytesToHex(aliceShared) === bytesToHex(bobShared), "X3DH keys differ");

// A tampered signed prekey must refuse.
let refused = false;
try {
  const bad = { ...bundle, signedPrekey: generateOneTimePrekeys(1)[0]!.public };
  x3dhInitiate(alice, bad);
} catch {
  refused = true;
}
assert(refused, "tampered signed prekey accepted");

// --- Ratchet: Alice opens the session, first message ---
let aliceState = initiatorSession(aliceShared, bundle, init);
let bobState = receiverSession(bob, bobShared, init.identityKey);

const m1 = encryptMessage(aliceState, ALICE_ID, BOB_ID, "hello bob");
assert(m1.header.x3dh !== undefined, "first message carries no x3dh init");
const o1 = decryptMessage(
  bobState, m1.header, m1.ciphertext, ALICE_ID, BOB_ID, bytesToHex(m1.frankHash),
);
assert(o1.plaintext === "hello bob", "round trip failed");
assert(o1.frankVerified, "genuine frank did not verify");

// --- Bob replies (DH ratchet turn) ---
const m2 = encryptMessage(bobState, BOB_ID, ALICE_ID, "hi alice");
assert(m2.header.x3dh === undefined, "receiver echoed x3dh init");
const o2 = decryptMessage(
  aliceState, m2.header, m2.ciphertext, BOB_ID, ALICE_ID, bytesToHex(m2.frankHash),
);
assert(o2.plaintext === "hi alice", "reply round trip failed");
assert(o2.frankVerified, "reply frank did not verify");

// --- Long alternating conversation with state serialization ---
for (let i = 0; i < 20; i++) {
  aliceState = deserializeState(serializeState(aliceState));
  bobState = deserializeState(serializeState(bobState));
  const fromAlice = i % 2 === 0;
  const text = `message ${i}`;
  const sealed = fromAlice
    ? encryptMessage(aliceState, ALICE_ID, BOB_ID, text)
    : encryptMessage(bobState, BOB_ID, ALICE_ID, text);
  const opened = fromAlice
    ? decryptMessage(bobState, sealed.header, sealed.ciphertext, ALICE_ID, BOB_ID, bytesToHex(sealed.frankHash))
    : decryptMessage(aliceState, sealed.header, sealed.ciphertext, BOB_ID, ALICE_ID, bytesToHex(sealed.frankHash));
  assert(opened.plaintext === text, `alternating round trip ${i} failed`);
}

// --- Out-of-order delivery: skipped message keys ---
const s1 = encryptMessage(aliceState, ALICE_ID, BOB_ID, "first");
const s2 = encryptMessage(aliceState, ALICE_ID, BOB_ID, "second");
const s3 = encryptMessage(aliceState, ALICE_ID, BOB_ID, "third");
const r3 = decryptMessage(bobState, s3.header, s3.ciphertext, ALICE_ID, BOB_ID, bytesToHex(s3.frankHash));
assert(r3.plaintext === "third", "out-of-order head failed");
const r1 = decryptMessage(bobState, s1.header, s1.ciphertext, ALICE_ID, BOB_ID, bytesToHex(s1.frankHash));
assert(r1.plaintext === "first", "skipped key 1 failed");
const r2 = decryptMessage(bobState, s2.header, s2.ciphertext, ALICE_ID, BOB_ID, bytesToHex(s2.frankHash));
assert(r2.plaintext === "second", "skipped key 2 failed");

// --- Franking: fabrication detected ---
const fabricated = computeFrank(r1.frankKey, ALICE_ID, BOB_ID, "i will hurt you");
assert(
  bytesToHex(frankCommitment(fabricated)) !== bytesToHex(s1.frankHash),
  "fabricated plaintext produced the same commitment",
);
const genuine = computeFrank(r1.frankKey, ALICE_ID, BOB_ID, "first");
assert(
  bytesToHex(frankCommitment(genuine)) === bytesToHex(s1.frankHash),
  "genuine plaintext did not recommit",
);

// --- Tampered ciphertext refuses to decrypt ---
const s4 = encryptMessage(aliceState, ALICE_ID, BOB_ID, "tamper me");
const tampered = s4.ciphertext.slice();
tampered[5] = (tampered[5]! + 1) & 0xff;
let decryptRefused = false;
try {
  decryptMessage(bobState, s4.header, tampered, ALICE_ID, BOB_ID, bytesToHex(s4.frankHash));
} catch {
  decryptRefused = true;
}
assert(decryptRefused, "tampered ciphertext decrypted");

// --- Safety number: order-independent, distinct per pair ---
const sn1 = safetyNumber(identityPublic(alice), identityPublic(bob));
const sn2 = safetyNumber(identityPublic(bob), identityPublic(alice));
assert(sn1 === sn2, "safety number depends on order");
assert(sn1.split(" ").length === 12, "safety number shape wrong");
const mallory = generateDeviceKeys();
assert(
  safetyNumber(identityPublic(alice), identityPublic(mallory)) !== sn1,
  "safety number collision",
);

process.stdout.write("ALL DM CRYPTO TESTS PASSED\n");
