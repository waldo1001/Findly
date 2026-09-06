import { describe, expect, it } from "vitest";
import { LAST_SEEN_WRITE_SKIP_MS, shouldRefreshLastSeen } from "../../../src/domain/device/lastSeenPolicy";

describe("domain/device/lastSeenPolicy", () => {
  it("skips the write when less than a minute has passed since the last recorded lastSeenAt", async () => {
    const lastSeenAt = "2026-07-19T09:00:00.000Z";
    const now = new Date("2026-07-19T09:00:59.999Z"); // 59.999s later

    expect(shouldRefreshLastSeen(lastSeenAt, now)).toBe(false);
  });

  it("refreshes exactly at the one-minute boundary (>= the skip window, not only >)", () => {
    const lastSeenAt = "2026-07-19T09:00:00.000Z";
    const now = new Date("2026-07-19T09:01:00.000Z"); // exactly 60s later

    expect(shouldRefreshLastSeen(lastSeenAt, now)).toBe(true);
  });

  it("refreshes when well over a minute has passed", () => {
    const lastSeenAt = "2026-07-19T09:00:00.000Z";
    const now = new Date("2026-07-19T09:05:00.000Z");

    expect(shouldRefreshLastSeen(lastSeenAt, now)).toBe(true);
  });

  it("exposes the skip window as exactly one minute", () => {
    expect(LAST_SEEN_WRITE_SKIP_MS).toBe(60_000);
  });
});
