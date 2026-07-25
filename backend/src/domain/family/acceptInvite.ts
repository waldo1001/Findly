// specs/001 §3.4 — accept invite (authenticated user without a family). Pure domain
// logic: no Azure/Google imports.

import { AppError } from "../../http/errors";
import { acceptInviteRequestSchema, parseOrThrow } from "../../http/validate";
import type { Clock } from "../../ports/support";
import type {
  EntitlementsRepo,
  FamilyMember,
  FamilyRepo,
  InviteRepo,
  Role,
  UserRepo,
} from "../../ports/repositories";
import { getFeatures, type Features } from "../plan";
import { normalizeInviteCode } from "./inviteCode";

export interface AcceptInviteDeps {
  inviteRepo: InviteRepo;
  familyRepo: FamilyRepo;
  userRepo: UserRepo;
  entitlementsRepo: EntitlementsRepo;
  clock: Clock;
}

export interface AcceptInviteInput {
  uid: string;
  /** The caller's familyId from the resolved auth context (§1.5), null if no profile. */
  familyId: string | null;
  body: unknown;
}

export interface AcceptInviteResult {
  familyId: string;
  familyName: string;
  role: Role;
  features: Features;
}

export async function acceptInvite(input: AcceptInviteInput, deps: AcceptInviteDeps): Promise<AcceptInviteResult> {
  if (input.familyId) {
    throw new AppError("FAMILY_ALREADY_MEMBER", "caller already belongs to a family");
  }

  const { inviteCode, displayName } = parseOrThrow(acceptInviteRequestSchema, input.body);
  const normalizedCode = normalizeInviteCode(inviteCode);

  const invite = await deps.inviteRepo.getInvite(normalizedCode);
  if (!invite) {
    throw new AppError("INVITE_INVALID", "unknown invite code");
  }

  const now = deps.clock.now();
  if (new Date(invite.expiresAt).getTime() <= now.getTime()) {
    throw new AppError("INVITE_EXPIRED", "invite code expired");
  }

  // Fail-closed on deleted families (008 §5.3, 001 §3.4): a straggler invite row can
  // outlive its family (a partial family-deletion failure leaves the canonical Invites row
  // behind after the meta row is already gone, 002 §2.1). Verify the family still exists
  // BEFORE consuming the single-use code, and — deliberately — report the exact same
  // INVITE_INVALID an unknown code would get, so a deleted family can never be resurrected
  // or even detected through this endpoint.
  const familyMeta = await deps.familyRepo.getFamilyMeta(invite.familyId);
  if (!familyMeta) {
    throw new AppError("INVITE_INVALID", "invite references a family that no longer exists");
  }
  const entitlements = await deps.entitlementsRepo.get(invite.familyId);
  if (!entitlements) {
    throw new AppError("INTERNAL_ERROR", "family has no entitlements record");
  }
  const features = getFeatures(entitlements.subscriptionStatus);

  const usedAt = now.toISOString();
  const consumeResult = await deps.inviteRepo.consumeInvite(normalizedCode, input.uid, usedAt);
  if (consumeResult === "alreadyUsed") {
    throw new AppError("INVITE_ALREADY_USED", "invite code already used");
  }

  const member: FamilyMember = { userId: input.uid, role: invite.role, displayName, joinedAt: usedAt };
  await deps.familyRepo.addMember(invite.familyId, member);
  await deps.userRepo.createProfile(input.uid, { familyId: invite.familyId, role: invite.role, displayName });

  return { familyId: invite.familyId, familyName: familyMeta.familyName, role: invite.role, features };
}
