// specs/001 §3.3 — create invite (parent). Pure domain logic: no Azure/Google imports.

import { AppError } from "../../http/errors";
import { createInviteRequestSchema, parseOrThrow } from "../../http/validate";
import type { Clock, InviteCodeGenerator } from "../../ports/support";
import type { EntitlementsRepo, FamilyRepo, InviteRecord, InviteRepo, Role } from "../../ports/repositories";
import { getFeatures, type Features } from "../plan";
import { normalizeInviteCode } from "./inviteCode";

const INVITE_TTL_HOURS = 72;

export interface CreateInviteDeps {
  inviteRepo: InviteRepo;
  /** Family deletion's invite-revocation lookup (002 §2.1/§4.2, B19) — this task writes
   * the `invite:{code}` index row, never reads it back. */
  familyRepo: FamilyRepo;
  entitlementsRepo: EntitlementsRepo;
  inviteCodeGenerator: InviteCodeGenerator;
  clock: Clock;
}

export interface CreateInviteInput {
  uid: string;
  /** The caller's familyId from the resolved auth context (§1.5), null if no profile. */
  familyId: string | null;
  role: Role | null;
  body: unknown;
}

export interface CreateInviteResult {
  inviteCode: string;
  role: Role;
  expiresAt: string;
  features: Features;
}

export async function createInvite(input: CreateInviteInput, deps: CreateInviteDeps): Promise<CreateInviteResult> {
  if (!input.familyId) {
    throw new AppError("FAMILY_NOT_FOUND", "caller has no family");
  }
  if (input.role !== "parent") {
    throw new AppError("AUTH_FORBIDDEN", "only a parent may create invites");
  }
  const familyId = input.familyId;

  const body = parseOrThrow(createInviteRequestSchema, input.body);

  const entitlements = await deps.entitlementsRepo.get(familyId);
  if (!entitlements) {
    throw new AppError("INTERNAL_ERROR", "family has no entitlements record");
  }
  const features = getFeatures(entitlements.subscriptionStatus);

  const inviteCode = normalizeInviteCode(deps.inviteCodeGenerator.next());
  const now = deps.clock.now();
  const createdAt = now.toISOString();
  const expiresAt = new Date(now.getTime() + INVITE_TTL_HOURS * 60 * 60 * 1000).toISOString();

  const invite: InviteRecord = {
    inviteCode,
    familyId,
    role: body.role,
    emailHint: body.emailHint,
    createdBy: input.uid,
    createdAt,
    expiresAt,
  };
  await deps.inviteRepo.createInvite(invite);
  // Family-side index row, written AFTER the canonical row (001 §3.3, 002 §2.1): lets
  // family deletion (008 §5.3) find and revoke outstanding invites. The acceptance path
  // never reads it.
  await deps.familyRepo.addInviteIndexEntry(familyId, { code: inviteCode, expiresAt });

  return { inviteCode, role: body.role, expiresAt, features };
}
