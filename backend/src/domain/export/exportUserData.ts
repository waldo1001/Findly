// specs/001 §13.1 `GET /export`, specs/008 §2/§3 — data export. Pure domain logic: no
// Azure/Google imports. Read-only mirror of the erasure coverage table (008 §2): every
// "yes" row is walked to completion in-process (no pagination in the response, 008 §3)
// before the document is returned. Authorization/quota order follows the spec prose
// (001 §13.1): profile -> forbidden/not-found -> quota.

import { AppError } from "../../http/errors";
import { exportQuerySchema, parseOrThrow } from "../../http/validate";
import type { Clock } from "../../ports/support";
import type {
  DeviceRepo,
  EntitlementsRepo,
  FamilyRepo,
  GroupLastKnownRepo,
  GroupRepo,
  GroupRole,
  LastKnownRecord,
  LastKnownRepo,
  Role,
  UsageMetric,
  UsageRepo,
  UserRepo,
} from "../../ports/repositories";
import type { EventLine, FixLine, HistoryStore } from "../../ports/historyStore";
import { getFeatures, type Features } from "../plan";
import { toDeviceView, type DeviceView } from "../device/deviceView";
import { deriveGroupState, type GroupState } from "../group/groupState";
import { resolveExportWindow } from "./exportWindow";

const HISTORY_PAGE_SIZE = 500;

// specs/001 §13.1 — the export's providerData note (verbatim).
const FIREBASE_PROVIDER_DATA_NOTE =
  "Your phone number and sign-in metadata are held by Firebase Authentication, not by Findly; they are deleted when your account is deleted.";

export interface ExportDataDeps {
  userRepo: UserRepo;
  familyRepo: FamilyRepo;
  deviceRepo: DeviceRepo;
  lastKnownRepo: LastKnownRepo;
  groupRepo: GroupRepo;
  groupLastKnownRepo: GroupLastKnownRepo;
  historyStore: HistoryStore;
  usageRepo: UsageRepo;
  entitlementsRepo: EntitlementsRepo;
  clock: Clock;
}

export interface ExportDataInput {
  uid: string;
  /** The caller's familyId from the resolved auth context (§1.5), null if family-less. */
  familyId: string | null;
  /** The caller's role from the resolved auth context (§1.5), null if family-less. */
  role: Role | null;
  /** Raw query params (userId?) — validated here. */
  query: unknown;
}

export interface ExportSubject {
  userId: string;
  displayName: string;
}

export interface ExportFamily {
  familyId: string;
  familyName: string;
  role: Role;
  joinedAt: string;
}

export interface ExportGroupMembership {
  groupId: string;
  name: string;
  role: GroupRole;
  displayName: string;
  joinedAt: string;
  state: Exclude<GroupState, "expired">;
  endsAt: string;
}

export interface ExportGroupPosition {
  groupId: string;
  lat: number;
  lon: number;
  accuracyM: number;
  recordedAt: string;
}

export interface ExportUsageRow {
  date: string;
  metric: UsageMetric;
  count: number;
}

export interface ExportDocument {
  formatVersion: 1;
  generatedAt: string;
  subject: ExportSubject;
  /** null when the subject is family-less (001 §13.1). */
  family: ExportFamily | null;
  devices: DeviceView[];
  lastKnown: LastKnownRecord[];
  locationHistory: (FixLine & { deviceId: string })[];
  geofenceEvents: EventLine[];
  groups: ExportGroupMembership[];
  groupPositions: ExportGroupPosition[];
  usage: ExportUsageRow[];
  providerData: { firebaseAuthentication: string };
}

function usageDate(now: Date): string {
  return now.toISOString().slice(0, 10);
}

/** Walks HistoryStore.readFixHistory to exhaustion (cursor loop) — export has no pagination
 * in its RESPONSE (008 §3); this just bounds each internal round trip to the store. */
async function readAllFixes(
  store: HistoryStore,
  familyId: string,
  userId: string,
  from: string,
  to: string,
): Promise<(FixLine & { deviceId: string })[]> {
  const results: (FixLine & { deviceId: string })[] = [];
  let cursor: string | null = null;
  do {
    const page = await store.readFixHistory(familyId, userId, undefined, from, to, HISTORY_PAGE_SIZE, cursor);
    results.push(...page.items);
    cursor = page.nextCursor;
  } while (cursor);
  return results;
}

/** Same cursor-exhaustion idiom as readAllFixes, for the interleaved events/ blobs
 * (002 §3.1), filtered server-side to the subject's own lines (008 §2). */
async function readAllEvents(
  store: HistoryStore,
  familyId: string,
  userId: string,
  from: string,
  to: string,
): Promise<EventLine[]> {
  const results: EventLine[] = [];
  let cursor: string | null = null;
  do {
    const page = await store.readEventHistory(familyId, from, to, userId, HISTORY_PAGE_SIZE, cursor);
    results.push(...page.items);
    cursor = page.nextCursor;
  } while (cursor);
  return results;
}

export async function exportUserData(input: ExportDataInput, deps: ExportDataDeps): Promise<ExportDocument> {
  const query = parseOrThrow(exportQuerySchema, input.query);
  const subjectUserId = query.userId ?? input.uid;

  // Resolve the subject + authorize (001 §13.1, 008 §3): self is always allowed; a parent
  // may name any CURRENT member of their own family; everyone else naming another user is
  // forbidden.
  let subjectDisplayName: string;
  let family: ExportFamily | null = null;

  if (subjectUserId !== input.uid) {
    if (input.role !== "parent") {
      throw new AppError("AUTH_FORBIDDEN", "only a parent may export another family member");
    }
    // Invariant (002 §2.2): role is denormalized from Families and is null iff familyId is
    // null — role === "parent" here guarantees familyId is set.
    const familyId = input.familyId as string;
    const members = await deps.familyRepo.listMembers(familyId);
    const target = members.find((m) => m.userId === subjectUserId);
    if (!target) {
      // Removed ex-members are not exportable targets (their retained history stays
      // reachable via 001 §5.3 until retention expires, 008 §3).
      throw new AppError("MEMBER_NOT_FOUND", "member not found in caller's family");
    }
    const meta = await deps.familyRepo.getFamilyMeta(familyId);
    if (!meta) {
      throw new AppError("INTERNAL_ERROR", "family meta record missing");
    }
    subjectDisplayName = target.displayName;
    family = { familyId, familyName: meta.familyName, role: target.role, joinedAt: target.joinedAt };
  } else if (input.familyId) {
    const familyId = input.familyId;
    const members = await deps.familyRepo.listMembers(familyId);
    // Invariant: FamilyRepo.addMember + UserRepo.createProfile are always written together
    // (createFamily/acceptInvite), so the caller always appears in their own family's roster.
    const me = members.find((m) => m.userId === input.uid);
    if (!me) {
      throw new AppError("INTERNAL_ERROR", "caller missing from own family roster");
    }
    const meta = await deps.familyRepo.getFamilyMeta(familyId);
    if (!meta) {
      throw new AppError("INTERNAL_ERROR", "family meta record missing");
    }
    subjectDisplayName = me.displayName;
    family = { familyId, familyName: meta.familyName, role: me.role, joinedAt: me.joinedAt };
  } else {
    const profile = await deps.userRepo.getProfile(input.uid);
    subjectDisplayName = profile?.displayName ?? input.uid;
  }

  // Quota (001 §9/§13.1, 008 §3): counted against the CALLER, same family/uid partition
  // rule as every other metric (001 §9) — never the export's subject on a cross-export.
  const usagePartition = input.familyId ?? input.uid;
  let features: Features;
  if (input.familyId) {
    const entitlements = await deps.entitlementsRepo.get(input.familyId);
    if (!entitlements) {
      throw new AppError("INTERNAL_ERROR", "family has no entitlements record");
    }
    features = getFeatures(entitlements.subscriptionStatus);
  } else {
    features = getFeatures("free");
  }

  const now = deps.clock.now();
  const today = usageDate(now);
  const usedToday = await deps.usageRepo.get(usagePartition, "exports", today);
  if (usedToday >= features.limits.exportsPerDay) {
    throw new AppError("LIMIT_EXCEEDED", "daily export quota reached", { limit: "exportsPerDay" });
  }

  // Devices (002 §2.4, 008 §2) — push tokens never leave DeviceRepo (toDeviceView, same
  // shape as the 001 §4.1 response object).
  const deviceRecords = await deps.deviceRepo.listDevices(subjectUserId);
  const devices: DeviceView[] = deviceRecords.map(toDeviceView);

  // Last-known positions (002 §2.5, 008 §2) — already the exact export shape.
  const lastKnownRecords = await deps.lastKnownRepo.listByOwner(subjectUserId);
  const lastKnown: LastKnownRecord[] = lastKnownRecords.map((r) => ({ ...r }));

  // The subject's own family, if any — NOT necessarily input.familyId's caller-vs-subject
  // ambiguity: `family` above is set exactly when the subject has one (both the self- and
  // cross-export branches populate it; only the family-less self-export branch leaves it
  // null), so it is the correct gate for the subject's OWN family-scoped data below.
  const subjectFamilyId = family?.familyId ?? null;

  // Location history + geofence events (002 §3.1, 008 §2) — full physical retention window
  // (400 d), deliberately beyond features.limits.historyDays (008 §3). Family-scoped: a
  // family-less subject has neither.
  let locationHistory: (FixLine & { deviceId: string })[] = [];
  let geofenceEvents: EventLine[] = [];
  if (subjectFamilyId) {
    const { from, to } = resolveExportWindow(now);
    [locationHistory, geofenceEvents] = await Promise.all([
      readAllFixes(deps.historyStore, subjectFamilyId, subjectUserId, from, to),
      readAllEvents(deps.historyStore, subjectFamilyId, subjectUserId, from, to),
    ]);
  }

  // Group memberships + own positions (002 §2.2/§2.10/§2.12, 008 §2) — "membership facts";
  // groups are family-independent, so this runs regardless of subjectFamilyId.
  const memberships = await deps.userRepo.listGroupMemberships(subjectUserId);
  const groups: ExportGroupMembership[] = [];
  const groupPositions: ExportGroupPosition[] = [];
  for (const membership of memberships) {
    const meta = await deps.groupRepo.getGroupMeta(membership.groupId);
    if (!meta) continue; // orphaned reverse-index row (self-healing skip, same as listGroups.ts)
    const member = await deps.groupRepo.getMember(membership.groupId, subjectUserId);
    if (!member) continue; // reverse index disagrees with the roster (self-healing skip)

    const state = deriveGroupState(now, meta.endsAt, meta.expiryPolicy, features.limits.groupGraceDays);
    if (state === "expired") continue; // never serialized (005 §2.2, 001 §12)

    groups.push({
      groupId: meta.groupId,
      name: meta.name,
      role: member.role,
      displayName: member.displayName,
      joinedAt: member.joinedAt,
      state,
      endsAt: meta.endsAt,
    });

    const positions = await deps.groupLastKnownRepo.listByGroup(membership.groupId);
    const own = positions.find((p) => p.userId === subjectUserId);
    if (own) {
      groupPositions.push({
        groupId: meta.groupId,
        lat: own.lat,
        lon: own.lon,
        accuracyM: own.accuracyM,
        recordedAt: own.recordedAt,
      });
    }
  }

  // Usage (002 §2.9, 008 §2) — "uid-keyed rows only": a family member's usage is ALWAYS
  // family-keyed (001 §9's "per family/day — per user/day for family-less callers" rule has
  // no per-member exception), so there is never a subject-scoped row to show for one; only a
  // family-less subject's own uid partition holds anything exportable.
  let usage: ExportUsageRow[] = [];
  if (!subjectFamilyId) {
    const rows = await deps.usageRepo.listByPartition(subjectUserId);
    usage = rows.map((r) => ({ date: r.date, metric: r.metric, count: r.count }));
  }

  await deps.usageRepo.increment(usagePartition, "exports", today);

  return {
    formatVersion: 1,
    generatedAt: now.toISOString(),
    subject: { userId: subjectUserId, displayName: subjectDisplayName },
    family,
    devices,
    lastKnown,
    locationHistory,
    geofenceEvents,
    groups,
    groupPositions,
    usage,
    providerData: { firebaseAuthentication: FIREBASE_PROVIDER_DATA_NOTE },
  };
}
