import { describe, expect, it } from "vitest";
import { deriveGroupState } from "../../../src/domain/group/groupState";

// specs/005 §2.2 — the derived-state pure function. Boundary mutants (< vs <=, etc.) MUST
// be killed here: exactly `endsAt`, exactly `graceUntil`, all three policies.
describe("domain/group/groupState deriveGroupState", () => {
  const ENDS_AT = new Date("2026-08-02T22:00:00Z");
  const GRACE_DAYS = 7;

  it("is active strictly before endsAt, for every policy", () => {
    const before = new Date(ENDS_AT.getTime() - 1000);
    expect(deriveGroupState(before, ENDS_AT.toISOString(), "delete", GRACE_DAYS)).toBe("active");
    expect(deriveGroupState(before, ENDS_AT.toISOString(), "grace", GRACE_DAYS)).toBe("active");
    expect(deriveGroupState(before, ENDS_AT.toISOString(), "archive", GRACE_DAYS)).toBe("active");
  });

  it("delete policy: exactly at endsAt is expired (not active)", () => {
    expect(deriveGroupState(ENDS_AT, ENDS_AT.toISOString(), "delete", GRACE_DAYS)).toBe("expired");
  });

  it("delete policy: after endsAt is expired", () => {
    const after = new Date(ENDS_AT.getTime() + 1000);
    expect(deriveGroupState(after, ENDS_AT.toISOString(), "delete", GRACE_DAYS)).toBe("expired");
  });

  it("grace policy: exactly at endsAt is ended (not active, not expired)", () => {
    expect(deriveGroupState(ENDS_AT, ENDS_AT.toISOString(), "grace", GRACE_DAYS)).toBe("ended");
  });

  it("grace policy: just before graceUntil is still ended", () => {
    const graceUntil = new Date(ENDS_AT.getTime() + GRACE_DAYS * 24 * 60 * 60 * 1000);
    const justBefore = new Date(graceUntil.getTime() - 1000);
    expect(deriveGroupState(justBefore, ENDS_AT.toISOString(), "grace", GRACE_DAYS)).toBe("ended");
  });

  it("grace policy: exactly at graceUntil is expired (not ended)", () => {
    const graceUntil = new Date(ENDS_AT.getTime() + GRACE_DAYS * 24 * 60 * 60 * 1000);
    expect(deriveGroupState(graceUntil, ENDS_AT.toISOString(), "grace", GRACE_DAYS)).toBe("expired");
  });

  it("grace policy: after graceUntil is expired", () => {
    const graceUntil = new Date(ENDS_AT.getTime() + GRACE_DAYS * 24 * 60 * 60 * 1000);
    const after = new Date(graceUntil.getTime() + 1000);
    expect(deriveGroupState(after, ENDS_AT.toISOString(), "grace", GRACE_DAYS)).toBe("expired");
  });

  it("archive policy: exactly at endsAt is archived", () => {
    expect(deriveGroupState(ENDS_AT, ENDS_AT.toISOString(), "archive", GRACE_DAYS)).toBe("archived");
  });

  it("archive policy: long after endsAt stays archived (never expires)", () => {
    const farFuture = new Date(ENDS_AT.getTime() + 365 * 24 * 60 * 60 * 1000);
    expect(deriveGroupState(farFuture, ENDS_AT.toISOString(), "archive", GRACE_DAYS)).toBe("archived");
  });

  it("grace policy honors a different groupGraceDays value (owner-plan-derived)", () => {
    const shortGrace = 1;
    const graceUntil = new Date(ENDS_AT.getTime() + shortGrace * 24 * 60 * 60 * 1000);
    const justBefore = new Date(graceUntil.getTime() - 1000);
    expect(deriveGroupState(justBefore, ENDS_AT.toISOString(), "grace", shortGrace)).toBe("ended");
    expect(deriveGroupState(graceUntil, ENDS_AT.toISOString(), "grace", shortGrace)).toBe("expired");
  });

  // specs/005 §2.2/§2.5 — endsAt null = no end date: always active, whatever the policy,
  // however far `now` is in the future.
  it("endsAt null is active for every policy (no end date, 005 §2.5)", () => {
    const farFuture = new Date("2099-01-01T00:00:00Z");
    expect(deriveGroupState(farFuture, null, "delete", GRACE_DAYS)).toBe("active");
    expect(deriveGroupState(farFuture, null, "grace", GRACE_DAYS)).toBe("active");
    expect(deriveGroupState(farFuture, null, "archive", GRACE_DAYS)).toBe("active");
  });
});
