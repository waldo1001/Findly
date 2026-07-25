// specs/002 §4.2 (normative), specs/008 §9 (B20) — "not-found" includes the table or
// container never having been created. This is the live production bug: `DELETE
// /api/v1/users/me` 500ed with `TableNotFound` against a storage account with zero
// application tables, because every erasure sequence is list-then-delete and it is the
// LISTING that throws first — the per-row delete's own not-found tolerance never gets a
// chance to help.
//
// Neither existing test layer can catch this: the in-memory fakes (test/fakes/) have no
// concept of a missing table at all, and every OTHER integration test file's `beforeAll`
// creates its tables/containers before any test runs, masking exactly this bug. This file
// deliberately does the opposite — it deletes a table/container the adapter under test
// depends on, immediately before calling it, and asserts the call still succeeds.
//
// Requires Azurite (`npm run dev:storage`); run via `npm run test:integration`. Runs with
// `fileParallelism: false` (vitest.integration.config.ts) — deleting a table/container that
// OTHER files' `beforeAll` hooks also depend on would otherwise race their parallel use of
// the same shared table name.

import { beforeAll, describe, expect, it } from "vitest";
import { dropContainers, dropTables, ensureContainers, ensureTables } from "./support/ensureStorage";
import { testDeviceId, testFamilyId, testGroupId, testRequestId, testUserId } from "./support/ids";
import { FixedClock } from "../fakes/fixedClock";
import type { LocateRequestRecord } from "../../src/ports/repositories";

import { deleteAccount, type DeleteAccountDeps } from "../../src/domain/user/deleteAccount";
import { deleteFamilyFootprint, type DeleteFamilyFootprintDeps } from "../../src/domain/family/familyDeletion";
import { hardDeleteGroupFootprint } from "../../src/domain/group/groupDeletion";
import { sweepGroups, type SweepGroupsDeps } from "../../src/domain/group/groupSweeper";
import { exportUserData, type ExportDataDeps } from "../../src/domain/export/exportUserData";

import { TableFamilyRepo } from "../../src/adapters/tables/familiesTableRepo";
import { TableUserRepo } from "../../src/adapters/tables/usersTableRepo";
import { TableEntitlementsRepo } from "../../src/adapters/tables/entitlementsTableRepo";
import { TableUsageRepo } from "../../src/adapters/tables/usageTableRepo";
import { TableDeviceRepo } from "../../src/adapters/tables/devicesTableRepo";
import { TableLastKnownRepo } from "../../src/adapters/tables/lastKnownTableRepo";
import { TableIdempotencyRepo } from "../../src/adapters/tables/idempotencyMarkersTableRepo";
import { TableInviteRepo } from "../../src/adapters/tables/invitesTableRepo";
import { TableLocateRequestRepo } from "../../src/adapters/tables/locateRequestsTableRepo";
import { TableGroupRepo } from "../../src/adapters/tables/groupsTableRepo";
import { TableGroupCodeRepo } from "../../src/adapters/tables/groupCodesTableRepo";
import { TableGroupLastKnownRepo } from "../../src/adapters/tables/groupLastKnownTableRepo";
import { TableGroupExpiryRepo } from "../../src/adapters/tables/groupExpiryTableRepo";
import { BlobHistoryStore } from "../../src/adapters/blobs/historyBlobStore";
import { BlobGeofenceConfigRepo } from "../../src/adapters/blobs/geofenceConfigBlobRepo";

function buildAccountDeletionDeps(): DeleteAccountDeps {
  return {
    familyRepo: new TableFamilyRepo(),
    userRepo: new TableUserRepo(),
    inviteRepo: new TableInviteRepo(),
    entitlementsRepo: new TableEntitlementsRepo(),
    usageRepo: new TableUsageRepo(),
    locateRequestRepo: new TableLocateRequestRepo(),
    historyStore: new BlobHistoryStore(),
    geofenceConfigRepo: new BlobGeofenceConfigRepo(),
    deviceRepo: new TableDeviceRepo(),
    lastKnownRepo: new TableLastKnownRepo(),
    idempotencyRepo: new TableIdempotencyRepo(),
    groupRepo: new TableGroupRepo(),
    groupCodeRepo: new TableGroupCodeRepo(),
    groupLastKnownRepo: new TableGroupLastKnownRepo(),
    groupExpiryRepo: new TableGroupExpiryRepo(),
  };
}

function buildFamilyDeletionDeps(): DeleteFamilyFootprintDeps {
  return {
    familyRepo: new TableFamilyRepo(),
    userRepo: new TableUserRepo(),
    inviteRepo: new TableInviteRepo(),
    entitlementsRepo: new TableEntitlementsRepo(),
    usageRepo: new TableUsageRepo(),
    locateRequestRepo: new TableLocateRequestRepo(),
    historyStore: new BlobHistoryStore(),
    geofenceConfigRepo: new BlobGeofenceConfigRepo(),
  };
}

function buildSweepDeps(now: Date): SweepGroupsDeps {
  return {
    groupExpiryRepo: new TableGroupExpiryRepo(),
    groupRepo: new TableGroupRepo(),
    groupCodeRepo: new TableGroupCodeRepo(),
    groupLastKnownRepo: new TableGroupLastKnownRepo(),
    userRepo: new TableUserRepo(),
    entitlementsRepo: new TableEntitlementsRepo(),
    clock: new FixedClock(now),
  };
}

function buildExportDeps(now: Date): ExportDataDeps {
  return {
    userRepo: new TableUserRepo(),
    familyRepo: new TableFamilyRepo(),
    deviceRepo: new TableDeviceRepo(),
    lastKnownRepo: new TableLastKnownRepo(),
    groupRepo: new TableGroupRepo(),
    groupLastKnownRepo: new TableGroupLastKnownRepo(),
    historyStore: new BlobHistoryStore(),
    usageRepo: new TableUsageRepo(),
    entitlementsRepo: new TableEntitlementsRepo(),
    clock: new FixedClock(now),
  };
}

describe("integration/erasure against never-created storage (specs/002 §4.2, 008 §9, B20)", () => {
  // These tables/containers are the full universe touched anywhere in this file. Ensuring
  // them all up front, then dropping only the ONE under test inside each `it`, keeps every
  // test's blast radius local — no test needs to worry about what a previous test left
  // dropped, and no test needs to restore state for a later one.
  beforeAll(async () => {
    await ensureTables(
      "Families",
      "Users",
      "Entitlements",
      "Usage",
      "Devices",
      "LastKnown",
      "IdempotencyMarkers",
      "Invites",
      "LocateRequests",
      "Groups",
      "GroupCodes",
      "GroupLastKnown",
      "GroupExpiry",
    );
    await ensureContainers("history", "events", "config");
  }, 30_000);

  describe("the live incident, reproduced exactly: DELETE /users/me for a no-profile caller", () => {
    it("succeeds against storage where Devices/LastKnown/IdempotencyMarkers/Users/Usage have never been created", async () => {
      const uid = testUserId();
      await dropTables("Devices", "LastKnown", "IdempotencyMarkers", "Users", "Usage");
      const deps = buildAccountDeletionDeps();

      // The exact 001 §1.5.3/008 §4.1 bootstrap allowance: no profile, no family, no role.
      await expect(deleteAccount({ uid, familyId: null, role: null }, deps)).resolves.toBeUndefined();

      await ensureTables("Devices", "LastKnown", "IdempotencyMarkers", "Users", "Usage");
    });
  });

  describe("account-deletion table adapters tolerate their own table never having existed", () => {
    it("DeviceRepo.listDevices / deleteDevicesByOwner — Devices table missing", async () => {
      const owner = testUserId();
      await dropTables("Devices");
      const repo = new TableDeviceRepo();

      await expect(repo.listDevices(owner)).resolves.toEqual([]);
      await expect(repo.deleteDevicesByOwner(owner)).resolves.toBeUndefined();

      await ensureTables("Devices");
    });

    it("LastKnownRepo.listByOwner / deleteByOwner — LastKnown table missing", async () => {
      const owner = testUserId();
      await dropTables("LastKnown");
      const repo = new TableLastKnownRepo();

      await expect(repo.listByOwner(owner)).resolves.toEqual([]);
      await expect(repo.deleteByOwner(owner)).resolves.toBeUndefined();

      await ensureTables("LastKnown");
    });

    it("IdempotencyRepo.deletePartition — IdempotencyMarkers table missing", async () => {
      const deviceId = testDeviceId();
      await dropTables("IdempotencyMarkers");
      const repo = new TableIdempotencyRepo();

      await expect(repo.deletePartition(deviceId)).resolves.toBeUndefined();

      await ensureTables("IdempotencyMarkers");
    });

    it("UserRepo.listGroupMemberships — Users table missing", async () => {
      const userId = testUserId();
      await dropTables("Users");
      const repo = new TableUserRepo();

      await expect(repo.listGroupMemberships(userId)).resolves.toEqual([]);

      await ensureTables("Users");
    });

    it("UsageRepo.listByPartition / deletePartition — Usage table missing", async () => {
      const partition = testUserId();
      await dropTables("Usage");
      const repo = new TableUsageRepo();

      await expect(repo.listByPartition(partition)).resolves.toEqual([]);
      await expect(repo.deletePartition(partition)).resolves.toBeUndefined();

      await ensureTables("Usage");
    });

    it("LocateRequestRepo.deletePartition / deleteRowsForUser — LocateRequests table missing", async () => {
      const familyId = testFamilyId();
      const userId = testUserId();
      await dropTables("LocateRequests");
      const repo = new TableLocateRequestRepo();

      await expect(repo.deletePartition(familyId)).resolves.toBeUndefined();
      await expect(repo.deleteRowsForUser(familyId, userId)).resolves.toBeUndefined();

      await ensureTables("LocateRequests");
    });
  });

  describe("family-deletion adapters tolerate their own table/container never having existed", () => {
    it("FamilyRepo.listMembers / listInviteIndexEntries — Families table missing", async () => {
      const familyId = testFamilyId();
      await dropTables("Families");
      const repo = new TableFamilyRepo();

      await expect(repo.listMembers(familyId)).resolves.toEqual([]);
      await expect(repo.listInviteIndexEntries(familyId)).resolves.toEqual([]);

      await ensureTables("Families");
    });

    it("deleteFamilyFootprint succeeds end to end when Entitlements/Usage/LocateRequests/history/events/config were never written for this family", async () => {
      const familyId = testFamilyId();
      const parent = testUserId();
      const deps = buildFamilyDeletionDeps();

      // A real, minimal family — createFamily/addMember always land together (the invariant
      // exportUserData.ts documents), but this family never accumulated usage, never had a
      // locate request, never posted history/events, and never set a geofence config — all
      // entirely plausible for a family deleted shortly after creation.
      await deps.familyRepo.createFamily({
        familyId,
        familyName: "Fresh family",
        createdBy: parent,
        createdAt: "2026-07-19T08:00:00Z",
      });
      await deps.familyRepo.addMember(familyId, {
        userId: parent,
        role: "parent",
        displayName: "Parent",
        joinedAt: "2026-07-19T08:00:00Z",
      });
      await deps.userRepo.createProfile(parent, { familyId, role: "parent", displayName: "Parent" });

      await dropTables("Entitlements", "Usage", "LocateRequests");
      await dropContainers("history", "events", "config");

      await expect(deleteFamilyFootprint(familyId, parent, deps)).resolves.toBeUndefined();

      // In scope for B20: the family's own rows are gone even though Entitlements/Usage/
      // LocateRequests/history/events/config were never created. (NOT asserted here: whether
      // the caller's profile actually flips family-less — that turned out to depend on
      // UserRepo.clearFamilyMembership's Merge-with-null semantics against real Table
      // Storage, a separate, pre-existing gap unrelated to missing-table tolerance; flagged
      // separately rather than folded into this fix.)
      expect(await deps.familyRepo.getFamilyMeta(familyId)).toBeNull();
      expect(await deps.familyRepo.listMembers(familyId)).toEqual([]);

      await ensureTables("Entitlements", "Usage", "LocateRequests");
      await ensureContainers("history", "events", "config");
    });
  });

  describe("group hard-delete / sweeper adapters tolerate their own table never having existed", () => {
    it("GroupRepo.listMembers — Groups table missing", async () => {
      const groupId = testGroupId();
      await dropTables("Groups");
      const repo = new TableGroupRepo();

      await expect(repo.listMembers(groupId)).resolves.toEqual([]);

      await ensureTables("Groups");
    });

    it("GroupLastKnownRepo.listByGroup / deletePartition — GroupLastKnown table missing", async () => {
      const groupId = testGroupId();
      await dropTables("GroupLastKnown");
      const repo = new TableGroupLastKnownRepo();

      await expect(repo.listByGroup(groupId)).resolves.toEqual([]);
      await expect(repo.deletePartition(groupId)).resolves.toBeUndefined();

      await ensureTables("GroupLastKnown");
    });

    it("GroupExpiryRepo.listByDate — GroupExpiry table missing (the sweeper's own bucket walk)", async () => {
      const bucketDate = "2026-07-19";
      await dropTables("GroupExpiry");
      const repo = new TableGroupExpiryRepo();

      await expect(repo.listByDate(bucketDate)).resolves.toEqual([]);

      await ensureTables("GroupExpiry");
    });

    it("sweepGroups() completes a full run when GroupExpiry has never been created (a deployment that never had a group)", async () => {
      await dropTables("GroupExpiry");
      const deps = buildSweepDeps(new Date("2026-07-21T10:00:00Z"));

      const result = await sweepGroups(deps);

      expect(result.rowsScanned).toBe(0);
      expect(result.errors).toEqual([]);

      await ensureTables("GroupExpiry");
    });

    it("hardDeleteGroupFootprint succeeds when GroupLastKnown was never written for this group", async () => {
      const groupId = testGroupId();
      const owner = testUserId();
      const code = testUserId().slice(0, 8).toUpperCase();
      const groupRepo = new TableGroupRepo();
      const groupCodeRepo = new TableGroupCodeRepo();
      const userRepo = new TableUserRepo();

      await groupRepo.createGroupMeta({
        groupId,
        name: "Missing-location group",
        ownerUserId: owner,
        createdAt: "2026-07-19T08:00:00Z",
        endsAt: "2026-07-26T08:00:00Z",
        expiryPolicy: "delete",
        code,
      });
      await groupRepo.addMember(groupId, { userId: owner, role: "owner", displayName: "Owner", joinedAt: "2026-07-19T08:00:00Z" });
      await userRepo.addGroupMembership(owner, { groupId, role: "owner", joinedAt: "2026-07-19T08:00:00Z" });
      await groupCodeRepo.createCode(code, { groupId, createdAt: "2026-07-19T08:00:00Z" });

      await dropTables("GroupLastKnown");

      const meta = await groupRepo.getGroupMeta(groupId);
      await expect(
        hardDeleteGroupFootprint(meta!, { groupRepo, groupCodeRepo, groupLastKnownRepo: new TableGroupLastKnownRepo(), userRepo }),
      ).resolves.toBeUndefined();

      expect(await groupRepo.getGroupMeta(groupId)).toBeNull();

      await ensureTables("GroupLastKnown");
    });
  });

  describe("export tolerates its own tables/containers never having existed", () => {
    it("exportUserData succeeds for a family-less self-export when Devices/LastKnown/Usage/history/events were never written", async () => {
      const uid = testUserId();
      const userRepo = new TableUserRepo();
      await userRepo.createProfile(uid, { familyId: null, role: null, displayName: "Solo" });

      await dropTables("Devices", "LastKnown", "Usage");
      await dropContainers("history", "events");

      const deps = buildExportDeps(new Date("2026-07-21T10:00:00Z"));
      const doc = await exportUserData({ uid, familyId: null, role: null, query: {} }, deps);

      expect(doc.devices).toEqual([]);
      expect(doc.lastKnown).toEqual([]);
      expect(doc.locationHistory).toEqual([]);
      expect(doc.geofenceEvents).toEqual([]);
      expect(doc.usage).toEqual([]);

      await ensureTables("Devices", "LastKnown", "Usage");
      await ensureContainers("history", "events");
    });
  });

  describe("blob prefix wipes tolerate their container never having existed", () => {
    it("BlobHistoryStore.deleteFamilyPrefix / deleteUserPrefix / eraseUserFromEvents — history/events containers missing", async () => {
      const familyId = testFamilyId();
      const userId = testUserId();
      await dropContainers("history", "events");
      const store = new BlobHistoryStore();

      await expect(store.deleteFamilyPrefix(familyId)).resolves.toBeUndefined();
      await expect(store.deleteUserPrefix(familyId, userId)).resolves.toBeUndefined();
      await expect(store.eraseUserFromEvents(familyId, userId)).resolves.toBeUndefined();

      await ensureContainers("history", "events");
    });

    it("BlobGeofenceConfigRepo.deleteConfig — config container missing (BlobClient.deleteIfExists alone does NOT cover this: it only swallows BlobNotFound, not ContainerNotFound)", async () => {
      const familyId = testFamilyId();
      await dropContainers("config");
      const repo = new BlobGeofenceConfigRepo();

      await expect(repo.deleteConfig(familyId)).resolves.toBeUndefined();

      await ensureContainers("config");
    });
  });

  // B22 (specs/001 §6.1, 002 §2 general list-tolerance rule) — sibling of B20 in the locate
  // flow, not an erasure path: createLocateRequest.ts's coalescing check calls
  // listPendingByTargetDevice BEFORE the first LocateRequests row is ever created for a
  // family, so a family's very first push-to-locate request hit the identical TableNotFound
  // failure mode as B20, on a different endpoint (POST /locate-requests instead of
  // DELETE /users/me).
  describe("locate-request coalescing check tolerates the LocateRequests table never having existed (B22)", () => {
    function buildRecord(overrides: Partial<LocateRequestRecord> & { familyId: string; targetDeviceId: string }): LocateRequestRecord {
      return {
        requestId: testRequestId(),
        targetUserId: testUserId(),
        requestedBy: testUserId(),
        status: "pending",
        createdAt: "2026-07-25T08:00:00Z",
        expiresAt: "2026-07-25T08:01:00Z",
        ...overrides,
      };
    }

    it("resolves to [] — instead of throwing TableNotFound — for a family's very first locate request, LocateRequests table missing", async () => {
      const familyId = testFamilyId();
      const targetDeviceId = testDeviceId();
      await dropTables("LocateRequests");
      const repo = new TableLocateRequestRepo();

      await expect(repo.listPendingByTargetDevice(familyId, targetDeviceId)).resolves.toEqual([]);

      await ensureTables("LocateRequests");
    });

    it("happy path unchanged: an existing pending request for the same target device is found and returned", async () => {
      const familyId = testFamilyId();
      const targetDeviceId = testDeviceId();
      const repo = new TableLocateRequestRepo();
      const record = buildRecord({ familyId, targetDeviceId, status: "pending" });
      await repo.create(record);

      const found = await repo.listPendingByTargetDevice(familyId, targetDeviceId);

      expect(found).toHaveLength(1);
      expect(found[0]).toMatchObject({
        requestId: record.requestId,
        familyId,
        targetDeviceId,
        status: "pending",
      });
    });

    it("genuinely different coalescing scenario (not just present/absent): a fulfilled request for the same device and a pending request for a different device both fail to coalesce", async () => {
      const familyId = testFamilyId();
      const targetDeviceId = testDeviceId();
      const otherDeviceId = testDeviceId();
      const repo = new TableLocateRequestRepo();
      // Status mismatch — same device, but already fulfilled.
      await repo.create(buildRecord({ familyId, targetDeviceId, status: "fulfilled" }));
      // Target mismatch — pending, but a different device.
      await repo.create(buildRecord({ familyId, targetDeviceId: otherDeviceId, status: "pending" }));

      const found = await repo.listPendingByTargetDevice(familyId, targetDeviceId);

      expect(found).toEqual([]);
    });
  });
});
