"use client";

import { useEffect, useState } from "react";
import { LockSimple } from "@phosphor-icons/react";
import { Dialog } from "@/components/Dialog";
import { conversationSafetyNumber } from "@/lib/dm/client";

/**
 * The verification screen (design §13): a plain-language explanation of
 * the encryption plus the safety number two people can compare out of
 * band. Optional, low-prominence, honest about what it does and does
 * not prove.
 */
export function VerifyDialog({
  open,
  onClose,
  peerId,
  peerHandle,
}: {
  open: boolean;
  onClose: () => void;
  peerId: string;
  peerHandle: string;
}) {
  return (
    <Dialog open={open} onClose={onClose} label={`Verify @${peerHandle}`}>
      {open ? <VerifyBody peerId={peerId} peerHandle={peerHandle} onClose={onClose} /> : null}
    </Dialog>
  );
}

/** Mounted fresh on each open, so its state never goes stale. */
function VerifyBody({
  peerId,
  peerHandle,
  onClose,
}: {
  peerId: string;
  peerHandle: string;
  onClose: () => void;
}) {
  const [code, setCode] = useState<string | null>(null);
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    let cancelled = false;
    void conversationSafetyNumber(peerId).then((value) => {
      if (cancelled) return;
      setCode(value);
      setLoaded(true);
    });
    return () => {
      cancelled = true;
    };
  }, [peerId]);

  return (
    <div className="flex flex-col gap-3 p-5">
      <h2 className="flex items-center gap-2 text-heading">
        <LockSimple size={20} aria-hidden />
        End-to-end encrypted
      </h2>
      <p className="text-body text-text-secondary">
        Messages in this conversation are encrypted on your device and can only be read on your
        device and @{peerHandle}&apos;s. Hersciety stores only scrambled data it cannot read. If
        you report a message, your own app attaches the messages you choose — that is the only
        way message content ever reaches our safety team.
      </p>
      {loaded && code ? (
        <>
          <h3 className="text-label text-text-primary">Safety number</h3>
          <p className="rounded-md bg-surface px-4 py-3 text-center font-mono text-body text-text-primary">
            {code}
          </p>
          <p className="text-caption text-text-tertiary">
            If you and @{peerHandle} compare this number somewhere else you both trust — in
            person, or on a call — and it matches, no one is sitting between you. It changes when
            either of you gets a new device.
          </p>
        </>
      ) : loaded ? (
        <p className="text-body text-text-secondary">
          The safety number appears once this conversation has exchanged its first message.
        </p>
      ) : null}
      <div className="flex justify-end">
        <button
          type="button"
          data-autofocus
          onClick={onClose}
          className="min-h-11 rounded-md px-4 text-label text-accent hover:bg-accent-subtle"
        >
          Done
        </button>
      </div>
    </div>
  );
}
