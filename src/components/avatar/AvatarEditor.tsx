"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { Camera } from "@phosphor-icons/react";
import { Dialog } from "@/components/Dialog";
import { useToast } from "@/components/shell/ToastProvider";
import { useViewer } from "@/components/shell/Providers";
import { invalidateAvatar } from "@/components/avatar/useAvatarMedia";
import { AVATAR_MAX_BYTES, AVATAR_MIN_DIM, AVATAR_REJECTION_MESSAGE } from "@/lib/media/avatar";

/**
 * The avatar upload entry points and the crop step (spec P2E sections
 * 6 and 7): a square frame with a circular-mask preview, drag to
 * reposition, a zoom slider (plus arrow-key nudging), then a square
 * canvas export that becomes the upload source. The client export is a
 * convenience, never a security boundary — the server re-decodes,
 * auto-orients, strips every scrap of metadata by full re-encode and
 * builds the served variants itself (spec 7.3).
 *
 * The file's name is read by nothing here: only bytes, size and type
 * ever leave this component.
 */

/** The crop viewport's css-px ceiling; it shrinks with the screen below 352px wide. */
const MAX_VIEWPORT = 288;
const EXPORT_SIZE = 1024; // square export edge
const MAX_ZOOM = 3;

type Phase =
  | { step: "crop" }
  | { step: "uploading" }
  | { step: "error"; message: string; fatal: boolean };

export function ChangePhotoControl({
  variant,
  hasPhoto,
}: {
  /** "camera": the circular overlay button on the own-profile avatar.
   *  "row": the text button inside the edit-profile dialog. */
  variant: "camera" | "row";
  hasPhoto: boolean;
}) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [file, setFile] = useState<File | null>(null);

  const label = hasPhoto ? "Change photo" : "Add a photo";
  return (
    <>
      <input
        ref={inputRef}
        type="file"
        accept="image/jpeg,image/png,image/webp"
        className="hidden"
        onChange={(event) => {
          const chosen = event.target.files?.[0] ?? null;
          event.target.value = "";
          if (chosen) setFile(chosen);
        }}
      />
      {variant === "camera" ? (
        <button
          type="button"
          aria-label="Change profile photo"
          onClick={() => inputRef.current?.click()}
          className="absolute -bottom-1 -right-1 flex size-8 items-center justify-center rounded-full border border-border bg-surface-raised text-text-primary shadow-e1 hover:bg-accent-subtle"
        >
          <Camera size={18} aria-hidden />
        </button>
      ) : (
        <button
          type="button"
          onClick={() => inputRef.current?.click()}
          className="min-h-11 rounded-md border border-border-strong bg-surface px-4 text-label text-text-primary hover:bg-surface-raised"
        >
          {label}
        </button>
      )}
      {file ? <AvatarCropDialog file={file} onClose={() => setFile(null)} /> : null}
    </>
  );
}

/** "Remove photo" — routine, not destructive (spec 6.1): text-secondary, no confirm. */
export function RemovePhotoButton() {
  const router = useRouter();
  const viewer = useViewer();
  const { showToast } = useToast();
  const [busy, setBusy] = useState(false);

  const remove = async () => {
    setBusy(true);
    const response = await fetch("/api/avatar", { method: "DELETE" }).catch(() => null);
    setBusy(false);
    if (!response?.ok) {
      showToast("Could not remove your photo. Try again.");
      return;
    }
    invalidateAvatar(viewer.id);
    showToast("Photo removed");
    router.refresh();
  };

  return (
    <button
      type="button"
      disabled={busy}
      onClick={() => void remove()}
      className="min-h-11 rounded-md px-4 text-label text-text-secondary hover:bg-surface-raised disabled:opacity-50"
    >
      {busy ? "Removing…" : "Remove photo"}
    </button>
  );
}

function AvatarCropDialog({ file, onClose }: { file: File; onClose: () => void }) {
  const router = useRouter();
  const viewer = useViewer();
  const { showToast } = useToast();

  const [url] = useState(() => URL.createObjectURL(file));
  const imageRef = useRef<HTMLImageElement | null>(null);
  const viewportRef = useRef<HTMLDivElement | null>(null);
  // The crop square's real rendered size: 288px with room to spare,
  // smaller on narrow phones (min(288px, 100vw - 64px) in CSS). All
  // crop maths read this measured value so the export stays correct.
  const [viewport, setViewport] = useState(MAX_VIEWPORT);
  const [dims, setDims] = useState<{ w: number; h: number } | null>(null);
  // Up-front size check with a stated reason (spec 6.5); the server
  // re-checks everything.
  const [phase, setPhase] = useState<Phase>(() =>
    file.size > AVATAR_MAX_BYTES
      ? { step: "error", message: AVATAR_REJECTION_MESSAGE.too_large, fatal: true }
      : { step: "crop" },
  );
  const [zoom, setZoom] = useState(1);
  const [offset, setOffset] = useState({ x: 0, y: 0 });
  const dragRef = useRef<{ pointerId: number; startX: number; startY: number; base: { x: number; y: number } } | null>(null);

  useEffect(() => () => URL.revokeObjectURL(url), [url]);

  useEffect(() => {
    const node = viewportRef.current;
    if (!node) return;
    const measure = () => {
      const width = node.getBoundingClientRect().width;
      if (width > 0) setViewport(width);
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(node);
    return () => observer.disconnect();
  }, [phase.step]);

  const coverScale = dims ? Math.max(viewport / dims.w, viewport / dims.h) : 1;
  const scale = coverScale * zoom;

  const clampOffset = useCallback(
    (next: { x: number; y: number }, atZoom: number) => {
      if (!dims) return next;
      const s = coverScale * atZoom;
      const maxX = Math.max(0, (dims.w * s - viewport) / 2);
      const maxY = Math.max(0, (dims.h * s - viewport) / 2);
      return {
        x: Math.min(maxX, Math.max(-maxX, next.x)),
        y: Math.min(maxY, Math.max(-maxY, next.y)),
      };
    },
    [dims, coverScale, viewport],
  );

  // The offset is re-clamped where it is used, so a viewport resize
  // mid-crop (e.g. a rotation) can never show or export past the edge.
  const shownOffset = clampOffset(offset, zoom);

  const onImageLoad = () => {
    const img = imageRef.current;
    if (!img) return;
    if (img.naturalWidth < AVATAR_MIN_DIM || img.naturalHeight < AVATAR_MIN_DIM) {
      setPhase({ step: "error", message: AVATAR_REJECTION_MESSAGE.too_small, fatal: true });
      return;
    }
    setDims({ w: img.naturalWidth, h: img.naturalHeight });
  };

  const save = async () => {
    const img = imageRef.current;
    if (!img || !dims) return;
    setPhase({ step: "uploading" });
    try {
      // The visible square in image coordinates.
      const sourceSize = viewport / scale;
      const sourceX = dims.w / 2 - (viewport / 2 + shownOffset.x) / scale;
      const sourceY = dims.h / 2 - (viewport / 2 + shownOffset.y) / scale;
      const exportEdge = Math.min(EXPORT_SIZE, Math.max(AVATAR_MIN_DIM, Math.round(sourceSize)));
      const canvas = document.createElement("canvas");
      canvas.width = exportEdge;
      canvas.height = exportEdge;
      const context = canvas.getContext("2d");
      if (!context) throw new Error("no canvas");
      context.drawImage(img, sourceX, sourceY, sourceSize, sourceSize, 0, 0, exportEdge, exportEdge);
      const blob = await new Promise<Blob | null>((resolve) =>
        canvas.toBlob(resolve, "image/webp", 0.9),
      );
      if (!blob) throw new Error("no blob");

      const ticketResponse = await fetch("/api/avatar/ticket", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ size: blob.size, type: blob.type || "image/webp" }),
      });
      const ticket = (await ticketResponse.json()) as {
        ok: boolean;
        error?: string;
        ticketId?: string;
        uploadUrl?: string;
      };
      if (!ticket.ok || !ticket.ticketId || !ticket.uploadUrl) {
        setPhase({ step: "error", message: ticket.error ?? "Something went wrong uploading that. Please try again.", fatal: false });
        return;
      }
      const putResponse = await fetch(ticket.uploadUrl, {
        method: "PUT",
        headers: { "content-type": blob.type || "image/webp" },
        body: blob,
      });
      if (!putResponse.ok) {
        setPhase({ step: "error", message: "Something went wrong uploading that. Please try again.", fatal: false });
        return;
      }
      const commitResponse = await fetch("/api/avatar/commit", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ ticketId: ticket.ticketId }),
      });
      const committed = (await commitResponse.json()) as { ok: boolean; error?: string };
      if (!committed.ok) {
        setPhase({ step: "error", message: committed.error ?? "Something went wrong uploading that. Please try again.", fatal: false });
        return;
      }
      invalidateAvatar(viewer.id);
      showToast("Profile photo updated");
      onClose();
      router.refresh();
    } catch {
      setPhase({ step: "error", message: "Something went wrong uploading that. Please try again.", fatal: false });
    }
  };

  const busy = phase.step === "uploading";

  return (
    <Dialog open onClose={busy ? () => undefined : onClose} label="Position your photo">
      <div className="flex flex-col gap-3 p-4">
        <h2 className="text-heading">Position your photo</h2>

        {phase.step === "error" && !dims ? null : (
          <div className="flex flex-col items-center gap-3">
            <div
              ref={viewportRef}
              role="application"
              aria-label="Photo position. Drag, or use the arrow keys, to move the photo inside the circle."
              tabIndex={0}
              onKeyDown={(event) => {
                const nudge = 10;
                const moves: Record<string, [number, number]> = {
                  ArrowLeft: [nudge, 0],
                  ArrowRight: [-nudge, 0],
                  ArrowUp: [0, nudge],
                  ArrowDown: [0, -nudge],
                };
                const move = moves[event.key];
                if (!move) return;
                event.preventDefault();
                setOffset((current) => clampOffset({ x: current.x + move[0], y: current.y + move[1] }, zoom));
              }}
              onPointerDown={(event) => {
                event.currentTarget.setPointerCapture(event.pointerId);
                dragRef.current = {
                  pointerId: event.pointerId,
                  startX: event.clientX,
                  startY: event.clientY,
                  base: offset,
                };
              }}
              onPointerMove={(event) => {
                const drag = dragRef.current;
                if (!drag || drag.pointerId !== event.pointerId) return;
                setOffset(
                  clampOffset(
                    {
                      x: drag.base.x + (event.clientX - drag.startX),
                      y: drag.base.y + (event.clientY - drag.startY),
                    },
                    zoom,
                  ),
                );
              }}
              onPointerUp={() => {
                dragRef.current = null;
              }}
              className="relative aspect-square touch-none overflow-hidden rounded-md bg-background"
              style={{ width: `min(${MAX_VIEWPORT}px, calc(100vw - 64px))`, cursor: "move" }}
            >
              {/* eslint-disable-next-line @next/next/no-img-element -- local
                  object URL being positioned on a canvas, not a remote image */}
              <img
                ref={imageRef}
                src={url}
                alt=""
                draggable={false}
                onLoad={onImageLoad}
                onError={() =>
                  setPhase({ step: "error", message: AVATAR_REJECTION_MESSAGE.unreadable, fatal: true })
                }
                className="absolute left-1/2 top-1/2 max-w-none select-none"
                style={
                  dims
                    ? {
                        width: dims.w * scale,
                        height: dims.h * scale,
                        transform: `translate(calc(-50% + ${shownOffset.x}px), calc(-50% + ${shownOffset.y}px))`,
                      }
                    : { visibility: "hidden" }
                }
              />
              <div
                aria-hidden
                className="pointer-events-none absolute inset-0 rounded-full"
                style={{ boxShadow: "0 0 0 9999px var(--scrim)" }}
              />
            </div>

            <label className="flex w-full max-w-72 items-center gap-2">
              <span className="text-caption text-text-secondary">Zoom</span>
              <input
                type="range"
                min={1}
                max={MAX_ZOOM}
                step={0.01}
                value={zoom}
                disabled={!dims || busy}
                onChange={(event) => {
                  const nextZoom = Number(event.target.value);
                  setZoom(nextZoom);
                  setOffset((current) => clampOffset(current, nextZoom));
                }}
                className="w-full accent-accent"
                aria-label="Zoom"
              />
            </label>
          </div>
        )}

        <p role="status" aria-live="polite" className="min-h-5 text-body text-danger">
          {phase.step === "error" ? phase.message : busy ? <span className="text-text-secondary">Uploading…</span> : null}
        </p>

        <div className="flex justify-end gap-2">
          <button
            type="button"
            disabled={busy}
            onClick={onClose}
            className="min-h-11 rounded-md px-4 text-label text-accent hover:bg-accent-subtle disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            type="button"
            disabled={!dims || busy || (phase.step === "error" && phase.fatal)}
            onClick={() => void save()}
            className="min-h-11 rounded-md bg-accent-fill px-4 text-label text-on-accent hover:bg-accent-hover disabled:opacity-50"
          >
            {busy ? "Saving…" : "Save photo"}
          </button>
        </div>
      </div>
    </Dialog>
  );
}
