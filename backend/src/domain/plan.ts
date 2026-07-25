// specs/001 §9 — Entitlements & `features`. The single source of plan limits/flags.
// Every limit-enforcement point MUST read this object — never a literal (001 §9, §11).

export type SubscriptionStatus = "free" | "active";

export interface PlanLimits {
  maxDevices: number;
  maxGeofences: number;
  historyDays: number;
  minSyncIntervalMinutes: number;
  locateRequestsPerDay: number;
  /** Caller-scoped (001 §9): the caller's own non-expired memberships, owned + joined (005 §4). */
  maxActiveGroups: number;
  /** Owner-scoped (001 §9, §12.6): resolved from the group OWNER's plan at join time. */
  maxGroupMembers: number;
  /** Caller-scoped (001 §9, §12.1/§12.4): enforced against the caller's own features. */
  maxGroupDurationDays: number;
  /** Derived graceUntil for `grace`-policy groups (005 §2.2, §4). */
  groupGraceDays: number;
  /** Caller-scoped (001 §9, §13.1): GET /export quota, counted against the caller even
   * when exporting another family member (008 §3). */
  exportsPerDay: number;
}

export interface PlanFlags {
  pushToLocate: boolean;
  geofencing: boolean;
  historyReplay: boolean;
  groups: boolean;
}

export interface PlanBenefits {
  limits: PlanLimits;
  flags: PlanFlags;
}

export interface Features extends PlanBenefits {
  subscriptionStatus: SubscriptionStatus;
}

const FREE_PLAN: PlanBenefits = {
  limits: {
    maxDevices: 10,
    maxGeofences: 20,
    historyDays: 90,
    minSyncIntervalMinutes: 5,
    locateRequestsPerDay: 100,
    maxActiveGroups: 5,
    maxGroupMembers: 200,
    maxGroupDurationDays: 30,
    groupGraceDays: 7,
    exportsPerDay: 3,
  },
  flags: {
    pushToLocate: true,
    geofencing: true,
    historyReplay: true,
    groups: true,
  },
};

// "active" currently mirrors "free" — a reserved placeholder (001 §9). Changing plan
// benefits later is editing this matrix, nothing else.
export const PLAN_MATRIX: Record<SubscriptionStatus, PlanBenefits> = {
  free: FREE_PLAN,
  active: FREE_PLAN,
};

export function getFeatures(subscriptionStatus: SubscriptionStatus): Features {
  return { subscriptionStatus, ...PLAN_MATRIX[subscriptionStatus] };
}
