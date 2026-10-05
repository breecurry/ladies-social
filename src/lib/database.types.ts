/**
 * Hand-maintained database types for the current schema
 * (supabase/migrations). Regenerate with `supabase gen types` once a
 * project is linked; keep shapes in sync with the SQL until then.
 */
export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];

export type SystemRole = "owner" | "admin" | "moderator" | "ts_reviewer";
export type TrustLevel = "member" | "established";
export type AccountStatus =
  "active" | "restricted" | "suspended" | "banned" | "deactivated" | "deleted";
export type ReplyControl = "everyone" | "followed" | "mentioned";
export type PostVisibility = "visible" | "pending_scan" | "removed_moderation" | "removed_author";
export type ReportSubject = "post" | "user";
export type ReportReason =
  | "harassment"
  | "hate"
  | "violence_threat"
  | "doxxing"
  | "csam"
  | "ncii"
  | "spam"
  | "impersonation"
  | "self_harm"
  | "other";
export type ReportStatus = "open" | "in_review" | "actioned" | "dismissed" | "escalated";
export type ReportRouting = "standard" | "admin_only" | "owner_conflict";
export type NotifType = "follow" | "like" | "reply" | "mention" | "system";

export type ProfileRow = {
  user_id: string;
  handle: string;
  display_name: string | null;
  bio: string | null;
  avatar_media_key: string | null;
  trust_level: TrustLevel;
  founding_member: boolean;
  is_system: boolean;
  status: AccountStatus;
  status_expires_at: string | null;
  search_indexable: boolean;
  created_at: string;
  updated_at: string;
};

export type UserPrivateRow = {
  user_id: string;
  legal_name: string;
  dob: string;
  email: string;
  phone_e164: string | null;
  phone_verified_at: string | null;
  age_attested_at: string;
  device_fingerprint_hash: string | null;
  signup_ip: string | null;
  last_login_ip: string | null;
  last_login_at: string | null;
  signup_flags: Json | null;
};

export type RoleAssignmentRow = {
  id: string;
  user_id: string;
  role: SystemRole;
  granted_by: string;
  granted_at: string;
  revoked_at: string | null;
  revoked_by: string | null;
};

export type AuditLogRow = {
  seq: number;
  occurred_at: string;
  actor_id: string | null;
  actor_role: string;
  action: string;
  target_type: string | null;
  target_id: string | null;
  before_state: Json | null;
  after_state: Json | null;
  detail: Json;
  ip: string | null;
  session_id: string | null;
  prev_hash: string;
  row_hash: string;
};

export type AppConfigRow = {
  key: string;
  value: Json;
  updated_at: string;
};

export type FollowRow = {
  follower_id: string;
  followee_id: string;
  created_at: string;
};

export type BlockRow = {
  blocker_id: string;
  blocked_id: string;
  created_at: string;
};

export type MuteRow = {
  muter_id: string;
  muted_id: string;
  created_at: string;
};

export type HiddenAccountRow = {
  hider_id: string;
  hidden_id: string;
  created_at: string;
};

export type PostRow = {
  id: number;
  author_id: string;
  parent_post_id: number | null;
  root_post_id: number;
  depth: number;
  body: string;
  reply_control: ReplyControl;
  like_count: number;
  reply_count: number;
  visibility: PostVisibility;
  created_at: string;
  edited_at: string | null;
  deleted_at: string | null;
};

export type LikeRow = {
  user_id: string;
  post_id: number;
  created_at: string;
};

export type ReportRow = {
  id: string;
  reporter_id: string;
  subject_type: ReportSubject;
  subject_post_id: number | null;
  subject_user_id: string;
  reason: ReportReason;
  details: string | null;
  routing: ReportRouting;
  status: ReportStatus;
  assigned_to: string | null;
  created_at: string;
  resolved_at: string | null;
  resolved_by: string | null;
  resolution_note: string | null;
};

export type NotificationRow = {
  id: number;
  user_id: string;
  actor_id: string | null;
  type: NotifType;
  post_id: number | null;
  created_at: string;
  read_at: string | null;
};

export type NotificationPrefsRow = {
  user_id: string;
  prefs: Json;
  updated_at: string;
};

/** Row shape returned by feed_following(). Identity is the handle ONLY. */
export type FeedPost = {
  id: number;
  author_id: string;
  author_handle: string;
  author_founding: boolean;
  body: string;
  reply_control: ReplyControl;
  like_count: number;
  reply_count: number;
  viewer_liked: boolean;
  created_at: string;
};

/** Row shape returned by get_thread(). Tombstones have unavailable=true. */
export type ThreadPost = {
  id: number;
  parent_post_id: number | null;
  depth: number;
  author_id: string | null;
  author_handle: string;
  author_founding: boolean;
  body: string;
  reply_control: ReplyControl;
  like_count: number;
  reply_count: number;
  viewer_liked: boolean;
  unavailable: boolean;
  created_at: string;
};

/** Row shape returned by profile_posts(). */
export type ProfilePost = FeedPost & {
  parent_author_handle: string | null;
  parent_excerpt: string | null;
};

/** Row shape returned by search_people() and the follow lists. */
export type PersonRow = {
  user_id: string;
  handle: string;
  founding: boolean;
  bio: string | null;
  viewer_follows: boolean;
};

export type FollowListRow = PersonRow & { followed_at: string };

/** Row shape returned by get_notifications(). */
export type NotificationItem = {
  id: number;
  type: NotifType;
  actor_id: string | null;
  actor_handle: string;
  post_id: number | null;
  post_excerpt: string | null;
  created_at: string;
  read_at: string | null;
};

type TableDef<Row, Insert = Partial<Row>, Update = Partial<Row>> = {
  Row: Row;
  Insert: Insert;
  Update: Update;
  Relationships: [];
};

export type Database = {
  public: {
    Tables: {
      profiles: TableDef<ProfileRow>;
      user_private: TableDef<UserPrivateRow>;
      role_assignments: TableDef<RoleAssignmentRow>;
      audit_log: TableDef<AuditLogRow>;
      app_config: TableDef<AppConfigRow>;
      follows: TableDef<FollowRow>;
      blocks: TableDef<BlockRow>;
      mutes: TableDef<MuteRow>;
      hidden_accounts: TableDef<HiddenAccountRow>;
      posts: TableDef<PostRow>;
      likes: TableDef<LikeRow>;
      reports: TableDef<ReportRow>;
      notifications: TableDef<NotificationRow>;
      notification_prefs: TableDef<NotificationPrefsRow>;
    };
    Views: Record<string, never>;
    Functions: {
      create_member: {
        Args: {
          p_user_id: string;
          p_email: string;
          p_legal_name: string;
          p_dob: string;
          p_handle: string;
          p_signup_ip: string | null;
          p_email_hash: string | null;
          p_fingerprint_hash: string | null;
          p_signals: Json;
          p_flagged: boolean;
        };
        Returns: undefined;
      };
      bootstrap_owner: {
        Args: {
          p_user: string;
          p_handle: string;
          p_legal_name: string;
          p_dob: string;
          p_email: string;
          p_phone?: string | null;
        };
        Returns: undefined;
      };
      create_system_account: {
        Args: { p_user: string; p_handle: string };
        Returns: undefined;
      };
      record_signup_attempt: {
        Args: { p_ip: string | null; p_email_hash: string | null };
        Returns: undefined;
      };
      count_signups_from_subnet: {
        Args: { p_ip: string };
        Returns: number;
      };
      count_signup_attempts_from_ip: {
        Args: { p_ip: string };
        Returns: number;
      };
      identifier_is_banned: {
        Args: { p_kind: "email_hash" | "phone_hash" | "device_hash"; p_hash: string };
        Returns: boolean;
      };
      verify_audit_chain: {
        Args: Record<string, never>;
        Returns: { ok: boolean; checked_rows: number; broken_at_seq: number | null }[];
      };
      grant_role: { Args: { p_target: string; p_role: SystemRole }; Returns: undefined };
      revoke_role: { Args: { p_target: string; p_role: SystemRole }; Returns: undefined };
      set_display_name_visibility: { Args: { p_show: boolean }; Returns: undefined };
      create_post: {
        Args: { p_body: string; p_parent?: number | null; p_reply_control?: ReplyControl };
        Returns: number;
      };
      delete_post: { Args: { p_post: number }; Returns: undefined };
      file_report: {
        Args: {
          p_subject: ReportSubject;
          p_post?: number | null;
          p_user?: string | null;
          p_reason: ReportReason;
          p_details?: string | null;
        };
        Returns: string;
      };
      feed_following: {
        Args: { p_before?: string | null; p_limit?: number };
        Returns: FeedPost[];
      };
      get_thread: { Args: { p_post: number }; Returns: ThreadPost[] };
      profile_posts: {
        Args: { p_user: string; p_replies?: boolean; p_before?: string | null; p_limit?: number };
        Returns: ProfilePost[];
      };
      search_people: { Args: { p_query: string; p_limit?: number }; Returns: PersonRow[] };
      list_followers: {
        Args: { p_user: string; p_before?: string | null; p_limit?: number };
        Returns: FollowListRow[];
      };
      list_following: {
        Args: { p_user: string; p_before?: string | null; p_limit?: number };
        Returns: FollowListRow[];
      };
      get_notifications: {
        Args: { p_before?: string | null; p_limit?: number };
        Returns: NotificationItem[];
      };
      notif_mark_all_read: { Args: Record<string, never>; Returns: undefined };
    };
    Enums: {
      system_role: SystemRole;
      trust_level: TrustLevel;
      account_status: AccountStatus;
      post_visibility: PostVisibility;
      reply_control: ReplyControl;
      report_subject: ReportSubject;
      report_reason: ReportReason;
      report_status: ReportStatus;
      report_routing: ReportRouting;
      notif_type: NotifType;
    };
    CompositeTypes: Record<string, never>;
  };
};
