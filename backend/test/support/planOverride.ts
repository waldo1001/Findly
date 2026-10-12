import { afterEach, beforeEach } from "vitest";
import { PLAN_MATRIX, type PlanLimits } from "../../src/domain/plan";

/**
 * Temporarily overrides FREE-plan limits (`PLAN_MATRIX.free` is the object `getFeatures`
 * spreads, and "active" aliases it) for the surrounding `describe` — restored after each test.
 * Used to exercise `maxGroupDurationDays` horizon logic now that the shipped free plan is
 * `null` (no cap, 001 §9) without ever hardcoding a literal at a call site.
 */
export function useLimitOverride(overrides: Partial<PlanLimits>): void {
  let saved: PlanLimits | null = null;
  beforeEach(() => {
    saved = { ...PLAN_MATRIX.free.limits };
    Object.assign(PLAN_MATRIX.free.limits, overrides);
  });
  afterEach(() => {
    if (saved) Object.assign(PLAN_MATRIX.free.limits, saved);
    saved = null;
  });
}
