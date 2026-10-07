// specs/001 §5.2, 011 §2 — dormant = now − (lastSeenAt ?? registeredAt) > 30 days.
import { describe, expect, it } from "vitest";
import { DORMANT_AFTER_DAYS, isDormant } from "../../../src/domain/device/dormancy";

const DAY_MS = 24 * 60 * 60 * 1000;
const NOW = new Date("2026-10-07T12:00:00Z");
const ago = (ms: number) => new Date(NOW.getTime() - ms).toISOString();

describe("domain/device/dormancy", () => {
  it("DORMANT_AFTER_DAYS is 30", () => {
    expect(DORMANT_AFTER_DAYS).toBe(30);
  });

  it("exactly 30 days of silence is NOT dormant", () => {
    expect(isDormant({ lastSeenAt: ago(30 * DAY_MS), registeredAt: ago(90 * DAY_MS) }, NOW)).toBe(false);
  });

  it("one millisecond past 30 days IS dormant", () => {
    expect(isDormant({ lastSeenAt: ago(30 * DAY_MS + 1), registeredAt: ago(90 * DAY_MS) }, NOW)).toBe(true);
  });

  it("a recent lastSeenAt is not dormant even when registeredAt is ancient", () => {
    expect(isDormant({ lastSeenAt: ago(DAY_MS), registeredAt: ago(400 * DAY_MS) }, NOW)).toBe(false);
  });

  it("an absent lastSeenAt falls back to registeredAt (not dormant when recent)", () => {
    expect(isDormant({ registeredAt: ago(29 * DAY_MS) }, NOW)).toBe(false);
  });

  it("an absent lastSeenAt falls back to registeredAt (dormant when old)", () => {
    expect(isDormant({ registeredAt: ago(31 * DAY_MS) }, NOW)).toBe(true);
  });

  it("a lastSeenAt in the future is not dormant", () => {
    expect(isDormant({ lastSeenAt: ago(-DAY_MS), registeredAt: ago(90 * DAY_MS) }, NOW)).toBe(false);
  });
});
