// specs/001 §1.5 — auth context resolution, performed on every request.

import { AppError } from "./errors";
import { TokenExpiredError, TokenInvalidError, type TokenVerifier } from "../ports/tokenVerifier";
import type { Role, UsageRepo, UserRepo } from "../ports/repositories";
import type { Clock } from "../ports/support";

export interface AuthContext {
  uid: string;
  familyId: string | null;
  role: Role | null;
}

export interface AuthGuardDeps {
  tokenVerifier: TokenVerifier;
  userRepo: UserRepo;
  usageRepo: UsageRepo;
  clock: Clock;
}

export interface AuthGuardOptions {
  /**
   * True for the four §1.5.3 profile-bootstrapping endpoints — POST /families,
   * POST /invites/accept, POST /groups, POST /groups/join (§1.5 step 3) — PLUS
   * DELETE /users/me (§13.2, B18): the one non-bootstrapping endpoint the §1.5.3 allowance
   * also names, since account deletion must be an idempotent no-op for a caller with no
   * profile at all (008 §4.1) rather than a 404. Every other endpoint without a profile gets
   * PROFILE_NOT_FOUND.
   */
  allowNoProfile?: boolean;
}

const BEARER_PREFIX = "Bearer ";

function usageDate(now: Date): string {
  return now.toISOString().slice(0, 10);
}

/**
 * Resolves {uid, familyId, role} from the Authorization header (§1.5 steps 1-3).
 * Role checks against the endpoint's required role (§1.6) are the caller's responsibility.
 *
 * specs/001 §9 (B14) — apiCalls increments exactly once here, immediately after token
 * verification succeeds (the actual "authenticated" boundary), regardless of what happens
 * afterward: a later 2xx, a business-reason 4xx from the domain layer, or even the
 * PROFILE_NOT_FOUND thrown a few lines below. This is the single call site for the whole
 * backend — every domain use-case used to increment this on its own success path only,
 * which under-counted any authenticated request that failed for a business reason. A 401
 * (thrown above, before this point) never increments. The familyId-or-uid partition rule is
 * unchanged (002 §2.9): familyId when the caller has one, else their own uid — including the
 * moment a not-yet-bootstrapped caller (no profile at all) hits one of the four §1.5.3
 * bootstrap endpoints, where uid is all that's known yet.
 */
export async function authenticate(
  authorizationHeader: string | undefined | null,
  deps: AuthGuardDeps,
  options: AuthGuardOptions = {},
): Promise<AuthContext> {
  if (!authorizationHeader || !authorizationHeader.startsWith(BEARER_PREFIX)) {
    throw new AppError("AUTH_MISSING_TOKEN", "missing or malformed Authorization header");
  }
  const token = authorizationHeader.slice(BEARER_PREFIX.length).trim();
  if (!token) {
    throw new AppError("AUTH_MISSING_TOKEN", "missing bearer token");
  }

  let uid: string;
  try {
    const verified = await deps.tokenVerifier.verify(token);
    uid = verified.uid;
  } catch (err) {
    if (err instanceof TokenExpiredError) {
      throw new AppError("AUTH_TOKEN_EXPIRED", "token expired");
    }
    if (err instanceof TokenInvalidError) {
      throw new AppError("AUTH_INVALID_TOKEN", err.message);
    }
    throw new AppError("AUTH_INVALID_TOKEN", "token verification failed");
  }

  const profile = await deps.userRepo.getProfile(uid);
  const usagePartition = profile?.familyId ?? uid;
  await deps.usageRepo.increment(usagePartition, "apiCalls", usageDate(deps.clock.now()));

  if (!profile) {
    if (options.allowNoProfile) {
      return { uid, familyId: null, role: null };
    }
    throw new AppError("PROFILE_NOT_FOUND", "caller has no profile");
  }
  return { uid, familyId: profile.familyId, role: profile.role };
}
