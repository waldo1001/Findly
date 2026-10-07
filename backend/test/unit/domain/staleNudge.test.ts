// specs/011 §4.1 — the seven eligibility conditions of the stale nudge, each at its boundary.
import { describe, expect, it } from "vitest";
import {
  NUDGE_MAX_SYNC_INTERVAL_MINUTES,
  NUDGE_QUIET_MINUTES,
  isNudgeDue,
  type NudgeCandidate,
} from "../../../src/domain/device/staleNudge";

const MIN = 60_000;
const HOUR = 60 * MIN;
const DAY = 24 * HOUR;
// 2026-10-07 10:00Z = 12:00 Europe/Brussels (CEST) — comfortably inside the quiet-hours window.
const NOW = new Date("2026-10-07T10:00:00Z");
const ago = (ms: number, now: Date = NOW) => new Date(now.getTime() - ms).toISOString();

function dev(overrides: Partial<NudgeCandidate> = {}, now: Date = NOW): NudgeCandidate {
  return {
    trackingEnabled: true,
    syncIntervalMinutes: 15,
    staleNudgeEnabled: true,
    pushToken: "tok",
    pushInvalid: false,
    registeredAt: ago(30 * DAY, now),
    lastSeenAt: ago(3 * HOUR, now),
    ...overrides,
  };
}

describe("domain/device/staleNudge constants", () => {
  it("pins the 011 §4.1 numbers", () => {
    expect(NUDGE_MAX_SYNC_INTERVAL_MINUTES).toBe(30);
    expect(NUDGE_QUIET_MINUTES).toBe(120);
  });
});

describe("isNudgeDue — baseline", () => {
  it("a quiet presence device inside the window with no prior nudge is due", () => {
    expect(isNudgeDue(dev(), NOW)).toBe(true);
  });
});

describe("isNudgeDue — condition 1: presence device (tracking on, interval <= 30)", () => {
  it("tracking disabled -> not due", () => {
    expect(isNudgeDue(dev({ trackingEnabled: false }), NOW)).toBe(false);
  });
  it.each([5, 15, 30])("interval %i is eligible", (syncIntervalMinutes) => {
    expect(isNudgeDue(dev({ syncIntervalMinutes }), NOW)).toBe(true);
  });
  it.each([31, 60, 120])("interval %i is never eligible", (syncIntervalMinutes) => {
    expect(isNudgeDue(dev({ syncIntervalMinutes }), NOW)).toBe(false);
  });
  it("the quiet threshold is the same 120 min at interval 5 and 30", () => {
    for (const syncIntervalMinutes of [5, 30]) {
      expect(isNudgeDue(dev({ syncIntervalMinutes, lastSeenAt: ago(120 * MIN) }), NOW)).toBe(false);
      expect(isNudgeDue(dev({ syncIntervalMinutes, lastSeenAt: ago(120 * MIN + 1) }), NOW)).toBe(true);
    }
  });
});

describe("isNudgeDue — condition 2: staleNudgeEnabled", () => {
  it("false -> not due", () => {
    expect(isNudgeDue(dev({ staleNudgeEnabled: false }), NOW)).toBe(false);
  });
  it("true -> due", () => {
    expect(isNudgeDue(dev({ staleNudgeEnabled: true }), NOW)).toBe(true);
  });
  it("absent reads as true (002 §2.4)", () => {
    const { staleNudgeEnabled: _omit, ...rest } = dev();
    expect(isNudgeDue(rest, NOW)).toBe(true);
  });
});

describe("isNudgeDue — condition 3: valid push token", () => {
  it("no token -> not due", () => {
    const { pushToken: _omit, ...rest } = dev();
    expect(isNudgeDue(rest, NOW)).toBe(false);
  });
  it("empty token -> not due", () => {
    expect(isNudgeDue(dev({ pushToken: "" }), NOW)).toBe(false);
  });
  it("pushInvalid -> not due", () => {
    expect(isNudgeDue(dev({ pushInvalid: true }), NOW)).toBe(false);
  });
});

describe("isNudgeDue — condition 4: quiet strictly > 120 min on lastSeenAt ?? registeredAt", () => {
  it("exactly 120 min -> not due", () => {
    expect(isNudgeDue(dev({ lastSeenAt: ago(120 * MIN) }), NOW)).toBe(false);
  });
  it("120 min + 1 ms -> due", () => {
    expect(isNudgeDue(dev({ lastSeenAt: ago(120 * MIN + 1) }), NOW)).toBe(true);
  });
  it("recently seen -> not due", () => {
    expect(isNudgeDue(dev({ lastSeenAt: ago(MIN) }), NOW)).toBe(false);
  });
  it("absent lastSeenAt falls back to registeredAt (quiet)", () => {
    const { lastSeenAt: _omit, ...rest } = dev({ registeredAt: ago(3 * HOUR) });
    expect(isNudgeDue(rest, NOW)).toBe(true);
  });
  it("absent lastSeenAt falls back to registeredAt (fresh registration -> not due)", () => {
    const { lastSeenAt: _omit, ...rest } = dev({ registeredAt: ago(10 * MIN) });
    expect(isNudgeDue(rest, NOW)).toBe(false);
  });
  it("lastSeenAt wins over an ancient registeredAt", () => {
    expect(isNudgeDue(dev({ registeredAt: ago(3 * DAY), lastSeenAt: ago(MIN) }), NOW)).toBe(false);
  });
});

describe("isNudgeDue — condition 5: given up after 7 days (<= 7 d)", () => {
  it("exactly 7 days quiet -> due", () => {
    expect(isNudgeDue(dev({ lastSeenAt: ago(7 * DAY) }), NOW)).toBe(true);
  });
  it("7 days + 1 ms quiet -> not due", () => {
    expect(isNudgeDue(dev({ lastSeenAt: ago(7 * DAY + 1) }), NOW)).toBe(false);
  });
  it("the cap also applies to the registeredAt fallback", () => {
    const { lastSeenAt: _omit, ...rest } = dev({ registeredAt: ago(7 * DAY + 1) });
    expect(isNudgeDue(rest, NOW)).toBe(false);
  });
});

describe("isNudgeDue — condition 6: rate limit (lastNudgedAt absent or >= 24 h)", () => {
  it("absent -> due", () => {
    expect(isNudgeDue(dev(), NOW)).toBe(true);
  });
  it("nudged 24 h - 1 ms ago -> not due", () => {
    expect(isNudgeDue(dev({ lastNudgedAt: ago(DAY - 1) }), NOW)).toBe(false);
  });
  it("nudged exactly 24 h ago -> due", () => {
    expect(isNudgeDue(dev({ lastNudgedAt: ago(DAY) }), NOW)).toBe(true);
  });
  it("nudged long ago -> due", () => {
    expect(isNudgeDue(dev({ lastNudgedAt: ago(3 * DAY) }), NOW)).toBe(true);
  });
});

describe("isNudgeDue — condition 7: [08:00, 21:00) Europe/Brussels, across both DST transitions", () => {
  // [label, UTC instant, expected]. Each row is at a window edge for the offset in force that day.
  const cases: Array<[string, string, boolean]> = [
    // Winter (CET, UTC+1)
    ["winter 07:59:59 local", "2026-01-15T06:59:59Z", false],
    ["winter 08:00:00 local", "2026-01-15T07:00:00Z", true],
    ["winter 20:59:59 local", "2026-01-15T19:59:59Z", true],
    ["winter 21:00:00 local", "2026-01-15T20:00:00Z", false],
    // Summer (CEST, UTC+2)
    ["summer 07:59:59 local", "2026-07-15T05:59:59Z", false],
    ["summer 08:00:00 local", "2026-07-15T06:00:00Z", true],
    ["summer 20:59:59 local", "2026-07-15T18:59:59Z", true],
    ["summer 21:00:00 local", "2026-07-15T19:00:00Z", false],
    // Spring-forward 2026-03-29 (01:00Z). Day before: CET.
    ["day before spring DST, 07:59:59 local", "2026-03-28T06:59:59Z", false],
    ["day before spring DST, 08:00 local", "2026-03-28T07:00:00Z", true],
    ["day before spring DST, 20:59:59 local", "2026-03-28T19:59:59Z", true],
    ["day before spring DST, 21:00 local", "2026-03-28T20:00:00Z", false],
    // Transition day itself, after the switch: CEST.
    ["spring DST day, 07:59:59 local", "2026-03-29T05:59:59Z", false],
    ["spring DST day, 08:00 local", "2026-03-29T06:00:00Z", true],
    ["spring DST day, 20:59:59 local", "2026-03-29T18:59:59Z", true],
    ["spring DST day, 21:00 local", "2026-03-29T19:00:00Z", false],
    // Day after: CEST.
    ["day after spring DST, 07:59:59 local", "2026-03-30T05:59:59Z", false],
    ["day after spring DST, 08:00 local", "2026-03-30T06:00:00Z", true],
    // Fall-back 2026-10-25 (01:00Z). Day before: CEST.
    ["day before autumn DST, 07:59:59 local", "2026-10-24T05:59:59Z", false],
    ["day before autumn DST, 08:00 local", "2026-10-24T06:00:00Z", true],
    ["day before autumn DST, 20:59:59 local", "2026-10-24T18:59:59Z", true],
    ["day before autumn DST, 21:00 local", "2026-10-24T19:00:00Z", false],
    // Transition day, after the switch: CET.
    ["autumn DST day, 07:59:59 local", "2026-10-25T06:59:59Z", false],
    ["autumn DST day, 08:00 local", "2026-10-25T07:00:00Z", true],
    ["autumn DST day, 20:59:59 local", "2026-10-25T19:59:59Z", true],
    ["autumn DST day, 21:00 local", "2026-10-25T20:00:00Z", false],
    // Day after: CET.
    ["day after autumn DST, 07:59:59 local", "2026-10-26T06:59:59Z", false],
    ["day after autumn DST, 08:00 local", "2026-10-26T07:00:00Z", true],
    // Deep night / midday sanity.
    ["local midnight", "2026-07-14T22:00:00Z", false],
    ["local noon", "2026-07-15T10:00:00Z", true],
  ];
  it.each(cases)("%s (%s) -> %s", (_label, iso, expected) => {
    const now = new Date(iso);
    expect(isNudgeDue(dev({}, now), now)).toBe(expected);
  });
});

describe("isNudgeDue — conditions are independent", () => {
  it("a device failing two conditions is still not due", () => {
    expect(isNudgeDue(dev({ pushInvalid: true, trackingEnabled: false }), NOW)).toBe(false);
  });
});

describe("isNudgeDue — a corrupt stored timestamp fails closed (no nudge)", () => {
  it("unparseable lastSeenAt", () => {
    expect(isNudgeDue(dev({ lastSeenAt: "not-a-date" }), NOW)).toBe(false);
  });
  it("unparseable registeredAt when lastSeenAt is absent", () => {
    const { lastSeenAt: _omit, ...rest } = dev({ registeredAt: "garbage" });
    expect(isNudgeDue(rest, NOW)).toBe(false);
  });
  it("unparseable lastNudgedAt", () => {
    expect(isNudgeDue(dev({ lastNudgedAt: "garbage" }), NOW)).toBe(false);
  });
});
