// specs/011 §4.2, 002 §4.3 — the staleNudger run: gate, scan, claim-before-send, token hygiene,
// counts-only result.
import { describe, expect, it } from "vitest";
import { runStaleNudge, STALE_NUDGE_ENABLED_VALUE } from "../../../src/domain/device/staleNudge";
import { InMemoryDeviceRepo } from "../../fakes/inMemoryDeviceRepo";
import { FakePushSender } from "../../fakes/fakePushSender";
import { FixedClock } from "../../fakes/fixedClock";
import type { DeviceRecord } from "../../../src/ports/repositories";

const HOUR = 60 * 60_000;
const NOW = new Date("2026-10-07T10:00:00Z");
const ago = (ms: number) => new Date(NOW.getTime() - ms).toISOString();

function device(deviceId: string, overrides: Partial<DeviceRecord> = {}): DeviceRecord {
  return {
    deviceId,
    ownerUserId: "u1",
    platform: "ios",
    model: "iPhone",
    appVersion: "1.2.0",
    deviceName: "Eric's iPhone",
    pushToken: `tok-${deviceId}`,
    pushInvalid: false,
    syncIntervalMinutes: 15,
    trackingEnabled: true,
    registeredAt: ago(100 * HOUR),
    lastSeenAt: ago(3 * HOUR),
    staleNudgeEnabled: true,
    ...overrides,
  };
}

/** Reads carry a storage etag (002 §4.3); the assertions below are about the stored fields. */
async function stored(repo: InMemoryDeviceRepo, id: string) {
  const row = await repo.getDevice("u1", id);
  if (!row) return row;
  const { etag: _etag, ...fields } = row;
  return fields;
}

function setup() {
  const deviceRepo = new InMemoryDeviceRepo();
  const pushSender = new FakePushSender();
  const clock = new FixedClock(NOW);
  const run = (setting: string | undefined = STALE_NUDGE_ENABLED_VALUE) =>
    runStaleNudge({ deviceRepo, pushSender, clock, enabledSetting: setting });
  return { deviceRepo, pushSender, clock, run };
}

describe("runStaleNudge — gate (STALE_NUDGE_ENABLED must be exactly \"true\")", () => {
  it("the enabled value is the string \"true\"", () => {
    expect(STALE_NUDGE_ENABLED_VALUE).toBe("true");
  });

  it("an explicit undefined setting disables (default parameter must not kick in)", async () => {
    const { deviceRepo, pushSender } = setup();
    deviceRepo.seed("u1", device("d1"));
    const result = await runStaleNudge({
      deviceRepo,
      pushSender,
      clock: new FixedClock(NOW),
      enabledSetting: undefined,
    });
    expect(pushSender.sent).toHaveLength(0);
    expect(result.enabled).toBe(false);
  });

  it.each(["", "false", "TRUE", "True", "1", " true", "true "])(
    "setting %j -> nothing sent, nothing claimed",
    async (setting) => {
      const { deviceRepo, pushSender, run } = setup();
      deviceRepo.seed("u1", device("d1"));
      const result = await run(setting);
      expect(pushSender.sent).toHaveLength(0);
      expect((await deviceRepo.getDevice("u1", "d1"))?.lastNudgedAt).toBeUndefined();
      expect(result).toEqual({ enabled: false, evaluated: 0, due: 0, sent: 0, failed: 0, skipped: 0 });
    },
  );
});

describe("runStaleNudge — scan and send", () => {
  it("scans every owner's devices, nudges only the due ones, and counts", async () => {
    const { deviceRepo, pushSender, run } = setup();
    deviceRepo.seed("u1", device("due1"));
    deviceRepo.seed("u2", device("due2", { ownerUserId: "u2" }));
    deviceRepo.seed("u2", device("fresh", { ownerUserId: "u2", lastSeenAt: ago(HOUR) }));
    const result = await run();
    expect(pushSender.sent.map((m) => (m as { token: string }).token).sort()).toEqual(["tok-due1", "tok-due2"]);
    expect(result).toEqual({ enabled: true, evaluated: 3, due: 2, sent: 2, failed: 0, skipped: 0 });
  });

  it("sends a STALE_NUDGE message carrying only data.type", async () => {
    const { deviceRepo, pushSender, run } = setup();
    deviceRepo.seed("u1", device("d1"));
    await run();
    expect(pushSender.sent).toEqual([{ type: "STALE_NUDGE", token: "tok-d1", data: { type: "STALE_NUDGE" } }]);
  });

  it("claims lastNudgedAt = now, so a second run in the same window sends nothing", async () => {
    const { deviceRepo, pushSender, run } = setup();
    deviceRepo.seed("u1", device("d1"));
    await run();
    expect((await deviceRepo.getDevice("u1", "d1"))?.lastNudgedAt).toBe(NOW.toISOString());
    const second = await run();
    expect(pushSender.sent).toHaveLength(1);
    expect(second.due).toBe(0);
  });

  it("the claim happens BEFORE the send", async () => {
    const { deviceRepo, pushSender, run } = setup();
    deviceRepo.seed("u1", device("d1"));
    let claimedAtSend: string | undefined;
    const original = pushSender.send.bind(pushSender);
    pushSender.send = async (m) => {
      claimedAtSend = (await deviceRepo.getDevice("u1", "d1"))?.lastNudgedAt;
      return original(m);
    };
    await run();
    expect(claimedAtSend).toBe(NOW.toISOString());
  });

  it("the claim is a timestamp-only merge: no other stored field changes", async () => {
    const { deviceRepo, run } = setup();
    const before = device("d1", { deviceName: "Original", syncIntervalMinutes: 30 });
    deviceRepo.seed("u1", before);
    await run();
    expect(await stored(deviceRepo, "d1")).toEqual({ ...before, lastNudgedAt: NOW.toISOString() });
  });

  it("a device removed between scan and claim is not sent to and not resurrected", async () => {
    const { deviceRepo, pushSender, run } = setup();
    deviceRepo.seed("u1", device("d1"));
    const original = deviceRepo.listAllDevices.bind(deviceRepo);
    deviceRepo.listAllDevices = async () => {
      const rows = await original();
      await deviceRepo.deleteDevice("u1", "d1"); // concurrent DELETE /devices/{id} after the scan
      return rows;
    };
    const result = await run();
    expect(pushSender.sent).toHaveLength(0);
    expect(await deviceRepo.getDevice("u1", "d1")).toBeNull();
    expect(result).toEqual({ enabled: true, evaluated: 1, due: 1, sent: 0, failed: 0, skipped: 1 });
  });
});

describe("runStaleNudge — overlapping runs (002 §4.3 ETag-conditional claim)", () => {
  it("two runs that scanned the same version: exactly one claims and sends, the other skips", async () => {
    const { deviceRepo, pushSender, run } = setup();
    deviceRepo.seed("u1", device("d1"));
    const [a, b] = await Promise.all([run(), run()]);
    expect(pushSender.sent).toHaveLength(1);
    expect(a.sent + b.sent).toBe(1);
    expect(a.skipped + b.skipped).toBe(1);
  });

  it("sent + failed + skipped always equals due", async () => {
    const { deviceRepo, pushSender, run } = setup();
    deviceRepo.seed("u1", device("d1"));
    deviceRepo.seed("u1", device("d2"));
    deviceRepo.seed("u1", device("d3"));
    pushSender.setOutcome("error");
    const r = await run();
    expect(r.sent + r.failed + r.skipped).toBe(r.due);
  });

  it("a write between scan and claim (stale ETag) makes the claim lose: skipped, no send", async () => {
    const { deviceRepo, pushSender, run } = setup();
    deviceRepo.seed("u1", device("d1"));
    const original = deviceRepo.listAllDevices.bind(deviceRepo);
    deviceRepo.listAllDevices = async () => {
      const rows = await original();
      await deviceRepo.touchLastSeen("u1", "d1", ago(60_000)); // device calls in after the scan
      return rows;
    };
    const result = await run();
    expect(pushSender.sent).toHaveLength(0);
    expect(result.skipped).toBe(1);
  });
});

describe("runStaleNudge — outcomes (001 §8.5)", () => {
  it("invalidToken marks pushInvalid and nothing else, counted as failed", async () => {
    const { deviceRepo, pushSender, run } = setup();
    const before = device("d1");
    deviceRepo.seed("u1", before);
    pushSender.setOutcome("invalidToken");
    const result = await run();
    expect(await stored(deviceRepo, "d1")).toEqual({
      ...before,
      pushInvalid: true,
      lastNudgedAt: NOW.toISOString(),
    });
    expect(result).toEqual({ enabled: true, evaluated: 1, due: 1, sent: 0, failed: 1, skipped: 0 });
  });

  it("invalidToken on a device removed meanwhile does not resurrect it", async () => {
    const { deviceRepo, pushSender, run } = setup();
    deviceRepo.seed("u1", device("d1"));
    pushSender.setOutcome("invalidToken");
    const original = pushSender.send.bind(pushSender);
    pushSender.send = async (m) => {
      await deviceRepo.deleteDevice("u1", "d1");
      return original(m);
    };
    await run();
    expect(await deviceRepo.getDevice("u1", "d1")).toBeNull();
  });

  it("error outcome: counted failed, claim stays (no retry before 24 h), pushInvalid untouched", async () => {
    const { deviceRepo, pushSender, run } = setup();
    deviceRepo.seed("u1", device("d1"));
    pushSender.setOutcome("error");
    const result = await run();
    const row = await deviceRepo.getDevice("u1", "d1");
    expect(row?.pushInvalid).toBe(false);
    expect(row?.lastNudgedAt).toBe(NOW.toISOString());
    expect(result).toEqual({ enabled: true, evaluated: 1, due: 1, sent: 0, failed: 1, skipped: 0 });
  });

  it("a thrown transport failure is counted failed and does not stop the other devices", async () => {
    const { deviceRepo, pushSender, run } = setup();
    deviceRepo.seed("u1", device("d1"));
    deviceRepo.seed("u1", device("d2"));
    let calls = 0;
    pushSender.send = async (m) => {
      calls += 1;
      if (calls === 1) throw new Error("boom");
      pushSender.sent.push(m);
      return "ok";
    };
    const result = await run();
    expect(result).toEqual({ enabled: true, evaluated: 2, due: 2, sent: 1, failed: 1, skipped: 0 });
  });

  it("the result carries counts only", async () => {
    const { deviceRepo, run } = setup();
    deviceRepo.seed("u1", device("d1"));
    const result = await run();
    expect(Object.keys(result).sort()).toEqual(["due", "enabled", "evaluated", "failed", "sent", "skipped"]);
  });
});
