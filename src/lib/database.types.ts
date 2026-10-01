/**
 * Hand-maintained database types for the Phase 1 schema
 * (supabase/migrations). Regenerate with `supabase gen types` once a
 * project is linked; keep shapes in sync with the SQL until then.
 */
export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];

export type SystemRole = "owner" | "admin" | "moderator" | "ts_reviewer";
export type MemberPrivilege = "auto_admit";
export type TrustLevel = "pending_vouch" | "member" | "established";
export type AccountStatus =
  "active" | "restricted" | "suspended" | "banned" | "deactivated" | "deleted";
export type AdmissionStatus =
  | "awaiting_vouch"
  | "queued"
  | "info_requested"
  | "admitted_vouched"
  | "admitted_reviewed"
  | "rejected"
  | "auto_rejected";
export type VouchRequestStatus = "pending" | "confirmed" | "declined" | "lapsed" | "cancelled";
export type TriageBucket = "clean" | "flagged" | "auto_rejected";

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
  vouched_by: string | null;
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
};

export type AdmissionApplicationRow = {
  id: string;
  user_id: string;
  status: AdmissionStatus;
  inviter_named: boolean;
  vouch_confirmed: boolean;
  triage_bucket: TriageBucket;
  triage_signals: Json;
  triage_score: number | null;
  info_request: string | null;
  info_response: string | null;
  decided_at: string | null;
  decided_by: string | null;
  decision_note: string | null;
  created_at: string;
  updated_at: string;
};

export type VouchRequestRow = {
  id: string;
  application_id: string;
  applicant_user_id: string;
  voucher_user_id: string;
  status: VouchRequestStatus;
  created_at: string;
  deadline: string;
  responded_at: string | null;
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

export type PrivilegeGrantRow = {
  id: string;
  user_id: string;
  privilege: MemberPrivilege;
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
      admission_applications: TableDef<AdmissionApplicationRow>;
      vouch_requests: TableDef<VouchRequestRow>;
      role_assignments: TableDef<RoleAssignmentRow>;
      privilege_grants: TableDef<PrivilegeGrantRow>;
      audit_log: TableDef<AuditLogRow>;
      app_config: TableDef<AppConfigRow>;
    };
    Views: Record<string, never>;
    Functions: {
      create_application: {
        Args: {
          p_user_id: string;
          p_email: string;
          p_legal_name: string;
          p_dob: string;
          p_handle: string;
          p_phone: string;
          p_inviter_handle: string | null;
          p_signup_ip: string | null;
          p_fingerprint_hash: string | null;
          p_signals: Json;
          p_bucket: TriageBucket;
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
      lapse_expired_vouch_requests: { Args: Record<string, never>; Returns: number };
      confirm_vouch: { Args: { p_request: string }; Returns: undefined };
      decline_vouch: { Args: { p_request: string }; Returns: undefined };
      get_my_vouch_requests: {
        Args: Record<string, never>;
        Returns: {
          id: string;
          applicant_handle: string;
          applicant_legal_name: string;
          created_at: string;
          deadline: string;
        }[];
      };
      my_application_status: {
        Args: Record<string, never>;
        Returns: {
          status: "pending" | "info_requested" | "admitted" | "rejected";
          message: string | null;
        }[];
      };
      submit_info_response: { Args: { p_text: string }; Returns: undefined };
      review_approve: { Args: { p_app: string; p_note?: string | null }; Returns: undefined };
      review_reject: { Args: { p_app: string; p_note?: string | null }; Returns: undefined };
      review_request_info: { Args: { p_app: string; p_message: string }; Returns: undefined };
      owner_vouch_stats: {
        Args: Record<string, never>;
        Returns: {
          user_id: string;
          handle: string;
          vouches_confirmed: number;
          vouchees_admitted: number;
          vouchees_in_good_standing: number;
          vouchees_removed: number;
          requests_pending: number;
          has_auto_admit: boolean;
        }[];
      };
      verify_audit_chain: {
        Args: Record<string, never>;
        Returns: { ok: boolean; checked_rows: number; broken_at_seq: number | null }[];
      };
      grant_role: { Args: { p_target: string; p_role: SystemRole }; Returns: undefined };
      revoke_role: { Args: { p_target: string; p_role: SystemRole }; Returns: undefined };
      grant_privilege: {
        Args: { p_target: string; p_privilege: MemberPrivilege };
        Returns: undefined;
      };
      revoke_privilege: {
        Args: { p_target: string; p_privilege: MemberPrivilege };
        Returns: undefined;
      };
      set_display_name_visibility: { Args: { p_show: boolean }; Returns: undefined };
    };
    Enums: {
      system_role: SystemRole;
      member_privilege: MemberPrivilege;
      trust_level: TrustLevel;
      account_status: AccountStatus;
      admission_status: AdmissionStatus;
      vouch_request_status: VouchRequestStatus;
      triage_bucket: TriageBucket;
    };
    CompositeTypes: Record<string, never>;
  };
};
