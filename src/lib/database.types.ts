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
export type ReportSubject = "post" | "user" | "message";
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
export type NotifType = "follow" | "like" | "reply" | "mention" | "system" | "message";
export type DmConversationState = "request" | "accepted";
export type DmRequestPolicy = "everyone" | "followed" | "no_one";
export type ModAction =
  | "dismiss"
  | "warn"
  | "remove_content"
  | "restore_content"
  | "restrict"
  | "suspend"
  | "lift"
  | "ban"
  | "unban"
  | "escalate";

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
  /**
   * Discover opt-out (owner decision 2026-10-07: ON by default).
   * false = never surfaced in anyone's Discover feed or suggestions;
   * @handle search and existing-follower visibility are unaffected.
   */
  discoverable: boolean;
  created_at: string;
  updated_at: string;
};

export type UserPrivateRow = {
  user_id: string;
  legal_name: string;
  email: string;
  phone_e164: string | null;
  phone_verified_at: string | null;
  age_attested_at: string;
  device_fingerprint_hash: string | null;
  signup_ip: string | null;
  last_login_ip: string | null;
  last_login_at: string | null;
  signup_flags: Json | null;
  tos_agreed_at: string | null;
  tos_version: string | null;
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
  body: string | null;
  created_at: string;
  read_at: string | null;
};

/**
 * One enforcement action (the console's history). Keyed to user ids
 * that every surface resolves to @handles — the row itself carries no
 * name. `message` is what the member was told; `note` never leaves
 * staff surfaces. No app role reads or writes this table directly.
 */
export type ModerationActionRow = {
  id: number;
  target_user_id: string;
  post_id: number | null;
  action: ModAction;
  rule: ReportReason | null;
  duration_days: number | null;
  message: string | null;
  note: string | null;
  actor_id: string;
  actor_role: string;
  created_at: string;
  expires_at: string | null;
};

/**
 * The durable queue for the safety@ email copy of every report
 * (owner decision: two traceable copies). Written only inside
 * file_report(); the dispatcher may only mark rows sent.
 */
export type SafetyEmailOutboxRow = {
  id: number;
  report_id: string;
  recipient: string;
  subject: string;
  body: string;
  created_at: string;
  sent_at: string | null;
  attempts: number;
  last_error: string | null;
};

export type NotificationPrefsRow = {
  user_id: string;
  prefs: Json;
  updated_at: string;
};

/**
 * One 14-day age-gate device block (spec §17.3). By design this row
 * holds a hashed fingerprint, timestamps and a reference code — and
 * NOTHING else. No app role can read or write the table directly; the
 * age-gate functions below are the only path.
 */
export type AgeGateBlockRow = {
  id: number;
  fingerprint_hash: string | null;
  reference_code: string;
  created_at: string;
  expires_at: string;
};

/** Row shape returned by the age-gate block functions. */
export type AgeGateBlockResult = {
  reference_code: string;
  expires_at: string;
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

/**
 * Row shape returned by feed_discover(). FeedPost plus the one signal
 * Discover needs that Following never does: whether the viewer already
 * follows the author (the card shows the Follow pill when she does not).
 */
export type DiscoverPost = FeedPost & { viewer_follows: boolean };

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
  body: string | null;
  created_at: string;
  read_at: string | null;
};

/** One case row from mod_queue(): reports grouped by accused (+post). */
export type ModQueueCase = {
  accused_id: string;
  accused_handle: string;
  accused_status: AccountStatus;
  subject_post_id: number | null;
  top_reason: ReportReason;
  report_count: number;
  reporter_count: number;
  newest_at: string;
  case_state: string;
  priority: "critical" | "high" | "normal";
  assigned_handle: string | null;
};

/** Row shape returned by mod_queue_counts(). */
export type ModQueueCounts = {
  open_count: number;
  critical_count: number;
  in_review_count: number;
};

/** One report inside a case (reporter identity deliberately absent). */
export type ModCaseReport = {
  report_id: string;
  reason: ReportReason;
  details: string | null;
  status: ReportStatus;
  created_at: string;
  assigned_handle: string | null;
  resolution_note: string | null;
};

/** Row shape returned by mod_view_reporters() (an audited reveal). */
export type ModReporterRow = {
  report_id: string;
  reporter_handle: string;
  reporter_reports_24h: number;
};

/** One post in the in-case thread context. Removed content stubs to "". */
export type ModContextPost = {
  id: number;
  parent_post_id: number | null;
  depth: number;
  author_handle: string;
  body: string;
  visibility: PostVisibility;
  author_deleted: boolean;
  created_at: string;
  is_subject: boolean;
};

/** One recent post on an account-level case. */
export type ModAccountPost = {
  id: number;
  body: string;
  visibility: PostVisibility;
  is_reply: boolean;
  created_at: string;
};

/** The account-context strip for a case. */
export type ModAccountContext = {
  handle: string;
  status: AccountStatus;
  status_expires_at: string | null;
  joined_at: string;
  post_count: number;
  prior_actions: number;
  is_staff: boolean;
};

/** One row of an account's enforcement trail (staff surface). */
export type ModEnforcementRow = {
  action: ModAction;
  rule: ReportReason | null;
  duration_days: number | null;
  actor_role: string;
  actor_handle: string | null;
  note: string | null;
  created_at: string;
  expires_at: string | null;
};

/** The member's own "what happened to me" status. */
export type MyAccountStatus = {
  status: AccountStatus;
  status_expires_at: string | null;
  last_action: ModAction | null;
  last_rule: ReportReason | null;
  last_message: string | null;
  last_action_at: string | null;
};

// ---------------------------------------------------------------
// Direct messages (Phase 2C). The server stores ciphertext only;
// bytea travels as "\x"-prefixed hex over PostgREST.
// ---------------------------------------------------------------

/** Messages settings row (absent row = these defaults). */
export type DmSettingsRow = {
  user_id: string;
  requests_from: DmRequestPolicy;
  dms_enabled: boolean;
  read_receipts: boolean;
  updated_at: string;
};

/** The member's own active device, from dm_my_device(). */
export type DmMyDevice = {
  device_id: string;
  identity_key: string;
  created_at: string;
  prekeys_remaining: number;
};

/** A prekey bundle for session setup, from dm_prekey_bundle(). */
export type DmPrekeyBundle = {
  device_id: string;
  identity_key: string;
  signed_prekey: string;
  signed_prekey_sig: string;
  prekey_id: number | null;
  prekey: string | null;
};

/** One inbox row, from dm_list_conversations(). @handle only, ever. */
export type DmConversationRow = {
  conversation_id: string;
  correspondent_id: string;
  correspondent_handle: string;
  state: DmConversationState;
  is_initiator: boolean;
  muted: boolean;
  cleared_before: string | null;
  last_message_at: string;
  unread_count: number;
  my_last_read_at: string | null;
  peer_read_at: string | null;
};

/** The result row of dm_send_message(). */
export type DmSendResult = {
  message_id: number;
  conversation_id: string;
  conversation_state: DmConversationState;
  sent_at: string;
};

/** One ciphertext row, from dm_fetch_messages(). */
export type DmWireMessage = {
  id: number;
  sender_id: string;
  sender_handle: string;
  sender_device_id: string;
  recipient_device_id: string;
  header: Json;
  ciphertext: string;
  frank_hash: string;
  sent_at: string;
};

/** One evidence row in the console transcript, from mod_dm_evidence(). */
export type ModDmEvidenceRow = {
  report_id: string;
  reason: ReportReason;
  report_status: ReportStatus;
  reported_at: string;
  message_id: number;
  sender_handle: string;
  plaintext: string;
  verified: boolean;
  sent_at: string;
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
      moderation_actions: TableDef<ModerationActionRow>;
      safety_email_outbox: TableDef<SafetyEmailOutboxRow>;
      age_gate_blocks: TableDef<AgeGateBlockRow>;
      dm_settings: TableDef<DmSettingsRow>;
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
        Args: { p_before?: string | null; p_limit?: number; p_before_id?: number | null };
        Returns: FeedPost[];
      };
      feed_discover: {
        Args: { p_limit?: number; p_offset?: number };
        Returns: DiscoverPost[];
      };
      suggested_accounts: { Args: { p_limit?: number }; Returns: PersonRow[] };
      get_thread: { Args: { p_post: number }; Returns: ThreadPost[] };
      profile_posts: {
        Args: {
          p_user: string;
          p_replies?: boolean;
          p_before?: string | null;
          p_limit?: number;
          p_before_id?: number | null;
        };
        Returns: ProfilePost[];
      };
      search_people: { Args: { p_query: string; p_limit?: number }; Returns: PersonRow[] };
      list_followers: {
        Args: {
          p_user: string;
          p_before?: string | null;
          p_limit?: number;
          p_before_user?: string | null;
        };
        Returns: FollowListRow[];
      };
      list_following: {
        Args: {
          p_user: string;
          p_before?: string | null;
          p_limit?: number;
          p_before_user?: string | null;
        };
        Returns: FollowListRow[];
      };
      get_notifications: {
        Args: { p_before?: string | null; p_limit?: number; p_before_id?: number | null };
        Returns: NotificationItem[];
      };
      notif_mark_all_read: { Args: Record<string, never>; Returns: undefined };
      mod_claim: { Args: { p_target: string; p_post?: number | null }; Returns: number };
      mod_dismiss: {
        Args: { p_target: string; p_post?: number | null; p_note?: string | null };
        Returns: number;
      };
      mod_reopen: { Args: { p_target: string; p_post?: number | null }; Returns: number };
      mod_warn: {
        Args: {
          p_target: string;
          p_rule: ReportReason;
          p_message: string;
          p_post?: number | null;
          p_remove?: boolean;
          p_note?: string | null;
        };
        Returns: undefined;
      };
      mod_remove_post: {
        Args: { p_post: number; p_rule: ReportReason; p_note?: string | null };
        Returns: undefined;
      };
      mod_restore_post: {
        Args: { p_post: number; p_note?: string | null };
        Returns: undefined;
      };
      mod_restrict: {
        Args: { p_target: string; p_days: number; p_rule: ReportReason; p_note?: string | null };
        Returns: undefined;
      };
      mod_suspend: {
        Args: { p_target: string; p_days: number; p_rule: ReportReason; p_note?: string | null };
        Returns: undefined;
      };
      mod_lift: { Args: { p_target: string; p_note?: string | null }; Returns: undefined };
      mod_escalate: {
        Args: { p_target: string; p_post?: number | null; p_note?: string | null };
        Returns: number;
      };
      mod_ban: {
        Args: {
          p_target: string;
          p_rule: ReportReason;
          p_note: string;
          p_email_hash?: string | null;
          p_phone_hash?: string | null;
          p_ban_device?: boolean;
        };
        Returns: undefined;
      };
      owner_unban: { Args: { p_target: string; p_note?: string | null }; Returns: undefined };
      mod_queue: { Args: { p_state?: string; p_limit?: number }; Returns: ModQueueCase[] };
      mod_queue_counts: { Args: Record<string, never>; Returns: ModQueueCounts[] };
      mod_case: {
        Args: { p_target: string; p_post?: number | null };
        Returns: ModCaseReport[];
      };
      mod_view_reporters: {
        Args: { p_target: string; p_post?: number | null };
        Returns: ModReporterRow[];
      };
      mod_post_context: { Args: { p_post: number }; Returns: ModContextPost[] };
      mod_account_posts: {
        Args: { p_target: string; p_limit?: number };
        Returns: ModAccountPost[];
      };
      mod_account_context: { Args: { p_target: string }; Returns: ModAccountContext[] };
      mod_enforcement_history: {
        Args: { p_target: string };
        Returns: ModEnforcementRow[];
      };
      my_account_status: { Args: Record<string, never>; Returns: MyAccountStatus[] };
      refresh_my_status: { Args: Record<string, never>; Returns: boolean };
      record_age_gate_block: {
        Args: { p_fingerprint_hash: string | null };
        Returns: AgeGateBlockResult[];
      };
      get_age_gate_block: {
        Args: { p_fingerprint_hash: string | null; p_code: string | null };
        Returns: AgeGateBlockResult[];
      };
      lookup_age_gate_block: {
        Args: { p_code: string };
        Returns: { reference_code: string; created_at: string; expires_at: string }[];
      };
      clear_age_gate_block: { Args: { p_code: string }; Returns: boolean };
      record_tos_consent: {
        Args: { p_user_id: string; p_version: string };
        Returns: boolean;
      };
      dm_feature_enabled: { Args: Record<string, never>; Returns: boolean };
      dm_register_device: {
        Args: {
          p_device_name: string;
          p_identity_key: string;
          p_signed_prekey: string;
          p_signed_prekey_sig: string;
          p_prekeys: string[];
        };
        Returns: string;
      };
      dm_add_prekeys: { Args: { p_prekeys: string[] }; Returns: number };
      dm_my_device: { Args: Record<string, never>; Returns: DmMyDevice[] };
      dm_can_message: { Args: { p_user: string }; Returns: string };
      dm_prekey_bundle: { Args: { p_user: string }; Returns: DmPrekeyBundle[] };
      dm_send_message: {
        Args: {
          p_recipient: string;
          p_recipient_device: string;
          p_header: Json;
          p_ciphertext: string;
          p_frank_hash: string;
        };
        Returns: DmSendResult[];
      };
      dm_accept_request: { Args: { p_conversation: string }; Returns: undefined };
      dm_decline_request: { Args: { p_conversation: string }; Returns: undefined };
      dm_delete_conversation: { Args: { p_conversation: string }; Returns: undefined };
      dm_set_muted: {
        Args: { p_conversation: string; p_muted: boolean };
        Returns: undefined;
      };
      dm_mark_read: { Args: { p_conversation: string }; Returns: undefined };
      dm_list_conversations: {
        Args: { p_requests?: boolean };
        Returns: DmConversationRow[];
      };
      dm_unread_total: { Args: Record<string, never>; Returns: number };
      dm_fetch_messages: {
        Args: { p_conversation: string; p_after_id?: number | null; p_limit?: number };
        Returns: DmWireMessage[];
      };
      file_dm_report: {
        Args: {
          p_conversation: string;
          p_reason: ReportReason;
          p_details?: string | null;
          p_evidence: Json;
        };
        Returns: string;
      };
      mod_dm_evidence: { Args: { p_target: string }; Returns: ModDmEvidenceRow[] };
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
      mod_action: ModAction;
      dm_conversation_state: DmConversationState;
      dm_request_policy: DmRequestPolicy;
    };
    CompositeTypes: Record<string, never>;
  };
};
