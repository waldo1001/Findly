// specs/001 §13.2, specs/002 §4.2 (B18) — the table-adapter mechanics account deletion
// depends on: LastKnown/IdempotencyMarkers partition wipes, LocateRequests' OData `or`
// filter (requestedBy OR targetUserId), and Users.deleteProfile's idempotent not-found
// swallow. Requires Azurite (`npm run dev:storage`); run via `npm run test:integration`.

import { beforeAll, describe, expect, it } from "vitest";
import { ensureTables } from "./support/ensureStorage";
import { testFamilyId, testUserId } from "./support/ids";
import { TableLastKnownRepo } from "../../src/adapters/tables/lastKnownTableRepo";
import { TableIdempotencyRepo } from "../../src/adapters/tables/idempotencyMarkersTableRepo";
import { TableLocateRequestRepo } from "../../src/adapters/tables/locateRequestsTableRepo";
import { TableUserRepo } from "../../src/adapters/tables/usersTableRepo";
import type { LastKnownRecord, LocateRequestRecord } from "../../src/ports/repositories";

function lastKnown(overrides: Partial<LastKnownRecord> = {}): LastKnownRecord {
  return {
    deviceId: "device-1",
    lat: 51.0543,
    lon: 3.7174,
    accuracyM: 12.5,
    batteryPct: 78,
    recordedAt: "2026-07-19T09:00:00Z",
    receivedAt: "2026-07-19T09:00:02Z",
    source: "periodic",
    ...overrides,
  };
}

function locateRequest(overrides: Partial<LocateRequestRecord> = {}): LocateRequestRecord {
  return {
    requestId: "lr_00000000000000000001",
    familyId: "fam_placeholder",
    targetUserId: "target",
    targetDeviceId: "device-1",
    requestedBy: "requester",
    status: "pending",
    createdAt: "2026-07-19T08:00:00Z",
    expiresAt: "2026-07-19T08:01:00Z",
    ...overrides,
  };
}

describe("integration/account-deletion adapters (specs/001 §13.2, 002 §4.2, B18)", () => {
  beforeAll(async () => {
    await ensureTables("LastKnown", "IdempotencyMarkers", "LocateRequests", "Users");
  }, 30_000);

  it("LastKnownRepo.deleteByOwner wipes the owner's whole partition, leaving another owner untouched", async () => {
    const repo = new TableLastKnownRepo();
    const subject = testUserId();
    const other = testUserId();
    await repo.upsertIfNewer(subject, lastKnown({ deviceId: "device-a" }));
    await repo.upsertIfNewer(subject, lastKnown({ deviceId: "device-b" }));
    await repo.upsertIfNewer(other, lastKnown({ deviceId: "device-c" }));

    await repo.deleteByOwner(subject);

    expect(await repo.listByOwner(subject)).toEqual([]);
    expect(await repo.listByOwner(other)).toHaveLength(1);
  });

  it("LastKnownRepo.deleteByOwner is idempotent (a second call on an already-empty partition is a no-op)", async () => {
    const repo = new TableLastKnownRepo();
    const subject = testUserId();

    await expect(repo.deleteByOwner(subject)).resolves.toBeUndefined();
    await expect(repo.deleteByOwner(subject)).resolves.toBeUndefined();
  });

  it("IdempotencyRepo.deletePartition wipes every batch:/event:/fix: row for one deviceId, leaving another device untouched", async () => {
    const repo = new TableIdempotencyRepo();
    const subjectDevice = `device_${testUserId()}`;
    const otherDevice = `device_${testUserId()}`;
    await repo.tryInsertBatchMarker(subjectDevice, "batch-1", { receivedAt: "2026-07-19T08:00:00Z", fixCount: 1 });
    await repo.tryInsertEventMarker(subjectDevice, "evt-1", "2026-07-19T08:00:00Z");
    await repo.tryInsertFixMarker(subjectDevice, "fix-1", "2026-07-19T08:00:00Z");
    await repo.tryInsertBatchMarker(otherDevice, "batch-2", { receivedAt: "2026-07-19T08:00:00Z", fixCount: 1 });

    await repo.deletePartition(subjectDevice);

    // Re-insertable now (gone) for the subject's device...
    expect(await repo.tryInsertBatchMarker(subjectDevice, "batch-1", { receivedAt: "x", fixCount: 1 })).toBe(true);
    expect(await repo.tryInsertEventMarker(subjectDevice, "evt-1", "x")).toBe(true);
    expect(await repo.tryInsertFixMarker(subjectDevice, "fix-1", "x")).toBe(true);
    // ...but the other device's marker survives untouched.
    expect(await repo.tryInsertBatchMarker(otherDevice, "batch-2", { receivedAt: "x", fixCount: 1 })).toBe(false);
  });

  it("IdempotencyRepo.deletePartition is idempotent (a second call on an already-empty partition is a no-op)", async () => {
    const repo = new TableIdempotencyRepo();
    const device = `device_${testUserId()}`;

    await expect(repo.deletePartition(device)).resolves.toBeUndefined();
    await expect(repo.deletePartition(device)).resolves.toBeUndefined();
  });

  it("LocateRequestRepo.deleteRowsForUser deletes rows naming the subject as EITHER requestedBy OR targetUserId, leaving a row naming neither", async () => {
    const repo = new TableLocateRequestRepo();
    const familyId = testFamilyId();
    const subject = testUserId();
    const other = testUserId();
    const third = testUserId();

    await repo.create(locateRequest({ requestId: "lr_00000000000000000001", familyId, requestedBy: subject, targetUserId: other }));
    await repo.create(locateRequest({ requestId: "lr_00000000000000000002", familyId, requestedBy: other, targetUserId: subject }));
    await repo.create(locateRequest({ requestId: "lr_00000000000000000003", familyId, requestedBy: other, targetUserId: third }));

    await repo.deleteRowsForUser(familyId, subject);

    expect(await repo.get(familyId, "lr_00000000000000000001")).toBeNull();
    expect(await repo.get(familyId, "lr_00000000000000000002")).toBeNull();
    expect(await repo.get(familyId, "lr_00000000000000000003")).not.toBeNull();
  });

  it("LocateRequestRepo.deleteRowsForUser is idempotent (a second call after already-clean is a no-op)", async () => {
    const repo = new TableLocateRequestRepo();
    const familyId = testFamilyId();
    const subject = testUserId();

    await expect(repo.deleteRowsForUser(familyId, subject)).resolves.toBeUndefined();
    await expect(repo.deleteRowsForUser(familyId, subject)).resolves.toBeUndefined();
  });

  it("UserRepo.deleteProfile is idempotent — calling it again after the row is already gone does not throw (001 §13.2, 002 §4.2 step 8)", async () => {
    const repo = new TableUserRepo();
    const userId = testUserId();
    await repo.createProfile(userId, { familyId: null, role: null, displayName: "Eric" });

    await repo.deleteProfile(userId);
    expect(await repo.getProfile(userId)).toBeNull();

    await expect(repo.deleteProfile(userId)).resolves.toBeUndefined();
  });

  it("UserRepo.deleteProfile is a no-op for a userId that never had a profile row at all", async () => {
    const repo = new TableUserRepo();
    const userId = testUserId();

    await expect(repo.deleteProfile(userId)).resolves.toBeUndefined();
  });
});
