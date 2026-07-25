import { describe, expect, it } from "vitest";
import { getFeatures, PLAN_MATRIX } from "../../../src/domain/plan";

// specs/001 §9 — hardcoded expectations (not derived from PLAN_MATRIX) so mutation
// testing actually kills literal-flip mutants in plan.ts, per §11's own test checklist.
describe("domain/plan", () => {
  it("derives free-tier features exactly as specified in 001 §9", () => {
    expect(getFeatures("free")).toEqual({
      subscriptionStatus: "free",
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
    });
  });

  it('"active" currently mirrors "free" benefits (reserved placeholder, 001 §9)', () => {
    const active = getFeatures("active");
    const free = getFeatures("free");

    expect(active.limits).toEqual(free.limits);
    expect(active.flags).toEqual(free.flags);
    expect(PLAN_MATRIX.active).toBe(PLAN_MATRIX.free);
  });
});
