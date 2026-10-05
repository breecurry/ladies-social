"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";
import { Dialog } from "@/components/Dialog";
import { useToast } from "@/components/shell/ToastProvider";
import { useViewer } from "@/components/shell/Providers";
import { ChangePhotoControl, RemovePhotoButton } from "@/components/avatar/AvatarEditor";

/**
 * Edit profile (spec §7.4, P2E §6.1): the profile photo row (change /
 * remove, both routine) and the bio. Name visibility deliberately
 * lives in Settings, Privacy, with its own confirmation and preview.
 */
export function EditProfileDialog({
  initialBio,
  hasPhoto,
}: {
  initialBio: string | null;
  hasPhoto: boolean;
}) {
  const router = useRouter();
  const viewer = useViewer();
  const { showToast } = useToast();
  const [open, setOpen] = useState(false);
  const [bio, setBio] = useState(initialBio ?? "");
  const [busy, setBusy] = useState(false);

  const save = async () => {
    setBusy(true);
    const supabase = createSupabaseBrowserClient();
    const { error } = await supabase
      .from("profiles")
      .update({ bio: bio.trim() === "" ? null : bio.trim() })
      .eq("user_id", viewer.id);
    setBusy(false);
    if (error) {
      showToast("Could not save your bio. Try again.");
      return;
    }
    setOpen(false);
    showToast("Profile updated");
    router.refresh();
  };

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="min-h-11 rounded-full border border-border-strong bg-surface px-6 text-label text-text-primary hover:bg-surface-raised"
      >
        Edit profile
      </button>
      <Dialog open={open} onClose={() => setOpen(false)} label="Edit profile" maxWidth="max-w-md">
        <div className="flex flex-col gap-3 p-4">
          <h2 className="text-heading">Edit profile</h2>
          <div className="flex flex-col gap-1.5">
            <span className="text-label text-text-primary">Profile photo</span>
            <div className="flex flex-wrap items-center gap-2">
              <ChangePhotoControl variant="row" hasPhoto={hasPhoto} />
              {hasPhoto ? <RemovePhotoButton /> : null}
            </div>
          </div>
          <label className="flex flex-col gap-1.5">
            <span className="text-label text-text-primary">Bio</span>
            <textarea
              data-autofocus
              value={bio}
              maxLength={300}
              rows={4}
              onChange={(event) => setBio(event.target.value)}
              placeholder="A line about you"
              className="w-full rounded-md border border-border-strong bg-surface px-3 py-2 text-body text-text-primary placeholder:text-text-tertiary"
            />
            <span className="text-caption text-text-tertiary">Up to 300 characters.</span>
          </label>
          <p className="text-caption text-text-tertiary">
            How your name appears is controlled in Settings, Privacy. Members see your @handle by
            default.
          </p>
          <div className="flex justify-end gap-2">
            <button
              type="button"
              onClick={() => setOpen(false)}
              className="min-h-11 rounded-md px-4 text-label text-accent hover:bg-accent-subtle"
            >
              Cancel
            </button>
            <button
              type="button"
              disabled={busy}
              onClick={() => void save()}
              className="min-h-11 rounded-md bg-accent-fill px-4 text-label text-on-accent hover:bg-accent-hover disabled:opacity-50"
            >
              {busy ? "Saving…" : "Save"}
            </button>
          </div>
        </div>
      </Dialog>
    </>
  );
}
