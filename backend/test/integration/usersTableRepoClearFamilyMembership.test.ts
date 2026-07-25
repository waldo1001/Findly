// specs/002 §2.2/§4.2, specs/008 §4.2/§5.2 — B21: TableUserRepo.clearFamilyMembership had
// never actually worked. It called `updateEntity({ familyId: null, role: null }, "Merge")`,
// but Table Storage's Merge has no `null` type: the @azure/data-tables SDK silently drops
// null-valued properties from the merge payload instead of clearing them server-side. The
// call succeeded (etag rotated) but familyId/role were left untouched on the stored row —
// the whole point of family deletion's member-flip (002 §4.2 steps 1/6) and the account-
// deletion cascade (B18) that reuses it. No prior test caught this because it only checked
// the call didn't throw, never read the raw entity back. Requires Azurite
// (`npm run dev:storage`); run via `npm run test:integration`.

import { beforeAll, describe, expect, it } from "vitest";
import { RestError } from "@azure/data-tables";
import { ensureTables } from "./support/ensureStorage";
import { testUserId } from "./support/ids";
import { createTableClient } from "../../src/adapters/tables/tableClientFactory";
import { TableUserRepo } from "../../src/adapters/tables/usersTableRepo";

const PROFILE_ROW_KEY = "profile";

describe("integration/Users.clearFamilyMembership — real Merge-with-null semantics (specs/002 §2.2/§4.2, B21)", () => {
  beforeAll(async () => {
    await ensureTables("Users");
  }, 30_000);

  it("clears familyId/role on the RAW stored entity while preserving displayName (the exact repro)", async () => {
    const repo = new TableUserRepo();
    const userId = testUserId();
    await repo.createProfile(userId, { familyId: "fam_abc123", role: "member", displayName: "Test" });

    await repo.clearFamilyMembership(userId);

    // Bypass the port entirely — read the raw entity via a fresh TableClient, the same way
    // the bug report proved the old Merge-with-null call was a no-op server-side. Asserting
    // through getProfile() would only prove the port's own null-coercion on read, which is
    // exactly the blind spot that let this bug ship.
    const raw = createTableClient("Users");
    const entity = await raw.getEntity(userId, PROFILE_ROW_KEY);
    expect(entity.familyId).toBeUndefined();
    expect(entity.role).toBeUndefined();
    expect(entity.displayName).toBe("Test");
  });

  it("is idempotent when called again on an already-cleared profile", async () => {
    const repo = new TableUserRepo();
    const userId = testUserId();
    await repo.createProfile(userId, { familyId: "fam_abc123", role: "member", displayName: "Test" });
    await repo.clearFamilyMembership(userId);

    await expect(repo.clearFamilyMembership(userId)).resolves.toBeUndefined();

    const raw = createTableClient("Users");
    const entity = await raw.getEntity(userId, PROFILE_ROW_KEY);
    expect(entity.familyId).toBeUndefined();
    expect(entity.role).toBeUndefined();
    expect(entity.displayName).toBe("Test");
  });

  it("is a no-op for a userId that never had a profile row at all (swallows not-found)", async () => {
    const repo = new TableUserRepo();
    const userId = testUserId();

    await expect(repo.clearFamilyMembership(userId)).resolves.toBeUndefined();
  });

  it("swallows not-found even if the row is deleted concurrently between its read and its write", async () => {
    const repo = new TableUserRepo();
    const userId = testUserId();
    await repo.createProfile(userId, { familyId: "fam_abc123", role: "member", displayName: "Test" });

    // Inject a real concurrent delete between clearFamilyMembership's own getEntity (read)
    // and its updateEntity (write) — same "reach into the private client" idiom as the
    // displayName-race test below, but simulating the row vanishing mid-retry (008 §4.2's
    // "a concurrent DELETE /families/me/members/{userId} may have already deleted the
    // profile row entirely out from under a family deletion's own roster snapshot").
    const rawClient = (repo as unknown as { client: ReturnType<typeof createTableClient> }).client;
    const realGetEntity = rawClient.getEntity.bind(rawClient);
    let injected = false;
    rawClient.getEntity = (async (partitionKey: string, rowKey: string) => {
      const result = await realGetEntity(partitionKey, rowKey);
      if (!injected) {
        injected = true;
        const other = createTableClient("Users");
        await other.deleteEntity(userId, PROFILE_ROW_KEY);
      }
      return result;
    }) as typeof rawClient.getEntity;

    await expect(repo.clearFamilyMembership(userId)).resolves.toBeUndefined();
    const raw = createTableClient("Users");
    await expect(raw.getEntity(userId, PROFILE_ROW_KEY)).rejects.toThrow();
  });

  it("SECURITY/CORRECTNESS: a concurrent displayName update (updateProfile) racing clearFamilyMembership converges — neither write is lost", async () => {
    const repo = new TableUserRepo();
    const userId = testUserId();
    await repo.createProfile(userId, { familyId: "fam_abc123", role: "member", displayName: "Original" });

    // Reach into the adapter's private TableClient (same TOCTOU-injection idiom as
    // groupSweeper.test.ts's "concurrent owner PATCH-extend" race, adapted to the point
    // where THIS adapter reads: clearFamilyMembership's own getEntity call). We let the
    // real read happen, then land a REAL concurrent updateEntity (a genuine Azurite ETag
    // rotation, not a simulated one) for a displayName change before returning the
    // now-stale snapshot back to clearFamilyMembership — forcing its subsequent
    // Replace-with-etag call to hit a real 412 and retry.
    const rawClient = (repo as unknown as { client: ReturnType<typeof createTableClient> }).client;
    const realGetEntity = rawClient.getEntity.bind(rawClient);
    let injected = false;
    rawClient.getEntity = (async (partitionKey: string, rowKey: string) => {
      const result = await realGetEntity(partitionKey, rowKey);
      if (!injected) {
        injected = true;
        const racer = createTableClient("Users");
        await racer.updateEntity({ partitionKey: userId, rowKey: PROFILE_ROW_KEY, displayName: "Raced Name" }, "Merge");
      }
      return result;
    }) as typeof rawClient.getEntity;

    await repo.clearFamilyMembership(userId);

    const raw = createTableClient("Users");
    const entity = await raw.getEntity(userId, PROFILE_ROW_KEY);
    expect(entity.familyId).toBeUndefined();
    expect(entity.role).toBeUndefined();
    // The racer's displayName update must survive the retry — clearFamilyMembership's
    // Replace must re-read on conflict, not blindly reapply its first, now-stale snapshot.
    expect(entity.displayName).toBe("Raced Name");
  });

  it("throws (does not silently drop) once the retry budget is exhausted under sustained ETag contention — this is a correctness guarantee, not telemetry (unlike Usage's log-and-drop, 002 §2.9)", async () => {
    const repo = new TableUserRepo();
    const userId = testUserId();
    await repo.createProfile(userId, { familyId: "fam_abc123", role: "member", displayName: "Test" });

    const rawClient = (repo as unknown as { client: ReturnType<typeof createTableClient> }).client;
    const realUpdateEntity = rawClient.updateEntity.bind(rawClient);
    let calls = 0;
    rawClient.updateEntity = (async (...args: Parameters<typeof realUpdateEntity>) => {
      calls += 1;
      throw new RestError("simulated sustained ETag conflict", { statusCode: 412 });
    }) as typeof rawClient.updateEntity;

    await expect(repo.clearFamilyMembership(userId)).rejects.toThrow();
    expect(calls).toBeGreaterThan(1); // actually retried, not just a single attempt

    // The row is untouched by the failed attempts — still has its original data.
    const raw = createTableClient("Users");
    const entity = await raw.getEntity(userId, PROFILE_ROW_KEY);
    expect(entity.familyId).toBe("fam_abc123");
    expect(entity.displayName).toBe("Test");
  });
});
